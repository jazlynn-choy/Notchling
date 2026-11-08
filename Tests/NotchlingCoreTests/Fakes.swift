import Foundation
@testable import NotchlingCore

/// In-memory stand-in for Apple Reminders. `@unchecked Sendable` is fine here:
/// tests drive it from the main actor only.
final class FakeRemindersProvider: RemindersProviding, @unchecked Sendable {
    var access: AccessStatus = .granted
    var grantOnRequest = true
    var reminderLists = [ReminderList(id: "home", title: "Home"), ReminderList(id: "work", title: "Work")]
    var reminders: [String: [Todo]] = [:]   // listID ("" = default) -> items
    var completedIDs: [String] = []
    var failNextComplete = false
    var failFetch = false
    private var onChange: (@Sendable () -> Void)?

    func authorizationStatus() -> AccessStatus { access }

    func requestAccess() async -> Bool {
        access = grantOnRequest ? .granted : .denied
        return grantOnRequest
    }

    func lists() -> [ReminderList] { reminderLists }

    func incompleteReminders(in listID: String?) async throws -> [Todo] {
        if failFetch { throw RemindersError.noList }
        return reminders[listID ?? "", default: []]
    }

    func add(title: String, to listID: String?) throws {
        reminders[listID ?? "", default: []].append(Todo(id: UUID().uuidString, title: title, created: Date()))
    }

    func complete(id: String) throws {
        if failNextComplete {
            failNextComplete = false
            throw RemindersError.notFound
        }
        completedIDs.append(id)
        for key in reminders.keys { reminders[key]?.removeAll { $0.id == id } }
    }

    func observeChanges(_ onChange: @escaping @Sendable () -> Void) { self.onChange = onChange }

    /// Simulates an edit made in the Reminders app or on another device.
    func simulateExternalChange() { onChange?() }
}

/// Records what the app asked the player to do. Tests drive it from the main actor only.
final class FakeMediaProvider: MediaProviding, @unchecked Sendable {
    var track: Track?
    var library: [SongResult] = []
    var searches: [String] = []
    var played: [SongResult] = []
    var repeatRequests: [RepeatMode] = []
    var spotifySearches: [String] = []
    var isSpotifyInstalled = true

    func nowPlaying() async -> Track? { track }
    var sent: [MediaCommand] = []
    var resumed: [MediaApp] = []
    func send(_ command: MediaCommand, to app: MediaApp) async { sent.append(command) }
    func resume(_ app: MediaApp) async { resumed.append(app) }
    func setRepeat(_ mode: RepeatMode, for app: MediaApp) async { repeatRequests.append(mode) }

    func searchLibrary(_ query: String, limit: Int) async -> [SongResult] {
        searches.append(query)
        let matches = library.filter { $0.title.localizedCaseInsensitiveContains(query) }
        return Array(matches.prefix(limit))
    }

    func play(_ song: SongResult) async { played.append(song) }
    func openSpotifySearch(_ query: String) async { spotifySearches.append(query) }
}

struct FakePowerProvider: PowerProviding {
    func read() -> PowerStatus? { nil }
}

final class FakeCalendarProvider: CalendarProviding, @unchecked Sendable {
    var access: AccessStatus = .granted
    var events: [CalendarEvent] = []
    var requestedRanges: [(Date, Date)] = []

    func authorizationStatus() -> AccessStatus { access }
    func requestAccess() async -> Bool {
        access = .granted
        return true
    }
    func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        requestedRanges.append((start, end))
        return events.filter { $0.end > start && $0.start < end }
    }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {}
}

struct FakeLoginItem: LoginItemManaging {
    var isEnabled = false
    var error: Error?

    func setEnabled(_ enabled: Bool) throws {
        if let error { throw error }
    }
}

struct FakeError: LocalizedError {
    var errorDescription: String? { "Not allowed" }
}

/// A fresh, isolated UserDefaults per test so tests never touch the real app's settings.
func makeIsolatedDefaults(_ name: String = #function) -> UserDefaults {
    let suite = "notchling.tests.\(name).\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// Canned HTTP responses. Records every request so tests can check what was sent.
final class FakeHTTPClient: HTTPClient, @unchecked Sendable {
    var handler: (URLRequest) throws -> (Int, String) = { _ in (404, "") }
    private(set) var requests: [URLRequest] = []
    private let lock = NSLock()

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lock.withLock { requests.append(request) }
        let (status, body) = try handler(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (Data(body.utf8), response)
    }

    func formBody(of request: URLRequest) -> [String: String] {
        let text = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        return Dictionary(uniqueKeysWithValues: text.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1).map(String.init)
            return (parts[0], (parts.count > 1 ? parts[1] : "").removingPercentEncoding ?? "")
        })
    }
}

final class InMemorySecretStore: SecretStore, @unchecked Sendable {
    var values: [String: String] = [:]
    func read(_ key: String) -> String? { values[key] }
    func write(_ value: String, for key: String) { values[key] = value }
    func delete(_ key: String) { values[key] = nil }
}

/// Plays the browser: once the app "opens" the authorize URL, redirects back with its state.
final class FakeAuthCallback: AuthCallbackReceiving, @unchecked Sendable {
    var authorizeURL: URL?
    var reply: (_ state: String) -> String = { "/callback?code=the-code&state=\($0)" }

    func waitForCallback(port: UInt16, path: String, timeout: Duration) async throws -> URL {
        while authorizeURL == nil { try await Task.sleep(for: .milliseconds(5)) }
        let items = URLComponents(url: authorizeURL!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let state = items.first { $0.name == "state" }?.value ?? ""
        return URL(string: "http://127.0.0.1:\(port)\(reply(state))")!
    }
}

final class FakeWeatherProvider: WeatherProviding, @unchecked Sendable {
    var places: [Place] = []
    var nextReport: WeatherReport?
    var fail = false
    private(set) var reportRequests = 0

    func searchPlaces(_ query: String) async throws -> [Place] { places }
    func report(for place: Place, unit: TemperatureUnit) async throws -> WeatherReport {
        reportRequests += 1
        if fail { throw URLError(.notConnectedToInternet) }
        return nextReport!
    }
}

/// Waits until `condition` holds (checking every 5 ms, up to `timeout`), for effects that
/// happen in a background Task. Unlike a fixed sleep, it's fast when things are fast and
/// doesn't fail just because a CI machine is busy.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(5))
    }
}
