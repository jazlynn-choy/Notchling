import Foundation
import Testing
@testable import NotchlingCore

@MainActor
@Suite("NotchSettings")
struct NotchSettingsTests {
    @Test func freshInstallUsesDefaults() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem())
        #expect(settings.wingWidth == NotchSettings.defaultSizes.wing)
        #expect(settings.leftWing == .musicOrDate)
        #expect(settings.showBattery)
        #expect(settings.selectedListID == nil)
    }

    @Test func changesPersistAcrossLaunches() {
        let defaults = makeIsolatedDefaults()
        let first = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        first.wingWidth = 100
        first.leftWing = .date
        first.showTime = false
        first.reminderListID = "work"

        let second = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(second.wingWidth == 100)
        #expect(second.leftWing == .date)
        #expect(!second.showTime)
        #expect(second.selectedListID == "work")
    }

    @Test func outOfRangeStoredValuesAreClamped() {
        let defaults = makeIsolatedDefaults()
        defaults.set(9999.0, forKey: NotchSettings.Key.wingWidth)
        defaults.set(-5.0, forKey: NotchSettings.Key.panelHeight)
        let settings = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(settings.wingWidth == NotchSettings.wingRange.upperBound)
        #expect(settings.panelHeight == NotchSettings.panelHeightRange.lowerBound)
    }

    @Test func unknownLeftWingValueFallsBack() {
        let defaults = makeIsolatedDefaults()
        defaults.set("removed-option", forKey: NotchSettings.Key.leftWing)
        #expect(NotchSettings(defaults: defaults, loginItem: FakeLoginItem()).leftWing == .musicOrDate)
    }

    @Test func resetSizesRestoresDefaults() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem())
        settings.wingWidth = 10
        settings.panelWidth = 600
        settings.resetSizes()
        #expect(settings.wingWidth == NotchSettings.defaultSizes.wing)
        #expect(settings.panelWidth == NotchSettings.defaultSizes.panelWidth)
    }

    @Test func failedLoginItemChangeIsReportedAndRolledBack() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(),
                                     loginItem: FakeLoginItem(isEnabled: false, error: FakeError()))
        settings.launchAtLogin = true
        #expect(settings.loginItemError == "Not allowed")
        #expect(!settings.launchAtLogin)
    }

    @Test func geometryReflectsSettings() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem())
        settings.wingWidth = 50
        let geometry = settings.geometry(notchSize: CGSize(width: 185, height: 32))
        #expect(geometry.collapsedSize.width == 285)
    }
}
