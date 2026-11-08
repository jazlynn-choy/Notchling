import Foundation

/// Live system state shown in the notch: clock, battery and what's playing.
@MainActor
public final class NotchModel: ObservableObject {
    @Published public var isExpanded = false
    @Published public private(set) var now = Date()
    @Published public private(set) var power = PowerStatus(level: 100, isCharging: false)
    @Published public private(set) var track: Track?

    /// Off when no visible widget shows music, so the app stops running AppleScript every 2s.
    public var mediaEnabled = true {
        didSet { if !mediaEnabled { track = nil } }
    }

    /// Which player the play button starts when nothing is playing yet.
    public var preferredApp: MediaApp = .spotify

    /// The physical notch size for the screen we're drawing on.
    public let notchSize: CGSize

    private let media: MediaProviding
    private let powerSource: PowerProviding
    private var loops: [Task<Void, Never>] = []

    public init(notchSize: CGSize, media: MediaProviding, power: PowerProviding) {
        self.notchSize = notchSize
        self.media = media
        self.powerSource = power
    }

    /// Starts the polling loops. Separate from `init` so tests can drive refreshes by hand.
    public func start() {
        stop()
        loops = [
            repeating(every: .seconds(1)) { $0.now = Date() },
            repeating(every: .seconds(30)) { $0.refreshPower() },
            repeating(every: .seconds(2)) { await $0.refreshMedia() },
        ]
    }

    public func stop() {
        loops.forEach { $0.cancel() }
        loops = []
    }

    public func refreshPower() {
        if let status = powerSource.read(), status != power { power = status }
    }

    public func refreshMedia() async {
        guard mediaEnabled else { return }
        let latest = await media.nowPlaying()
        if latest != track { track = latest }
    }

    public func send(_ command: MediaCommand) {
        let media = media
        guard let app = track?.app else {
            // Nothing playing: play starts the preferred player instead of doing nothing.
            guard command == .playPause else { return }
            let preferred = preferredApp
            Task {
                await media.resume(preferred)
                try? await Task.sleep(for: .milliseconds(800))   // a just-opened player needs a moment
                await refreshMedia()
            }
            return
        }
        Task {
            await media.send(command, to: app)
            try? await Task.sleep(for: .milliseconds(300))   // let the player update its state
            await refreshMedia()
        }
    }

    /// Steps the loop setting off → all → one (Music) or off ↔ all (Spotify). Updates the UI
    /// right away; the next poll confirms what the player actually did.
    public func cycleRepeat() {
        guard var current = track else { return }
        let mode = current.repeatMode.next(for: current.app)
        current.repeatMode = mode
        track = current
        let media = media
        Task { await media.setRepeat(mode, for: current.app) }
    }

    private func repeating(every interval: Duration,
                           _ body: @escaping @MainActor (NotchModel) async -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await body(self)
                try? await Task.sleep(for: interval)
            }
        }
    }
}
