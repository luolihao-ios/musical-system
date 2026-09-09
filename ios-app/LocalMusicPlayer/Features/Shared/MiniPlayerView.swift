import SwiftUI
import UIKit

enum MiniPlayerGestureAction: Equatable {
    case none
    case dismiss
    case openNowPlaying

    static func resolve(translation: CGSize, threshold: CGFloat = 35) -> Self {
        if translation.height >= threshold {
            return .dismiss
        }
        if translation.height <= -threshold {
            return .openNowPlaying
        }
        return .none
    }
}

struct MiniPlayerView: View {
    @Bindable var model: NowPlayingModel
    let openNowPlaying: () -> Void
    var dismiss: () -> Void = {}

    @State private var dragProgress: CGFloat = 0
    @State private var dragStartProgress: CGFloat = 0
    @State private var dragOffset: CGFloat = 0
    @State private var dragStartOffset: CGFloat = 0
    @State private var didStartDrag = false

    private let compactHeight: CGFloat = 60

    private var expandedHeight: CGFloat {
        min(max(UIScreen.main.bounds.height * 0.84, 520), 780)
    }

    private var availableDistance: CGFloat {
        max(expandedHeight - compactHeight, 1)
    }

    var body: some View {
        ZStack(alignment: .top) {
            compactContent
                .opacity(max(0, 1 - dragProgress * 1.15))

            expandedContent
                .opacity(min(max(dragProgress * 1.35, 0), 1))
                .scaleEffect(0.92 + dragProgress * 0.08, anchor: .top)
                .allowsHitTesting(dragProgress > 0.01)
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: compactHeight
                + (expandedHeight - compactHeight) * dragProgress,
            alignment: .top
        )
        .offset(y: dragOffset)
        .background(.ultraThinMaterial)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 22 * dragProgress,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: 22 * dragProgress,
                style: .continuous
            )
        )
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
        .clipped()
        .contentShape(Rectangle())
        // 只有明显位移才由外层手势接管，避免拖拽与打开详情同时触发。
        .highPriorityGesture(dragGesture)
        .allowsHitTesting(true)
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            Button(action: openNowPlaying) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("打开正在播放")
            .layoutPriority(1)

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
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel("关闭播放器")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(height: compactHeight)
    }

    private var expandedContent: some View {
        VStack(spacing: 14) {
            Capsule()
                .fill(Color.secondary.opacity(0.45))
                .frame(width: 42, height: 5)
                .padding(.top, 8)

            ArtworkView(
                path: model.state.currentTrack?.artworkReference,
                cornerRadius: 24
            )
            .frame(
                width: min(UIScreen.main.bounds.width - 48, 330),
                height: min(UIScreen.main.bounds.width - 48, 330)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: .black.opacity(0.32), radius: 24, y: 12)

            VStack(spacing: 4) {
                Text(model.state.currentTrack?.title ?? "正在播放")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                Text(model.state.currentTrack?.artist ?? "爱乐之城")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 28) {
                Button {
                    Task { await model.previous() }
                } label: {
                    Image(systemName: "backward.end.fill")
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("上一首")
                Button {
                    Task { await model.togglePlayback() }
                } label: {
                    Image(
                        systemName: model.state.isPlaying
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .font(.title3)
                    .frame(width: 58, height: 58)
                    .background(PlayerTheme.accent, in: Circle())
                    .foregroundStyle(.white)
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
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !didStartDrag {
                    dragStartProgress = dragProgress
                    dragStartOffset = dragOffset
                    didStartDrag = true
                }
                let translation = value.translation.height
                if translation < 0 {
                    dragProgress = MiniPlayerDragState.progress(
                        from: dragStartProgress,
                        translation: translation,
                        availableDistance: availableDistance
                    )
                    dragOffset = 0
                } else {
                    dragProgress = dragStartProgress
                    dragOffset = max(dragStartOffset + translation, 0)
                }
            }
            .onEnded { value in
                didStartDrag = false
                let decision = MiniPlayerDragState.settle(
                    progress: dragProgress,
                    translation: value.translation.height,
                    availableDistance: availableDistance
                )
                switch decision {
                case .expand:
                    dragOffset = 0
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                        dragProgress = 1
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                        openNowPlaying()
                        dragProgress = 0
                    }
                case .dismiss:
                    let closeDistance = compactHeight + 24
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragOffset = closeDistance
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        dragOffset = 0
                        dismiss()
                    }
                case .compact:
                    withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.86)) {
                        dragProgress = 0
                        dragOffset = 0
                    }
                }
            }
    }
}
