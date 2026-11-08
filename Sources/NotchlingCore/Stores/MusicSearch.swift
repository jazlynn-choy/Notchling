import Foundation

/// Search-as-you-type over the Music library, shown inside the music card.
///
/// Playing *any* song (not just ones in your library) would need Apple's MusicKit with a
/// developer token, or Spotify's Web API with a login. Neither is possible from a scripting
/// bridge, so songs outside the library go to Spotify's own search instead.
@MainActor
public final class MusicSearch: ObservableObject {
    @Published public var isOpen = false {
        didSet { if !isOpen { query = "" } }
    }
    @Published public var query = "" {
        didSet { if query != oldValue { scheduleSearch() } }
    }
    @Published public private(set) var results: [SongResult] = []
    @Published public private(set) var isSearching = false
    /// True once a search for the current query has finished, so the UI can say "no matches".
    @Published public private(set) var hasSearched = false
    public let canSearchSpotify: Bool

    /// Called after a song starts, so the now-playing card can refresh.
    public var onPlay: (() -> Void)?

    private let media: MediaProviding
    private let debounce: Duration
    private let limit: Int
    private var searchTask: Task<Void, Never>?

    public init(media: MediaProviding, debounce: Duration = .milliseconds(300), limit: Int = 8) {
        self.media = media
        self.debounce = debounce
        self.limit = limit
        self.canSearchSpotify = media.isSpotifyInstalled
    }

    public var trimmedQuery: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    public func play(_ song: SongResult) {
        let media = media
        Task {
            await media.play(song)
            isOpen = false
            onPlay?()
        }
    }

    public func searchSpotify() {
        let media = media, query = trimmedQuery
        guard !query.isEmpty else { return }
        Task { await media.openSpotifySearch(query) }
        isOpen = false
    }

    /// Waits until typing pauses, then searches. A newer keystroke cancels the older search,
    /// so a slow result for "ta" can never overwrite the results for "taylor".
    private func scheduleSearch() {
        searchTask?.cancel()
        let query = trimmedQuery
        hasSearched = false
        guard !query.isEmpty else {
            results = []
            isSearching = false
            return
        }
        let media = media, debounce = debounce, limit = limit
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.isSearching = true
            let found = await media.searchLibrary(query, limit: limit)
            guard !Task.isCancelled, let self else { return }
            results = found
            isSearching = false
            hasSearched = true
        }
    }

    /// Test hook: waits for the in-flight search.
    func settle() async { await searchTask?.value }
}
