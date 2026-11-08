import NotchlingCore
import SwiftUI

extension AgentState {
    var color: Color {
        switch self {
        case .needsInput: return .orange
        case .working: return Color(red: 0.85, green: 0.47, blue: 0.34)   // Claude's terracotta
        case .done: return .green
        case .ready: return .white.opacity(0.4)
        }
    }

    var symbol: String {
        switch self {
        case .needsInput: return "hand.raised.fill"
        case .working: return "sparkle"
        case .done: return "checkmark.circle.fill"
        case .ready: return "moon.zzz.fill"
        }
    }
}

/// A sparkle that spins while the agent works.
struct AgentGlyph: View {
    let state: AgentState
    var size: CGFloat = 10

    var body: some View {
        if state == .working {
            TimelineView(.animation(minimumInterval: 1 / 20)) { context in
                Image(systemName: state.symbol)
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(state.color)
                    .rotationEffect(.degrees(context.date.timeIntervalSinceReferenceDate * 120))
            }
        } else {
            Image(systemName: state.symbol)
                .font(.system(size: size, weight: .bold))
                .foregroundStyle(state.color)
        }
    }
}

struct AgentWing: View {
    let now: Date
    let wingWidth: CGFloat
    @EnvironmentObject var agents: AgentStatusStore

    var body: some View {
        if let session = agents.headline(at: now) {
            HStack(spacing: 4) {
                AgentGlyph(state: session.state)
                Text(wingWidth > 110 ? session.activity : session.state.label)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(session.state == .needsInput ? Color.orange : Color.white)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Claude Code in \(session.project): \(session.activity)")
        }
    }
}

struct AgentCard: View {
    let now: Date
    @EnvironmentObject var agents: AgentStatusStore
    @Environment(\.openNotchSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "sparkle").font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AgentState.working.color)
                Text("Claude Code").font(.system(size: 11, weight: .bold))
            }
            if agents.sessions.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No sessions yet").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                    Button("Connect Claude Code…") { openSettings() }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AgentState.working.color)
                }
            }
            VerticalScroll {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(agents.sessions) { session in
                        HStack(alignment: .top, spacing: 7) {
                            AgentGlyph(state: session.state, size: 11).frame(width: 14)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text(session.project).font(.system(size: 11, weight: .semibold))
                                    Spacer(minLength: 4)
                                    Text(session.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                                        .font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                                }
                                Text(session.activity)
                                    .font(.system(size: 10))
                                    .foregroundStyle(session.state == .needsInput ? Color.orange : .white.opacity(0.6))
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
