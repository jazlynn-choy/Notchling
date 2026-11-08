import AppKit

/// Reads and controls Music / Spotify with AppleScript.
///
/// macOS has no public "now playing" API, and the private MediaRemote framework is locked
/// down on recent macOS, so scripting the two big players is the reliable public route.
public struct AppleScriptMediaProvider: MediaProviding {
    /// Separates fields in script output. A control character, so song titles can't contain it.
    static let separator = "\u{1F}"

    public init() {}

    public func nowPlaying() async -> Track? {
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        var paused: Track?
        // Only ask apps that are already open — `tell application` would otherwise launch them.
        for app in MediaApp.allCases where running.contains(app.bundleID) {
            guard let output = Self.run(Self.statusScript(for: app)),
                  let track = Self.parseStatus(output, app: app) else { continue }
            if track.isPlaying { return track }
            if paused == nil { paused = track }
        }
        return paused
    }

    public func send(_ command: MediaCommand, to app: MediaApp) async {
        _ = Self.run("tell application \"\(app.rawValue)\" to \(command.rawValue)")
    }

    static func statusScript(for app: MediaApp) -> String {
        """
        tell application "\(app.rawValue)"
            if player state is stopped then return "stopped"
            set sep to character id 31
            return (player state as string) & sep & (name of current track) & sep & (artist of current track)
        end tell
        """
    }

    /// Turns `"playing␟Title␟Artist"` into a `Track`. Public for tests.
    public static func parseStatus(_ output: String, app: MediaApp) -> Track? {
        let parts = output.components(separatedBy: separator)
        guard parts.count == 3, ["playing", "paused"].contains(parts[0]) else { return nil }
        return Track(title: parts[1], artist: parts[2], app: app, isPlaying: parts[0] == "playing")
    }

    /// Runs `osascript` and returns trimmed stdout, or nil on failure. Blocking: callers are
    /// async and off the main actor, so this never stalls the UI.
    static func run(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
