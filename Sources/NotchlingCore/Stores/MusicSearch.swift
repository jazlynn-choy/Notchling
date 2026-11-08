import Foundation

/// Search-as-you-type inside the music card, over Spotify's catalog (when signed in) or the
/// Music library. Results play in the matching app.
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
    /// Why the last search failed, e.g. "Connect Spotify in Settings…".
    @Published public private(set) var errorMessage: String?
    /// Where searches go. Changing it re-runs the current query.
    @Published public var source: MediaApp {
        didSet { if source != oldValue { scheduleSearch() } }
    }
    public let canSearchSpotify: Bool

    /// Called after a song starts, so the now-playing card can refresh.
    public var onPlay: (() -> Void)?

    private let media: MediaProviding
    private var catalogs: [MediaApp: SongCatalog]
    private let debounce: Duration
    private let limit: Int
    private var searchTask: Task<Void, Never>?

    public init(media: MediaProviding, catalogs: [MediaApp: SongCatalog]? = nil, source: MediaApp = .music,
                debounce: Duration = .milliseconds(300), limit: Int = 8) {
        self.media = media
        self.catalogs = catalogs ?? [.music: MusicLibraryCatalog(media: media)]
        self.source = source
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
        errorMessage = nil
        guard !query.isEmpty, let catalog = catalogs[source] else {
            results = []
            isSearching = false
            return
        }
        let debounce = debounce, limit = limit
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.isSearching = true
            let outcome: Result<[SongResult], Error>
            do { outcome = .success(try await catalog.search(query, limit: limit)) } catch { outcome = .failure(error) }
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case .success(let found):
                results = found
                hasSearched = true
            case .failure(let error):
                results = []
                errorMessage = error.localizedDescription
            }
            isSearching = false
        }
    }

    /// Test hook: waits for the in-flight search.
    func settle() async { await searchTask?.value }
}
