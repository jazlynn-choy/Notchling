import Foundation
import Testing
@testable import NotchlingCore

@Suite("WidgetLayout")
struct WidgetLayoutTests {
    @Test func everyWidgetFitsExactlyOneKindOfSlot() {
        for kind in WidgetKind.allCases {
            #expect(kind.fits(.leftWing) == kind.fits(.rightWing), "\(kind) treats the wings differently")
            #expect(kind.fits(.leftWing) != kind.fits(.panel), "\(kind) must be a wing or a panel widget")
        }
    }

    @Test func initDropsMisplacedAndDuplicateWidgets() {
        let layout = WidgetLayout(leftWing: [.time, .musicCard, .time],
                                  rightWing: [],
                                  panel: [.battery, .remindersCard, .remindersCard])
        #expect(layout.leftWing == [.time])
        #expect(layout.panel == [.remindersCard])
    }

    @Test func slotsAreCappedAtCapacity() {
        let layout = WidgetLayout(leftWing: [.time, .date, .battery, .reminderCount, .nowPlaying],
                                  rightWing: [], panel: [])
        #expect(layout.leftWing.count == WidgetSlot.leftWing.capacity)
        #expect(layout.addable(to: .leftWing).isEmpty)
    }

    @Test func addOnlyAcceptsWidgetsThatFitAndArentThereYet() {
        var layout = WidgetLayout(leftWing: [], rightWing: [.time], panel: [])
        layout.add(.time, to: .rightWing)        // duplicate
        layout.add(.musicCard, to: .rightWing)   // wrong slot
        layout.add(.battery, to: .rightWing)
        #expect(layout.rightWing == [.time, .battery])
    }

    @Test func theSameWidgetCanSitInBothWings() {
        var layout = WidgetLayout(leftWing: [.time], rightWing: [], panel: [])
        layout.add(.time, to: .rightWing)
        #expect(layout.rightWing == [.time])
    }

    @Test(arguments: [(-1, [WidgetKind.battery, .time, .reminderCount]),
                      (1, [WidgetKind.time, .reminderCount, .battery]),
                      (-5, [WidgetKind.battery, .time, .reminderCount]),
                      (5, [WidgetKind.time, .reminderCount, .battery])])
    func moveShiftsWithinBounds(offset: Int, expected: [WidgetKind]) {
        var layout = WidgetLayout(leftWing: [], rightWing: [.time, .battery, .reminderCount], panel: [])
        layout.move(.battery, in: .rightWing, by: offset)
        #expect(layout.rightWing == expected)
    }

    @Test func removeTakesOnlyThatSlotsCopy() {
        var layout = WidgetLayout(leftWing: [.time], rightWing: [.time], panel: [])
        layout.remove(.time, from: .leftWing)
        #expect(layout.leftWing.isEmpty)
        #expect(layout.rightWing == [.time])
    }

    @Test func storageRoundTrips() {
        let layout = WidgetLayout(leftWing: [.date], rightWing: [.battery, .time], panel: [.dayCard, .remindersCard])
        #expect(WidgetLayout(storageValue: layout.storageValue) == layout)
    }

    @Test func unknownStoredWidgetsAreSkippedNotFatal() {
        let stored: [String: [String]] = ["leftWing": ["date", "weather-from-v9"], "panel": ["remindersCard"]]
        let layout = WidgetLayout(storageValue: stored)
        #expect(layout == WidgetLayout(leftWing: [.date], rightWing: [], panel: [.remindersCard]))
    }

    @Test func corruptStorageIsRejected() {
        #expect(WidgetLayout(storageValue: "not a layout") == nil)
        #expect(WidgetLayout(storageValue: nil) == nil)
    }

    @Test func freshInstallHasNothingToMigrate() {
        #expect(WidgetLayout.migrating(from: makeIsolatedDefaults()) == nil)
    }

    @Test func defaultLayoutPollsMediaButCanTurnItOff() {
        #expect(WidgetLayout.default.allWidgets.contains { $0.usesMedia })
        let quiet = WidgetLayout(leftWing: [.date], rightWing: [.time], panel: [.remindersCard])
        #expect(!quiet.allWidgets.contains { $0.usesMedia })
    }
}
