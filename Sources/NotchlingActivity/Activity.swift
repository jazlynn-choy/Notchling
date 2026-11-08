import Foundation

/// Something happening in a terminal that the notch should show: a build running, a
/// deploy finished, a message from a script. Written by the `notch` command, read by the app.
public struct Activity: Codable, Equatable, Identifiable, Sendable {
    public enum State: String, Codable, Sendable {
        case running, succeeded, failed
        /// A one-off message (`notch "Deploy finished"`).
        case info
    }

    public var id: String
    public var title: String
    /// The latest line of output, or the result: "Finished in 12s".
    public var detail: String?
    /// 0...1 when the output shows a percentage or "n/m", else nil (an indeterminate spinner).
    public var progress: Double?
    public var state: State
    public var startedAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, title: String, detail: String? = nil, progress: Double? = nil,
                state: State, startedAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.detail = detail
        self.progress = progress
        self.state = state
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var isFinished: Bool { state != .running }
}

/// The shared folder: one JSON file per activity, replaced atomically on every update.
public struct ActivityFolder: Sendable {
    public let url: URL

    public init(url: URL = ActivityFolder.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Notchling/activities")
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }()

    public func write(_ activity: Activity) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Self.encoder.encode(activity).write(to: file(for: activity.id), options: .atomic)
    }

    public func readAll() -> [Activity] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) else { return [] }
        return files.filter { $0.pathExtension == "json" }.compactMap { file in
            (try? Data(contentsOf: file)).flatMap { try? Self.decoder.decode(Activity.self, from: $0) }
        }
    }

    public func remove(id: String) {
        try? FileManager.default.removeItem(at: file(for: id))
    }

    /// IDs are filtered to safe characters so one can never point outside the folder.
    private func file(for id: String) -> URL {
        let safe = id.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        return url.appendingPathComponent("\(safe.isEmpty ? "activity" : safe).json")
    }
}

/// Reading progress and a readable status line out of raw command output.
public enum OutputParser {
    /// The last percentage ("45%", "45.5 %") or fraction ("[3/10]", "3 of 10") in a line.
    public static func progress(in line: String) -> Double? {
        let text = stripANSI(line)
        if let match = text.matches(of: /(\d{1,3}(?:\.\d+)?)\s?%/).last, let value = Double(match.1), value <= 100 {
            return value / 100
        }
        if let match = text.matches(of: /(\d+)\s*(?:\/|of)\s*(\d+)/).last,
           let done = Double(match.1), let total = Double(match.2), total > 0, done <= total {
            return done / total
        }
        return nil
    }

    /// Removes colour codes and carriage-return overwrites, keeping what a terminal would show.
    public static func stripANSI(_ text: String) -> String {
        let lastSegment = text.split(separator: "\r", omittingEmptySubsequences: true).last.map(String.init) ?? text
        return lastSegment.replacing(/\e\[[0-9;?]*[ -\/]*[@-~]/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "1m 5s", "12s", "850ms".
    public static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 1 { return "\(Int(seconds * 1000))ms" }
        let total = Int(seconds.rounded())
        return total < 60 ? "\(total)s" : "\(total / 60)m \(total % 60)s"
    }
}
