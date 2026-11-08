import CoreGraphics

/// All the sizing math for the notch, in one pure value type so it can be unit tested
/// without a screen. Rects use AppKit screen coordinates (origin bottom-left, y up).
public struct NotchGeometry: Equatable, Sendable {
    /// The physical notch, read from the screen's safe-area insets.
    public var notchSize: CGSize
    /// Width of each "wing" drawn beside the notch while collapsed.
    public var wingWidth: CGFloat
    /// Requested size of the pop-down panel.
    public var panelSize: CGSize
    /// The small outward curve where the shape meets the top of the screen.
    public var ear: CGFloat

    /// The panel can never be narrower or shorter than this past the notch itself.
    public static let minimumPanelExtra = CGSize(width: 40, height: 120)

    public init(notchSize: CGSize, wingWidth: CGFloat, panelSize: CGSize, ear: CGFloat = 8) {
        self.notchSize = notchSize
        self.wingWidth = wingWidth
        self.panelSize = panelSize
        self.ear = ear
    }

    public var collapsedSize: CGSize {
        CGSize(width: notchSize.width + max(0, wingWidth) * 2, height: notchSize.height)
    }

    public var expandedSize: CGSize {
        CGSize(width: max(panelSize.width, notchSize.width + Self.minimumPanelExtra.width),
               height: max(panelSize.height, notchSize.height + Self.minimumPanelExtra.height))
    }

    public func size(expanded: Bool) -> CGSize {
        expanded ? expandedSize : collapsedSize
    }

    /// The transparent window is sized for the largest the shape can get, so animating
    /// between states never resizes the window (which would flicker).
    public func windowFrame(on screen: CGRect) -> CGRect {
        let width = max(expandedSize.width, collapsedSize.width) + ear * 2 + 40
        let height = expandedSize.height + 30
        return CGRect(x: screen.midX - width / 2, y: screen.maxY - height, width: width, height: height)
    }

    /// Hovering here opens the panel. Only the notch itself (plus the very top pixel row),
    /// not the wings, so passing the pointer along the menu bar doesn't pop it open.
    public func openTriggerRect(on screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - notchSize.width / 2, y: screen.maxY - notchSize.height,
               width: notchSize.width, height: notchSize.height + 1)
    }

    /// While open, the panel stays open as long as the pointer is inside this rect.
    public func stayOpenRect(on screen: CGRect, slack: CGFloat = 6) -> CGRect {
        let size = expandedSize
        return CGRect(x: screen.midX - size.width / 2, y: screen.maxY - size.height,
                      width: size.width, height: size.height)
            .insetBy(dx: -slack, dy: -slack)
    }
}
