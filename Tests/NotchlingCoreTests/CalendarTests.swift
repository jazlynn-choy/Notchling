import Foundation
import Testing
@testable import NotchlingCore

@MainActor
@Suite("Calendar")
struct CalendarTests {
    var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()
    // en_US formats times with a narrow no-break space (U+202F) before AM/PM.
    let locale = Locale(identifier: "en_US")
    // Saturday 7 Nov 2026, 15:00 UTC
    let now = Date(timeIntervalSince1970: 1_794_063_600)

    func event(_ id: String, startsIn minutes: Double, lasts: Double = 30, allDay: Bool = false) -> CalendarEvent {
        let start = now.addingTimeInterval(minutes * 60)
        return CalendarEvent(id: id, title: id, start: start, end: start.addingTimeInterval(lasts * 60), isAllDay: allDay)
    }

    func makeStore(_ events: [CalendarEvent]) async -> (CalendarStore, FakeCalendarProvider) {
        let provider = FakeCalendarProvider()
        provider.events = events
        let store = CalendarStore(provider: provider, calendar: calendar)
        await store.reload(now: now)
        return (store, provider)
    }

    @Test func fetchesFromStartOfTodayToEndOfTomorrow() async {
        let (_, provider) = await makeStore([])
        let range = try? #require(provider.requestedRanges.first)
        #expect(range?.0 == calendar.startOfDay(for: now))
        #expect(range?.1 == calendar.startOfDay(for: now).addingTimeInterval(2 * 86_400))
    }

    @Test func nextEventSkipsFinishedAndAllDayEvents() async {
        let (store, _) = await makeStore([
            event("Done", startsIn: -60),
            event("Birthday", startsIn: -900, lasts: 1440, allDay: true),
            event("Standup", startsIn: 12),
            event("Lunch", startsIn: 90),
        ])
        #expect(store.nextEvent(at: now)?.title == "Standup")
    }

    @Test func eventInProgressCountsAsNext() async {
        let (store, _) = await makeStore([event("Meeting", startsIn: -10), event("Later", startsIn: 60)])
        #expect(store.nextEvent(at: now)?.title == "Meeting")
    }

    @Test func agendaIsTodayOnlyWithAllDayFirst() async {
        let (store, _) = await makeStore([
            event("Standup", startsIn: 12),
            event("Holiday", startsIn: -900, lasts: 1440, allDay: true),
            event("Tomorrow", startsIn: 20 * 60),
            event("Done", startsIn: -60),
        ])
        #expect(store.agenda(at: now).map(\.title) == ["Holiday", "Standup"])
    }

    @Test func noAccessMeansNoFetch() async {
        let provider = FakeCalendarProvider()
        provider.access = .notDetermined
        let store = CalendarStore(provider: provider, calendar: calendar)
        await store.reload(now: now)
        #expect(provider.requestedRanges.isEmpty)
        await store.requestAccess()
        #expect(store.access == .granted)
        #expect(provider.requestedRanges.count == 1)
    }

    @Test(arguments: [(-5.0, "now"), (0.5, "1m"), (12.0, "12m"), (65.0, "1h 5m"), (180.0, "6:00\u{202F}PM"),
                      (20 * 60.0, "Tomorrow 11:00\u{202F}AM")])
    func compactLabels(minutes: Double, expected: String) {
        let label = EventTimeLabel.compact(for: event("E", startsIn: minutes), now: now,
                                           calendar: calendar, locale: locale)
        #expect(label == expected)
    }

    @Test func fullLabels() {
        func full(_ event: CalendarEvent) -> String {
            EventTimeLabel.full(for: event, now: now, calendar: calendar, locale: locale)
        }
        #expect(full(event("E", startsIn: -1)) == "Now")
        #expect(full(event("E", startsIn: 12)) == "In 12 min")
        #expect(full(event("E", startsIn: 180)) == "6:00\u{202F}PM")
        #expect(full(event("E", startsIn: 0, allDay: true)) == "All day")
    }
}
