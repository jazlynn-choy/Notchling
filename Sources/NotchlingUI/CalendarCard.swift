import NotchlingCore
import SwiftUI

/// What's left of today in Calendar.
struct CalendarCard: View {
    let now: Date
    @EnvironmentObject var calendar: CalendarStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "calendar").font(.system(size: 10, weight: .bold)).foregroundStyle(.red)
                Text("Calendar").font(.system(size: 11, weight: .bold))
            }
            switch calendar.access {
            case .granted: agenda
            case .notDetermined: connectPrompt
            case .denied: deniedMessage
            }
        }
        .cardStyle()
    }

    @ViewBuilder private var agenda: some View {
        let events = calendar.agenda(at: now)
        if events.isEmpty {
            Text("Nothing else today").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
        }
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(events) { event in
                    HStack(spacing: 7) {
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(event.color.map(Color.init(rgb:)) ?? .white)
                            .frame(width: 3, height: 14)
                        Text(event.title).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 4)
                        let label = EventTimeLabel.full(for: event, now: now)
                        Text(label)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(label == "Now" ? Color.orange : Color.white.opacity(0.45))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private var connectPrompt: some View {
        VStack {
            Spacer(minLength: 0)
            Button("Connect to Calendar") { Task { await calendar.requestAccess() } }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(Color.red))
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private var deniedMessage: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Notchling can't see Calendar. Allow it in System Settings → Privacy & Security → Calendars.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
            Button("Open Privacy Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(.plain).font(.system(size: 10, weight: .semibold)).foregroundStyle(.red)
        }
    }
}
