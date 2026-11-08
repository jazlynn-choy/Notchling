import Foundation
import Testing
@testable import NotchlingCore

@MainActor
@Suite("Music: loop and search")
struct MusicTests {
    @Test func loopCyclesThroughWhatEachPlayerSupports() {
        #expect(RepeatMode.off.next(for: .music) == .all)
        #expect(RepeatMode.all.next(for: .music) == .one)
        #expect(RepeatMode.one.next(for: .music) == .off)
        #expect(RepeatMode.off.next(for: .spotify) == .all)
        #expect(RepeatMode.all.next(for: .spotify) == .off)
    }

    @Test func cycleRepeatUpdatesRightAwayAndTellsThePlayer() async {
        let media = FakeMediaProvider()
        media.track = Track(title: "S", artist: "A", app: .music, isPlaying: true)
        let model = NotchModel(notchSize: .zero, media: media, power: FakePowerProvider())
        await model.refreshMedia()
        model.cycleRepeat()
        #expect(model.track?.repeatMode == .all)
        try? await Task.sleep(for: .milliseconds(50))
        #expect(media.repeatRequests == [.all])
    }

    @Test func cycleRepeatDoesNothingWithoutATrack() {
        let media = FakeMediaProvider()
        let model = NotchModel(notchSize: .zero, media: media, power: FakePowerProvider())
        model.cycleRepeat()
        #expect(model.track == nil)
    }

    func makeSearch(_ media: FakeMediaProvider) -> MusicSearch {
        media.library = [SongResult(id: "1", title: "Espresso", artist: "Sabrina Carpenter"),
                         SongResult(id: "2", title: "Espresso Macchiato", artist: "Tommy Cash"),
                         SongResult(id: "3", title: "Juno", artist: "Sabrina Carpenter")]
        return MusicSearch(media: media, debounce: .milliseconds(20))
    }

    @Test func typingQuicklyOnlySearchesTheFinalQuery() async {
        let media = FakeMediaProvider()
        let search = makeSearch(media)
        search.query = "e"
        search.query = "es"
        search.query = "espresso"
        await search.settle()
        #expect(media.searches == ["espresso"])
        #expect(search.results.map(\.id) == ["1", "2"])
        #expect(search.hasSearched)
    }

    @Test func clearingTheQueryClearsResultsWithoutSearching() async {
        let media = FakeMediaProvider()
        let search = makeSearch(media)
        search.query = "juno"
        await search.settle()
        search.query = "   "
        await search.settle()
        #expect(search.results.isEmpty)
        #expect(!search.hasSearched)
        #expect(media.searches == ["juno"])
    }

    @Test func playingASongClosesSearch() async throws {
        let media = FakeMediaProvider()
        let search = makeSearch(media)
        var played = false
        search.onPlay = { played = true }
        search.isOpen = true
        search.play(media.library[2])
        try await Task.sleep(for: .milliseconds(50))
        #expect(media.played.map(\.id) == ["3"])
        #expect(!search.isOpen)
        #expect(played)
    }

    @Test func spotifySearchHandsOffTheTrimmedQuery() async throws {
        let media = FakeMediaProvider()
        let search = makeSearch(media)
        search.isOpen = true
        search.query = "  not in my library "
        search.searchSpotify()
        try await Task.sleep(for: .milliseconds(50))
        #expect(media.spotifySearches == ["not in my library"])
        #expect(!search.isOpen)
    }

    @Test func closingSearchResetsIt() {
        let search = makeSearch(FakeMediaProvider())
        search.isOpen = true
        search.query = "x"
        search.isOpen = false
        #expect(search.query.isEmpty)
    }
}
