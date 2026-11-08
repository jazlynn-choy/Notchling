import EventKit

/// Apple Reminders through EventKit.
///
/// `@unchecked Sendable`: `EKEventStore` isn't annotated for Swift concurrency, but Apple
/// documents it as safe to use from multiple threads. The only mutable state here is
/// `observer`, which is written once at startup.
public final class EventKitRemindersProvider: RemindersProviding, @unchecked Sendable {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    public init() {}

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func authorizationStatus() -> AccessStatus {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    public func lists() -> [ReminderList] {
        store.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private func calendar(for listID: String?) -> EKCalendar? {
        if let listID, let calendar = store.calendar(withIdentifier: listID) { return calendar }
        return store.defaultCalendarForNewReminders()
    }

    public func incompleteReminders(in listID: String?) async throws -> [Todo] {
        let calendars = calendar(for: listID).map { [$0] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil,
                                                              calendars: calendars)
        return await withCheckedContinuation { continuation in
            // EventKit calls back on a background queue; convert to Sendable values right here.
            store.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: (reminders ?? []).map(Self.todo(from:)))
            }
        }
    }

    public func add(title: String, to listID: String?) throws {
        guard let calendar = calendar(for: listID) else { throw RemindersError.noList }
        let reminder = EKReminder(eventStore: store)
        reminder.title = title
        reminder.calendar = calendar
        try store.save(reminder, commit: true)
    }

    public func complete(id: String) throws {
        guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else {
            throw RemindersError.notFound
        }
        reminder.isCompleted = true
        try store.save(reminder, commit: true)
    }

    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                          queue: nil) { _ in onChange() }
    }

    private static func todo(from reminder: EKReminder) -> Todo {
        Todo(id: reminder.calendarItemIdentifier,
             title: reminder.title ?? "",
             due: reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) },
             created: reminder.creationDate)
    }
}
