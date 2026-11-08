import CoreGraphics
import Foundation
import Testing
@testable import NotchlingCore

@Suite("Stacked panel columns")
struct StackingTests {
    func layout(_ columns: [[WidgetKind]]) -> WidgetLayout {
        WidgetLayout(leftWing: [], rightWing: [], columns: columns)
    }

    @Test func columnsRoundTripThroughStorageAndOldLayoutsLoadUnstacked() {
        let original = layout([[.musicCard, .weatherCard], [.remindersCard]])
        #expect(original.panelColumns == [[.musicCard, .weatherCard], [.remindersCard]])
        #expect(WidgetLayout(storageValue: original.storageValue) == original)
        let old: [String: [String]] = ["panel": ["musicCard", "weatherCard"]]
        #expect(WidgetLayout(storageValue: old)?.panelColumns == [[.musicCard], [.weatherCard]])
    }

    @Test func weatherCanStackUnderMusic() {
        var l = layout([[.musicCard], [.remindersCard], [.weatherCard]])
        let result1 = l.drop(.weatherCard, at: .below(.musicCard))
        #expect(result1)
        #expect(l.panelColumns == [[.musicCard, .weatherCard], [.remindersCard]])
    }

    @Test func dropAboveAndIntoANewColumn() {
        var l = layout([[.musicCard, .weatherCard], [.remindersCard]])
        let result2 = l.drop(.remindersCard, at: .above(.musicCard))
        #expect(result2)
        #expect(l.panelColumns == [[.remindersCard, .musicCard, .weatherCard]])
        let result3 = l.drop(.weatherCard, at: .newColumn(at: 0))
        #expect(result3)
        #expect(l.panelColumns == [[.weatherCard], [.remindersCard, .musicCard]])
    }

    @Test func movingALoneCardRightAccountsForItsOwnColumnDisappearing() {
        var l = layout([[.musicCard], [.remindersCard], [.weatherCard]])
        let result101 = l.drop(.musicCard, at: .newColumn(at: 2))   // between reminders and weather
        #expect(result101)
        #expect(l.panelColumns == [[.remindersCard], [.musicCard], [.weatherCard]])
    }

    @Test func limitsAreEnforced() {
        var full = layout([[.musicCard, .weatherCard, .dayCard], [.remindersCard]])
        let result102 = full.drop(.remindersCard, at: .below(.musicCard))   // column already has 3
        #expect(!result102)
        var wide = layout([[.musicCard], [.remindersCard], [.weatherCard], [.dayCard], [.notesCard]])
        #expect(wide.panelColumns.count == WidgetLayout.maxColumns)   // 5th column dropped
        let result103 = wide.drop(.musicCard, at: .below(.musicCard))       // onto itself
        #expect(!result103)
    }

    @Test func removingATopCardPromotesTheOneBelow() {
        var l = layout([[.remindersCard], [.musicCard, .weatherCard]])
        l.remove(.musicCard, from: .panel)
        #expect(l.panelColumns == [[.remindersCard], [.weatherCard]])
    }

    @Test func addFillsColumnsThenStacks() {
        var l = layout([[.musicCard], [.remindersCard], [.weatherCard], [.dayCard]])
        l.add(.notesCard, to: .panel)
        #expect(l.panelColumns.count == 4)
        #expect(l.panelColumns[0] == [.musicCard, .notesCard])
    }

    @Test func setStackedTogglesWithTheCardAbove() {
        var l = layout([[.musicCard], [.weatherCard], [.remindersCard]])
        let result4 = l.setStacked(.weatherCard, true)
        #expect(result4)
        #expect(l.panelColumns == [[.musicCard, .weatherCard], [.remindersCard]])
        let result5 = l.setStacked(.weatherCard, false)
        #expect(result5)
        #expect(l.panelColumns == [[.musicCard], [.weatherCard], [.remindersCard]])
        let result104 = l.setStacked(.musicCard, true)   // nothing above the first card
        #expect(!result104)
    }

    @Test func reorderingInSettingsGivesTheMovedCardItsOwnColumn() {
        var l = layout([[.musicCard, .weatherCard], [.remindersCard]])
        l.move(.musicCard, in: .panel, by: 2)
        #expect(l.panelColumns == [[.weatherCard], [.remindersCard], [.musicCard]])
    }
}

@Suite("Panel frames, drop targets and the height divider")
struct PanelGeometryTests {
    let columns: [[WidgetKind]] = [[.musicCard, .weatherCard], [.remindersCard]]
    let size = CGSize(width: 410, height: 200)

    var frames: [[CGRect]] {
        PanelLayout.frames(columnWeights: [1, 1], heightWeights: [[1, 1], [1]], size: size, spacing: 10)
    }

    @Test func framesTileThePanel() {
        let f = frames
        #expect(f[0][0] == CGRect(x: 0, y: 0, width: 200, height: 96))
        #expect(f[0][1] == CGRect(x: 0, y: 104, width: 200, height: 96))
        #expect(f[1][0] == CGRect(x: 210, y: 0, width: 200, height: 200))
    }

    @Test(arguments: [
        (CGPoint(x: 100, y: 20), WidgetLayout.PanelDrop.above(.musicCard)),
        (CGPoint(x: 100, y: 70), .below(.musicCard)),
        (CGPoint(x: 100, y: 180), .below(.weatherCard)),
        (CGPoint(x: 10, y: 50), .newColumn(at: 0)),
        (CGPoint(x: 195, y: 50), .newColumn(at: 1)),
        (CGPoint(x: 205, y: 50), .newColumn(at: 1)),   // the gap between columns
        (CGPoint(x: 400, y: 50), .newColumn(at: 2)),
        (CGPoint(x: 300, y: 150), .below(.remindersCard)),
    ])
    func dropTargets(point: CGPoint, expected: WidgetLayout.PanelDrop) {
        #expect(PanelLayout.dropTarget(at: point, frames: frames, columns: columns, dragging: .dayCard) == expected)
    }

    @Test func droppingOnItselfDoesNothing() {
        #expect(PanelLayout.dropTarget(at: CGPoint(x: 300, y: 100), frames: frames, columns: columns,
                                       dragging: .remindersCard) == nil)
    }

    @Test func dividerFollowsThePointerAndKeepsTheTotal() {
        let (top, bottom) = PanelLayout.resizePair(weights: (1, 1), heights: (96, 96), delta: 24)
        #expect(abs(top + bottom - 2) < 1e-9)
        #expect(abs(top / (top + bottom) * 192 - 120) < 1e-9)   // top card is now 120 of 192 pt
    }

    @Test func dividerStopsAtTheMinimumHeight() {
        let (top, _) = PanelLayout.resizePair(weights: (1, 1), heights: (96, 96), delta: -500)
        #expect(abs(top / 2 * 192 - PanelLayout.minimumCardHeight) < 1e-9)
    }
}
