import NotchlingCore
import SwiftUI

/// The Settings window. Expects `NotchSettings` and `RemindersStore` in the environment.
public struct SettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var reminders: RemindersStore

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
        .frame(width: 440)
        .frame(minHeight: 480, idealHeight: 680)
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
                HStack(spacing: 10) {
                    Image(systemName: kind.symbol).frame(width: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                        Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    rowButton("chevron.up", "Move \(kind.title) earlier", disabled: index == 0) {
                        settings.widgets.move(kind, in: slot, by: -1)
                    }
                    rowButton("chevron.down", "Move \(kind.title) later", disabled: index == widgets.count - 1) {
                        settings.widgets.move(kind, in: slot, by: 1)
                    }
                    rowButton("minus.circle.fill", "Remove \(kind.title)", disabled: false) {
                        settings.widgets.remove(kind, from: slot)
                    }
                }
            }
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
            }
        }
        .animation(.default, value: widgets)
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
