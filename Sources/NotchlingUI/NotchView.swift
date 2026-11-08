import NotchlingCore
import SwiftUI

/// Root view hosted in the notch window. Expects `NotchSettings` and `RemindersStore`
/// in the environment.
public struct NotchView: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var settings: NotchSettings
    let openSettings: () -> Void

    public init(model: NotchModel, openSettings: @escaping () -> Void) {
        self.model = model
        self.openSettings = openSettings
    }

    public var body: some View {
        let geometry = settings.geometry(notchSize: model.notchSize)
        let size = geometry.size(expanded: model.isExpanded)
        ZStack(alignment: .top) {
            NotchShape(ear: geometry.ear, bottomRadius: model.isExpanded ? 20 : 10)
                .fill(Color.black)
                .frame(width: size.width + geometry.ear * 2, height: size.height)
                .shadow(color: .black.opacity(model.isExpanded ? 0.45 : 0), radius: 12, y: 4)

            Group {
                if model.isExpanded {
                    ExpandedView(model: model, geometry: geometry, openSettings: openSettings)
                        .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
                } else {
                    CollapsedView(model: model, wingWidth: geometry.wingWidth)
                        .transition(.opacity)
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.38, dampingFraction: 0.78), value: model.isExpanded)
        .animation(.easeOut(duration: 0.2), value: settings.wingWidth)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }
}

/// The wings beside the notch while it's closed.
struct CollapsedView: View {
    @ObservedObject var model: NotchModel
    let wingWidth: CGFloat
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(settings.widgets.leftWing) { WingWidgetView(kind: $0, model: model, wingWidth: wingWidth) }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .frame(width: wingWidth)

            Spacer(minLength: model.notchSize.width)

            HStack(spacing: 6) {
                Spacer(minLength: 0)
                ForEach(settings.widgets.rightWing) { WingWidgetView(kind: $0, model: model, wingWidth: wingWidth) }
            }
            .padding(.trailing, 10)
            .frame(width: wingWidth)
        }
        .lineLimit(1)
        .opacity(wingWidth < 30 ? 0 : 1)   // too narrow to show anything legible
    }
}

/// The panel that drops down on hover.
struct ExpandedView: View {
    @ObservedObject var model: NotchModel
    let geometry: NotchGeometry
    let openSettings: () -> Void
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Text(model.now, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .foregroundStyle(.white.opacity(0.7))
                Text(model.now, format: .dateTime.hour().minute()).monospacedDigit()
                Spacer(minLength: model.notchSize.width)
                BatteryBadge(status: model.power, showsPercentage: true)
                IconButton(symbol: "gearshape.fill", label: "Settings", action: openSettings)
                IconButton(symbol: "power", label: "Quit Notchling") { NSApp.terminate(nil) }
            }
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .frame(height: max(model.notchSize.height - 6, 20))
            .padding(.horizontal, 20)

            HStack(alignment: .top, spacing: 10) {
                let cards = settings.widgets.panel
                if cards.isEmpty {
                    Text("No panel widgets. Add some in Settings.")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                // Each card's share of the width comes from its size (S/M/L) in Settings.
                let widths = PanelLayout.widths(for: cards.map(settings.cardSize(for:)),
                                                totalWidth: geometry.expandedSize.width - 28,
                                                spacing: 10)
                ForEach(Array(zip(cards, widths)), id: \.0) { kind, width in
                    PanelWidgetView(kind: kind, model: model)
                        .frame(width: width)
                }
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}
