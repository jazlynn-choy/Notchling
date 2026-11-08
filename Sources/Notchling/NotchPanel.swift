import AppKit

/// A borderless, transparent, non-activating panel that floats over the menu bar on every Space.
final class NotchPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true   // take the keyboard only when a text field is clicked
    }

    /// Needed so the "add a reminder" field can receive typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

extension NSScreen {
    /// The built-in display with a camera notch, or nil if none is connected.
    static var withNotch: NSScreen? { screens.first { $0.safeAreaInsets.top > 0 } }

    /// The notch's size in points. Screens without one get a virtual notch.
    var notchSize: CGSize {
        guard safeAreaInsets.top > 0 else {
            return CGSize(width: 190, height: max(24, frame.maxY - visibleFrame.maxY))
        }
        var width: CGFloat = 200
        if let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea {
            width = frame.width - left.width - right.width
        }
        return CGSize(width: width, height: safeAreaInsets.top)
    }
}
