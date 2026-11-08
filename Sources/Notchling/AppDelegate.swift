import AppKit
import Combine
import NotchlingCore
import NotchlingUI
import SwiftUI

/// Composition root: builds the real providers, the stores and the window, and wires them together.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = NotchSettings()
    private lazy var reminders = RemindersStore(provider: EventKitRemindersProvider(),
                                                listID: settings.selectedListID)
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
        model = NotchModel(notchSize: screen.notchSize, media: AppleScriptMediaProvider(),
                           power: IOKitPowerProvider())
        model.start()
        buildPanel()
        observe()
        Task { await reminders.reload() }
    }

    private func buildPanel() {
        panel = NotchPanel()
        let root = NotchView(model: model, openSettings: { [weak self] in self?.showSettings() })
            .environmentObject(settings)
            .environmentObject(reminders)
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
            model = NotchModel(notchSize: current.notchSize, media: AppleScriptMediaProvider(),
                               power: IOKitPowerProvider())
            model.start()
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
            }
        } else if panel.isKeyWindow {
            // Hand the keyboard back to whatever app the user was typing in.
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
    }

    private func showSettings() {
        setExpanded(false)
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView()
                .environmentObject(settings)
                .environmentObject(reminders))
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                                  styleMask: [.titled, .closable], backing: .buffered, defer: false)
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
