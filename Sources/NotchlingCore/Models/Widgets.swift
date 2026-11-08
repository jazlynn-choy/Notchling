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
        case .panel: return 4
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
    case weather = "weather"
    case worldClock = "worldClock"
    case countdown = "countdown"
    case agent = "agent"
    // Panel widgets
    case musicCard = "musicCard"
    case remindersCard = "remindersCard"
    case dayCard = "dayCard"
    case focusCard = "focusCard"
    case calendarCard = "calendarCard"
    case weatherCard = "weatherCard"
    case worldClockCard = "worldClockCard"
    case countdownCard = "countdownCard"
    case notesCard = "notesCard"
    case agentCard = "agentCard"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .nowPlaying: return "Now playing"
        case .nowPlayingOrDate: return "Now playing, or date"
        case .date: return "Date"
        case .time: return "Time"
        case .battery: return "Battery"
        case .reminderCount: return "Open reminders count"
        case .focusTimer, .focusCard: return "Focus timer"
        case .nextEvent: return "Next event"
        case .weather, .weatherCard: return "Weather"
        case .worldClock: return "World clock"
        case .worldClockCard: return "World clocks"
        case .countdown, .countdownCard: return "Countdown"
        case .musicCard: return "Music controls"
        case .remindersCard: return "Reminders"
        case .dayCard: return "Today"
        case .calendarCard: return "Calendar"
        case .notesCard: return "Notes"
        case .agent: return "Claude Code"
        case .agentCard: return "Claude Code sessions"
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
        case .focusTimer: return "Time left, while a focus session is running"
        case .nextEvent: return "Your next meeting and how soon it starts"
        case .weather: return "Temperature and an icon for your city"
        case .worldClock: return "The time in your first world-clock city"
        case .countdown: return "Days left until your countdown date"
        case .musicCard: return "Song, controls, loop and search for Spotify or Music"
        case .remindersCard: return "Your Apple Reminders: tick off or add new ones"
        case .dayCard: return "A calendar tile for today's date"
        case .focusCard: return "Start, pause and pick a length for a focus session"
        case .calendarCard: return "The rest of today's events from Calendar"
        case .weatherCard: return "Conditions, temperature and today's high and low"
        case .worldClockCard: return "The time in up to three cities"
        case .countdownCard: return "A big day count to the date you choose"
        case .notesCard: return "A scratchpad that's saved as you type"
        case .agent: return "What Claude Code is doing, and when it needs you"
        case .agentCard: return "Every Claude Code session: working, waiting or done"
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
        case .weather, .weatherCard: return "cloud.sun"
        case .worldClock, .worldClockCard: return "globe"
        case .countdown, .countdownCard: return "hourglass"
        case .notesCard: return "note.text"
        case .agent, .agentCard: return "sparkle"
        }
    }

    public func fits(_ slot: WidgetSlot) -> Bool {
        switch self {
        case .nowPlaying, .nowPlayingOrDate, .date, .time, .battery, .reminderCount, .focusTimer, .nextEvent,
             .weather, .worldClock, .countdown, .agent:
            return slot.isWing
        case .musicCard, .remindersCard, .dayCard, .focusCard, .calendarCard, .weatherCard, .worldClockCard,
             .countdownCard, .notesCard, .agentCard:
            return slot == .panel
        }
    }

    /// How wide a panel card starts out. Users can change it per card.
    public var defaultCardSize: CardSize {
        switch self {
        case .remindersCard, .calendarCard, .agentCard: return .large
        case .musicCard, .notesCard, .worldClockCard: return .medium
        default: return .small
        }
    }

    /// Whether this widget needs now-playing information, so polling can stop when none does.
    public var usesMedia: Bool { [.nowPlaying, .nowPlayingOrDate, .musicCard].contains(self) }

    /// Whether this widget reads Calendar, so the app only touches EventKit events when needed.
    public var usesCalendar: Bool { self == .nextEvent || self == .calendarCard }

    /// Whether this widget needs the weather, so the app only calls the network when needed.
    public var usesWeather: Bool { self == .weather || self == .weatherCard }

    /// Whether this widget shows Claude Code activity, so the app only watches for it when needed.
    public var usesAgent: Bool { self == .agent || self == .agentCard }
}

