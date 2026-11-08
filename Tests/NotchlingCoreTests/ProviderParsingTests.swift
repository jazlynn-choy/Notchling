import Foundation
import IOKit.ps
import Testing
@testable import NotchlingCore

@Suite("Provider parsing")
struct ProviderParsingTests {
    let sep = AppleScriptMediaProvider.separator

    @Test func parsesPlayingTrack() {
        let track = AppleScriptMediaProvider.parseStatus("playing\(sep)Espresso\(sep)Sabrina Carpenter", app: .spotify)
        #expect(track == Track(title: "Espresso", artist: "Sabrina Carpenter", app: .spotify, isPlaying: true))
    }

    @Test func parsesPausedTrack() {
        let track = AppleScriptMediaProvider.parseStatus("paused\(sep)Song\(sep)Artist", app: .music)
        #expect(track?.isPlaying == false)
    }

    @Test func titlesMayContainNewlinesAndPipes() {
        let track = AppleScriptMediaProvider.parseStatus("playing\(sep)A | B\nC\(sep)X", app: .music)
        #expect(track?.title == "A | B\nC")
    }

    @Test(arguments: ["stopped", "", "playing\(AppleScriptMediaProvider.separator)only-title", "garbage"])
    func rejectsUnusableOutput(_ output: String) {
        #expect(AppleScriptMediaProvider.parseStatus(output, app: .music) == nil)
    }

    @Test func powerStatusFromIOKitDictionary() {
        let status = IOKitPowerProvider.status(from: [
            kIOPSCurrentCapacityKey: 45, kIOPSMaxCapacityKey: 60,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        ])
        #expect(status == PowerStatus(level: 75, isCharging: true))
    }

    @Test func powerStatusOnBattery() {
        let status = IOKitPowerProvider.status(from: [
            kIOPSCurrentCapacityKey: 100, kIOPSMaxCapacityKey: 100,
            kIOPSPowerSourceStateKey: kIOPSBatteryPowerValue,
        ])
        #expect(status == PowerStatus(level: 100, isCharging: false))
    }

    @Test func powerStatusRejectsMissingOrZeroCapacity() {
        #expect(IOKitPowerProvider.status(from: [:]) == nil)
        #expect(IOKitPowerProvider.status(from: [kIOPSCurrentCapacityKey: 5, kIOPSMaxCapacityKey: 0]) == nil)
    }
}
