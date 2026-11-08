import Foundation

/// Connects Claude Code to the notch through Claude Code's hooks: a tiny shell script that
/// Claude Code runs on each event, which saves the event where Notchling can read it.
public enum ClaudeHooks {
    /// Events the notch cares about.
    static let events = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse",
                         "Notification", "Stop", "SessionEnd"]
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse"]
    public static let scriptName = "claude-hook.sh"

    /// Must never slow down or break Claude Code: no output, no dependencies beyond the
    /// base system, and it always exits 0. Each session's latest event replaces the last one,
    /// written to a temp file and renamed so Notchling never reads half a file. Prompts and
    /// file contents are removed before the event is kept.
    public static let script = """
    #!/bin/sh
    # Notchling: shows what Claude Code is doing in the MacBook notch.
    # Installed by Notchling > Settings > Claude Code. Remove it there, too.
    dir="$HOME/Library/Application Support/Notchling/agents"
    mkdir -p "$dir" 2>/dev/null || exit 0
    tmp=$(mktemp "$dir/.event.XXXXXX" 2>/dev/null) || exit 0
    cat > "$tmp"
    for key in prompt tool_response tool_input.content tool_input.old_string tool_input.new_string tool_input.edits tool_input.new_source tool_input.prompt; do
        /usr/bin/plutil -remove "$key" "$tmp" >/dev/null 2>&1
    done
    id=$(/usr/bin/plutil -extract session_id raw -o - "$tmp" 2>/dev/null | tr -cd 'A-Za-z0-9-')
    if [ -n "$id" ]; then mv -f "$tmp" "${dir:?}/$id.json"; else rm -f "${tmp:?}"; fi
    exit 0

    """

    /// The hook command, quoted because "Application Support" has a space in it.
    public static func command(scriptPath: String) -> String {
        "\"\(scriptPath)\""
    }

    /// Adds Notchling's hooks to Claude Code settings, leaving every other setting and hook alone.
    /// Idempotent: running it twice doesn't add duplicates.
    public static func installing(into settings: [String: Any], command: String,
                                  approvalCommand: String? = nil) -> [String: Any] {
        var settings = removing(from: settings, command: command)
        if let approvalCommand { settings = removing(from: settings, command: approvalCommand) }
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        if let approvalCommand {
            var entries = hooks["PermissionRequest"] as? [[String: Any]] ?? []
            entries.append(["matcher": "*", "hooks": [["type": "command", "command": approvalCommand,
                                                       "timeout": ClaudeApprovals.hookTimeout]]])
            hooks["PermissionRequest"] = entries
        }
        for event in events {
            var entries = hooks[event] as? [[String: Any]] ?? []
            var entry: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if toolEvents.contains(event) { entry["matcher"] = "*" }
            entries.append(entry)
            hooks[event] = entries
        }
        settings["hooks"] = hooks
        return settings
    }

    /// Removes only Notchling's hooks. Drops event keys (and `hooks`) that end up empty.
    public static func removing(from settings: [String: Any], command: String) -> [String: Any] {
        var settings = settings
        guard var hooks = settings["hooks"] as? [String: Any] else { return settings }
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept: [[String: Any]] = entries.compactMap { entry in
                guard let commands = entry["hooks"] as? [[String: Any]] else { return entry }
                let others = commands.filter { ($0["command"] as? String) != command }
                if others.count == commands.count { return entry }
                if others.isEmpty { return nil }
                var trimmed = entry
                trimmed["hooks"] = others
                return trimmed
            }
            hooks[event] = kept.isEmpty ? nil : kept
        }
        settings["hooks"] = hooks.isEmpty ? nil : hooks
        return settings
    }

    public static func isInstalled(in settings: [String: Any], command: String,
                                   approvalCommand: String? = nil) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        let wanted = events.map { ($0, command) } + (approvalCommand.map { [("PermissionRequest", $0)] } ?? [])
        return wanted.allSatisfy { event, wantedCommand in
            (hooks[event] as? [[String: Any]] ?? []).contains { entry in
                (entry["hooks"] as? [[String: Any]] ?? []).contains { ($0["command"] as? String) == wantedCommand }
            }
        }
    }
}

/// Reads and writes `~/.claude/settings.json` and the hook script on disk.
public struct ClaudeHookInstaller: Sendable {
    public let settingsURL: URL
    public let supportDirectory: URL

    public init(settingsURL: URL = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".claude/settings.json"),
                supportDirectory: URL = ClaudeHookInstaller.defaultSupportDirectory) {
        self.settingsURL = settingsURL
        self.supportDirectory = supportDirectory
    }

    public static var defaultSupportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notchling")
    }

    public var eventsDirectory: URL { supportDirectory.appendingPathComponent("agents") }
    var scriptURL: URL { supportDirectory.appendingPathComponent(ClaudeHooks.scriptName) }
    var command: String { ClaudeHooks.command(scriptPath: scriptURL.path) }
    var approvalScriptURL: URL { supportDirectory.appendingPathComponent(ClaudeApprovals.scriptName) }
    var approvalCommand: String { ClaudeHooks.command(scriptPath: approvalScriptURL.path) }
    /// The settings file as it was before Notchling first touched it.
    var backupURL: URL { settingsURL.appendingPathExtension("before-notchling") }

    public var isInstalled: Bool {
        (try? ClaudeHooks.isInstalled(in: readSettings(), command: command, approvalCommand: approvalCommand)) == true
            && FileManager.default.isExecutableFile(atPath: scriptURL.path)
            && FileManager.default.isExecutableFile(atPath: approvalScriptURL.path)
    }

    public func install() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: eventsDirectory, withIntermediateDirectories: true)
        try ClaudeHooks.script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        try ClaudeApprovals.script.write(to: approvalScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: approvalScriptURL.path)
        let settings = try readSettings()
        if fileManager.fileExists(atPath: settingsURL.path), !fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.copyItem(at: settingsURL, to: backupURL)
        }
        try writeSettings(ClaudeHooks.installing(into: settings, command: command, approvalCommand: approvalCommand))
    }

    public func uninstall() throws {
        let withoutStatus = ClaudeHooks.removing(from: try readSettings(), command: command)
        try writeSettings(ClaudeHooks.removing(from: withoutStatus, command: approvalCommand))
        try? FileManager.default.removeItem(at: scriptURL)
        try? FileManager.default.removeItem(at: approvalScriptURL)
    }

    /// A missing file is an empty object. A file that isn't valid JSON throws rather than
    /// being overwritten, so a hand-edited settings file is never lost.
    func readSettings() throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: settingsURL.path) else { return [:] }
        let data = try Data(contentsOf: settingsURL)
        if data.isEmpty { return [:] }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    func writeSettings(_ settings: [String: Any]) throws {
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: settingsURL, options: .atomic)
    }
}
