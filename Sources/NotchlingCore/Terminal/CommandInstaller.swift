import Foundation

/// Puts the `notch` command on the user's PATH as a symlink to the copy inside the app,
/// so it updates whenever the app does.
public struct CommandInstaller: Sendable {
    public struct Location: Equatable, Sendable {
        public let directory: URL
        public let isWritable: Bool
        public let isOnPath: Bool

        public init(directory: URL, isWritable: Bool, isOnPath: Bool) {
            self.directory = directory
            self.isWritable = isWritable
            self.isOnPath = isOnPath
        }
    }

    public let source: URL
    public let name = "notch"

    public init(source: URL) {
        self.source = source
    }

    /// Prefer a writable folder that's already on PATH (Homebrew's, on Apple silicon), so
    /// `notch` works in new terminals with no setup; else ~/.local/bin, which the user adds.
    public static func choose(from locations: [Location]) -> Location? {
        locations.first { $0.isWritable && $0.isOnPath } ?? locations.first { $0.isWritable }
    }

    public static func candidates(path: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
                                  home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [Location] {
        let onPath = Set(path.split(separator: ":").map(String.init))
        let local = home.appendingPathComponent(".local/bin")
        return ["/opt/homebrew/bin", "/usr/local/bin", local.path].map { dir in
            let url = URL(fileURLWithPath: dir)
            let writable = FileManager.default.isWritableFile(atPath: dir) || dir == local.path
            // GUI apps get a minimal PATH, so also count the usual shell folders as "on PATH".
            let usual = dir == "/opt/homebrew/bin" || dir == "/usr/local/bin"
            return Location(directory: url, isWritable: writable, isOnPath: onPath.contains(dir) || usual)
        }
    }

    /// Where it's installed, if a link to this app's copy exists in any candidate folder.
    public func installedLocation(in locations: [Location]) -> URL? {
        locations.map { $0.directory.appendingPathComponent(name) }.first(where: pointsToUs)
    }

    public enum InstallError: LocalizedError, Equatable {
        case noWritableFolder
        case occupied(String)

        public var errorDescription: String? {
            switch self {
            case .noWritableFolder: return "No folder on your PATH is writable."
            case .occupied(let path): return "Something else is already installed at \(path), so it was left alone."
            }
        }
    }

    @discardableResult
    public func install(into location: Location) throws -> URL {
        let link = location.directory.appendingPathComponent(name)
        let fileManager = FileManager.default
        if (try? fileManager.destinationOfSymbolicLink(atPath: link.path)) != nil || fileManager.fileExists(atPath: link.path) {
            // Only ever replace our own link, never another tool that happens to be called `notch`.
            guard pointsToUs(link) else { throw InstallError.occupied(link.path) }
            try fileManager.removeItem(at: link)
        }
        try fileManager.createDirectory(at: location.directory, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(at: link, withDestinationURL: source)
        return link
    }

    public func uninstall(from locations: [Location]) {
        for link in locations.map({ $0.directory.appendingPathComponent(name) }) where pointsToUs(link) {
            try? FileManager.default.removeItem(at: link)
        }
    }

    func pointsToUs(_ link: URL) -> Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return URL(fileURLWithPath: target).standardizedFileURL == source.standardizedFileURL
            || target.hasSuffix("Notchling.app/Contents/MacOS/notch")
    }
}

/// Settings state for the command.
@MainActor
public final class CommandSetup: ObservableObject {
    @Published public private(set) var installedAt: URL?
    @Published public private(set) var message: String?
    public let installer: CommandInstaller
    private let locations: () -> [CommandInstaller.Location]

    public init(installer: CommandInstaller,
                locations: @escaping () -> [CommandInstaller.Location] = { CommandInstaller.candidates() }) {
        self.installer = installer
        self.locations = locations
        installedAt = installer.installedLocation(in: locations())
    }

    public var isAvailable: Bool { FileManager.default.isExecutableFile(atPath: installer.source.path) }

    public func install() {
        guard let location = CommandInstaller.choose(from: locations()) else {
            message = CommandInstaller.InstallError.noWritableFolder.errorDescription
            return
        }
        do {
            installedAt = try installer.install(into: location)
            message = location.isOnPath ? nil
                : "Installed in \(location.directory.path). Add it to your PATH: "
                + "echo 'export PATH=\"$HOME/.local/bin:$PATH\"' >> ~/.zshrc"
        } catch {
            message = error.localizedDescription
        }
    }

    public func uninstall() {
        installer.uninstall(from: locations())
        installedAt = installer.installedLocation(in: locations())
        message = nil
    }
}
