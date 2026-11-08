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

public enum AccessStatus: Sendable, Equatable {
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
    public var repeatMode: RepeatMode
    /// Album cover (Spotify provides one; Music's scripting doesn't expose a URL).
    public var artworkURL: URL?

    public init(title: String, artist: String, app: MediaApp, isPlaying: Bool, repeatMode: RepeatMode = .off,
                artworkURL: URL? = nil) {
        self.title = title
        self.artist = artist
        self.app = app
        self.isPlaying = isPlaying
        self.repeatMode = repeatMode
        self.artworkURL = artworkURL
    }
}

/// Loop setting. Music supports all three; Spotify's scripting only has on/off (repeat all).
public enum RepeatMode: String, Sendable, CaseIterable {
    case off, all, one

    /// What the loop button switches to next for `app`.
    public func next(for app: MediaApp) -> RepeatMode {
        switch (self, app) {
        case (.off, _): return .all
        case (.all, .music): return .one
        case (.all, .spotify), (.one, _): return .off
        }
    }
}

/// A song found by search, in either player.
public struct SongResult: Identifiable, Equatable, Sendable {
    /// Music's persistent ID, or a Spotify URI like `spotify:track:…`.
    public let id: String
    public let title: String
    public let artist: String
    /// Which app can play it.
    public let app: MediaApp
    /// What to keep playing after it: the album's Spotify URI, so the album carries on.
    public let contextURI: String?
    public let artworkURL: URL?

    public init(id: String, title: String, artist: String, app: MediaApp = .music,
                contextURI: String? = nil, artworkURL: URL? = nil) {
        self.id = id
        self.title = title
        self.artist = artist
        self.app = app
        self.contextURI = contextURI
        self.artworkURL = artworkURL
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

/// A calendar event, copied out of EventKit into a plain value.
public struct CalendarEvent: Identifiable, Equatable, Sendable {
    public let id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    /// The calendar's colour as sRGB components (0...1), if known.
    public var color: RGB?

    public struct RGB: Equatable, Sendable {
        public var red, green, blue: Double
        public init(red: Double, green: Double, blue: Double) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, color: RGB? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.color = color
    }
}
