import Foundation

/// Answering Claude Code's permission prompts from the notch.
///
/// Claude Code runs a `PermissionRequest` hook when it's about to ask you to allow a tool.
/// Ours writes the request to a file and waits a few seconds for an answer file from the app.
/// Anything other than a clear Allow/Deny (no answer in time, "ask in terminal", Notchling not
/// running, approvals switched off) prints nothing, which Claude Code treats as "no decision",
/// so it asks in the terminal exactly as it would without Notchling. Failing safe is the point:
/// the notch can only ever answer a request you saw, and never answers on its own.
public enum ClaudeApprovals {
    public static let scriptName = "claude-approve.sh"
    /// Seconds Claude Code lets the hook run. Comfortably above the longest wait the app allows.
    static let hookTimeout = 150
    public static let waitRange: ClosedRange<Int> = 10...120
    public static let defaultWait = 30

    static let enabledFlag = "approvals-enabled"
    static let waitFile = "approval-wait"

    /// `${var:?}` makes the shell stop rather than run `rm` on a path built from an empty
    /// variable, so a bug can never turn a cleanup into a delete of the wrong folder.
    public static let script = """
    #!/bin/sh
    # Notchling: answer Claude Code's permission prompts from the MacBook notch.
    # No answer in time (or Notchling closed) = no decision, so Claude Code asks as usual.
    # Installed by Notchling > Settings > Claude Code. Remove it there, too.
    base="$HOME/Library/Application Support/Notchling"
    dir="$base/approvals"
    [ -f "$base/approvals-enabled" ] || exit 0
    [ -n "$NOTCHLING_TEST_SKIP_PROCESS_CHECK" ] || /usr/bin/pgrep -x Notchling >/dev/null 2>&1 || exit 0
    mkdir -p "$dir" 2>/dev/null || exit 0
    id=$(/usr/bin/uuidgen 2>/dev/null | tr -cd 'A-Za-z0-9-')
    [ -n "$id" ] || exit 0
    tmp="$dir/.request.$id"
    cat > "$tmp"
    for key in transcript_path permission_suggestions tool_input.content tool_input.old_string tool_input.new_string tool_input.edits tool_input.new_source; do
        /usr/bin/plutil -remove "$key" "$tmp" >/dev/null 2>&1
    done
    mv -f "$tmp" "${dir:?}/${id:?}.request.json" || exit 0
    wait=$(cat "$base/approval-wait" 2>/dev/null | tr -cd '0-9')
    [ -n "$wait" ] || wait=30
    [ "$wait" -ge 10 ] 2>/dev/null || wait=10
    [ "$wait" -le 120 ] 2>/dev/null || wait=120
    ticks=$((wait * 5))
    answer=""
    i=0
    while [ "$i" -lt "$ticks" ]; do
        if [ -f "${dir:?}/${id:?}.decision" ]; then answer=$(cat "${dir:?}/${id:?}.decision" 2>/dev/null); break; fi
        sleep 0.2
        i=$((i + 1))
    done
    rm -f "${dir:?}/${id:?}.request.json" "${dir:?}/${id:?}.decision"
    case "$answer" in
        allow) printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}' ;;
        deny) printf '%s\\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Denied from the notch (Notchling)."}}}' ;;
    esac
    exit 0

    """
}

public enum ApprovalDecision: String, Sendable {
    case allow, deny
    /// Hand it back to Claude Code's normal prompt right away.
    case ask
}

/// One pending permission request.
public struct ApprovalRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public var sessionID: String
    public var project: String
    public var toolName: String
    /// "Run a command", "Edit NotchView.swift", "Use github".
    public var title: String
    /// The exact command or path, for the user to check before allowing. Never Claude's
    /// paraphrase: you approve what will actually run.
    public var detail: String?
    /// Claude's description of what it's doing ("Run the test suite"), shown as a caption.
    public var note: String?
    public var createdAt: Date

    public init(id: String, sessionID: String, project: String, toolName: String, title: String,
                detail: String?, note: String? = nil, createdAt: Date) {
        self.id = id
        self.sessionID = sessionID
        self.project = project
        self.toolName = toolName
        self.title = title
        self.detail = detail
        self.note = note
        self.createdAt = createdAt
    }

    public init?(id: String, json data: Data, createdAt: Date) {
        guard let event = AgentEvent(json: data) else { return nil }
        let tool = event.toolName ?? "a tool"
        self.init(id: id, sessionID: event.sessionID,
                  project: event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code",
                  toolName: tool, title: Self.title(tool: tool, detail: event.toolTarget),
                  detail: event.toolTarget.map { String($0.prefix(600)) },
                  note: event.toolDescription.map { String($0.prefix(120)) }, createdAt: createdAt)
    }

    /// Phrased as what Claude wants to do: "Claude wants to: Run a command".
    static func title(tool: String, detail: String?) -> String {
        let file = detail.map { URL(fileURLWithPath: $0).lastPathComponent }
        switch tool {
        case "Bash": return "Run a command"
        case "Edit", "MultiEdit", "NotebookEdit": return "Edit \(file ?? "a file")"
        case "Write": return "Create \(file ?? "a file")"
        case "WebFetch": return "Open a web page"
        case "WebSearch": return "Search the web"
        default:
            let described = AgentActivity.describe(tool: tool, detail: detail)
            return described.prefix(1).uppercased() + described.dropFirst()
        }
    }
}

