import Foundation
import Testing
@testable import NotchlingCore

func makeTempDirectory(_ name: String = #function) -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("notchling-tests-\(name.filter(\.isLetter))-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("Claude Code activity")
struct AgentActivityTests {
    let now = Date(timeIntervalSince1970: 1_794_063_600)

    @Test func parsesHookJSONLeniently() throws {
        let json = #"{"session_id":"s1","hook_event_name":"PreToolUse","cwd":"/Users/me/Camera Notch","tool_name":"Edit","tool_input":{"file_path":"/x/NotchView.swift"},"extra":{"ignored":true}}"#
        let event = try #require(AgentEvent(json: Data(json.utf8)))
        #expect(event == AgentEvent(sessionID: "s1", name: "PreToolUse", cwd: "/Users/me/Camera Notch",
                                    toolName: "Edit", toolDetail: "/x/NotchView.swift"))
        #expect(AgentEvent(json: Data(#"{"hook_event_name":"Stop"}"#.utf8)) == nil)
        #expect(AgentEvent(json: Data("not json".utf8)) == nil)
    }

    @Test(arguments: [
        ("Edit", "/a/b/NotchView.swift", "Editing NotchView.swift"),
        ("Read", "/a/README.md", "Reading README.md"),
        ("Bash", "swift test --parallel", "Running swift test --parallel"),
        ("Bash", "echo one\necho two", "Running echo one"),
        ("Grep", "TODO", "Searching the code"),
        ("mcp__github__create_pr", nil, "Using github"),
        ("Task", "Find the bug", "Running a subagent"),
        ("SomethingNew", nil, "Using SomethingNew"),
    ] as [(String, String?, String)])
    func describesTools(tool: String, detail: String?, expected: String) {
        #expect(AgentActivity.describe(tool: tool, detail: detail) == expected)
    }

    @Test func longCommandsAreShortened() {
        let text = AgentActivity.describe(tool: "Bash", detail: String(repeating: "x", count: 200))
        #expect(text.count < 60)
        #expect(text.hasSuffix("…"))
    }

    @Test(arguments: [("SessionStart", AgentState.ready), ("UserPromptSubmit", .working), ("PreToolUse", .working),
                      ("PostToolUse", .working), ("Notification", .needsInput), ("Stop", .done)])
    func eventsMapToStates(name: String, state: AgentState) {
        let session = AgentActivity.session(from: AgentEvent(sessionID: "s", name: name, cwd: "/p/App"), at: now)
        #expect(session?.state == state)
        #expect(session?.project == "App")
    }

    @Test func sessionEndRemovesTheSession() {
        #expect(AgentActivity.session(from: AgentEvent(sessionID: "s", name: "SessionEnd"), at: now) == nil)
    }

    @Test func notificationShowsClaudesMessage() {
        let event = AgentEvent(sessionID: "s", name: "Notification", message: "Claude needs your permission to use Bash")
        #expect(AgentActivity.session(from: event, at: now)?.activity == "Claude needs your permission to use Bash")
    }

    @Test func headlinePrefersWhoeverNeedsYou() {
        func session(_ id: String, _ state: AgentState, ago: TimeInterval) -> AgentSession {
            AgentSession(id: id, project: id, state: state, activity: "", updatedAt: now.addingTimeInterval(-ago))
        }
        let sessions = [session("a", .working, ago: 1), session("b", .needsInput, ago: 300), session("c", .done, ago: 5)]
        #expect(AgentActivity.headline(of: sessions, now: now)?.id == "b")
        #expect(AgentActivity.headline(of: [session("a", .ready, ago: 1)], now: now) == nil)
        #expect(AgentActivity.headline(of: [session("c", .done, ago: 60)], now: now)?.id == "c")
        #expect(AgentActivity.headline(of: [session("c", .done, ago: 3600)], now: now) == nil)   // faded out
    }
}

