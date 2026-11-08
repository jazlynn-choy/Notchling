import Foundation
import ServiceManagement

enum LeftWingContent: String, CaseIterable, Identifiable {
    case musicOrDate, date, music, nothing
    var id: String { rawValue }
    var label: String {
        switch self {
        case .musicOrDate: return "Music, or date when nothing plays"
        case .date: return "Date"
        case .music: return "Music only"
        case .nothing: return "Nothing"
        }
    }
}

/// Every user-adjustable option, saved to UserDefaults the moment it changes.
final class NotchSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var wingWidth: Double       { didSet { d.set(wingWidth, forKey: "wingWidth") } }
    @Published var panelWidth: Double      { didSet { d.set(panelWidth, forKey: "panelWidth") } }
    @Published var panelHeight: Double     { didSet { d.set(panelHeight, forKey: "panelHeight") } }
    @Published var leftWing: LeftWingContent { didSet { d.set(leftWing.rawValue, forKey: "leftWing") } }
    @Published var showTodoCount: Bool     { didSet { d.set(showTodoCount, forKey: "showTodoCount") } }
    @Published var showTime: Bool          { didSet { d.set(showTime, forKey: "showTime") } }
    @Published var showBattery: Bool       { didSet { d.set(showBattery, forKey: "showBattery") } }
    @Published var showMusicCard: Bool     { didSet { d.set(showMusicCard, forKey: "showMusicCard") } }
    @Published var haptics: Bool           { didSet { d.set(haptics, forKey: "haptics") } }
    @Published var reminderListID: String  { didSet { d.set(reminderListID, forKey: "reminderListID") } }
    @Published var launchAtLogin: Bool     { didSet { applyLoginItem() } }
    @Published private(set) var loginItemError: String?

    static let defaults: [String: Any] = [
        "wingWidth": 72.0, "panelWidth": 440.0, "panelHeight": 190.0,
        "leftWing": LeftWingContent.musicOrDate.rawValue,
        "showTodoCount": true, "showTime": true, "showBattery": true,
        "showMusicCard": true, "haptics": true, "reminderListID": "",
    ]

    init() {
        d.register(defaults: Self.defaults)
        wingWidth = d.double(forKey: "wingWidth")
        panelWidth = d.double(forKey: "panelWidth")
        panelHeight = d.double(forKey: "panelHeight")
        leftWing = LeftWingContent(rawValue: d.string(forKey: "leftWing") ?? "") ?? .musicOrDate
        showTodoCount = d.bool(forKey: "showTodoCount")
        showTime = d.bool(forKey: "showTime")
        showBattery = d.bool(forKey: "showBattery")
        showMusicCard = d.bool(forKey: "showMusicCard")
        haptics = d.bool(forKey: "haptics")
        reminderListID = d.string(forKey: "reminderListID") ?? ""
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func resetLayout() {
        wingWidth = Self.defaults["wingWidth"] as! Double
        panelWidth = Self.defaults["panelWidth"] as! Double
        panelHeight = Self.defaults["panelHeight"] as! Double
    }

    private func applyLoginItem() {
        do {
            if launchAtLogin { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            loginItemError = nil
        } catch {
            loginItemError = error.localizedDescription
        }
    }
}
