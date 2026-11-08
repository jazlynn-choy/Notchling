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
                HStack(spacing: 10) {
                    Image(systemName: kind.symbol).frame(width: 18).foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(kind.title)
                        Text(kind.summary).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if slot == .panel {
                        Picker("Size of \(kind.title)", selection: Binding(
                            get: { settings.cardSize(for: kind) },
                            set: { settings.setCardSize($0, for: kind) })) {
                            ForEach(CardSize.allCases) { Text($0.label).tag($0).help($0.title) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
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
            } else if slot == .panel {
                Text("S, M and L set how much of the panel's width each card gets.")
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

struct MusicSettingsSection: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var spotify: SpotifyConnection

    var body: some View {
        Section {
            Picker("Search plays songs in", selection: $settings.musicSource) {
                Text("Spotify").tag(MediaApp.spotify)
                Text("Apple Music (your library)").tag(MediaApp.music)
            }
            if settings.musicSource == .spotify {
                spotifyStatus
                TextField("Spotify Client ID", text: $spotify.clientID)
                    .font(.system(.body, design: .monospaced))
                if spotify.status == .needsClientID || spotify.status == .disconnected {
                    setupSteps
                }
            }
        } header: {
            Text("Music")
        } footer: {
            if settings.musicSource == .spotify {
                Text("Searching all of Spotify needs a free Spotify developer app, which is how Spotify lets "
                     + "apps sign in. Your password never goes to Notchling.")
            }
        }
    }

    @ViewBuilder private var spotifyStatus: some View {
        HStack {
            switch spotify.status {
            case .connected:
                Label("Connected to Spotify", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                Spacer()
                Button("Disconnect") { spotify.disconnect() }
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Finish signing in in your browser…")
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Spacer()
                Button("Try again") { Task { await spotify.connect() } }
            case .disconnected:
                Text("Not connected")
                Spacer()
                Button("Connect Spotify") { Task { await spotify.connect() } }
                    .buttonStyle(.borderedProminent)
            case .needsClientID:
                Text("Paste a Client ID below to connect").foregroundStyle(.secondary)
            }
        }
    }

    private var setupSteps: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One-time setup").font(.headline)
            Text("1. Open the Spotify developer dashboard and create an app.")
            Text("2. Add this Redirect URI and tick “Web API”:")
            HStack {
                Text(SpotifyAuth.redirectURI).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(SpotifyAuth.redirectURI, forType: .string)
                }
                .controlSize(.small)
            }
            Text("3. Copy the app's Client ID into the field above, then Connect.")
            Link("Open the Spotify developer dashboard",
                 destination: URL(string: "https://developer.spotify.com/dashboard")!)
        }
        .font(.callout)
    }
}

struct WeatherSettingsSection: View {
    @EnvironmentObject var weather: WeatherStore

    var body: some View {
        Section("Weather") {
            HStack {
                Text("City")
                Spacer()
                Text(weather.place.map { "\($0.name)\($0.region.isEmpty ? "" : ", \($0.region)")" } ?? "Not set")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            TextField("Search for a city", text: $weather.placeQuery)
            ForEach(weather.placeResults) { place in
                Button { weather.choose(place) } label: {
                    VStack(alignment: .leading) {
                        Text(place.name)
                        Text(place.region).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Picker("Units", selection: $weather.unit) {
                ForEach(TemperatureUnit.allCases) { Text($0.symbol).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Weather from Open-Meteo. Only the city's location is sent.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

struct WorldClockSettingsSection: View {
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        Section {
            ForEach(settings.worldClockZones, id: \.self) { id in
                HStack {
                    Text(WorldClock.cityName(for: id))
                    Text(id).font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button { settings.removeWorldClock(id) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(WorldClock.cityName(for: id))")
                }
            }
            if settings.worldClockZones.count < WorldClock.maxCities {
                Picker("Add a city", selection: Binding(get: { "" }, set: { settings.addWorldClock($0) })) {
                    Text("Choose…").tag("")
                    ForEach(WorldClock.allZones, id: \.id) { Text($0.label).tag($0.id) }
                }
            }
        } header: {
            Text("World clocks")
        } footer: {
            Text("Up to \(WorldClock.maxCities) cities. The wing shows the first one.")
        }
    }
}

struct ClaudeCodeSettingsSection: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var setup: ClaudeHookSetup

    var body: some View {
        Section {
            HStack {
                if setup.isInstalled {
                    Label("Connected", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Spacer()
                    Button("Disconnect") { setup.uninstall() }
                } else {
                    Text("Show what Claude Code is doing, and when it needs you.")
                    Spacer()
                    Button("Connect") { connect() }.buttonStyle(.borderedProminent)
                }
            }
            if let error = setup.lastError {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            Toggle("Chime when Claude needs you or finishes", isOn: $settings.agentChime)
        } header: {
            Text("Claude Code")
        } footer: {
            Text("Connect adds a small hook to ~/.claude/settings.json (your existing settings are kept, with a "
                 + "backup). It records only which tool Claude is using and in which folder, never your prompts "
                 + "or file contents. New Claude Code sessions pick it up; restart open ones.")
        }
    }

    /// Connecting also puts the agent widget beside the notch, so it's visible straight away.
    private func connect() {
        setup.install()
        guard setup.isInstalled, !settings.widgets.allWidgets.contains(where: \.usesAgent) else { return }
        if settings.widgets.addable(to: .leftWing).contains(.agent) {
            settings.widgets.add(.agent, to: .leftWing)
        } else {
            settings.widgets.add(.agent, to: .rightWing)
        }
    }
}