/// Starting sizes for panel cards. Users can then drag a card to any width in between;
/// what's stored is the card's *weight*, its share of the width relative to the others.
public enum CardSize: String, CaseIterable, Identifiable, Sendable {
    case small, medium, large

    public var id: String { rawValue }
    public var label: String { rawValue.prefix(1).uppercased() }
    public var title: String { rawValue.capitalized }

    /// Share of the width. A large card is 2.5× a small one.
    public var weight: Double {
        switch self {
        case .small: return 1
        case .medium: return 1.6
        case .large: return 2.5
        }
    }
}

/// Splits the panel's width between cards by weight, and works out what a drag means.
/// Pure math, so the editing behaviour is unit tested without SwiftUI.
public enum PanelLayout {
    /// The narrowest/widest a card can be made, as a weight.
    public static let weightRange: ClosedRange<Double> = 0.5...4
    public static let minimumWidth: Double = 90

    /// Widths for cards with `weights`, filling `totalWidth` with `spacing` between them. Every
    /// card gets at least `minimum` (if there's room), so a small card can't be squeezed to nothing.
    public static func widths(for weights: [Double], totalWidth: Double, spacing: Double,
                              minimum: Double = minimumWidth) -> [Double] {
        guard !weights.isEmpty else { return [] }
        let (floor, extra) = split(count: weights.count, totalWidth: totalWidth, spacing: spacing, minimum: minimum)
        let totalWeight = weights.reduce(0, +)
        return weights.map { floor + extra * $0 / totalWeight }
    }

    /// The weight card `index` needs so that it ends up `targetWidth` wide, with the other
    /// cards keeping their weights. This is what makes a resize handle track the pointer.
    public static func weight(toMake index: Int, width targetWidth: Double, weights: [Double],
                              totalWidth: Double, spacing: Double, minimum: Double = minimumWidth) -> Double {
        guard weights.indices.contains(index), weights.count > 1 else { return weights.first ?? 1 }
        let (floor, extra) = split(count: weights.count, totalWidth: totalWidth, spacing: spacing, minimum: minimum)
        guard extra > 0 else { return weights[index] }
        let others = weights.enumerated().filter { $0.offset != index }.reduce(0) { $0 + $1.element }
        // width = floor + extra * w / (w + others)  →  w = others * q / (1 - q)
        let share = min(max((targetWidth - floor) / extra, 0.001), 0.95)
        return (others * share / (1 - share)).clamped(to: weightRange)
    }

    /// Where a card dragged sideways by `translation` should land: it moves past a neighbour
    /// once its centre crosses the neighbour's centre.
    public static func targetIndex(moving index: Int, by translation: Double, widths: [Double],
                                   spacing: Double) -> Int {
        guard widths.indices.contains(index) else { return index }
        let centres = widths.indices.map { i in
            widths[..<i].reduce(0, +) + spacing * Double(i) + widths[i] / 2
        }
        let draggedCentre = centres[index] + translation
        var target = index
        while target < widths.count - 1, draggedCentre > centres[target + 1] { target += 1 }
        while target > 0, draggedCentre < centres[target - 1] { target -= 1 }
        return target
    }

    private static func split(count: Int, totalWidth: Double, spacing: Double,
                              minimum: Double) -> (floor: Double, extra: Double) {
        let available = max(0, totalWidth - spacing * Double(count - 1))
        let floor = min(minimum, available / Double(count))
        return (floor, available - floor * Double(count))
    }
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
    /// Moves a widget to the other wing (or between any two slots it fits). Returns whether
    /// it moved: it won't if it doesn't fit there, is already there, or the slot is full.
    @discardableResult
    public mutating func transfer(_ kind: WidgetKind, from source: WidgetSlot, to destination: WidgetSlot) -> Bool {
        guard source != destination, self[source].contains(kind), addable(to: destination).contains(kind) else {
            return false
        }
        remove(kind, from: source)
        add(kind, to: destination)
        return true
    }

    /// For SwiftUI's `onMove` (drag to reorder in Settings).
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int, in slot: WidgetSlot) {
        var items = self[slot]
        let moving = source.sorted().filter(items.indices.contains).map { items[$0] }
        let insertAt = destination - source.filter { $0 < destination }.count
        for index in source.sorted(by: >) where items.indices.contains(index) { items.remove(at: index) }
        items.insert(contentsOf: moving, at: min(max(insertAt, 0), items.count))
        self[slot] = items
    }

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
