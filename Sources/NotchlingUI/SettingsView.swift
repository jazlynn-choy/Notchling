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

            Section("Bar beside the notch") {
                Picker("Left side shows", selection: $settings.leftWing) {
                    ForEach(LeftWingContent.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Open reminders count", isOn: $settings.showTodoCount)
                Toggle("Time", isOn: $settings.showTime)
                Toggle("Battery", isOn: $settings.showBattery)
            }

            Section("Panel") {
                Toggle("Music controls", isOn: $settings.showMusicCard)
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
                Toggle("Haptic tap when the panel opens", isOn: $settings.haptics)
                Toggle("Open at login", isOn: $settings.launchAtLogin)
                if let error = settings.loginItemError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
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
