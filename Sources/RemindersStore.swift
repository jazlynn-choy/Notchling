import Foundation
import EventKit

/// One row in the notch's to-do list, backed by an Apple Reminders item.
struct Todo: Identifiable, Equatable {
    let id: String          // EKReminder.calendarItemIdentifier
    var text: String
    var done: Bool
    var due: Date?
}

struct ReminderList: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Two-way sync with Apple Reminders through EventKit.
/// Anything added or ticked off here shows up in Reminders (and on your iPhone via iCloud), and vice versa.
final class RemindersStore: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var items: [Todo] = []
    @Published private(set) var lists: [ReminderList] = []
    @Published private(set) var access: Access = .unknown
    @Published var draft = ""   // text in the "add a to-do" field

    private let store = EKEventStore()
    private let settings: NotchSettings
    private var pendingCompletion: [String: DispatchWorkItem] = [:]

    init(settings: NotchSettings) {
        self.settings = settings
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            self?.reload()
        }
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess: access = .granted; reload()
        case .denied, .restricted, .writeOnly: access = .denied
        default: break
        }
    }

    func requestAccess() {
        store.requestFullAccessToReminders { granted, _ in
            DispatchQueue.main.async {
                self.access = granted ? .granted : .denied
                self.reload()
            }
        }
    }

    /// The Reminders list chosen in Settings, or the user's default list.
    private var targetCalendar: EKCalendar? {
        if !settings.reminderListID.isEmpty, let c = store.calendar(withIdentifier: settings.reminderListID) { return c }
        return store.defaultCalendarForNewReminders()
    }

    func reload() {
        guard access == .granted else { return }
        lists = store.calendars(for: .reminder)
            .map { ReminderList(id: $0.calendarIdentifier, title: $0.title) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        let cals = targetCalendar.map { [$0] }
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: cals)
        store.fetchReminders(matching: predicate) { reminders in
            let todos = (reminders ?? [])
                .sorted { a, b in
                    let da = a.dueDateComponents?.date ?? .distantFuture
                    let db = b.dueDateComponents?.date ?? .distantFuture
                    if da != db { return da < db }
                    return (a.creationDate ?? .distantPast) < (b.creationDate ?? .distantPast)
                }
                .map { Todo(id: $0.calendarItemIdentifier, text: $0.title ?? "", done: false,
                            due: $0.dueDateComponents.flatMap { Calendar.current.date(from: $0) }) }
            DispatchQueue.main.async {
                // Keep rows that are mid "tick" animation so they don't vanish instantly.
                let ticking = self.items.filter { self.pendingCompletion[$0.id] != nil }
                self.items = ticking + todos.filter { t in !ticking.contains { $0.id == t.id } }
            }
        }
    }

    func add(_ text: String) {
        let title = text.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, access == .granted, let cal = targetCalendar else { return }
        let r = EKReminder(eventStore: store)
        r.title = title
        r.calendar = cal
        try? store.save(r, commit: true)
        reload()
    }

    /// Ticking shows a check for a moment, then marks the reminder complete in Reminders.
    /// Ticking again within that moment cancels it.
    func toggle(_ todo: Todo) {
        guard let i = items.firstIndex(of: todo) else { return }
        if let work = pendingCompletion.removeValue(forKey: todo.id) {
            work.cancel()
            items[i].done = false
            return
        }
        items[i].done = true
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingCompletion[todo.id] = nil
            if let r = self.store.calendarItem(withIdentifier: todo.id) as? EKReminder {
                r.isCompleted = true
                try? self.store.save(r, commit: true)
            }
            self.items.removeAll { $0.id == todo.id }
        }
        pendingCompletion[todo.id] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    var openCount: Int { items.filter { !$0.done }.count }
}
