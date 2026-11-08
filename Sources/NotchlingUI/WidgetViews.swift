import NotchlingCore
import SwiftUI

/// Draws one widget in the bar beside the notch. Adding a wing widget means adding a
/// `WidgetKind` case and one branch here.
struct WingWidgetView: View {
    let kind: WidgetKind
    @ObservedObject var model: NotchModel
    /// Room available, so text-heavy widgets can drop detail when the wing is narrow.
    let wingWidth: CGFloat
    @EnvironmentObject var reminders: RemindersStore
    @EnvironmentObject var focus: FocusTimer
    @EnvironmentObject var calendar: CalendarStore

    var body: some View {
        switch kind {
        case .nowPlaying:
            nowPlaying
        case .nowPlayingOrDate:
            if model.track?.isPlaying == true { nowPlaying } else { date }
        case .date:
            date
        case .time:
            Text(model.now, format: .dateTime.hour().minute())
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
        case .battery:
            BatteryBadge(status: model.power, showsPercentage: false)
        case .reminderCount:
            if reminders.openCount > 0 {
                CountBadge(count: reminders.openCount)
                    .accessibilityLabel("\(reminders.openCount) open reminders")
            }
        case .focusTimer:
            if focus.isActive || focus.state == .finished {
                HStack(spacing: 3) {
                    Image(systemName: focus.state == .finished ? "checkmark.circle.fill" : "timer")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(focus.isRunning ? Color.orange : Color.white.opacity(0.6))
                    Text(FocusTimer.format(focus.remaining(at: model.now)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Focus timer")
            }
        case .nextEvent:
            if let event = calendar.nextEvent(at: model.now) {
                HStack(spacing: 4) {
                    Circle().fill(event.color.map(Color.init(rgb:)) ?? .white).frame(width: 6, height: 6)
                    if wingWidth > 100 {
                        Text(event.title).font(.system(size: 11, weight: .semibold))
                    }
                    Text(EventTimeLabel.compact(for: event, now: model.now))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
        case .weather:
            WeatherWing()
        case .worldClock:
            WorldClockWing(now: model.now, wingWidth: wingWidth)
        case .countdown:
            CountdownWing(now: model.now)
        case .musicCard, .remindersCard, .dayCard, .focusCard, .calendarCard, .weatherCard, .worldClockCard,
             .countdownCard, .notesCard:
            EmptyView()   // panel-only; `WidgetLayout` never puts these in a wing
        }
    }

    @ViewBuilder private var nowPlaying: some View {
        if model.track?.isPlaying == true {
            HStack(spacing: 6) {
                EqualizerBars().frame(width: 14, height: 10)
                if wingWidth > 70, let title = model.track?.title {
                    Text(title).font(.system(size: 11, weight: .semibold))
                }
            }
        }
    }

    private var date: some View {
        Text(model.now, format: .dateTime.weekday(.abbreviated).day())
            .font(.system(size: 11, weight: .semibold))
    }
}

/// Draws one card in the drop-down panel.
struct PanelWidgetView: View {
    let kind: WidgetKind
    @ObservedObject var model: NotchModel

    var body: some View {
        switch kind {
        case .musicCard: NowPlayingCard(model: model)
        case .remindersCard: RemindersCard()
        case .dayCard: DayCard(now: model.now)
        case .focusCard: FocusCard(now: model.now)
        case .calendarCard: CalendarCard(now: model.now)
        case .weatherCard: WeatherCard()
        case .worldClockCard: WorldClockCard(now: model.now)
        case .countdownCard: CountdownCard(now: model.now)
        case .notesCard: NotesCard()
        default: EmptyView()   // wing-only
        }
    }
}

/// A tear-off calendar page for today.
struct DayCard: View {
    let now: Date

    var body: some View {
        VStack(spacing: 0) {
            Text(now, format: .dateTime.month(.wide))
                .font(.system(size: 10, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(.red)
            Text(now, format: .dateTime.day())
                .font(.system(size: 40, weight: .light, design: .rounded))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
            Text(now, format: .dateTime.weekday(.wide))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
        }
        .lineLimit(1)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

extension Color {
    init(rgb: CalendarEvent.RGB) {
        self.init(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
}

/// The background every panel card shares.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }
}

extension View {
    func cardStyle() -> some View { modifier(CardBackground()) }
}
