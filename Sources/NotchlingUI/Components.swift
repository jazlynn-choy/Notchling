import NotchlingCore
import SwiftUI

struct IconButton: View {
    let symbol: String
    let label: String
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

struct ControlButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 12
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct CountBadge: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.black)
            .frame(minWidth: 14, minHeight: 14)
            .background(Circle().fill(Color.yellow))
    }
}

struct BatteryBadge: View {
    let status: PowerStatus
    let showsPercentage: Bool

    private var fill: Color {
        if status.isCharging { return .green }
        return status.level <= 20 ? .red : .white
    }

    var body: some View {
        HStack(spacing: 3) {
            if showsPercentage {
                Text("\(status.level)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 1)
                    .frame(width: 20, height: 10)
                RoundedRectangle(cornerRadius: 1.5).fill(fill)
                    .frame(width: max(2, 16 * CGFloat(status.level) / 100), height: 6)
                    .padding(.leading, 2)
                if status.isCharging {
                    Image(systemName: "bolt.fill").font(.system(size: 6, weight: .black))
                        .foregroundStyle(.black).frame(width: 20)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Battery \(status.level) percent\(status.isCharging ? ", charging" : "")")
    }
}

/// Four bouncing bars shown while music plays.
struct EqualizerBars: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                HStack(alignment: .center, spacing: proxy.size.width * 0.12) {
                    ForEach(0..<4, id: \.self) { index in
                        let phase = time * (3.1 + Double(index) * 1.3) + Double(index)
                        Capsule().fill(Color.white)
                            .frame(height: proxy.size.height * (0.35 + 0.65 * abs(sin(phase))))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Lets any view open the Settings window without threading a closure through every layer.
struct OpenNotchSettings: Sendable {
    let action: @MainActor @Sendable () -> Void
    @MainActor func callAsFunction() { action() }
}

private struct OpenNotchSettingsKey: EnvironmentKey {
    static let defaultValue = OpenNotchSettings {}
}

extension EnvironmentValues {
    var openNotchSettings: OpenNotchSettings {
        get { self[OpenNotchSettingsKey.self] }
        set { self[OpenNotchSettingsKey.self] = newValue }
    }
}
