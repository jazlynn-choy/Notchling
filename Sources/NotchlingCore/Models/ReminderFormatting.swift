import Foundation

public enum ReminderOrdering {
    /// Soonest due date first; undated reminders last, oldest first.
    public static func sorted(_ todos: [Todo]) -> [Todo] {
        todos.sorted { lhs, rhs in
            let lhsDue = lhs.due ?? .distantFuture
            let rhsDue = rhs.due ?? .distantFuture
            if lhsDue != rhsDue { return lhsDue < rhsDue }
            return (lhs.created ?? .distantPast) < (rhs.created ?? .distantPast)
        }
    }
}

/// The short label shown next to a reminder ("Today", "Tomorrow", "Nov 12").
public struct DueDateLabel: Equatable, Sendable {
    public let text: String
    public let isOverdue: Bool

    public init(text: String, isOverdue: Bool) {
        self.text = text
        self.isOverdue = isOverdue
    }

    /// `now`, `calendar` and `locale` are injectable so tests don't depend on the clock or the Mac's region.
    public static func make(for due: Date, now: Date = Date(),
                            calendar: Calendar = .current, locale: Locale = .current) -> DueDateLabel {
        let isOverdue = due < calendar.startOfDay(for: now)
        let relative: [(offset: Int, text: String)] = [(0, "Today"), (1, "Tomorrow"), (-1, "Yesterday")]
        for (offset, text) in relative {
            if let day = calendar.date(byAdding: .day, value: offset, to: now),
               calendar.isDate(due, inSameDayAs: day) {
                return DueDateLabel(text: text, isOverdue: isOverdue)
            }
        }
        var style = Date.FormatStyle.dateTime.month(.abbreviated).day()
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        style.locale = locale
        return DueDateLabel(text: due.formatted(style), isOverdue: isOverdue)
    }
}
