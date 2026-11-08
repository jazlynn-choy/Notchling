import Foundation
import Testing
@testable import NotchlingCore

@MainActor
@Suite("FocusTimer")
struct FocusTimerTests {
    /// A clock the test moves by hand.
    final class ManualClock {
        var now = Date(timeIntervalSince1970: 1_794_063_600)
        func advance(_ seconds: TimeInterval) { now.addTimeInterval(seconds) }
    }

    let clock = ManualClock()

    func makeTimer(_ defaults: UserDefaults = makeIsolatedDefaults()) -> FocusTimer {
        let clock = clock
        return FocusTimer(defaults: defaults, clock: { clock.now })
    }

    @Test func startsIdleAtTheChosenLength() {
        let timer = makeTimer()
        #expect(timer.state == .idle)
        #expect(timer.remaining(at: clock.now) == 25 * 60)
    }

    @Test func countsDownFromTheEndDate() {
        let timer = makeTimer()
        timer.toggle()
        clock.advance(60)
        #expect(timer.remaining(at: clock.now) == 24 * 60)
        #expect(abs(timer.progress(at: clock.now) - 1.0 / 25) < 1e-9)
    }

    @Test func pauseFreezesTheTimeAndResumeContinues() {
        let timer = makeTimer()
        timer.toggle()
        clock.advance(100)
        timer.toggle()   // pause
        clock.advance(500)   // time passes while paused
        #expect(timer.remaining(at: clock.now) == 1400)
        timer.toggle()   // resume
        clock.advance(400)
        #expect(timer.remaining(at: clock.now) == 1000)
    }

    @Test func finishesOnceAndCallsBackOnce() {
        let timer = makeTimer()
        var finishes = 0
        timer.onFinish = { finishes += 1 }
        timer.toggle()
        clock.advance(25 * 60 - 1)
        timer.tick(now: clock.now)
        #expect(timer.state != .finished)
        clock.advance(1)
        timer.tick(now: clock.now)
        timer.tick(now: clock.now)
        #expect(timer.state == .finished)
        #expect(finishes == 1)
    }

    @Test func lengthCannotChangeMidSessionButPersists() {
        let defaults = makeIsolatedDefaults()
        let timer = makeTimer(defaults)
        timer.setMinutes(50)
        timer.toggle()
        timer.setMinutes(5)   // ignored while running
        #expect(timer.minutes == 50)
        #expect(makeTimer(defaults).minutes == 50)
    }

    @Test func storedLengthOutOfRangeFallsBack() {
        let defaults = makeIsolatedDefaults()
        defaults.set(9999, forKey: FocusTimer.minutesKey)
        #expect(makeTimer(defaults).minutes == 25)
    }

    @Test(arguments: [(1500.0, "25:00"), (59.2, "1:00"), (0.4, "0:01"), (0.0, "0:00")])
    func formatRoundsUp(seconds: Double, expected: String) {
        #expect(FocusTimer.format(seconds) == expected)
    }
}
