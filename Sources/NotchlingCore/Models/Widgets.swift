import Foundation

/// Where a widget can be placed.
public enum WidgetSlot: String, CaseIterable, Identifiable, Sendable {
    case leftWing, rightWing, panel

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .leftWing: return "Left of the notch"
        case .rightWing: return "Right of the notch"
        case .panel: return "Panel"
        }
    }

    /// The panel is only so wide, so it holds a few cards. Wings can take anything that fits.
    public var capacity: Int {
        switch self {
        case .leftWing, .rightWing: return 4
        case .panel: return 3
        }
    }

    var isWing: Bool { self != .panel }
}

/// Every widget the app can show. Wing widgets are small enough for the bar beside the
/// notch; panel widgets are cards in the drop-down panel.
///
/// The raw values are persisted, so they must never change. Rename the case, not the string.
public enum WidgetKind: String, CaseIterable, Identifiable, Sendable {
    // Wing widgets
    case nowPlaying = "nowPlaying"
    case nowPlayingOrDate = "nowPlayingOrDate"
    case date = "date"
    case time = "time"
    case battery = "battery"
    case reminderCount = "reminderCount"
    case focusTimer = "focusTimer"
    case nextEvent = "nextEvent"
    // Panel widgets
    case musicCard = "musicCard"
    case remindersCard = "remindersCard"
    case dayCard = "dayCard"
    case focusCard = "focusCard"
    case calendarCard = "calendarCard"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nowPlaying: return "Now playing"
        case .nowPlayingOrDate: return "Now playing, or date"
        case .date: return "Date"
        case .time: return "Time"
        case .battery: return "Battery"
        case .reminderCount: return "Open reminders count"
        case .musicCard: return "Music controls"
        case .remindersCard: return "Reminders"
        case .dayCard: return "Today"
        case .focusTimer: return "Focus timer"
        case .nextEvent: return "Next event"
        case .focusCard: return "Focus timer"
        case .calendarCard: return "Calendar"
        }
    }

    public var summary: String {
        switch self {
        case .nowPlaying: return "Animated bars and the song title while music plays"
        case .nowPlayingOrDate: return "The song while music plays, otherwise the date"
        case .date: return "Weekday and day, like Sat 7"
        case .time: return "Current time"
        case .battery: return "Battery level, green while charging"
        case .reminderCount: return "A badge with how many reminders are open"
        case .musicCard: return "Song, artist and play controls for Music or Spotify"
        case .remindersCard: return "Your Apple Reminders: tick off or add new ones"
        case .dayCard: return "A calendar tile for today's date"
        case .focusTimer: return "Time left, while a focus session is running"
        case .nextEvent: return "Your next meeting and how soon it starts"
        case .focusCard: return "Start, pause and pick a length for a focus session"
        case .calendarCard: return "The rest of today's events from Calendar"
        }
    }

    /// SF Symbol shown in Settings.
    public var symbol: String {
        switch self {
        case .nowPlaying, .musicCard: return "music.note"
        case .nowPlayingOrDate: return "music.note.list"
        case .date, .dayCard: return "calendar"
        case .time: return "clock"
        case .battery: return "battery.75percent"
        case .reminderCount: return "number.circle"
        case .remindersCard: return "checklist"
        case .focusTimer, .focusCard: return "timer"
        case .nextEvent, .calendarCard: return "calendar.badge.clock"
        }
    }

    public func fits(_ slot: WidgetSlot) -> Bool {
        switch self {
        case .nowPlaying, .nowPlayingOrDate, .date, .time, .battery, .reminderCount, .focusTimer, .nextEvent:
            return slot.isWing
        case .musicCard, .remindersCard, .dayCard, .focusCard, .calendarCard:
            return slot == .panel
        }
    }

    /// Whether a panel card stretches to fill leftover width (true) or keeps a compact width.
    public var isFlexible: Bool { self == .remindersCard || self == .calendarCard }

    /// Whether this widget needs now-playing information, so polling can stop when none does.
    public var usesMedia: Bool { [.nowPlaying, .nowPlayingOrDate, .musicCard].contains(self) }

    /// Whether this widget reads Calendar, so the app only touches EventKit events when needed.
    public var usesCalendar: Bool { self == .nextEvent || self == .calendarCard }
}

/// Which widgets appear in each slot, in display order.
///
/// Invariants, enforced by every mutation and by `sanitized()`: each widget fits its slot,
/// appears at most once per slot, and no slot exceeds its capacity.
public struct WidgetLayout: Equatable, Sendable {
    public private(set) var leftWing: [WidgetKind]
    public private(set) var rightWing: [WidgetKind]
    public private(set) var panel: [WidgetKind]

