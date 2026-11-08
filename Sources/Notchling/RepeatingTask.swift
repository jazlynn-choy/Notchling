import Foundation

/// Runs an action now and then every `interval`, while switched on. Used for everything the
/// app refreshes in the background (calendar, weather, Claude Code, Spotify sign-in), so each
/// one is a line of wiring instead of its own timer bookkeeping.
@MainActor
final class RepeatingTask {
    private let interval: TimeInterval
    private let action: @MainActor () async -> Void
    private var timer: Timer?

    init(every interval: TimeInterval, _ action: @escaping @MainActor () async -> Void) {
        self.interval = interval
        self.action = action
    }

    var isRunning: Bool { timer != nil }

    func setRunning(_ running: Bool) {
        timer?.invalidate()
        timer = nil
        guard running else { return }
        fire()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
    }

    /// Runs the action once, now, without changing the schedule.
    func fire() {
        Task { await action() }
    }
}
