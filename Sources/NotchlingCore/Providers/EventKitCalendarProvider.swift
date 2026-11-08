import AppKit
import EventKit

/// Calendar events through EventKit. Same concurrency reasoning as
/// `EventKitRemindersProvider`: `EKEventStore` is thread-safe, events are converted to
/// `Sendable` values before they leave this type.
public final class EventKitCalendarProvider: CalendarProviding, @unchecked Sendable {
    private let store = EKEventStore()
    private var observer: NSObjectProtocol?

    public init() {}

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func authorizationStatus() -> AccessStatus {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    public func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    public func events(from start: Date, to end: Date) async -> [CalendarEvent] {
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map(Self.event(from:))
    }

    public func observeChanges(_ onChange: @escaping @Sendable () -> Void) {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store,
                                                          queue: nil) { _ in onChange() }
    }

    private static func event(from event: EKEvent) -> CalendarEvent {
        // An event's identifier is shared by every occurrence of a repeating event,
        // so add the start time to keep each occurrence unique.
        let base = event.eventIdentifier ?? UUID().uuidString
        return CalendarEvent(id: "\(base)@\(event.startDate.timeIntervalSince1970)",
                             title: event.title ?? "Untitled",
                             start: event.startDate,
                             end: event.endDate,
                             isAllDay: event.isAllDay,
                             color: rgb(event.calendar?.color))
    }

    private static func rgb(_ color: NSColor?) -> CalendarEvent.RGB? {
        guard let srgb = color?.usingColorSpace(.sRGB) else { return nil }
        return .init(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
    }
}
