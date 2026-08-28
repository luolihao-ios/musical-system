import SwiftUI

struct MiniPlayerView: View {
    @Bindable var model: NowPlayingModel
    let openNowPlaying: () -> Void

    var body: some View {
        ZStack {
            Button(action: openNowPlaying) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开正在播放")

            HStack(spacing: 12) {
                HStack(spacing: 12) {
                    ArtworkView(
                        path: model.state.currentTrack?.artworkReference,
                        cornerRadius: 8
                    )
                    .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.state.currentTrack?.title ?? "爱乐之城")
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)
                        Text(model.state.currentTrack?.artist ?? "本地播放")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .allowsHitTesting(false)
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
                .accessibilityLabel(
                    model.state.isPlaying ? "暂停" : "播放"
                )
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
        }
        .frame(height: 60)
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
                .allowsHitTesting(false)
        }
    }
}
