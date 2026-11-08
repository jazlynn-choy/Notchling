import NotchlingCore
import SwiftUI

/// Focus timer: a progress ring, one start/pause button, and length presets.
struct FocusCard: View {
    /// Passed in from the model's 1-second clock, so the ring redraws once a second.
    let now: Date
    @EnvironmentObject var focus: FocusTimer

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.1), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: focus.progress(at: now))
                    .stroke(Color.orange, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: focus.progress(at: now))
                VStack(spacing: 0) {
                    Text(focus.state == .finished ? "Done" : FocusTimer.format(focus.remaining(at: now)))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    if focus.isPaused {
                        Text("Paused").font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: 66, height: 66)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Focus timer, \(FocusTimer.format(focus.remaining(at: now))) left")

            HStack(spacing: 10) {
                ControlButton(symbol: focus.isRunning ? "pause.fill" : "play.fill",
                              label: focus.isRunning ? "Pause" : (focus.isActive ? "Resume" : "Start focus")) {
                    focus.toggle()
                }
                ControlButton(symbol: "arrow.counterclockwise", label: "Reset timer") { focus.reset() }
                    .disabled(focus.state == .idle)
                    .opacity(focus.state == .idle ? 0.3 : 1)
            }

            if !focus.isActive {
                HStack(spacing: 3) {
                    ForEach(FocusTimer.presetMinutes, id: \.self) { minutes in
                        Button("\(minutes)") { focus.setMinutes(minutes) }
                            .buttonStyle(.plain)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .frame(width: 22, height: 15)
                            .background(Capsule().fill(focus.minutes == minutes ? Color.orange : Color.white.opacity(0.08)))
                            .foregroundStyle(focus.minutes == minutes ? Color.black : Color.white)
                            .accessibilityLabel("\(minutes) minutes")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle()
    }
}
