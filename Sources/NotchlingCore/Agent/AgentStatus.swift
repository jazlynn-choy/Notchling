import Foundation

/// What a Claude Code session is up to, as far as the notch is concerned.
public enum AgentState: String, Sendable, Comparable {
    case ready, working, needsInput, done

    /// Higher = more deserving of the wing's single spot.
    var priority: Int {
        switch self {
        case .needsInput: return 3
        case .working: return 2
        case .done: return 1
        case .ready: return 0
        }
    }

    public static func < (lhs: AgentState, rhs: AgentState) -> Bool { lhs.priority < rhs.priority }

    public var label: String {
        switch self {
        case .ready: return "Ready"
        case .working: return "Working"
        case .needsInput: return "Needs you"
        case .done: return "Done"
        }
    }
}

public struct AgentSession: Identifiable, Equatable, Sendable {
    public let id: String
    /// The folder Claude Code is working in, e.g. "Camera Notch".
    public var project: String
    public var state: AgentState
    /// "Editing NotchView.swift", "Running swift test", "Claude needs your permission to use Bash".
    public var activity: String
    public var updatedAt: Date

    public init(id: String, project: String, state: AgentState, activity: String, updatedAt: Date) {
        self.id = id
        self.project = project
        self.state = state
        self.activity = activity
        self.updatedAt = updatedAt
    }
}

/// One Claude Code hook event, as written by the hook script. Only the fields the notch
/// uses; prompts and file contents are stripped by the script before they reach disk.
public struct AgentEvent: Equatable, Sendable {
    public var sessionID: String
    public var name: String
    public var cwd: String?
    public var toolName: String?
    public var toolDetail: String?
    public var message: String?
    /// The exact command (Bash) or path the tool acts on, never a paraphrase. What a
    /// permission prompt must show, since a description can be vague or wrong.
    public var toolTarget: String?
    /// Claude's own one-line description of the tool call, if it gave one.
    public var toolDescription: String?

    public init(sessionID: String, name: String, cwd: String? = nil, toolName: String? = nil,
                toolDetail: String? = nil, message: String? = nil, toolTarget: String? = nil,
                toolDescription: String? = nil) {
        self.sessionID = sessionID
        self.name = name
        self.cwd = cwd
        self.toolName = toolName
        self.toolDetail = toolDetail
        self.message = message
        self.toolTarget = toolTarget
        self.toolDescription = toolDescription
    }

    /// Lenient: unknown fields are ignored, and only `session_id` and `hook_event_name` are required.
    public init?(json data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = object["session_id"] as? String, !id.isEmpty,
              let name = object["hook_event_name"] as? String else { return nil }
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let detail = ["file_path", "notebook_path", "description", "command", "pattern", "url", "query"]
            .lazy.compactMap { input[$0] as? String }.first { !$0.isEmpty }
        let target = ["command", "file_path", "notebook_path", "url", "pattern", "query"]
            .lazy.compactMap { input[$0] as? String }.first { !$0.isEmpty }
        self.init(sessionID: id, name: name, cwd: object["cwd"] as? String,
                  toolName: object["tool_name"] as? String, toolDetail: detail,
                  message: object["message"] as? String, toolTarget: target,
                  toolDescription: (input["description"] as? String).flatMap { $0.isEmpty ? nil : $0 })
    }
}

public enum AgentActivity {
    /// Turns an event into the session's new state, or nil when the session ended.
    public static func session(from event: AgentEvent, at date: Date) -> AgentSession? {
        let project = event.cwd.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "Claude Code"
        let state: AgentState
        let activity: String
        switch event.name {
        case "SessionEnd":
            return nil
        case "SessionStart":
            (state, activity) = (.ready, "Ready")
        case "UserPromptSubmit", "PostToolUse", "SubagentStop", "PreCompact":
            (state, activity) = (.working, "Thinking…")
        case "PreToolUse":
            (state, activity) = (.working, describe(tool: event.toolName ?? "", detail: event.toolDetail))
        case "Notification":
            (state, activity) = (.needsInput, event.message ?? "Waiting for you")
        case "Stop":
            (state, activity) = (.done, "Finished")
        default:
            (state, activity) = (.working, "Working…")
        }
        return AgentSession(id: event.sessionID, project: project, state: state, activity: activity, updatedAt: date)
    }

    /// "Edit" + "/x/NotchView.swift" → "Editing NotchView.swift".
    public static func describe(tool: String, detail: String?) -> String {
        let file = detail.map { URL(fileURLWithPath: $0).lastPathComponent }
        switch tool {
        case "Edit", "MultiEdit", "Write", "NotebookEdit": return "Editing \(file ?? "a file")"
        case "Read": return "Reading \(file ?? "a file")"
        case "Bash": return "Running \(shorten(detail ?? "a command"))"
        case "Grep", "Glob": return "Searching the code"
        case "WebFetch", "WebSearch": return "Looking on the web"
        case "Task", "Agent": return "Running a subagent"
        case "TodoWrite": return "Planning"
        default:
            if tool.hasPrefix("mcp__") {
                let server = tool.split(separator: "_", omittingEmptySubsequences: true).dropFirst().first
                return "Using \(server.map(String.init) ?? "a tool")"
            }
            return tool.isEmpty ? "Working…" : "Using \(tool)"
        }
    }

    static func shorten(_ text: String, limit: Int = 40) -> String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
        return line.count > limit ? String(line.prefix(limit - 1)) + "…" : line
    }

    /// The session that gets the wing: whoever needs you, else whoever's working, else a
    /// recent finish. Old "done" sessions fade out of the wing (but stay in the card).
    public static func headline(of sessions: [AgentSession], now: Date,
                                doneFor: TimeInterval = 10 * 60) -> AgentSession? {
        sessions
            .filter { $0.state != .ready && ($0.state != .done || now.timeIntervalSince($0.updatedAt) < doneFor) }
            .max { ($0.state, $0.updatedAt) < ($1.state, $1.updatedAt) }
    }
}
