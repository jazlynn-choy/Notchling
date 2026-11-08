// Notchling — fills the space around the MacBook camera notch.
// Collapsed: "wings" beside the notch show music or the date, open reminders, time and battery.
// Hover the notch: a panel drops down with music controls and your Apple Reminders.

import Cocoa
import SwiftUI
import Combine

final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }   // so the reminder text field can take typing
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = NotchSettings()
    lazy var reminders = RemindersStore(settings: settings)
    var model: NotchModel!
    var panel: NotchPanel!
    var screen: NSScreen!
    var settingsWindow: NSWindow?
    var collapseWork: DispatchWorkItem?
    var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ note: Notification) {
        let (s, notch) = Self.notchScreen()
        screen = s
        model = NotchModel(notchSize: notch, settings: settings)
        buildPanel()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in self?.reposition() }
        settings.objectWillChange
            .sink { [weak self] _ in DispatchQueue.main.async { self?.reposition(); self?.model.objectWillChange.send() } }
            .store(in: &bag)
        // Poll the pointer so the panel never steals clicks from the menu bar while collapsed.
        Timer.scheduledTimer(withTimeInterval: 1 / 30, repeats: true) { [weak self] _ in self?.trackMouse() }
    }

    static func notchScreen() -> (NSScreen, CGSize) {
        if let s = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) {
            var w: CGFloat = 200
            if let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
                w = s.frame.width - l.width - r.width
            }
            return (s, CGSize(width: w, height: s.safeAreaInsets.top))
        }
        // No notch (e.g. external display only): draw a virtual one.
        let s = NSScreen.main ?? NSScreen.screens[0]
        return (s, CGSize(width: 190, height: max(24, s.frame.maxY - s.visibleFrame.maxY)))
    }

    func buildPanel() {
        panel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.becomesKeyOnlyIfNeeded = true   // only grab the keyboard when you click the text field

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

    func reposition() {
        screen = Self.notchScreen().0
        // The window is sized for the largest the panel can be; only the drawn shape changes.
        let w = max(model.expandedSize.width, model.collapsedSize.width) + model.ear * 2 + 40
        let h = model.expandedSize.height + 30
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h), display: true)
    }

    func showSettings() {
        setExpanded(false)
        if settingsWindow == nil {
            let host = NSHostingView(rootView: SettingsView().environmentObject(settings).environmentObject(reminders))
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                             styleMask: [.titled, .closable], backing: .buffered, defer: false)
            w.title = "Notchling Settings"
            w.contentView = host
            w.isReleasedWhenClosed = false
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func hitRect(for size: CGSize) -> NSRect {
        NSRect(x: screen.frame.midX - size.width / 2, y: screen.frame.maxY - size.height,
               width: size.width, height: size.height)
    }

    func trackMouse() {
        let p = NSEvent.mouseLocation
        if model.expanded {
            let inside = hitRect(for: model.expandedSize).insetBy(dx: -6, dy: -6).contains(p)
            if inside {
                collapseWork?.cancel(); collapseWork = nil
            } else if collapseWork == nil {
                let work = DispatchWorkItem { [weak self] in self?.setExpanded(false) }
                collapseWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
        } else {
            // Trigger only on the notch itself (plus the top edge), not the wings.
            var r = hitRect(for: model.notchSize)
            r.size.height += 1
            if r.contains(p) { setExpanded(true) }
        }
    }

    func setExpanded(_ on: Bool) {
        collapseWork?.cancel(); collapseWork = nil
        guard model.expanded != on else { return }
        model.expanded = on
        panel.ignoresMouseEvents = !on
        if !on && panel.isKeyWindow {
            panel.resignKey()
            NSWorkspace.shared.frontmostApplication?.activate()
        }
        if on {
            if settings.haptics { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
            model.refreshMedia()
            model.refreshBattery()
            reminders.reload()
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