    public static let `default` = WidgetLayout(leftWing: [.nowPlayingOrDate],
                                               rightWing: [.reminderCount, .time, .battery],
                                               panel: [.musicCard, .remindersCard])

    public init(leftWing: [WidgetKind], rightWing: [WidgetKind], panel: [WidgetKind]) {
        self.leftWing = Self.clean(leftWing, for: .leftWing)
        self.rightWing = Self.clean(rightWing, for: .rightWing)
        self.panel = Self.clean(panel, for: .panel)
    }

    public subscript(slot: WidgetSlot) -> [WidgetKind] {
        get {
            switch slot {
            case .leftWing: return leftWing
            case .rightWing: return rightWing
            case .panel: return panel
            }
        }
        set {
            let cleaned = Self.clean(newValue, for: slot)
            switch slot {
            case .leftWing: leftWing = cleaned
            case .rightWing: rightWing = cleaned
            case .panel: panel = cleaned
            }
        }
    }

    public var allWidgets: Set<WidgetKind> { Set(leftWing + rightWing + panel) }

    /// Widgets that could still be added to `slot`, or nothing if it's full.
    public func addable(to slot: WidgetSlot) -> [WidgetKind] {
        guard self[slot].count < slot.capacity else { return [] }
        return WidgetKind.allCases.filter { $0.fits(slot) && !self[slot].contains($0) }
    }

    public mutating func add(_ kind: WidgetKind, to slot: WidgetSlot) {
        guard addable(to: slot).contains(kind) else { return }
        self[slot].append(kind)
    }

    public mutating func remove(_ kind: WidgetKind, from slot: WidgetSlot) {
        self[slot].removeAll { $0 == kind }
    }

    /// Moves a widget one step earlier (negative offset) or later (positive) in its slot.
    public mutating func move(_ kind: WidgetKind, in slot: WidgetSlot, by offset: Int) {
        var items = self[slot]
        guard let from = items.firstIndex(of: kind) else { return }
        let to = min(max(from + offset, 0), items.count - 1)
        guard to != from else { return }
        items.remove(at: from)
        items.insert(kind, at: to)
        self[slot] = items
    }

    private static func clean(_ kinds: [WidgetKind], for slot: WidgetSlot) -> [WidgetKind] {
        var seen = Set<WidgetKind>()
        let valid = kinds.filter { $0.fits(slot) && seen.insert($0).inserted }
        return Array(valid.prefix(slot.capacity))
    }
}

// MARK: - Persistence

extension WidgetLayout {
    /// Stored as `{"leftWing": ["date"], ...}` with plain strings rather than synthesized
    /// `Codable`, so a widget removed in a later version (or a typo in a hand-edited plist)
    /// is skipped instead of throwing away the user's whole layout.
    public var storageValue: [String: [String]] {
        Dictionary(uniqueKeysWithValues: WidgetSlot.allCases.map { ($0.rawValue, self[$0].map(\.rawValue)) })
    }

    public init?(storageValue: Any?) {
        guard let raw = storageValue as? [String: [String]] else { return nil }
        func kinds(_ slot: WidgetSlot) -> [WidgetKind] {
            (raw[slot.rawValue] ?? []).compactMap(WidgetKind.init(rawValue:))
        }
        self.init(leftWing: kinds(.leftWing), rightWing: kinds(.rightWing), panel: kinds(.panel))
    }

    /// Builds a layout from the separate toggles used before widgets existed (v0.1),
    /// so upgrading keeps what the user had set up.
    public static func migrating(from defaults: UserDefaults) -> WidgetLayout? {
        guard legacyKeys.contains(where: { defaults.object(forKey: $0) != nil }) else { return nil }

        func flag(_ key: String) -> Bool { defaults.object(forKey: key) as? Bool ?? true }

        let left: [WidgetKind]
        switch defaults.string(forKey: "leftWing") {
        case "date": left = [.date]
        case "music": left = [.nowPlaying]
        case "nothing": left = []
        default: left = [.nowPlayingOrDate]
        }
        var right: [WidgetKind] = []
        if flag("showTodoCount") { right.append(.reminderCount) }
        if flag("showTime") { right.append(.time) }
        if flag("showBattery") { right.append(.battery) }
        let panel: [WidgetKind] = flag("showMusicCard") ? [.musicCard, .remindersCard] : [.remindersCard]
        return WidgetLayout(leftWing: left, rightWing: right, panel: panel)
    }

    /// Pre-widget preference keys. Deleted once migrated so migration runs only once.
    static let legacyKeys = ["leftWing", "showTodoCount", "showTime", "showBattery", "showMusicCard"]
}
