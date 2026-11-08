import Foundation
import Testing
@testable import NotchlingCore

@MainActor
@Suite("NotchSettings")
struct NotchSettingsTests {
    @Test func freshInstallUsesDefaults() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem())
        #expect(settings.wingWidth == NotchSettings.defaultSizes.wing)
        #expect(settings.widgets == .default)
        #expect(settings.selectedListID == nil)
    }

    @Test func changesPersistAcrossLaunches() {
        let defaults = makeIsolatedDefaults()
        let first = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        first.wingWidth = 100
        first.widgets.remove(.time, from: .rightWing)
        first.widgets.add(.dayCard, to: .panel)
        first.reminderListID = "work"

        let second = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(second.wingWidth == 100)
        #expect(!second.widgets.rightWing.contains(.time))
        #expect(second.widgets.panel == [.musicCard, .remindersCard, .dayCard])
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

    @Test func upgradeFromV01TogglesKeepsTheUsersChoices() {
        let defaults = makeIsolatedDefaults()
        defaults.set("date", forKey: "leftWing")
        defaults.set(false, forKey: "showTime")
        defaults.set(false, forKey: "showMusicCard")

        let settings = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(settings.widgets.leftWing == [.date])
        #expect(settings.widgets.rightWing == [.reminderCount, .battery])
        #expect(settings.widgets.panel == [.remindersCard])
        // Old keys are gone and the result is saved, so migration runs once.
        #expect(defaults.object(forKey: "leftWing") == nil)
        #expect(defaults.object(forKey: NotchSettings.Key.widgetLayout) != nil)
    }

    @Test func savedLayoutWinsOverLegacyKeys() {
        let defaults = makeIsolatedDefaults()
        defaults.set(["leftWing": ["time"], "rightWing": [], "panel": ["dayCard"]],
                     forKey: NotchSettings.Key.widgetLayout)
        defaults.set("date", forKey: "leftWing")
        let settings = NotchSettings(defaults: defaults, loginItem: FakeLoginItem())
        #expect(settings.widgets.leftWing == [.time])
        #expect(settings.widgets.panel == [.dayCard])
    }

    @Test func resetWidgetsRestoresDefault() {
        let settings = NotchSettings(defaults: makeIsolatedDefaults(), loginItem: FakeLoginItem())
        settings.widgets.remove(.remindersCard, from: .panel)
        settings.resetWidgets()
        #expect(settings.widgets == .default)
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
