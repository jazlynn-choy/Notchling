import Foundation
import NotchlingCore

// Demo data sources. Each stands in for a real system service, through the same protocols
// the app's providers implement, so the views can't tell the difference.

final class DemoMedia: MediaProviding, @unchecked Sendable {
    var track: Track? = Track(title: "Espresso", artist: "Sabrina Carpenter", app: .spotify, isPlaying: true)
    func nowPlaying() async -> Track? { track }
    func send(_ command: MediaCommand, to app: MediaApp) async {}
    func resume(_ app: MediaApp) async {}
    func setRepeat(_ mode: RepeatMode, for app: MediaApp) async {}
    func searchLibrary(_ query: String, limit: Int) async -> [SongResult] { [] }
    func play(_ song: SongResult) async {}
    func openSpotifySearch(_ query: String) async {}
    var isSpotifyInstalled: Bool { true }
}

struct DemoPower: PowerProviding {
    func read() -> PowerStatus? { PowerStatus(level: 82, isCharging: false) }
}

struct DemoLoginItem: LoginItemManaging {
    var isEnabled: Bool { false }
    func setEnabled(_ enabled: Bool) throws {}
}

final class DemoReminders: RemindersProviding, @unchecked Sendable {
    let now: Date
    init(now: Date) { self.now = now }
    func authorizationStatus() -> AccessStatus { .granted }
    func requestAccess() async -> Bool { true }
    func lists() -> [ReminderList] { [] }
    func incompleteReminders(in listID: String?) async throws -> [Todo] {
        [Todo(id: "1", title: "Submit internship application", due: now, created: now),
         Todo(id: "2", title: "Physics problem set", due: now.addingTimeInterval(86_400), created: now),
         Todo(id: "3", title: "Record the Notchling demo", created: now),
         Todo(id: "4", title: "Buy a birthday gift", created: now)]
    }
    func add(title: String, to listID: String?) throws {}
    func complete(id: String) throws {}
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {}
}

struct DemoCalendar: CalendarProviding {
    func authorizationStatus() -> AccessStatus { .granted }
    func requestAccess() async -> Bool { true }
    func events(from start: Date, to end: Date) async -> [CalendarEvent] { [] }
    func observeChanges(_ onChange: @escaping @Sendable () -> Void) {}
}

struct DemoWeather: WeatherProviding {
    func searchPlaces(_ query: String) async throws -> [Place] { [] }
    func report(for place: Place, unit: TemperatureUnit) async throws -> WeatherReport {
        WeatherReport(temperature: 24, high: 27, low: 19, condition: .partlyCloudy, isDay: true, fetchedAt: Date())
    }
}

final class DemoAgents: AgentEventSource, @unchecked Sendable {
    var events: [(event: AgentEvent, date: Date)] = []
    func latestEvents() -> [(event: AgentEvent, date: Date)] { events }
    func remove(sessionID: String) {}
}

final class DemoApprovals: ApprovalChannel, @unchecked Sendable {
    var files: [(id: String, data: Data, date: Date)] = []
    func pending() -> [(id: String, data: Data, date: Date)] { files }
    func answer(_ id: String, with decision: ApprovalDecision) -> Bool { true }
    func setEnabled(_ enabled: Bool, waitSeconds: Int) {}
}
