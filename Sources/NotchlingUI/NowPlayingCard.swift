import NotchlingCore
import SwiftUI

struct NowPlayingCard: View {
    @ObservedObject var model: NotchModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.track?.title ?? "Nothing playing")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(model.track?.artist ?? "Open Music or Spotify")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                }
            }
            HStack(spacing: 14) {
                ControlButton(symbol: "backward.fill", label: "Previous track") { model.send(.previousTrack) }
                ControlButton(symbol: model.track?.isPlaying == true ? "pause.fill" : "play.fill",
                              label: model.track?.isPlaying == true ? "Pause" : "Play",
                              size: 16) { model.send(.playPause) }
                ControlButton(symbol: "forward.fill", label: "Next track") { model.send(.nextTrack) }
            }
            .frame(maxWidth: .infinity)
            .disabled(model.track == nil)
            .opacity(model.track == nil ? 0.3 : 1)
        }
        .padding(10)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                if model.track?.isPlaying == true {
                    EqualizerBars().frame(width: 20, height: 16)
                } else {
                    Image(systemName: "music.note").font(.system(size: 17, weight: .semibold))
                }
            }
            .frame(width: 46, height: 46)
            .opacity(model.track == nil ? 0.35 : 1)
            .accessibilityHidden(true)
    }

    private var gradient: [Color] {
        switch model.track?.app {
        case .spotify:
            return [Color(red: 0.11, green: 0.73, blue: 0.33), Color(red: 0.05, green: 0.3, blue: 0.15)]
        default:
            return [Color(red: 0.98, green: 0.24, blue: 0.4), Color(red: 0.55, green: 0.1, blue: 0.6)]
        }
    }
}
