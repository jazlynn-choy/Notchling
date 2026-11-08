import AppKit
import Combine
import NotchlingActivity
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
    private let hookSetup = ClaudeHookSetup()
    private lazy var agents = AgentStatusStore(
        source: DirectoryAgentEventSource(directory: hookSetup.installer.eventsDirectory))
    private let editor = PanelEditor()
    private let approvals = ApprovalStore(channel: DirectoryApprovalChannel())
    private let activities = ActivityStore()
    private let commandSetup = CommandSetup(installer: CommandInstaller(
        source: Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/notch")))
    // Background refreshes. Each runs only while a widget needs it (see `observeFeatures`).
    private lazy var calendarLoop = RepeatingTask(every: 15 * 60) { [calendar] in await calendar.reload() }
    private lazy var weatherLoop = RepeatingTask(every: WeatherStore.maxAge) { [weather] in await weather.refresh() }
    private lazy var agentLoop = RepeatingTask(every: 1) { [agents] in agents.refresh() }
    private lazy var activityLoop = RepeatingTask(every: 0.5) { [activities] in activities.refresh() }
    private lazy var approvalLoop = RepeatingTask(every: 0.25) { [approvals] in approvals.refresh() }
    private lazy var spotifyLoop = RepeatingTask(every: 30 * 60) { [spotify] in await spotify.keepAlive() }
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
        observeScreenAndSettings()
        observeFeatures()
        Task { await reminders.reload() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        notes.saveNow()
        // Hand any waiting permission requests straight back to Claude Code's own prompt.
        for request in approvals.requests { approvals.answer(request, .ask) }
        approvals.setEnabled(false, waitSeconds: settings.approvalWait)
    }

    /// (Re)creates the live model and everything that listens to it.
    private func startModel(notchSize: CGSize) {
        modelSubscriptions = []
        model = NotchModel(notchSize: notchSize, media: media, power: IOKitPowerProvider())
        model.mediaEnabled = settings.widgets.allWidgets.contains(where: \.usesMedia)
        model.preferredApp = settings.musicSource
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
            .environmentObject(agents)
            .environmentObject(editor)
            .environmentObject(approvals)
            .environmentObject(activities)
        let host = NSHostingView(rootView: root)
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        panel.contentView = host
        reposition()
        panel.orderFrontRegardless()
    }

    private func showSettings() {
        setExpanded(false)
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView()
                .environmentObject(settings)
                .environmentObject(reminders)
                .environmentObject(calendar)
                .environmentObject(weather)
                .environmentObject(spotify)
                .environmentObject(hookSetup)
                .environmentObject(commandSetup))
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

// MARK: - Wiring

extension AppDelegate {
    private func observeScreenAndSettings() {
        NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.screenParametersChanged() }
            .store(in: &subscriptions)

        // Size settings change the window frame; debounce so dragging a slider stays smooth.
        settings.objectWillChange
            .debounce(for: .milliseconds(16), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.reposition() }
            .store(in: &subscriptions)

        settings.$musicSource
            .removeDuplicates()
            .sink { [weak self] source in
                self?.search.source = source
                self?.model.preferredApp = source
            }
            .store(in: &subscriptions)

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

    /// Each feature costs nothing until a widget that needs it is in the layout.
    private func observeFeatures() {
        whileShown(\.usesMedia) { [weak self] in self?.model.mediaEnabled = $0 }
        whileShown(\.usesCalendar) { [calendarLoop] in calendarLoop.setRunning($0) }   // + EKEventStoreChanged
        whileShown(\.usesWeather) { [weatherLoop] in weatherLoop.setRunning($0) }
        whileShown(\.usesAgent) { [agentLoop] in agentLoop.setRunning($0) }
        whileShown(\.usesActivity) { [activityLoop] in activityLoop.setRunning($0) }
        activities.onFinished = { activity in
            switch activity.state {
            case .succeeded: Self.chime("Glass")
            case .failed: Self.chime("Basso")
            case .info, .running: Self.chime("Pop")
            }
        }        // a cheap directory read

        // Spotify: renew the sign-in at launch, every 30 minutes and after every wake.
        spotifyLoop.setRunning(true)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
            .sink { [spotifyLoop] _ in spotifyLoop.fire() }
            .store(in: &subscriptions)

        // Approvals: on only when the hooks are installed and the setting is on.
        Publishers.CombineLatest3(hookSetup.$isInstalled, settings.$approvalsEnabled, settings.$approvalWait)
            .sink { [weak self] installed, enabled, wait in
                guard let self else { return }
                approvals.setEnabled(installed && enabled, waitSeconds: wait)
                approvalLoop.setRunning(installed && enabled)
            }
            .store(in: &subscriptions)
        approvals.onNewRequests = { [weak self] _ in
            guard let self else { return }
            setExpanded(true)
            if settings.agentChime { Self.chime("Funk") }
        }

        agents.onAttention = { [weak self] session in
            guard let self, settings.agentChime else { return }
            Self.chime(session.state == .needsInput ? "Funk" : "Glass")
        }
        focus.onFinish = { Self.chime("Glass") }

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
    }

    /// Calls `apply(true)` when a widget matching `uses` enters the layout, `false` when the last one leaves.
    private func whileShown(_ uses: @escaping (WidgetKind) -> Bool, _ apply: @escaping (Bool) -> Void) {
        settings.$widgets
            .map { $0.allWidgets.contains(where: uses) }
            .removeDuplicates()
            .sink(receiveValue: apply)
            .store(in: &subscriptions)
    }

    private static func chime(_ sound: String) {
        NSSound(named: sound)?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

// MARK: - Window position and hover

extension AppDelegate {
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
        // A permission request keeps the panel open until it's answered or times out.
        let mustStayOpen = !approvals.requests.isEmpty
        if mustStayOpen && !model.isExpanded { setExpanded(true) }
        if model.isExpanded {
            if mustStayOpen || geometry.stayOpenRect(on: screen.frame).contains(pointer) {
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
                if calendarLoop.isRunning { await calendar.reload() }
                if weatherLoop.isRunning { await weather.refresh() }
            }
        } else {
            search.isOpen = false
            editor.isEditing = false
        }
        if !expanded && panel.isKeyWindow {
            // Hand the keyboard back to whatever app the user was typing in.
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }
}
