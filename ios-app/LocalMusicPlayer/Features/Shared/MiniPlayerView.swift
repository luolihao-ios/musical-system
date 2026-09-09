import SwiftUI

enum MiniPlayerGestureAction: Equatable {
    case none, dismiss, openNowPlaying
    static func resolve(translation: CGSize, threshold: CGFloat = 35) -> Self {
        if translation.height >= threshold { return .dismiss }
        if translation.height <= -threshold { return .openNowPlaying }
        return .none
    }
}

private struct PlayerPanelFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct MiniPlayerView: View {
    @Bindable var model: NowPlayingModel
    let openNowPlaying: () -> Void
    var dismiss: () -> Void = {}
    var maximumHeight: CGFloat = 780
    var bottomInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel = PlayerPanelInteraction()
    @State private var lastSampleTime: TimeInterval = 0
    @State private var actualFrame = CGRect.zero
    private var compactHeight: CGFloat { 60 + bottomInset }
    private var fullHeight: CGFloat { max(compactHeight, maximumHeight) }
    private var height: CGFloat { panel.height(compact: compactHeight, expanded: fullHeight) }
    private var progress: CGFloat {
        min(1, max(0, (height - compactHeight) / max(1, fullHeight - compactHeight)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            // 详情页始终属于同一个面板；松手后没有第二次 sheet 弹出。
            NowPlayingView(
                model: model,
                closePanel: close,
                panelDragChanged: dragChanged,
                panelDragEnded: dragEnded
            )
            .frame(height: max(1, fullHeight - bottomInset))
            .opacity(progress)
            .allowsHitTesting(panel.phase == .expanded)
            .accessibilityHidden(panel.phase != .expanded)

            compactContent
                .opacity(1 - progress)
                .allowsHitTesting(panel.phase == .compact)
                .accessibilityHidden(panel.phase != .compact)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 8, coordinateSpace: .global)
                        .onChanged(dragChanged)
                        .onEnded(dragEnded)
                )
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(.regularMaterial)
        .clipShape(UnevenRoundedRectangle(
            topLeadingRadius: 22 * progress,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 22 * progress
        ))
        .contentShape(Rectangle())
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: PlayerPanelFrameKey.self, value: geometry.frame(in: .global))
            }
        }
        .onPreferenceChange(PlayerPanelFrameKey.self) { frame in
            actualFrame = frame
            if !panel.isDragging {
                PlayerInteractionDiagnostics.log("layout phase=\(panel.phase.rawValue) actualFrame=\(frame) targetHeight=\(height)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.panel")
        .accessibilityValue("\(panel.phase.rawValue);expansions=\(panel.expansionCount)")
        .onAppear {
            PlayerInteractionDiagnostics.log("panel appear compact=\(compactHeight) full=\(fullHeight) bottomInset=\(bottomInset)")
        }
        .onDisappear { PlayerInteractionDiagnostics.log("panel disappear frame=\(actualFrame)") }
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            Button(action: expand) {
                HStack(spacing: 12) {
                    ArtworkView(path: model.state.currentTrack?.artworkReference, cornerRadius: 8)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.state.currentTrack?.title ?? "爱乐之城")
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(model.state.currentTrack?.artist ?? "本地播放")
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("打开正在播放")
            Button { Task { await model.togglePlayback() } } label: {
                Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.state.isPlaying ? "暂停" : "播放")
            Button { Task { await model.next() } } label: {
                Image(systemName: "forward.end.fill").frame(width: 44, height: 44)
            }
            .accessibilityLabel("下一首")
            Button(action: close) {
                Image(systemName: "xmark").frame(width: 36, height: 44)
            }
            .accessibilityLabel("关闭播放器")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 60)
        .contentShape(Rectangle())
        .overlay(alignment: .top) {
            GeometryReader { geometry in
                Rectangle().fill(PlayerTheme.accent)
                    .frame(width: geometry.size.width * model.progress, height: 2)
            }
            .frame(height: 2).allowsHitTesting(false)
        }
    }

    private func expand() {
        guard !panel.isDragging, panel.phase == .compact else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { panel.expand() }
        PlayerInteractionDiagnostics.log("tap expand count=\(panel.expansionCount) frame=\(actualFrame)")
        openNowPlaying()
    }

    private func close() {
        PlayerInteractionDiagnostics.log("close button phase=\(panel.phase.rawValue) frame=\(actualFrame)")
        panel.close()
        dismiss()
    }

    private func dragChanged(_ value: DragGesture.Value) {
        if !panel.isDragging {
            PlayerInteractionDiagnostics.log("drag begin phase=\(panel.phase.rawValue) startY=\(value.startLocation.y) frame=\(actualFrame) height=\(height) threshold=\(height / 3)")
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            panel.drag(translation: value.translation.height, compact: compactHeight, expanded: fullHeight)
        }
        let now = Date.timeIntervalSinceReferenceDate
        if now - lastSampleTime >= 0.12 {
            lastSampleTime = now
            PlayerInteractionDiagnostics.log("drag sample y=\(value.location.y) translation=\(value.translation.height) targetHeight=\(height) actualFrame=\(actualFrame)")
        }
    }

    private func dragEnded(_ value: DragGesture.Value) {
        // 最后一帧也按绝对位移计算，处理快速松手。
        panel.drag(translation: value.translation.height, compact: compactHeight, expanded: fullHeight)
        let before = panel.phase
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            panel.release(compact: compactHeight, expanded: fullHeight)
        }
        PlayerInteractionDiagnostics.log("drag end translation=\(value.translation.height) from=\(before.rawValue) to=\(panel.phase.rawValue) expansions=\(panel.expansionCount) frame=\(actualFrame)")
        if panel.phase == .hidden { dismiss() }
        if before != .expanded && panel.phase == .expanded { openNowPlaying() }
    }
}
