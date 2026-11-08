import Foundation

/// One row in the notch's to-do list, backed by an Apple Reminders item.
public struct Todo: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var isDone: Bool
    public var due: Date?
    public var created: Date?

    public init(id: String, title: String, isDone: Bool = false, due: Date? = nil, created: Date? = nil) {
        self.id = id
        self.title = title
        self.isDone = isDone
        self.due = due
        self.created = created
    }
}

public struct ReminderList: Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public enum RemindersAccess: Sendable, Equatable {
    case notDetermined, granted, denied
}

public enum MediaApp: String, Sendable, CaseIterable {
    case spotify = "Spotify"
    case music = "Music"

    public var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }
}

public struct Track: Equatable, Sendable {
    public var title: String
    public var artist: String
    public var app: MediaApp
    public var isPlaying: Bool

    public init(title: String, artist: String, app: MediaApp, isPlaying: Bool) {
        self.title = title
        self.artist = artist
        self.app = app
        self.isPlaying = isPlaying
    }
}

/// AppleScript verbs shared by Music and Spotify.
public enum MediaCommand: String, Sendable {
    case playPause = "playpause"
    case nextTrack = "next track"
    case previousTrack = "previous track"
}

public struct PowerStatus: Equatable, Sendable {
    public var level: Int
    public var isCharging: Bool

    public init(level: Int, isCharging: Bool) {
        self.level = level
        self.isCharging = isCharging
    }
}
