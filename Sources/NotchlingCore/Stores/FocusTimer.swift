import Foundation

/// A focus (Pomodoro-style) countdown.
///
/// Stores an end *date* rather than counting down each second, so the time stays exact even
/// if the Mac sleeps or the clock tick is late. `tick(now:)` only checks whether it's done.
@MainActor
public final class FocusTimer: ObservableObject {
    public enum State: Equatable, Sendable {
        case idle
        case running(endsAt: Date)
        case paused(remaining: TimeInterval)
        case finished
    }

    public static let presetMinutes = [5, 15, 25, 50]
    static let minutesKey = "focusMinutes"

    @Published public private(set) var state: State = .idle
    /// Length of a session. Persisted, so the last choice sticks.
    @Published public private(set) var minutes: Int

    /// Called once when a running timer reaches zero.
    public var onFinish: (() -> Void)?

    private let defaults: UserDefaults
    private let clock: () -> Date

    public init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
        let stored = defaults.integer(forKey: Self.minutesKey)
        minutes = (1...180).contains(stored) ? stored : 25
    }

    public var duration: TimeInterval { TimeInterval(minutes * 60) }

    /// Running or paused: the timer is "in use" and worth showing in the wing.
    public var isActive: Bool {
        switch state {
        case .running, .paused: return true
        case .idle, .finished: return false
        }
    }

    public var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    public var isPaused: Bool {
        if case .paused = state { return true }
        return false
    }

    public func remaining(at now: Date) -> TimeInterval {
        switch state {
        case .idle: return duration
        case .running(let end): return max(0, end.timeIntervalSince(now))
        case .paused(let remaining): return remaining
        case .finished: return 0
        }
    }

    /// 0 at the start, 1 when done. Drives the progress ring.
    public func progress(at now: Date) -> Double {
        guard duration > 0 else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / duration))
    }

    public func setMinutes(_ value: Int) {
        guard (1...180).contains(value), !isActive else { return }
        minutes = value
        defaults.set(value, forKey: Self.minutesKey)
        if state == .finished { state = .idle }
    }

    /// Start, pause or resume, whichever makes sense: the one big button.
    public func toggle() {
        let now = clock()
        switch state {
        case .idle, .finished: state = .running(endsAt: now.addingTimeInterval(duration))
        case .running(let end): state = .paused(remaining: max(0, end.timeIntervalSince(now)))
        case .paused(let remaining): state = .running(endsAt: now.addingTimeInterval(remaining))
        }
    }

    public func reset() {
        state = .idle
    }

    public func tick(now: Date) {
        guard case .running(let end) = state, now >= end else { return }
        state = .finished
        onFinish?()
    }

    /// "24:59". Rounds up, so a timer never shows 0:00 while time is left.
    public static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded(.up))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