public protocol ApprovalChannel: Sendable {
    func pending() -> [(id: String, data: Data, date: Date)]
    /// Delivers a decision. False if the request is gone (answered elsewhere or timed out).
    func answer(_ id: String, with decision: ApprovalDecision) -> Bool
    func setEnabled(_ enabled: Bool, waitSeconds: Int)
}

/// The folder the hook script and the app use to talk to each other.
public struct DirectoryApprovalChannel: ApprovalChannel {
    let base: URL
    var folder: URL { base.appendingPathComponent("approvals") }

    public init(base: URL = ClaudeHookInstaller.defaultSupportDirectory) {
        self.base = base
    }

    public func pending() -> [(id: String, data: Data, date: Date)] {
        let suffix = ".request.json"
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        ) else { return [] }
        return files.filter { $0.lastPathComponent.hasSuffix(suffix) }.compactMap { url in
            let id = String(url.lastPathComponent.dropLast(suffix.count))
            guard Self.isValid(id), let data = try? Data(contentsOf: url) else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date()
            return (id, data, date)
        }
    }

    public func answer(_ id: String, with decision: ApprovalDecision) -> Bool {
        guard Self.isValid(id),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent("\(id).request.json").path)
        else { return false }
        // Write-then-rename, so the script never reads a half-written answer.
        let temp = folder.appendingPathComponent(".decision.\(id)")
        let final = folder.appendingPathComponent("\(id).decision")
        do {
            try Data(decision.rawValue.utf8).write(to: temp)
            if FileManager.default.fileExists(atPath: final.path) {
                _ = try FileManager.default.replaceItemAt(final, withItemAt: temp)
            } else {
                try FileManager.default.moveItem(at: temp, to: final)
            }
            return true
        } catch {
            try? FileManager.default.removeItem(at: temp)
            return false
        }
    }

    public func setEnabled(_ enabled: Bool, waitSeconds: Int) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        let flag = base.appendingPathComponent(ClaudeApprovals.enabledFlag)
        if enabled {
            fileManager.createFile(atPath: flag.path, contents: Data())
        } else {
            try? fileManager.removeItem(at: flag)
        }
        let wait = waitSeconds.clamped(to: ClaudeApprovals.waitRange)
        try? Data("\(wait)".utf8).write(to: base.appendingPathComponent(ClaudeApprovals.waitFile), options: .atomic)
    }

    /// IDs come from `uuidgen` in the script; anything else is ignored, so a crafted file name
    /// can't make the app write outside the folder.
    static func isValid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 64 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
}

/// Pending permission requests, oldest first, for the approval card.
@MainActor
public final class ApprovalStore: ObservableObject {
    @Published public private(set) var requests: [ApprovalRequest] = []
    /// Called with requests that just appeared, so the app can open the notch and chime.
    public var onNewRequests: (([ApprovalRequest]) -> Void)?
    public private(set) var waitSeconds: Int

    private let channel: ApprovalChannel
    /// Answered here, but the script hasn't cleaned up yet; keep them hidden meanwhile.
    private var answered: Set<String> = []

    public init(channel: ApprovalChannel, waitSeconds: Int = ClaudeApprovals.defaultWait) {
        self.channel = channel
        self.waitSeconds = waitSeconds
    }

    public func setEnabled(_ enabled: Bool, waitSeconds: Int) {
        self.waitSeconds = waitSeconds.clamped(to: ClaudeApprovals.waitRange)
        channel.setEnabled(enabled, waitSeconds: self.waitSeconds)
        if !enabled { requests = [] }
    }

    public func refresh() {
        let found = channel.pending().compactMap { ApprovalRequest(id: $0.id, json: $0.data, createdAt: $0.date) }
        answered.formIntersection(Set(found.map(\.id)))
        let next = found.filter { !answered.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        let known = Set(requests.map(\.id))
        let fresh = next.filter { !known.contains($0.id) }
        if next != requests { requests = next }
        if !fresh.isEmpty { onNewRequests?(fresh) }
    }

    /// Returns false if it was too late (Claude Code already moved on to its own prompt).
    @discardableResult
    public func answer(_ request: ApprovalRequest, _ decision: ApprovalDecision) -> Bool {
        let delivered = channel.answer(request.id, with: decision)
        answered.insert(request.id)
        requests.removeAll { $0.id == request.id }
        return delivered
    }

    /// Seconds left before Claude Code asks in the terminal instead.
    public func secondsLeft(for request: ApprovalRequest, now: Date) -> Int {
        let deadline = request.createdAt.addingTimeInterval(TimeInterval(waitSeconds))
        return max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }
}
