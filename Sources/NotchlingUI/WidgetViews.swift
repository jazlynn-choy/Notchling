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
        case .musicCard, .remindersCard, .dayCard:
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
