import Foundation

public enum LeftWingContent: String, CaseIterable, Identifiable, Sendable {
    case musicOrDate, date, music, nothing

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .musicOrDate: return "Music, or date when nothing plays"
        case .date: return "Date"
        case .music: return "Music only"
        case .nothing: return "Nothing"
        }
    }
}

/// Every user-adjustable option, persisted to `UserDefaults` the moment it changes.
@MainActor
public final class NotchSettings: ObservableObject {
    public enum Key {
        static let wingWidth = "wingWidth"
        static let panelWidth = "panelWidth"
        static let panelHeight = "panelHeight"
        static let leftWing = "leftWing"
        static let showTodoCount = "showTodoCount"
        static let showTime = "showTime"
        static let showBattery = "showBattery"
        static let showMusicCard = "showMusicCard"
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
    @Published public var leftWing: LeftWingContent {
        didSet { defaults.set(leftWing.rawValue, forKey: Key.leftWing) }
    }
    @Published public var showTodoCount: Bool {
        didSet { defaults.set(showTodoCount, forKey: Key.showTodoCount) }
    }
    @Published public var showTime: Bool {
        didSet { defaults.set(showTime, forKey: Key.showTime) }
    }
    @Published public var showBattery: Bool {
        didSet { defaults.set(showBattery, forKey: Key.showBattery) }
    }
    @Published public var showMusicCard: Bool {
        didSet { defaults.set(showMusicCard, forKey: Key.showMusicCard) }
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
            Key.leftWing: LeftWingContent.musicOrDate.rawValue,
            Key.showTodoCount: true, Key.showTime: true, Key.showBattery: true,
            Key.showMusicCard: true, Key.haptics: true, Key.reminderListID: "",
        ])
        // Clamp on load so a hand-edited or stale preference can't break the layout.
        wingWidth = defaults.double(forKey: Key.wingWidth).clamped(to: Self.wingRange)
        panelWidth = defaults.double(forKey: Key.panelWidth).clamped(to: Self.panelWidthRange)
        panelHeight = defaults.double(forKey: Key.panelHeight).clamped(to: Self.panelHeightRange)
        leftWing = LeftWingContent(rawValue: defaults.string(forKey: Key.leftWing) ?? "") ?? .musicOrDate
        showTodoCount = defaults.bool(forKey: Key.showTodoCount)
        showTime = defaults.bool(forKey: Key.showTime)
        showBattery = defaults.bool(forKey: Key.showBattery)
        showMusicCard = defaults.bool(forKey: Key.showMusicCard)
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
