import NotchlingActivity
import NotchlingCore
import SwiftUI

extension Activity.State {
    var color: Color {
        switch self {
        case .running: return .cyan
        case .succeeded: return .green
        case .failed: return .red
        case .info: return .white
        }
    }

    var symbol: String {
        switch self {
        case .running: return "terminal"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .info: return "bell.fill"
        }
    }
}

/// A ring when progress is known, a spinning arc when it isn't, a ✓/✗ when done.
struct ActivityIndicator: View {
    let activity: Activity
    var size: CGFloat = 12

    var body: some View {
        if activity.state == .running {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 2)
                if let progress = activity.progress {
                    Circle().trim(from: 0, to: progress)
                        .stroke(activity.state.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                } else {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        Circle().trim(from: 0, to: 0.3)
                            .stroke(activity.state.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 360))
                    }
                }
            }
            .frame(width: size, height: size)
        } else {
            Image(systemName: activity.state.symbol)
                .font(.system(size: size - 1, weight: .bold))
                .foregroundStyle(activity.state.color)
        }
    }
}

struct ActivityWing: View {
    let now: Date
    let wingWidth: CGFloat
    @EnvironmentObject var activities: ActivityStore

    var body: some View {
        if let activity = activities.headline(at: now) {
            HStack(spacing: 4) {
                ActivityIndicator(activity: activity, size: 11)
                if wingWidth > 90 {
                    Text(activity.title).font(.system(size: 11, weight: .semibold))
                }
                if activity.state == .running, let progress = activity.progress {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(activity.title): \(activity.detail ?? activity.state.rawValue)")
        }
    }
}

struct ActivityCard: View {
    @EnvironmentObject var activities: ActivityStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "terminal").font(.system(size: 10, weight: .bold)).foregroundStyle(.cyan)
                Text("Terminal").font(.system(size: 11, weight: .bold))
                Spacer()
                if activities.activities.contains(where: \.isFinished) {
                    Button("Clear") { activities.clearFinished() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            if activities.activities.isEmpty {
                Text("Try:  notch run npm test")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
            }
            VerticalScroll {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(activities.activities) { activity in
                        HStack(alignment: .top, spacing: 7) {
                            ActivityIndicator(activity: activity, size: 12).frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(activity.title).font(.system(size: 11, weight: .semibold))
                                if let detail = activity.detail {
                                    Text(detail).font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(activity.state == .failed ? Color.red.opacity(0.8)
                                                         : Color.white.opacity(0.55))
                                }
                            }
                            .lineLimit(1)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .cardStyle()
    }
}
