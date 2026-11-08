import Foundation
import IOKit.ps
import Testing
@testable import NotchlingCore

@Suite("Provider parsing")
struct ProviderParsingTests {
    let sep = AppleScriptMediaProvider.separator

    @Test func parsesPlayingTrack() {
        let track = AppleScriptMediaProvider.parseStatus("playing\(sep)Espresso\(sep)Sabrina Carpenter\(sep)off", app: .spotify)
        #expect(track == Track(title: "Espresso", artist: "Sabrina Carpenter", app: .spotify, isPlaying: true))
    }

    @Test func parsesPausedTrack() {
        let track = AppleScriptMediaProvider.parseStatus("paused\(sep)Song\(sep)Artist\(sep)off", app: .music)
        #expect(track?.isPlaying == false)
    }

    @Test func titlesMayContainNewlinesAndPipes() {
        let track = AppleScriptMediaProvider.parseStatus("playing\(sep)A | B\nC\(sep)X\(sep)off", app: .music)
        #expect(track?.title == "A | B\nC")
    }

    @Test(arguments: ["stopped", "", "playing\(AppleScriptMediaProvider.separator)only-title", "garbage"])
    func rejectsUnusableOutput(_ output: String) {
        #expect(AppleScriptMediaProvider.parseStatus(output, app: .music) == nil)
    }

    @Test(arguments: [("off", RepeatMode.off), ("all", .all), ("one", .one), ("weird", .off)])
    func parsesRepeatMode(raw: String, expected: RepeatMode) {
        let track = AppleScriptMediaProvider.parseStatus("playing\(sep)S\(sep)A\(sep)\(raw)", app: .music)
        #expect(track?.repeatMode == expected)
    }

    @Test func parsesSearchResultsAndSkipsBrokenRecords() {
        let rs = AppleScriptMediaProvider.recordSeparator
        let output = "A1\(sep)Espresso\(sep)Sabrina Carpenter\(rs)broken\(rs)\(sep)No ID\(sep)X\(rs)B2\(sep)Juno\(sep)Sabrina Carpenter\(rs)"
        #expect(AppleScriptMediaProvider.parseSearchResults(output) == [
            SongResult(id: "A1", title: "Espresso", artist: "Sabrina Carpenter"),
            SongResult(id: "B2", title: "Juno", artist: "Sabrina Carpenter"),
        ])
        #expect(AppleScriptMediaProvider.parseSearchResults("").isEmpty)
    }

    @Test func spotifySearchURLIsFullyEncoded() {
        let url = AppleScriptMediaProvider.spotifySearchURL(for: "  AC/DC & \"Back\" ")
        #expect(url?.absoluteString == "spotify:search:AC%2FDC%20%26%20%22Back%22")
        #expect(AppleScriptMediaProvider.spotifySearchURL(for: "   ") == nil)
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