/// In-memory event source.
final class FakeAgentSource: AgentEventSource, @unchecked Sendable {
    var events: [String: (AgentEvent, Date)] = [:]
    var removed: [String] = []
    func latestEvents() -> [(event: AgentEvent, date: Date)] { events.values.map { ($0.0, $0.1) } }
    func remove(sessionID: String) {
        removed.append(sessionID)
        events[sessionID] = nil
    }
    func post(_ id: String, _ name: String, at date: Date) {
        events[id] = (AgentEvent(sessionID: id, name: name, cwd: "/p/\(id)"), date)
    }
}

@MainActor
@Suite("Agent status store")
struct AgentStatusStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_063_600)

    @Test func chimesOnlyForChangesAfterLaunch() {
        let source = FakeAgentSource()
        source.post("old", "Stop", at: now.addingTimeInterval(-60))   // already done before launch
        let store = AgentStatusStore(source: source)
        var alerts: [String] = []
        store.onAttention = { alerts.append("\($0.id):\($0.state.label)") }
        store.refresh(now: now)
        #expect(alerts.isEmpty)

        source.post("new", "PreToolUse", at: now)
        store.refresh(now: now)
        source.post("new", "Notification", at: now)
        store.refresh(now: now)
        store.refresh(now: now)   // no change, no repeat
        source.post("new", "Stop", at: now)
        store.refresh(now: now)
        #expect(alerts == ["new:Needs you", "new:Done"])
    }

    @Test func endedSessionsAreRemovedFromDisk() {
        let source = FakeAgentSource()
        source.post("s", "SessionEnd", at: now)
        let store = AgentStatusStore(source: source)
        store.refresh(now: now)
        #expect(store.sessions.isEmpty)
        #expect(source.removed == ["s"])
    }

    @Test func longSilentWorkIsMarkedQuiet() {
        let source = FakeAgentSource()
        source.post("s", "PreToolUse", at: now.addingTimeInterval(-AgentStatusStore.quietAfter - 1))
        let store = AgentStatusStore(source: source)
        store.refresh(now: now)
        #expect(store.sessions.first?.state == .ready)
    }

    @Test func sessionsSortByUrgency() {
        let source = FakeAgentSource()
        source.post("done", "Stop", at: now)
        source.post("waiting", "Notification", at: now.addingTimeInterval(-100))
        source.post("busy", "PreToolUse", at: now)
        let store = AgentStatusStore(source: source)
        store.refresh(now: now)
        #expect(store.sessions.map(\.id) == ["waiting", "busy", "done"])
    }
}

@Suite("Claude Code hook script and installer")
struct ClaudeHookTests {
    /// Runs the real hook script with a fake HOME, like Claude Code would.
    func runHook(_ json: String, home: URL) throws -> (status: Int32, output: String) {
        let script = home.appendingPathComponent("hook.sh")
        try ClaudeHooks.script.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        try process.run()
        input.fileHandleForWriting.write(Data(json.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()
        let text = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return (process.terminationStatus, text)
    }

    @Test func scriptSavesTheEventWithoutPromptsOrFileContents() throws {
        let home = makeTempDirectory()
        let json = #"{"session_id":"abc-123","hook_event_name":"PreToolUse","cwd":"/p","prompt":"my secret plan","tool_name":"Write","tool_input":{"file_path":"/p/a.swift","content":"let password = 1"}}"#
        let result = try runHook(json, home: home)
        #expect(result.status == 0)
        #expect(result.output.isEmpty)   // must never print into Claude Code's output
        let saved = home.appendingPathComponent("Library/Application Support/Notchling/agents/abc-123.json")
        let text = try String(contentsOf: saved, encoding: .utf8)
        #expect(!text.contains("secret"))
        #expect(!text.contains("password"))
        #expect(AgentEvent(json: Data(text.utf8))?.toolDetail == "/p/a.swift")
    }

    @Test func scriptCannotBeTrickedIntoWritingOutsideItsFolder() throws {
        let home = makeTempDirectory()
        _ = try runHook(#"{"session_id":"../../../evil","hook_event_name":"Stop"}"#, home: home)
        let agents = home.appendingPathComponent("Library/Application Support/Notchling/agents")
        #expect(try FileManager.default.contentsOfDirectory(atPath: agents.path) == ["evil.json"])
    }

    @Test func scriptToleratesGarbageInput() throws {
        let home = makeTempDirectory()
        let result = try runHook("this is not json", home: home)
        #expect(result.status == 0)
        let agents = home.appendingPathComponent("Library/Application Support/Notchling/agents")
        #expect(try FileManager.default.contentsOfDirectory(atPath: agents.path).filter { !$0.hasPrefix(".") }.isEmpty)
    }

    let command = "\"/Users/me/Library/Application Support/Notchling/claude-hook.sh\""

    @Test func installKeepsOtherSettingsAndHooksAndIsIdempotent() throws {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]],
        ]
        let once = ClaudeHooks.installing(into: existing, command: command)
        let twice = ClaudeHooks.installing(into: once, command: command)
        #expect(NSDictionary(dictionary: once) == NSDictionary(dictionary: twice))
        #expect(once["model"] as? String == "opus")
        let stop = try #require((once["hooks"] as? [String: Any])?["Stop"] as? [[String: Any]])
        #expect(stop.count == 2)   // theirs + ours
        #expect(ClaudeHooks.isInstalled(in: once, command: command))
        let pre = try #require((once["hooks"] as? [String: Any])?["PreToolUse"] as? [[String: Any]])
        #expect(pre.first?["matcher"] as? String == "*")
    }

