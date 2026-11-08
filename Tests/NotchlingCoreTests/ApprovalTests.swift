import Foundation
import Testing
@testable import NotchlingCore

/// Runs the real approval hook script, plays the app's part through `DirectoryApprovalChannel`,
/// and checks what Claude Code would receive.
@Suite("Approve from the notch: hook script")
struct ApprovalScriptTests {
    // swiftlint:disable:next line_length - JSON exactly as Claude Code sends/receives it
    let request = #"{"session_id":"s1","hook_event_name":"PermissionRequest","cwd":"/p/App","tool_name":"Bash","tool_input":{"command":"npm test"},"permission_suggestions":[{"type":"addRules"}],"transcript_path":"/secret/transcript.jsonl"}"#

    struct Run {
        let process: Process
        let output: Pipe
        let home: URL
        var base: URL { home.appendingPathComponent("Library/Application Support/Notchling") }
    }

    func start(enabled: Bool = true) throws -> Run {
        let home = makeTempDirectory()
        let base = home.appendingPathComponent("Library/Application Support/Notchling")
        let channel = DirectoryApprovalChannel(base: base)
        channel.setEnabled(enabled, waitSeconds: 10)
        let script = home.appendingPathComponent("approve.sh")
        try ClaudeApprovals.script.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path]
        process.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin", "NOTCHLING_TEST_SKIP_PROCESS_CHECK": "1"]
        let input = Pipe(), output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        try process.run()
        input.fileHandleForWriting.write(Data(request.utf8))
        try input.fileHandleForWriting.close()
        return Run(process: process, output: output, home: home)
    }

    func waitForRequest(_ channel: DirectoryApprovalChannel) async throws -> (id: String, data: Data, date: Date) {
        for _ in 0..<100 {
            if let first = channel.pending().first { return first }
            try await Task.sleep(for: .milliseconds(20))
        }
        throw CancellationError()
    }

    func finish(_ run: Run) -> String {
        run.process.waitUntilExit()
        let text = String(data: run.output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @Test(arguments: [
        (ApprovalDecision.allow, #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}"#),
        (ApprovalDecision.deny,
         // swiftlint:disable:next line_length - JSON exactly as Claude Code sends/receives it
         #"{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the notch (Notchling)."}}}"#),
        (ApprovalDecision.ask, ""),   // "Ask in terminal": no decision, so Claude Code's own prompt shows
    ])
    func answerReachesClaudeCode(decision: ApprovalDecision, expected: String) async throws {
        let run = try start()
        let channel = DirectoryApprovalChannel(base: run.base)
        let pending = try await waitForRequest(channel)

        let request = try #require(ApprovalRequest(id: pending.id, json: pending.data, createdAt: pending.date))
        #expect(request.title == "Run a command")
        #expect(request.detail == "npm test")
        #expect(request.project == "App")
        let saved = String(data: pending.data, encoding: .utf8) ?? ""
        #expect(!saved.contains("transcript"))   // stripped before it touches disk

        #expect(channel.answer(pending.id, with: decision))
        #expect(finish(run) == expected)
        #expect(run.process.terminationStatus == 0)
        #expect(channel.pending().isEmpty)                                   // cleaned up
        #expect(!channel.answer(pending.id, with: .allow))                   // too late now
    }

    @Test func switchedOffMeansNoDecisionAndNoWaiting() throws {
        let started = Date()
        let run = try start(enabled: false)
        #expect(finish(run).isEmpty)
        #expect(Date().timeIntervalSince(started) < 3)
    }

    @Test func outputIsValidJSONForClaudeCode() throws {
        for decision in ["allow", "deny"] {
            let line = ClaudeApprovals.script.split(separator: "\n").first { $0.contains("\(decision)) printf") }
            let json = try #require(line?.split(separator: "'").dropFirst(3).first)
            let object = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any]
            let output = object?["hookSpecificOutput"] as? [String: Any]
            #expect(output?["hookEventName"] as? String == "PermissionRequest")
            #expect((output?["decision"] as? [String: Any])?["behavior"] as? String == decision)
        }
    }
}

final class FakeApprovalChannel: ApprovalChannel, @unchecked Sendable {
    var files: [(id: String, data: Data, date: Date)] = []
    var answers: [(String, ApprovalDecision)] = []
    var enabled: (Bool, Int)?

    func pending() -> [(id: String, data: Data, date: Date)] { files }
    func answer(_ id: String, with decision: ApprovalDecision) -> Bool {
        answers.append((id, decision))
        return files.contains { $0.id == id }
    }
    func setEnabled(_ enabled: Bool, waitSeconds: Int) { self.enabled = (enabled, waitSeconds) }

    func add(_ id: String, tool: String, detail: String, at date: Date) {
        // swiftlint:disable:next line_length - JSON exactly as Claude Code sends/receives it
        let json = #"{"session_id":"s","hook_event_name":"PermissionRequest","cwd":"/x/Proj","tool_name":"\#(tool)","tool_input":{"file_path":"\#(detail)","command":"\#(detail)"}}"#
        files.append((id, Data(json.utf8), date))
    }
}

@MainActor
@Suite("Approve from the notch: store")
struct ApprovalStoreTests {
    let now = Date(timeIntervalSince1970: 1_794_063_600)

    @Test func newRequestsOpenTheNotchOnceAndListOldestFirst() {
        let channel = FakeApprovalChannel()
        let store = ApprovalStore(channel: channel)
        var opened: [[String]] = []
        store.onNewRequests = { opened.append($0.map(\.id)) }
        channel.add("b", tool: "Bash", detail: "ls", at: now.addingTimeInterval(1))
        channel.add("a", tool: "Edit", detail: "/x/Main.swift", at: now)
        store.refresh()
        store.refresh()
        #expect(store.requests.map(\.id) == ["a", "b"])
        #expect(store.requests.first?.title == "Edit Main.swift")
        #expect(opened == [["b", "a"]] || opened == [["a", "b"]])
        #expect(opened.count == 1)
    }

    @Test func answeredRequestsStayHiddenUntilTheScriptCleansUp() {
        let channel = FakeApprovalChannel()
        let store = ApprovalStore(channel: channel)
        channel.add("a", tool: "Bash", detail: "rm -rf build", at: now)
        store.refresh()
        let request = store.requests[0]
        #expect(store.answer(request, .deny))
        store.refresh()   // the script hasn't removed its file yet
        #expect(store.requests.isEmpty)
        #expect(channel.answers.map(\.1) == [.deny])
    }

    @Test func countdownAndSettings() {
        let channel = FakeApprovalChannel()
        let store = ApprovalStore(channel: channel)
        store.setEnabled(true, waitSeconds: 500)
        #expect(store.waitSeconds == ClaudeApprovals.waitRange.upperBound)
        #expect(channel.enabled?.0 == true && channel.enabled?.1 == 120)
        let request = ApprovalRequest(id: "a", sessionID: "s", project: "P", toolName: "Bash", title: "Run a command",
                                      detail: nil, createdAt: now)
        #expect(store.secondsLeft(for: request, now: now.addingTimeInterval(100)) == 20)
        #expect(store.secondsLeft(for: request, now: now.addingTimeInterval(500)) == 0)
    }

    @Test func craftedIDsAreRejected() {
        #expect(DirectoryApprovalChannel.isValid("3F2504E0-4F89-11D3-9A0C-0305E82C3301"))
        #expect(!DirectoryApprovalChannel.isValid("../../etc/passwd"))
        #expect(!DirectoryApprovalChannel.isValid(""))
    }

    @Test func installerAddsAndRemovesThePermissionHook() throws {
        let status = "\"/s/claude-hook.sh\"", approve = "\"/s/claude-approve.sh\""
        let installed = ClaudeHooks.installing(into: ["theme": "dark"], command: status, approvalCommand: approve)
        let entry = try #require(((installed["hooks"] as? [String: Any])?["PermissionRequest"] as? [[String: Any]])?.first)
        let hook = try #require((entry["hooks"] as? [[String: Any]])?.first)
        #expect(entry["matcher"] as? String == "*")
        #expect(hook["timeout"] as? Int ?? 0 > ClaudeApprovals.waitRange.upperBound)
        #expect(ClaudeHooks.isInstalled(in: installed, command: status, approvalCommand: approve))
        #expect(!ClaudeHooks.isInstalled(in: ClaudeHooks.installing(into: [:], command: status),
                                         command: status, approvalCommand: approve))
        let removed = ClaudeHooks.removing(from: ClaudeHooks.removing(from: installed, command: status), command: approve)
        #expect(NSDictionary(dictionary: removed) == NSDictionary(dictionary: ["theme": "dark"]))
    }
}
