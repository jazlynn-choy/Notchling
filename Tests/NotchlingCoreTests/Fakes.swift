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
    func send(_ command: MediaCommand, to app: MediaApp) async {}
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
