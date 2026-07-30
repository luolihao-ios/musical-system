import SwiftUI

struct MiniPlayerView: View {
    @Bindable var model: NowPlayingModel
    let openNowPlaying: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: openNowPlaying) {
                HStack(spacing: 12) {
                    ArtworkView(
                        path: model.state.currentTrack?.artworkReference,
                        cornerRadius: 8
                    )
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.state.currentTrack?.title ?? "暮色音乐")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(model.state.currentTrack?.artist ?? "本地播放")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button {
                Task { await model.togglePlayback() }
            } label: {
                Image(
                    systemName: model.state.isPlaying
                        ? "pause.fill"
                        : "play.fill"
                )
                .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.state.isPlaying ? "暂停" : "播放")
            Button {
                Task { await model.next() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("下一首")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(PlayerTheme.accent)
                .frame(
                    maxWidth: .infinity,
                    maxHeight: 2,
                    alignment: .leading
                )
                .scaleEffect(x: model.progress, anchor: .leading)
        }
    }
}
