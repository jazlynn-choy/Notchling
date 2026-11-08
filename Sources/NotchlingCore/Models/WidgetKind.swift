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
        case .panel: return WidgetLayout.maxColumns * WidgetLayout.maxStack
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
