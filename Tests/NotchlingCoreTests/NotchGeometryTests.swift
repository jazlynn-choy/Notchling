import CoreGraphics
import Testing
@testable import NotchlingCore

@Suite("NotchGeometry")
struct NotchGeometryTests {
    // A 14" MacBook Pro: 1512×982 pt screen, 185×32 pt notch.
    let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    let notch = CGSize(width: 185, height: 32)

    func geometry(wing: CGFloat = 72, panel: CGSize = CGSize(width: 440, height: 190)) -> NotchGeometry {
        NotchGeometry(notchSize: notch, wingWidth: wing, panelSize: panel)
    }

    @Test func collapsedWidthIsNotchPlusBothWings() {
        #expect(geometry(wing: 72).collapsedSize == CGSize(width: 185 + 144, height: 32))
    }

    @Test func negativeWingWidthIsTreatedAsZero() {
        #expect(geometry(wing: -20).collapsedSize.width == 185)
    }

    @Test func expandedPanelUsesRequestedSize() {
        #expect(geometry().expandedSize == CGSize(width: 440, height: 190))
    }

    @Test func expandedPanelNeverSmallerThanTheNotchAllows() {
        let tiny = geometry(panel: CGSize(width: 10, height: 10))
        #expect(tiny.expandedSize.width == 185 + NotchGeometry.minimumPanelExtra.width)
        #expect(tiny.expandedSize.height == 32 + NotchGeometry.minimumPanelExtra.height)
    }

    @Test func windowIsCenteredAndPinnedToTheTop() {
        let frame = geometry().windowFrame(on: screen)
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY)
    }

    @Test func windowFitsBothStates() {
        for wing in [0, 72, 160] as [CGFloat] {
            let geometry = geometry(wing: wing)
            let frame = geometry.windowFrame(on: screen)
            #expect(frame.width >= geometry.collapsedSize.width)
            #expect(frame.width >= geometry.expandedSize.width)
            #expect(frame.height >= geometry.expandedSize.height)
        }
    }

    @Test func hoveringTheNotchOpensButTheWingsDoNot() {
        let trigger = geometry().openTriggerRect(on: screen)
        #expect(trigger.contains(CGPoint(x: screen.midX, y: screen.maxY - 5)))
        #expect(!trigger.contains(CGPoint(x: screen.midX + 185 / 2 + 30, y: screen.maxY - 5)))
        #expect(!trigger.contains(CGPoint(x: screen.midX, y: screen.maxY - 40)))
    }

    @Test func panelStaysOpenWithSmallSlackPastItsEdge() {
        let geometry = geometry()
        let rect = geometry.stayOpenRect(on: screen)
        let bottom = screen.maxY - geometry.expandedSize.height
        #expect(rect.contains(CGPoint(x: screen.midX, y: bottom - 3)))
        #expect(!rect.contains(CGPoint(x: screen.midX, y: bottom - 20)))
    }
}