    @Test func uninstallRemovesOnlyOurs() throws {
        let existing: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "say done"]]]]]]
        let removed = ClaudeHooks.removing(from: ClaudeHooks.installing(into: existing, command: command),
                                           command: command)
        #expect(NSDictionary(dictionary: removed) == NSDictionary(dictionary: existing))
        #expect(ClaudeHooks.removing(from: ClaudeHooks.installing(into: [:], command: command),
                                     command: command).isEmpty)
    }

    @Test func installerWritesScriptSettingsAndBackup() throws {
        let root = makeTempDirectory()
        let settingsURL = root.appendingPathComponent(".claude/settings.json")
        try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"theme":"dark"}"#.utf8).write(to: settingsURL)
        let installer = ClaudeHookInstaller(settingsURL: settingsURL, supportDirectory: root.appendingPathComponent("support"))

        try installer.install()
        #expect(installer.isInstalled)
        #expect(FileManager.default.fileExists(atPath: installer.backupURL.path))
        let written = try installer.readSettings()
        #expect(written["theme"] as? String == "dark")

        try installer.uninstall()
        #expect(!installer.isInstalled)
        #expect(NSDictionary(dictionary: try installer.readSettings()) == NSDictionary(dictionary: ["theme": "dark"]))
    }

    @Test func installerRefusesToOverwriteBrokenSettings() throws {
        let root = makeTempDirectory()
        let settingsURL = root.appendingPathComponent("settings.json")
        try Data("{ not valid json".utf8).write(to: settingsURL)
        let installer = ClaudeHookInstaller(settingsURL: settingsURL, supportDirectory: root.appendingPathComponent("s"))
        #expect(throws: (any Error).self) { try installer.install() }
        #expect(try String(contentsOf: settingsURL, encoding: .utf8) == "{ not valid json")
    }

    @Test func directorySourceSkipsTempFilesAndCleansUpOldOnes() throws {
        let dir = makeTempDirectory()
        let event = #"{"session_id":"s1","hook_event_name":"Stop"}"#
        try Data(event.utf8).write(to: dir.appendingPathComponent("s1.json"))
        try Data(event.utf8).write(to: dir.appendingPathComponent(".event.tmp"))
        let old = dir.appendingPathComponent("old.json")
        try Data(#"{"session_id":"old","hook_event_name":"Stop"}"#.utf8).write(to: old)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-3 * 86_400)],
                                              ofItemAtPath: old.path)
        let source = DirectoryAgentEventSource(directory: dir)
        #expect(source.latestEvents().map(\.event.sessionID) == ["s1"])
        #expect(!FileManager.default.fileExists(atPath: old.path))
        source.remove(sessionID: "s1")
        #expect(source.latestEvents().isEmpty)
    }
}
