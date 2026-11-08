import Foundation

/// Every user-adjustable option, persisted to `UserDefaults` the moment it changes.
@MainActor
public final class NotchSettings: ObservableObject {
    public enum Key {
        static let wingWidth = "wingWidth"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let widgetLayout = "widgetLayout"
        static let cardSizes = "cardSizes"
        static let musicSource = "musicSource"
        static let worldClockZones = "worldClockZones"
        static let countdownTitle = "countdownTitle"
        static let countdownDate = "countdownDate"
        static let haptics = "haptics"
        static let reminderListID = "reminderListID"
    }

    public static let wingRange: ClosedRange<Double> = 0...160
    public static let panelWidthRange: ClosedRange<Double> = 340...900
    public static let panelHeightRange: ClosedRange<Double> = 160...420
    public static let defaultSizes = (wing: 72.0, panelWidth: 440.0, panelHeight: 190.0)

    private let defaults: UserDefaults
    private let loginItem: LoginItemManaging

    @Published public var wingWidth: Double {
        didSet { defaults.set(wingWidth, forKey: Key.wingWidth) }
    }
    @Published public var panelWidth: Double {
        didSet { defaults.set(panelWidth, forKey: Key.panelWidth) }
    }
    @Published public var panelHeight: Double {
        didSet { defaults.set(panelHeight, forKey: Key.panelHeight) }
    }
    /// Which widgets show where. Edit it through `add`, `remove` and `move` on the layout.
    @Published public var widgets: WidgetLayout {
        didSet { defaults.set(widgets.storageValue, forKey: Key.widgetLayout) }
    }
    @Published public var haptics: Bool {
        didSet { defaults.set(haptics, forKey: Key.haptics) }
    }
    /// Per-card size overrides. Cards not listed use `WidgetKind.defaultCardSize`.
    @Published public private(set) var cardSizes: [WidgetKind: CardSize] {
        didSet {
            let raw = Dictionary(uniqueKeysWithValues: cardSizes.map { ($0.key.rawValue, $0.value.rawValue) })
            defaults.set(raw, forKey: Key.cardSizes)
        }
    }
    /// Which app song search uses.
    @Published public var musicSource: MediaApp {
        didSet { defaults.set(musicSource.rawValue, forKey: Key.musicSource) }
    }
    /// Time zone identifiers for the world clocks, at most `WorldClock.maxCities`.
    @Published public private(set) var worldClockZones: [String] {
        didSet { defaults.set(worldClockZones, forKey: Key.worldClockZones) }
    }
    @Published public var countdownTitle: String {
        didSet { defaults.set(countdownTitle, forKey: Key.countdownTitle) }
    }
    @Published public var countdownDate: Date {
        didSet { defaults.set(countdownDate, forKey: Key.countdownDate) }
    }
    /// Empty string = the default Reminders list.
    @Published public var reminderListID: String {
        didSet { defaults.set(reminderListID, forKey: Key.reminderListID) }
    }
    @Published public var launchAtLogin: Bool {
        didSet { if launchAtLogin != oldValue { applyLoginItem() } }
    }
    @Published public private(set) var loginItemError: String?

    public init(defaults: UserDefaults = .standard, loginItem: LoginItemManaging = MainAppLoginItem(),
                spotifyInstalled: Bool = true, now: Date = Date()) {
        self.defaults = defaults
        self.loginItem = loginItem
        defaults.register(defaults: [
            Key.wingWidth: Self.defaultSizes.wing,
            Key.panelWidth: Self.defaultSizes.panelWidth,
            Key.panelHeight: Self.defaultSizes.panelHeight,
            Key.haptics: true, Key.reminderListID: "",
        ])
        // Clamp on load so a hand-edited or stale preference can't break the layout.
        wingWidth = defaults.double(forKey: Key.wingWidth).clamped(to: Self.wingRange)
        panelWidth = defaults.double(forKey: Key.panelWidth).clamped(to: Self.panelWidthRange)
        panelHeight = defaults.double(forKey: Key.panelHeight).clamped(to: Self.panelHeightRange)
        widgets = Self.loadWidgets(from: defaults)
        let rawSizes = defaults.dictionary(forKey: Key.cardSizes) as? [String: String] ?? [:]
        cardSizes = rawSizes.reduce(into: [:]) { result, entry in
            if let kind = WidgetKind(rawValue: entry.key), let size = CardSize(rawValue: entry.value) {
                result[kind] = size
            }
        }
        haptics = defaults.bool(forKey: Key.haptics)
        reminderListID = defaults.string(forKey: Key.reminderListID) ?? ""
        musicSource = MediaApp(rawValue: defaults.string(forKey: Key.musicSource) ?? "")
            ?? (spotifyInstalled ? .spotify : .music)
        worldClockZones = (defaults.stringArray(forKey: Key.worldClockZones) ?? ["Europe/London", "America/New_York"])
            .filter { TimeZone(identifier: $0) != nil }
            .prefix(WorldClock.maxCities).map { $0 }
        countdownTitle = defaults.string(forKey: Key.countdownTitle) ?? "Holidays"
        countdownDate = defaults.object(forKey: Key.countdownDate) as? Date
            ?? Calendar.current.date(byAdding: .day, value: 30, to: now) ?? now
        launchAtLogin = loginItem.isEnabled
    }

    public var selectedListID: String? { reminderListID.isEmpty ? nil : reminderListID }

    public func geometry(notchSize: CGSize) -> NotchGeometry {
        NotchGeometry(notchSize: notchSize, wingWidth: CGFloat(wingWidth),
                      panelSize: CGSize(width: panelWidth, height: panelHeight))
    }

    public func resetSizes() {
        wingWidth = Self.defaultSizes.wing
        panelWidth = Self.defaultSizes.panelWidth
        panelHeight = Self.defaultSizes.panelHeight
    }

    public func resetWidgets() {
        widgets = .default
        cardSizes = [:]
    }

    public func addWorldClock(_ identifier: String) {
        guard TimeZone(identifier: identifier) != nil, !worldClockZones.contains(identifier),
              worldClockZones.count < WorldClock.maxCities else { return }
        worldClockZones.append(identifier)
    }

    public func removeWorldClock(_ identifier: String) {
        worldClockZones.removeAll { $0 == identifier }
    }

    public func cardSize(for kind: WidgetKind) -> CardSize {
        cardSizes[kind] ?? kind.defaultCardSize
    }

    public func setCardSize(_ size: CardSize, for kind: WidgetKind) {
        cardSizes[kind] = size == kind.defaultCardSize ? nil : size
    }

    /// Saved layout, else one migrated from v0.1's toggles, else the default.
    private static func loadWidgets(from defaults: UserDefaults) -> WidgetLayout {
        if let saved = WidgetLayout(storageValue: defaults.object(forKey: Key.widgetLayout)) {
            return saved
        }
        guard let migrated = WidgetLayout.migrating(from: defaults) else { return .default }
        defaults.set(migrated.storageValue, forKey: Key.widgetLayout)
        WidgetLayout.legacyKeys.forEach(defaults.removeObject(forKey:))
        return migrated
    }

    private func applyLoginItem() {
        do {
            try loginItem.setEnabled(launchAtLogin)
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
            launchAtLogin = loginItem.isEnabled   // reflect what actually happened
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
