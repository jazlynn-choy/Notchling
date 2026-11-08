import NotchlingCore
import SwiftUI

/// Song, controls and loop, plus a search mode for picking something to play.
struct NowPlayingCard: View {
    @ObservedObject var model: NotchModel
    @EnvironmentObject var search: MusicSearch

    var body: some View {
        Group {
            if search.isOpen { SongSearchView() } else { player }
        }
        .cardStyle()
    }

    private var player: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                artwork
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.track?.title ?? "Nothing playing")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(model.track?.artist ?? "Search for a song, or open Music or Spotify")
                        .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).lineLimit(2)
                }
                Spacer(minLength: 0)
                IconButton(symbol: "magnifyingglass", label: "Search for a song") { search.isOpen = true }
            }
            HStack(spacing: 10) {
                ControlButton(symbol: "backward.fill", label: "Previous track") { model.send(.previousTrack) }
                ControlButton(symbol: model.track?.isPlaying == true ? "pause.fill" : "play.fill",
                              label: model.track?.isPlaying == true ? "Pause" : "Play",
                              size: 16) { model.send(.playPause) }
                ControlButton(symbol: "forward.fill", label: "Next track") { model.send(.nextTrack) }
                loopButton
            }
            .frame(maxWidth: .infinity)
            .disabled(model.track == nil)
            .opacity(model.track == nil ? 0.3 : 1)
        }
    }

    private var loopButton: some View {
        let mode = model.track?.repeatMode ?? .off
        let label: String
        switch mode {
        case .off: label = "Loop is off"
        case .all: label = "Looping the playlist"
        case .one: label = "Looping this song"
        }
        return Button { model.cycleRepeat() } label: {
            Image(systemName: mode == .one ? "repeat.1" : "repeat")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(mode == .off ? Color.white.opacity(0.5) : Color.black)
                .frame(width: 24, height: 24)
                .background(Circle().fill(mode == .off ? Color.white.opacity(0.08) : Color.green))
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
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

/// Search-as-you-type over the Music library, with a hand-off to Spotify's search.
struct SongSearchView: View {
    @EnvironmentObject var search: MusicSearch
    @FocusState private var fieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white.opacity(0.5))
                TextField(search.source == .spotify ? "Search Spotify" : "Search your Music library",
                          text: $search.query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .focused($fieldFocused)
                    .onSubmit { if let first = search.results.first { search.play(first) } }
                if search.isSearching { ProgressView().controlSize(.mini) }
                IconButton(symbol: "xmark", label: "Close search") { search.isOpen = false }
            }
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.08)))

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(search.results) { song in
                        Button { search.play(song) } label: {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(song.title).font(.system(size: 11, weight: .medium))
                                Text(song.artist).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
                            }
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Play \(song.title) by \(song.artist)")
                    }
                    if let error = search.errorMessage {
                        Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if search.hasSearched && search.results.isEmpty {
                        Text("No songs found").font(.system(size: 10)).foregroundStyle(.white.opacity(0.4))
                    }
                    // Fallback when Spotify search isn't connected: open the query in the Spotify app.
                    if search.canSearchSpotify && !search.trimmedQuery.isEmpty
                        && (search.source == .music || search.errorMessage != nil) {
                        Button { search.searchSpotify() } label: {
                            Label("Search Spotify for “\(search.trimmedQuery)”", systemImage: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.green)
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear { fieldFocused = true }
    }
}
