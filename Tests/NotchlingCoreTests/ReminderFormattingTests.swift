import Foundation
import Testing
@testable import NotchlingCore

@Suite("Reminder formatting")
struct ReminderFormattingTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    let locale = Locale(identifier: "en_US")
    // Saturday 7 Nov 2026, 15:00 UTC
    let now = Date(timeIntervalSince1970: 1_794_063_600)

    func day(_ offset: Int, hour: Int = 9) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: DateComponents(day: offset, hour: hour), to: start)!
    }

    func label(_ date: Date) -> DueDateLabel {
        DueDateLabel.make(for: date, now: now, calendar: calendar, locale: locale)
    }

    @Test func relativeDayNames() {
        #expect(label(day(0)) == DueDateLabel(text: "Today", isOverdue: false))
        #expect(label(day(1)) == DueDateLabel(text: "Tomorrow", isOverdue: false))
        #expect(label(day(-1)) == DueDateLabel(text: "Yesterday", isOverdue: true))
    }

    @Test func earlierTodayIsNotOverdue() {
        // Due at 09:00 and it's 15:00: still "today", not flagged red.
        #expect(!label(day(0, hour: 9)).isOverdue)
    }

    @Test func otherDatesUseShortMonthAndDay() {
        #expect(label(day(5)).text == "Nov 12")
        #expect(label(day(-10)) == DueDateLabel(text: "Oct 28", isOverdue: true))
    }

    @Test func sortsByDueDateThenCreation() {
        let old = Date(timeIntervalSince1970: 0)
        let new = Date(timeIntervalSince1970: 100)
        let todos = [
            Todo(id: "undated-new", title: "", created: new),
            Todo(id: "later", title: "", due: day(3)),
            Todo(id: "undated-old", title: "", created: old),
            Todo(id: "soon", title: "", due: day(1)),
        ]
        #expect(ReminderOrdering.sorted(todos).map(\.id) == ["soon", "later", "undated-old", "undated-new"])
    }
}
