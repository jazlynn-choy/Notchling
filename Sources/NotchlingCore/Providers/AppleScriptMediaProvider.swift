import AppKit

/// Reads and controls Music / Spotify with AppleScript.
///
/// macOS has no public "now playing" API, and the private MediaRemote framework is locked
/// down on recent macOS, so scripting the two big players is the reliable public route.
public struct AppleScriptMediaProvider: MediaProviding {
    /// Separates fields in script output. A control character, so song titles can't contain it.
    static let separator = "\u{1F}"
    /// Separates records (one per search result).
    static let recordSeparator = "\u{1E}"

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

    public func resume(_ app: MediaApp) async {
        // An explicit tap on play, so opening the player is what the user asked for.
        _ = Self.run("tell application \"\(app.rawValue)\" to play")
    }

    public func setRepeat(_ mode: RepeatMode, for app: MediaApp) async {
        switch app {
        case .music:
            _ = Self.run("tell application \"Music\" to set song repeat to \(mode.rawValue)")
        case .spotify:
            _ = Self.run("tell application \"Spotify\" to set repeating to \(mode != .off)")
        }
    }

    public func searchLibrary(_ query: String, limit: Int) async -> [SongResult] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        // The query goes in as an argument, never spliced into the script, so quotes or
        // backslashes in what the user types can't change what the script does.
        let script = """
        on run argv
            set sep to character id 31
            set rs to character id 30
            set out to ""
            set n to 0
            tell application "Music"
                repeat with t in (search library playlist 1 for (item 1 of argv))
                    set out to out & (persistent ID of t) & sep & (name of t) & sep & (artist of t) & rs
                    set n to n + 1
                    if n is greater than or equal to ((item 2 of argv) as integer) then exit repeat
                end repeat
            end tell
            return out
        end run
        """
        guard let output = Self.run(script, arguments: [query, String(limit)]) else { return [] }
        return Self.parseSearchResults(output)
    }

    public func play(_ song: SongResult) async {
        let command: String
        switch song.app {
        case .music:
            command = "tell application \"Music\" to play (first track of library playlist 1 whose persistent ID is (item 1 of argv))"
        case .spotify where song.contextURI != nil:
            // Playing the track inside its album means the album keeps going afterwards.
            command = "tell application \"Spotify\" to play track (item 1 of argv) in context (item 2 of argv)"
        case .spotify:
            command = "tell application \"Spotify\" to play track (item 1 of argv)"
        }
        _ = Self.run("on run argv\n\(command)\nend run", arguments: [song.id] + (song.contextURI.map { [$0] } ?? []))
    }

    public func openSpotifySearch(_ query: String) async {
        guard let url = Self.spotifySearchURL(for: query) else { return }
        NSWorkspace.shared.open(url)
    }

    public var isSpotifyInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: MediaApp.spotify.bundleID) != nil
    }

    static func spotifySearchURL(for query: String) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .alphanumerics) else { return nil }
        return URL(string: "spotify:search:\(encoded)")
    }

    static func statusScript(for app: MediaApp) -> String {
        let repeatValue = app == .music
            ? "(song repeat as string) & sep & \"\""
            : "(my spotifyRepeat(repeating)) & sep & (artwork url of current track)"
        return """
        on spotifyRepeat(flag)
            if flag then return "all"
            return "off"
        end spotifyRepeat
        tell application "\(app.rawValue)"
            if player state is stopped then return "stopped"
            set sep to character id 31
            return (player state as string) & sep & (name of current track) & sep & (artist of current track) & sep & \(repeatValue)
        end tell
        """
    }

    /// Turns `"playing␟Title␟Artist␟all␟https://…"` into a `Track`. The artwork field is
    /// optional and may be empty. Public for tests.
    public static func parseStatus(_ output: String, app: MediaApp) -> Track? {
        let parts = output.components(separatedBy: separator)
        guard (4...5).contains(parts.count), ["playing", "paused"].contains(parts[0]) else { return nil }
        let artwork = parts.count == 5 ? URL(string: parts[4]).flatMap { $0.scheme == "https" ? $0 : nil } : nil
        return Track(title: parts[1], artist: parts[2], app: app, isPlaying: parts[0] == "playing",
                     repeatMode: RepeatMode(rawValue: parts[3]) ?? .off, artworkURL: artwork)
    }

    /// Turns `"id␟Title␟Artist␞id␟…␞"` into results, skipping malformed records. Public for tests.
    public static func parseSearchResults(_ output: String) -> [SongResult] {
        output.components(separatedBy: recordSeparator).compactMap { record in
            let parts = record.components(separatedBy: separator)
            guard parts.count == 3, !parts[0].isEmpty else { return nil }
            return SongResult(id: parts[0], title: parts[1], artist: parts[2])
        }
    }

    /// Runs `osascript` and returns trimmed stdout, or nil on failure. Blocking: callers are
    /// async and off the main actor, so this never stalls the UI.
    static func run(_ source: String, arguments: [String] = []) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source] + arguments
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
