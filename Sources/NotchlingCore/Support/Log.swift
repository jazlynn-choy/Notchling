import os

/// Loggers for Apple's unified log, one category per area of the app.
///
/// Read them in Console.app (filter by the subsystem), or in Terminal:
///
///     log stream --predicate 'subsystem == "local.notchling"' --level debug
///
/// Never log tokens, prompts, file contents, or the text of notes and reminders. Error messages
/// are marked `.public` so they are readable in a log someone attaches to a bug report.
public enum Log {
    public static let subsystem = "local.notchling"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let spotify = Logger(subsystem: subsystem, category: "spotify")
    public static let media = Logger(subsystem: subsystem, category: "media")
    public static let weather = Logger(subsystem: subsystem, category: "weather")
    public static let reminders = Logger(subsystem: subsystem, category: "reminders")
    public static let agent = Logger(subsystem: subsystem, category: "agent")
    public static let terminal = Logger(subsystem: subsystem, category: "terminal")
}
