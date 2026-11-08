import Foundation

/// Formatting for the world-clock widgets.
public enum WorldClock {
    public static let maxCities = 3

    /// "America/Argentina/Buenos_Aires" → "Buenos Aires".
    public static func cityName(for identifier: String) -> String {
        (identifier.split(separator: "/").last.map(String.init) ?? identifier)
            .replacingOccurrences(of: "_", with: " ")
    }

    /// Every time zone as (identifier, "City (Region)"), sorted by city, for the picker.
    public static let allZones: [(id: String, label: String)] = TimeZone.knownTimeZoneIdentifiers
        .filter { $0.contains("/") && !$0.hasPrefix("Etc/") }
        .map { id in
            let region = id.split(separator: "/").first.map(String.init) ?? ""
            return (id, "\(cityName(for: id)) (\(region.replacingOccurrences(of: "_", with: " ")))")
        }
        .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }

    public static func time(in zone: TimeZone, at now: Date, locale: Locale = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.timeStyle = .short
        return formatter.string(from: now)
    }

    /// Whether it's a different calendar day there: "Tomorrow", "Yesterday", or nil.
    public static func dayLabel(in zone: TimeZone, at now: Date, localZone: TimeZone = .current) -> String? {
        var there = Calendar(identifier: .gregorian)
        there.timeZone = zone
        var here = Calendar(identifier: .gregorian)
        here.timeZone = localZone
        let a = there.dateComponents([.year, .month, .day], from: now)
        let b = here.dateComponents([.year, .month, .day], from: now)
        guard let dayThere = here.date(from: a), let dayHere = here.date(from: b) else { return nil }
        switch here.dateComponents([.day], from: dayHere, to: dayThere).day ?? 0 {
        case 1...: return "Tomorrow"
        case ..<0: return "Yesterday"
        default: return nil
        }
    }

    /// "+8h", "−3h 30m", or "Same time" relative to here.
    public static func offsetLabel(for zone: TimeZone, at now: Date, localZone: TimeZone = .current) -> String {
        let minutes = (zone.secondsFromGMT(for: now) - localZone.secondsFromGMT(for: now)) / 60
        if minutes == 0 { return "Same time" }
        let sign = minutes > 0 ? "+" : "−"
        let hours = abs(minutes) / 60, rest = abs(minutes) % 60
        return rest == 0 ? "\(sign)\(hours)h" : "\(sign)\(hours)h \(rest)m"
    }
}

/// Day counts for the countdown widgets.
public enum Countdown {
    /// Whole calendar days from today to `target`'s day (negative once it's passed).
    public static func days(until target: Date, from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                to: calendar.startOfDay(for: target)).day ?? 0
    }

    /// For the wing: "12d", "Today", "Done".
    public static func compact(days: Int) -> String {
        switch days {
        case 0: return "Today"
        case ..<0: return "Done"
        default: return "\(days)d"
        }
    }

    /// For the card's caption: "days to go", "day to go", "today!", "days ago".
    public static func caption(days: Int) -> String {
        switch days {
        case 0: return "today!"
        case 1: return "day to go"
        case 2...: return "days to go"
        case -1: return "day ago"
        default: return "days ago"
        }
    }
}
