import Foundation

// Every system service the app touches sits behind one of these protocols.
// The real implementations live next to this file; tests swap in fakes.

public protocol RemindersProviding: Sendable {
    func authorizationStatus() -> AccessStatus
    func requestAccess() async -> Bool
    func lists() -> [ReminderList]
    /// `listID == nil` means the user's default Reminders list.
    func incompleteReminders(in listID: String?) async throws -> [Todo]
    func add(title: String, to listID: String?) throws
    func complete(id: String) throws
    /// Called (on any thread) whenever Reminders changes outside the app, e.g. from an iPhone.
    func observeChanges(_ onChange: @escaping @Sendable () -> Void)
}

public protocol MediaProviding: Sendable {
    /// The playing track, or a paused one if nothing plays. Never launches a player.
    func nowPlaying() async -> Track?
    func send(_ command: MediaCommand, to app: MediaApp) async
    func setRepeat(_ mode: RepeatMode, for app: MediaApp) async
    /// Songs in the user's Music library whose title, artist or album match `query`.
    func searchLibrary(_ query: String, limit: Int) async -> [SongResult]
    func play(_ song: SongResult) async
    /// Opens Spotify's own search, for songs that aren't in the Music library.
    func openSpotifySearch(_ query: String) async
    var isSpotifyInstalled: Bool { get }
}

public protocol CalendarProviding: Sendable {
    func authorizationStatus() -> AccessStatus
    func requestAccess() async -> Bool
    /// Events overlapping `start..<end`, across every calendar the user has.
    func events(from start: Date, to end: Date) async -> [CalendarEvent]
    func observeChanges(_ onChange: @escaping @Sendable () -> Void)
}

/// Somewhere songs can be searched: the Music library, or Spotify's catalog.
public protocol SongCatalog: Sendable {
    func search(_ query: String, limit: Int) async throws -> [SongResult]
}

/// Searches the local Music library through `MediaProviding`.
public struct MusicLibraryCatalog: SongCatalog {
    let media: MediaProviding
    public init(media: MediaProviding) { self.media = media }
    public func search(_ query: String, limit: Int) async throws -> [SongResult] {
        await media.searchLibrary(query, limit: limit)
    }
}

/// HTTP, behind a protocol so network code is tested with canned responses.
public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionHTTPClient: HTTPClient {
    public init() {}
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        return (data, http)
    }
}

/// Small secrets (tokens) that must not go in UserDefaults.
public protocol SecretStore: Sendable {
    func read(_ key: String) -> String?
    func write(_ value: String, for key: String)
    func delete(_ key: String)
}

/// Waits for the browser to come back to the app after signing in.
public protocol AuthCallbackReceiving: Sendable {
    /// Listens on `127.0.0.1:port` and returns the first request to `path`, as a full URL.
    func waitForCallback(port: UInt16, path: String, timeout: Duration) async throws -> URL
}

public protocol PowerProviding: Sendable {
    func read() -> PowerStatus?
}

public protocol LoginItemManaging: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

public enum RemindersError: LocalizedError, Equatable {
    case noList
    case notFound

    public var errorDescription: String? {
        switch self {
        case .noList: return "There's no Reminders list to add to."
        case .notFound: return "That reminder no longer exists."
        }
    }
}
