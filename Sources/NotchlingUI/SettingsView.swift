import NotchlingCore
import SwiftUI

/// The Settings window. Expects `NotchSettings`, `RemindersStore`, `CalendarStore`,
/// `WeatherStore` and `SpotifyConnection` in the environment.
public struct SettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var reminders: RemindersStore
    @EnvironmentObject var calendar: CalendarStore

    public init() {}

    public var body: some View {
        Form {
            Section("Size") {
                LabeledSlider(title: "Bar beside the notch", value: $settings.wingWidth,
                              range: NotchSettings.wingRange,
                              hint: "0 hides it, so only the real notch shows")
                LabeledSlider(title: "Panel width", value: $settings.panelWidth,
                              range: NotchSettings.panelWidthRange)
                LabeledSlider(title: "Panel height", value: $settings.panelHeight,
                              range: NotchSettings.panelHeightRange)
                Button("Reset sizes") { settings.resetSizes() }
            }

            ForEach(WidgetSlot.allCases) { WidgetSlotSection(slot: $0) }

            ClaudeCodeSettingsSection()
            MusicSettingsSection()
            if uses(.weather, .weatherCard) { WeatherSettingsSection() }
            if uses(.worldClock, .worldClockCard) { WorldClockSettingsSection() }
            if uses(.countdown, .countdownCard) {
                Section("Countdown") {
                    TextField("Counting down to", text: $settings.countdownTitle)
                    DatePicker("Date", selection: $settings.countdownDate, displayedComponents: .date)
                }
            }

            Section("Calendar") {
                switch calendar.access {
                case .granted:
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                case .notDetermined:
                    Button("Connect to Calendar") { Task { await calendar.requestAccess() } }
                case .denied:
                    Text("Turned off in System Settings → Privacy & Security → Calendars.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section("Reminders") {
                if reminders.access == .granted {
                    Picker("Reminders list", selection: $settings.reminderListID) {
                        Text("Default list").tag("")
                        ForEach(reminders.lists) { Text($0.title).tag($0.id) }
                    }
                } else {
                    Button("Connect to Reminders") { Task { await reminders.requestAccess() } }
                }
            }

            Section("General") {
                Button("Reset widgets to default") { settings.resetWidgets() }
                Toggle("Haptic tap when the panel opens", isOn: $settings.haptics)
                Toggle("Open at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .frame(minHeight: 480, idealHeight: 720)
    }

    /// Options for a widget only show while that widget is in the layout.
    private func uses(_ kinds: WidgetKind...) -> Bool {
        !settings.widgets.allWidgets.isDisjoint(with: kinds)
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var hint: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt").monospacedDigit().foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range, step: 2)
                .accessibilityLabel(title)
            if let hint { Text(hint).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

/// One slot's widgets, in order, with controls to reorder, remove and add.
struct WidgetSlotSection: View {
    let slot: WidgetSlot
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        let widgets = settings.widgets[slot]
        Section {
            if widgets.isEmpty {
                Text("Empty").foregroundStyle(.secondary)
            }
            ForEach(Array(widgets.enumerated()), id: \.element) { index, kind in
                let isStacked = slot == .panel && settings.widgets.stacked.contains(kind)
                HStack(spacing: 10) {
                    Image(systemName: isStacked ? "arrow.turn.down.right" : "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                        .padding(.leading, isStacked ? 14 : 0)
                        .help(isStacked ? "Stacked under the card above" : "Drag to reorder")
                    Image(systemName: kind.symbol).frame(width: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                        Text(kind.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer()
                    if slot == .panel && index > 0 {
                        rowButton(isStacked ? "rectangle.split.2x1" : "rectangle.split.1x2",
                                  isStacked ? "Give \(kind.title) its own column"
                                            : "Stack \(kind.title) under the card above",
                                  disabled: !isStacked && !canStack(kind)) {
                            settings.widgets.setStacked(kind, !isStacked)
                        }
                    }
                    if slot == .panel && !isStacked {
                        Slider(value: Binding(get: { settings.cardWeight(for: kind) },
                                              set: { settings.setCardWeight($0, for: kind) }),
                               in: PanelLayout.weightRange)
                            .frame(width: 90)
                            .help("Width of the \(kind.title) card")
                            .accessibilityLabel("Width of \(kind.title)")
                    }
                    if let other = otherWing, settings.widgets.addable(to: other).contains(kind) {
                        rowButton(slot == .leftWing ? "arrow.right.square" : "arrow.left.square",
                                  "Move \(kind.title) to the \(other.title.lowercased())", disabled: false) {
                            settings.widgets.transfer(kind, from: slot, to: other)
                        }
                    }
                    rowButton("minus.circle.fill", "Remove \(kind.title)", disabled: false) {
                        settings.widgets.remove(kind, from: slot)
                    }
                }
                .contextMenu {
                    Button("Move earlier") { settings.widgets.move(kind, in: slot, by: -1) }.disabled(index == 0)
                    Button("Move later") { settings.widgets.move(kind, in: slot, by: 1) }
                        .disabled(index == widgets.count - 1)
                    if let other = otherWing {
                        Button("Move to \(other.title.lowercased())") {
                            settings.widgets.transfer(kind, from: slot, to: other)
                        }
                        .disabled(!settings.widgets.addable(to: other).contains(kind))
                    }
                    if slot == .panel && index > 0 {
                        Button(isStacked ? "Give it its own column" : "Stack under the card above") {
                            settings.widgets.setStacked(kind, !isStacked)
                        }
                        .disabled(!isStacked && !canStack(kind))
                    }
                    Divider()
                    Button("Remove", role: .destructive) { settings.widgets.remove(kind, from: slot) }
                }
                // Keyboard and VoiceOver users can't drag, so reordering is also an action.
                .accessibilityAction(named: "Move earlier") { settings.widgets.move(kind, in: slot, by: -1) }
                .accessibilityAction(named: "Move later") { settings.widgets.move(kind, in: slot, by: 1) }
            }
            .onMove { from, to in settings.widgets.move(fromOffsets: from, toOffset: to, in: slot) }
            let addable = settings.widgets.addable(to: slot)
            Menu {
                ForEach(addable) { kind in
                    Button { settings.widgets.add(kind, to: slot) } label: {
                        Label(kind.title, systemImage: kind.symbol)
                    }
                }
            } label: {
                Label(widgets.count >= slot.capacity ? "Full (\(slot.capacity) max)" : "Add widget",
                      systemImage: "plus")
            }
            .disabled(addable.isEmpty)
        } header: {
            Text(slot.title)
        } footer: {
            if slot == .leftWing {
                Text("Wing widgets show beside the notch when it's closed. Widen the bar above if they're cut off.")
            } else if slot == .panel {
                Text("Stack a card under the one above (up to \(WidgetLayout.maxStack) per column, "
                     + "\(WidgetLayout.maxColumns) columns) to use the space better. The slider sets a column's width. "
                     + "Easiest of all: open the panel, click the pencil, and drag cards where you want them.")
            }
        }
        .animation(.default, value: widgets)
    }

    /// Whether `kind` could join the column of the card above it.
    private func canStack(_ kind: WidgetKind) -> Bool {
        var trial = settings.widgets
        return trial.setStacked(kind, true)
    }

    private var otherWing: WidgetSlot? {
        switch slot {
        case .leftWing: return .rightWing
        case .rightWing: return .leftWing
        case .panel: return nil
        }
    }

    private func rowButton(_ symbol: String, _ label: String, disabled: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol) }
            .buttonStyle(.borderless)
            .disabled(disabled)
            .help(label)
            .accessibilityLabel(label)
    }
}
