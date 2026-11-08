import Foundation

/// Every user-adjustable option, persisted to `UserDefaults` the moment it changes.
@MainActor
public final class NotchSettings: ObservableObject {
    public enum Key {
        static let wingWidth = "wingWidth"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let widgetLayout = "widgetLayout"
        static let haptics = "haptics"
        static let reminderListID = "reminderListID"
    }

    public static let wingRange: ClosedRange<Double> = 0...160
    public static let panelWidthRange: ClosedRange<Double> = 340...640
    public static let panelHeightRange: ClosedRange<Double> = 160...300
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
    /// Empty string = the default Reminders list.
    @Published public var reminderListID: String {
        didSet { defaults.set(reminderListID, forKey: Key.reminderListID) }
    }
    @Published public var launchAtLogin: Bool {
        didSet { if launchAtLogin != oldValue { applyLoginItem() } }
    }
    @Published public private(set) var loginItemError: String?

    public init(defaults: UserDefaults = .standard, loginItem: LoginItemManaging = MainAppLoginItem()) {
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
        haptics = defaults.bool(forKey: Key.haptics)
        reminderListID = defaults.string(forKey: Key.reminderListID) ?? ""
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
