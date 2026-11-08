import Foundation

/// Today's and tomorrow's events, for the calendar widgets.
@MainActor
public final class CalendarStore: ObservableObject {
    @Published public private(set) var access: AccessStatus
    @Published public private(set) var events: [CalendarEvent] = []

    private let provider: CalendarProviding
    private let calendar: Calendar

    public init(provider: CalendarProviding, calendar: Calendar = .current) {
        self.provider = provider
        self.calendar = calendar
        self.access = provider.authorizationStatus()
        provider.observeChanges { [weak self] in
            Task { @MainActor in await self?.reload() }
        }
    }

    public func requestAccess() async {
        access = await provider.requestAccess() ? .granted : .denied
        await reload()
    }

    /// Fetches from the start of today to the end of tomorrow.
    public func reload(now: Date = Date()) async {
        guard access == .granted else { return }
        let today = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 2, to: today) else { return }
        events = await provider.events(from: today, to: end)
            .sorted { ($0.start, $0.title) < ($1.start, $1.title) }
    }

    /// The next timed event that hasn't ended. All-day events are skipped: "Birthday, now"
    /// all day long isn't useful in a tiny wing.
    public func nextEvent(at now: Date) -> CalendarEvent? {
        events.first { !$0.isAllDay && $0.end > now }
    }

    /// What's left of today: all-day events first, then timed ones that haven't ended.
    public func agenda(at now: Date) -> [CalendarEvent] {
        let today = events.filter { calendar.isDate($0.start, inSameDayAs: now) || ($0.start < now && $0.end > now) }
        return today.filter(\.isAllDay) + today.filter { !$0.isAllDay && $0.end > now }
    }
}

/// Short labels for when an event happens, relative to now.
public enum EventTimeLabel {
    /// For the wing, where space is tight: "now", "12m", "1h 5m", "3:00 PM".
    public static func compact(for event: CalendarEvent, now: Date,
                               calendar: Calendar = .current, locale: Locale = .current) -> String {
        if event.start <= now { return "now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)m" }
        if minutes < 120 { return "1h \(minutes - 60)m" }
        return time(event.start, now: now, calendar: calendar, locale: locale)
    }

    /// For the panel: "Now", "In 12 min", "3:00 PM", "Tomorrow 9:00 AM", "All day".
    public static func full(for event: CalendarEvent, now: Date,
                            calendar: Calendar = .current, locale: Locale = .current) -> String {
        if event.isAllDay { return "All day" }
        if event.start <= now { return "Now" }
        let minutes = Int((event.start.timeIntervalSince(now) / 60).rounded(.up))
        if minutes < 60 { return "In \(minutes) min" }
        return time(event.start, now: now, calendar: calendar, locale: locale)
    }

    private static func time(_ date: Date, now: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = calendar.timeZone
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let text = formatter.string(from: date)
        return calendar.isDate(date, inSameDayAs: now) ? text : "Tomorrow \(text)"
    }
}
