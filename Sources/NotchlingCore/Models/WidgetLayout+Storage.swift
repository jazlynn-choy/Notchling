import Foundation

extension WidgetLayout {
    /// Stored as `{"leftWing": ["date"], ...}` with plain strings rather than synthesized
    /// `Codable`, so a widget removed in a later version (or a typo in a hand-edited plist)
    /// is skipped instead of throwing away the user's whole layout.
    public var storageValue: [String: [String]] {
        var value = Dictionary(uniqueKeysWithValues: WidgetSlot.allCases.map { ($0.rawValue, self[$0].map(\.rawValue)) })
        value["panelStacked"] = panel.filter(stacked.contains).map(\.rawValue)
        return value
    }

    public init?(storageValue: Any?) {
        guard let raw = storageValue as? [String: [String]] else { return nil }
        func kinds(_ slot: WidgetSlot) -> [WidgetKind] {
            (raw[slot.rawValue] ?? []).compactMap(WidgetKind.init(rawValue:))
        }
        let stacked = Set((raw["panelStacked"] ?? []).compactMap(WidgetKind.init(rawValue:)))
        self.init(leftWing: kinds(.leftWing), rightWing: kinds(.rightWing), panel: kinds(.panel), stacked: stacked)
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
