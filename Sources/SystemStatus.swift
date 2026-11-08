import Cocoa
import IOKit.ps

struct Track: Equatable {
    var title: String
    var artist: String
    var app: String
    var playing: Bool
}

/// Clock, battery and now-playing state. Sizes come from NotchSettings.
final class NotchModel: ObservableObject {
    @Published var expanded = false
    @Published var now = Date()
    @Published var battery = 100
    @Published var charging = false
    @Published var track: Track?

    let notchSize: CGSize
    let settings: NotchSettings
    let ear: CGFloat = 8   // the little outward curve where the shape meets the top edge

    var wing: CGFloat { CGFloat(settings.wingWidth) }
    var collapsedSize: CGSize { CGSize(width: notchSize.width + wing * 2, height: notchSize.height) }
    var expandedSize: CGSize {
        CGSize(width: max(CGFloat(settings.panelWidth), notchSize.width + 40),
               height: max(CGFloat(settings.panelHeight), notchSize.height + 120))
    }
    var currentSize: CGSize { expanded ? expandedSize : collapsedSize }

    private let mediaQueue = DispatchQueue(label: "notchling.media")

    init(notchSize: CGSize, settings: NotchSettings) {
        self.notchSize = notchSize
        self.settings = settings
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.refreshBattery() }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshMedia() }
        refreshBattery()
        refreshMedia()
    }

    func refreshBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return }
        for ps in list {
            guard let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            if let cap = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0 {
                battery = Int((Double(cap) / Double(max) * 100).rounded())
            }
            charging = (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        }
    }

    /// Now playing from Spotify or Apple Music — only if already running, never launches them.
    func refreshMedia() {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier })
        var apps: [String] = []
        if running.contains("com.spotify.client") { apps.append("Spotify") }
        if running.contains("com.apple.Music") { apps.append("Music") }
        guard !apps.isEmpty else { if track != nil { track = nil }; return }

        mediaQueue.async {
            var best: Track?
            for app in apps {
                let script = """
                tell application "\(app)"
                    if player state is stopped then return "stopped"
                    return (player state as string) & linefeed & (name of current track) & linefeed & (artist of current track)
                end tell
                """
                guard let out = Self.osascript(script) else { continue }
                let parts = out.components(separatedBy: "\n")
                guard parts.count >= 3 else { continue }
                let t = Track(title: parts[1], artist: parts[2], app: app, playing: parts[0] == "playing")
                if t.playing { best = t; break }
                if best == nil { best = t }
            }
            DispatchQueue.main.async { if self.track != best { self.track = best } }
        }
    }

    func control(_ command: String) {
        guard let app = track?.app else { return }
        mediaQueue.async {
            _ = Self.osascript("tell application \"\(app)\" to \(command)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.refreshMedia() }
        }
    }

    static func osascript(_ source: String) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", source]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
