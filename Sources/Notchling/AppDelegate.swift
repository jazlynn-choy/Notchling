import AppKit
import Combine
import NotchlingCore
import NotchlingUI
import SwiftUI

/// Composition root: builds the real providers, the stores and the window, and wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = NotchSettings(
        spotifyInstalled: NSWorkspace.shared.urlForApplication(withBundleIdentifier: MediaApp.spotify.bundleID) != nil)
    private lazy var reminders = RemindersStore(provider: EventKitRemindersProvider(),
                                                listID: settings.selectedListID)
    private let focus = FocusTimer()
    private let calendar = CalendarStore(provider: EventKitCalendarProvider())
    private let media: MediaProviding = AppleScriptMediaProvider()
    private let spotify = SpotifyConnection(http: URLSessionHTTPClient(), secrets: KeychainSecretStore(),
                                            callbacks: LoopbackCallbackServer(),
                                            openURL: { NSWorkspace.shared.open($0) })
    private lazy var search = MusicSearch(
        media: media,
        catalogs: [
            .music: MusicLibraryCatalog(media: media),
            .spotify: SpotifyCatalog(http: URLSessionHTTPClient(),
                                     token: { [spotify] in try await spotify.accessToken() },
                                     invalidateToken: { [spotify] in await spotify.invalidateAccessToken() }),
        ],
        source: settings.musicSource)
    private let weather = WeatherStore(provider: OpenMeteoWeatherProvider())
    private let notes = NotesStore()
    private var calendarTimer: Timer?
    private var weatherTimer: Timer?
    private var modelSubscriptions = Set<AnyCancellable>()
    private var model: NotchModel!
    private var panel: NotchPanel!
    private var screen: NSScreen!
    private var settingsWindow: NSWindow?
    private var hoverTimer: Timer?
    private var collapseWork: DispatchWorkItem?
    private var subscriptions = Set<AnyCancellable>()

    private var geometry: NotchGeometry { settings.geometry(notchSize: model.notchSize) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        screen = NSScreen.withNotch ?? NSScreen.main ?? NSScreen.screens[0]
        startModel(notchSize: screen.notchSize)
        buildPanel()
        observe()
        Task { await reminders.reload() }
    }

    /// (Re)creates the live model and everything that listens to it.
    private func startModel(notchSize: CGSize) {
        modelSubscriptions = []
        model = NotchModel(notchSize: notchSize, media: media, power: IOKitPowerProvider())
        model.mediaEnabled = settings.widgets.allWidgets.contains(where: \.usesMedia)
        model.start()
        // The focus timer checks for "done" on the same 1-second clock the UI uses.
        model.$now
            .sink { [weak self] now in self?.focus.tick(now: now) }
            .store(in: &modelSubscriptions)
    }

    private func buildPanel() {
        panel = NotchPanel()
        let root = NotchView(model: model, openSettings: { [weak self] in self?.showSettings() })
            .environmentObject(settings)
            .environmentObject(reminders)
            .environmentObject(focus)
            .environmentObject(calendar)
            .environmentObject(search)
            .environmentObject(weather)
            .environmentObject(notes)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()
    }

    private func observe() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &subscriptions)

        // Size settings change the window frame; debounce so dragging a slider stays smooth.
        settings.objectWillChange
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &subscriptions)

        // Only run the AppleScript now-playing poll while some widget actually shows music.
        settings.$widgets
            .map { $0.allWidgets.contains(where: \.usesMedia) }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.model.mediaEnabled = enabled }
            .store(in: &subscriptions)

        // Calendar is only read while a calendar widget is in the layout. A slow timer keeps
        // "next event" current across midnight; edits arrive through EKEventStoreChanged.
        settings.$widgets
            .map { $0.allWidgets.contains(where: \.usesCalendar) }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setCalendarEnabled(enabled) }
            .store(in: &subscriptions)

        // Weather is only fetched while a weather widget is in the layout.
        settings.$widgets
            .map { $0.allWidgets.contains(where: \.usesWeather) }
            .removeDuplicates()
            .sink { [weak self] enabled in self?.setWeatherEnabled(enabled) }
            .store(in: &subscriptions)

        settings.$musicSource
            .removeDuplicates()
            .sink { [weak self] source in self?.search.source = source }
            .store(in: &subscriptions)

        focus.onFinish = {
            NSSound(named: "Glass")?.play()
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }

        // Typing needs the panel to be the key window; a non-activating panel only becomes
        // key on its own when a text field is clicked, not when search opens from a button.
        search.$isOpen
            .removeDuplicates()
            .sink { [weak self] open in if open { self?.panel.makeKey() } }
            .store(in: &subscriptions)
        search.onPlay = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(400))
                await self?.model.refreshMedia()
            }
        }

        settings.$reminderListID
            .removeDuplicates()
            .sink { [weak self] id in self?.reminders.listID = id.isEmpty ? nil : id }
            .store(in: &subscriptions)

        // Poll the pointer instead of taking mouse events: while collapsed the window ignores
        // the mouse entirely, so clicks reach the menu bar items underneath the wings.
        hoverTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.trackMouse() }
        }
    }

    private func screenParametersChanged() {
        let current = NSScreen.withNotch ?? NSScreen.main ?? NSScreen.screens[0]
        if current.notchSize != model.notchSize {
            // A different notch size (e.g. display mode change) needs a fresh model.
            model.stop()
            screen = current
            startModel(notchSize: current.notchSize)
            buildPanel()
        } else {
            screen = current
            reposition()
        }
    }

    private func reposition() {
        panel.setFrame(geometry.windowFrame(on: screen.frame), display: true)
    }

    private func trackMouse() {
        let pointer = NSEvent.mouseLocation
        if model.isExpanded {
            if geometry.stayOpenRect(on: screen.frame).contains(pointer) {
                collapseWork?.cancel()
                collapseWork = nil
            } else if collapseWork == nil {
                // Short grace period so brushing past the edge doesn't snap it shut.
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated { self?.setExpanded(false) }
                }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
        } else if geometry.openTriggerRect(on: screen.frame).contains(pointer) {
            setExpanded(true)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        collapseWork?.cancel()
        collapseWork = nil
        guard model.isExpanded != expanded else { return }
        model.isExpanded = expanded
        panel.ignoresMouseEvents = !expanded
        if expanded {
            if settings.haptics {
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
            }
            model.refreshPower()
            Task {
                await model.refreshMedia()
                await reminders.reload()
                if calendarTimer != nil { await calendar.reload() }
                if weatherTimer != nil { await weather.refresh() }
            }
        } else {
            search.isOpen = false
        }
        if !expanded && panel.isKeyWindow {
            // Hand the keyboard back to whatever app the user was typing in.
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    private func setWeatherEnabled(_ enabled: Bool) {
        weatherTimer?.invalidate()
        weatherTimer = nil
        guard enabled else { return }
        Task { await weather.refresh() }
        weatherTimer = Timer.scheduledTimer(withTimeInterval: WeatherStore.maxAge, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.weather.refresh() }
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.saveNow()
    }

    private func setCalendarEnabled(_ enabled: Bool) {
        calendarTimer?.invalidate()
        calendarTimer = nil
        guard enabled else { return }
        Task { await calendar.reload() }
        calendarTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.calendar.reload() }
            }
        }
    }

    private func showSettings() {
        setExpanded(false)
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView()
                .environmentObject(settings)
                .environmentObject(reminders)
                .environmentObject(calendar)
                .environmentObject(weather)
                .environmentObject(spotify))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 720),
                                  styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "Notchling Settings"
            window.contentView = host
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
