import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var reminders: RemindersStore

    var body: some View {
        Form {
            Section("Size") {
                LabeledSlider(title: "Bar beside the notch", value: $settings.wingWidth, range: 0...160,
                              hint: "0 hides it, so only the real notch shows")
                LabeledSlider(title: "Panel width", value: $settings.panelWidth, range: 340...640)
                LabeledSlider(title: "Panel height", value: $settings.panelHeight, range: 160...300)
                Button("Reset sizes") { settings.resetLayout() }
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
                    Button("Connect to Reminders") { reminders.requestAccess() }
                }
            }

            Section("General") {
                Toggle("Haptic tap when the panel opens", isOn: $settings.haptics)
                Toggle("Open at login", isOn: $settings.launchAtLogin)
                if let err = settings.loginItemError {
                    Text(err).font(.caption).foregroundColor(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: settings.reminderListID) { _ in reminders.reload() }
    }
}

struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var hint: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value)) pt").monospacedDigit().foregroundColor(.secondary)
            }
            Slider(value: $value, in: range, step: 2)
            if let hint { Text(hint).font(.caption).foregroundColor(.secondary) }
        }
    }
}
