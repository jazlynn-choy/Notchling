import NotchlingCore
import SwiftUI

// Settings sections for individual integrations and widgets.

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
            Toggle("Answer permission prompts from the notch", isOn: $settings.approvalsEnabled)
            if settings.approvalsEnabled {
                Stepper(value: $settings.approvalWait, in: ClaudeApprovals.waitRange, step: 5) {
                    Text("Wait \(settings.approvalWait)s, then ask in the terminal")
                }
            }
        } header: {
            Text("Claude Code")
        } footer: {
            Text("Connect adds two small hooks to ~/.claude/settings.json (your existing settings are kept, with a "
                 + "backup). They record only which tool Claude is using and in which folder, never your prompts "
                 + "or file contents. When Claude asks permission, the notch opens with Allow / Deny; if you don't "
                 + "answer in time, Claude asks in the terminal as usual. Nothing is ever approved on its own. "
                 + "If you connected before, click Disconnect then Connect to add approvals. Restart open sessions.")
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

struct TerminalSettingsSection: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var command: CommandSetup

    var body: some View {
        Section {
            HStack {
                if let path = command.installedAt {
                    Label("Installed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(path.path).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("Uninstall") { command.uninstall() }
                } else {
                    Text("Show any terminal command's progress in the notch.")
                    Spacer()
                    Button("Install") { install() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!command.isAvailable)
                }
            }
            if let message = command.message {
                Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("notch run npm test").font(.caption.monospaced())
                Text("long-command | notch").font(.caption.monospaced())
                Text("notch \"Deploy finished\"").font(.caption.monospaced())
            }
            .foregroundStyle(.secondary)
            .textSelection(.enabled)
        } header: {
            Text("The notch command")
        } footer: {
            Text("Shows the command's latest output and any progress (\"45%\", \"3/10\") while it runs, then ✓ or ✗ "
                 + "with how long it took, and a chime. The command's output and exit code are unchanged.")
        }
    }

    /// Installing also puts the terminal widget beside the notch, so it's visible straight away.
    private func install() {
        command.install()
        guard command.installedAt != nil, !settings.widgets.allWidgets.contains(where: \.usesActivity) else { return }
        if settings.widgets.addable(to: .rightWing).contains(.activity) {
            settings.widgets.add(.activity, to: .rightWing)
        } else {
            settings.widgets.add(.activity, to: .leftWing)
        }
    }
}
