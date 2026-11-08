import Foundation

/// Where hook events come from. The real one reads the folder the hook script writes to.
public protocol AgentEventSource: Sendable {
    /// The latest event of each session, with when it happened.
    func latestEvents() -> [(event: AgentEvent, date: Date)]
    /// Forgets a session (after it ends).
    func remove(sessionID: String)
}

public struct DirectoryAgentEventSource: AgentEventSource {
    let directory: URL
    /// Files untouched this long belong to sessions that crashed or were killed; clean them up.
    let maxAge: TimeInterval
    let clock: @Sendable () -> Date

    public init(directory: URL, maxAge: TimeInterval = 24 * 3600, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.maxAge = maxAge
        self.clock = clock
    }

    public func latestEvents() -> [(event: AgentEvent, date: Date)] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                      options: [.skipsHiddenFiles]) else { return [] }
        let now = clock()
        return files.filter { $0.pathExtension == "json" }.compactMap { url in
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(date) > maxAge {
                try? fileManager.removeItem(at: url)
                return nil
            }
            guard let data = try? Data(contentsOf: url), let event = AgentEvent(json: data) else { return nil }
            return (event, date)
        }
    }

    public func remove(sessionID: String) {
        let safe = sessionID.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safe.isEmpty else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent("\(safe).json"))
    }
}

/// Live list of Claude Code sessions for the agent widgets.
@MainActor
public final class AgentStatusStore: ObservableObject {
    @Published public private(set) var sessions: [AgentSession] = []

    /// Called when a session starts needing you or finishes, so the app can chime.
    /// Not called for what's already on disk at launch.
    public var onAttention: ((AgentSession) -> Void)?

    /// A "working" session with no events for this long probably stopped without saying so.
    public static let quietAfter: TimeInterval = 30 * 60

    private let source: AgentEventSource
    private var hasLoaded = false

    public init(source: AgentEventSource) {
        self.source = source
    }

    public func refresh(now: Date = Date()) {
        var next: [AgentSession] = []
        for (event, date) in source.latestEvents() {
            guard var session = AgentActivity.session(from: event, at: date) else {
                source.remove(sessionID: event.sessionID)
                continue
            }
            if session.state == .working, now.timeIntervalSince(date) > Self.quietAfter {
                session.state = .ready
                session.activity = "Quiet for a while"
            }
            next.append(session)
        }
        next.sort { ($0.state, $0.updatedAt) > ($1.state, $1.updatedAt) }

        if hasLoaded {
            let previous = Dictionary(uniqueKeysWithValues: sessions.map { ($0.id, $0.state) })
            for session in next where [.needsInput, .done].contains(session.state)
                && previous[session.id] != session.state {
                onAttention?(session)
            }
        }
        hasLoaded = true
        if next != sessions { sessions = next }
    }

    public func headline(at now: Date) -> AgentSession? {
        AgentActivity.headline(of: sessions, now: now)
    }
}

/// The Settings switch for the Claude Code connection.
@MainActor
public final class ClaudeHookSetup: ObservableObject {
    @Published public private(set) var isInstalled: Bool
    @Published public private(set) var lastError: String?
    public let installer: ClaudeHookInstaller

    public init(installer: ClaudeHookInstaller = ClaudeHookInstaller()) {
        self.installer = installer
        isInstalled = installer.isInstalled
    }

    public func install() {
        run { try installer.install() }
    }

    public func uninstall() {
        run { try installer.uninstall() }
    }

    private func run(_ change: () throws -> Void) {
        do {
            try change()
            lastError = nil
        } catch {
            lastError = "Couldn't update ~/.claude/settings.json: \(error.localizedDescription)"
        }
        isInstalled = installer.isInstalled
    }
}
