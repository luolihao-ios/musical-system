import SwiftUI

enum MiniPlayerGestureAction: Equatable {
    case none, dismiss, openNowPlaying
    static func resolve(translation: CGSize, threshold: CGFloat = 35) -> Self {
        if translation.height >= threshold { return .dismiss }
        if translation.height <= -threshold { return .openNowPlaying }
        return .none
    }
}

struct PlayerPanelFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        // 未提供几何值的子树不能用默认零矩形覆盖已经测量的面板。
        if !next.isEmpty { value = next }
    }
}

struct MiniPlayerView: View {
    @Bindable var model: NowPlayingModel
    let openNowPlaying: () -> Void
    var dismiss: () -> Void = {}
    var maximumHeight: CGFloat = 780
    var maximumWidth: CGFloat = 390
    var bottomInset: CGFloat = 0
    var menuClearance: CGFloat = 90

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var panel = PlayerPanelInteraction()
    @State private var lastSampleTime: TimeInterval = 0
    @State private var actualFrame = CGRect.zero
    @State private var queueRequest = 0
    private var compactHeight: CGFloat { 60 }
    private var fullHeight: CGFloat { max(compactHeight, maximumHeight) }
    private var height: CGFloat { panel.height(compact: compactHeight, expanded: fullHeight) }
    private var progress: CGFloat {
        min(1, max(0, (height - compactHeight) / max(1, fullHeight - compactHeight)))
    }

    var body: some View {
        ZStack(alignment: .top) {
            if panel.phase == .expanded {
            // 详情页始终属于同一个面板；松手后没有第二次 sheet 弹出。
            NowPlayingView(
                model: model,
                queueRequest: queueRequest,
                closePanel: close,
                panelDragChanged: dragChanged,
                panelDragEnded: dragEnded,
                panelGestureFinished: { panel.finishGestureSession() }
            )
            .frame(height: max(1, fullHeight - bottomInset))
            .opacity(progress)
            .allowsHitTesting(panel.phase == .expanded)
            .accessibilityHidden(panel.phase != .expanded)
            } else {
            compactContent
                .opacity(1 - progress)
                .allowsHitTesting(panel.phase == .compact)
                .accessibilityHidden(panel.phase != .compact)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 30 - 8 * progress))
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
        .padding(.horizontal, 12 * (1 - progress))
        .padding(.bottom, menuClearance * (1 - progress))
        .onAppear {
            PlayerInteractionDiagnostics.log("panel appear compact=\(compactHeight) full=\(fullHeight) bottomInset=\(bottomInset)")
        }
        .onDisappear { PlayerInteractionDiagnostics.log("panel disappear frame=\(actualFrame)") }
        .onChange(of: maximumHeight) { _, _ in
            panel.cancelDragForResize()
            PlayerInteractionDiagnostics.log("panel resized height=\(maximumHeight) phase=\(panel.phase.rawValue)")
        }
        .onChange(of: maximumWidth) { _, _ in
            panel.cancelDragForResize()
            PlayerInteractionDiagnostics.log("panel resized width=\(maximumWidth) phase=\(panel.phase.rawValue)")
        }
    }

    private var compactContent: some View {
        HStack(spacing: 12) {
            Button(action: expand) {
                HStack(spacing: 12) {
                    ArtworkView(path: model.state.currentTrack?.artworkReference, cornerRadius: 23)
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(model.state.currentTrack?.title ?? String(localized: "爱乐之城"))
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(model.state.currentTrack?.artist ?? String(localized: "本地播放"))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .accessibilityLabel("打开正在播放")
            .accessibilityIdentifier("player.compact.open")
            .highPriorityGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .global)
                    .onEnded { value in
                        PlayerInteractionDiagnostics.log("compact swipe ignored translation=\(value.translation)")
                    }
            )
            Button {
                PlayerInteractionDiagnostics.log("compact playback tap before=\(model.state.isPlaying) frame=\(actualFrame)")
                Task {
                    await model.togglePlayback()
                    PlayerInteractionDiagnostics.log("compact playback complete after=\(model.state.isPlaying)")
                }
            } label: {
                Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(model.state.isPlaying ? String(localized: "暂停") : String(localized: "播放"))
            .accessibilityIdentifier("player.compact.playback")
            .accessibilityValue(model.state.isPlaying ? "playing" : "paused")
            Button {
                expand()
                queueRequest += 1
            } label: {
                Image(systemName: "list.bullet").frame(width: 44, height: 44)
            }
            .accessibilityLabel("播放队列")
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
        queueRequest = 0
        PlayerInteractionDiagnostics.log("close button phase=\(panel.phase.rawValue) frame=\(actualFrame)")
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) { panel.close() }
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
        guard panel.acceptsGesture else {
            PlayerInteractionDiagnostics.log("detail release ignored after resize")
            return
        }
        PlayerInteractionDiagnostics.log("detail release translation=\(value.translation) phase=\(panel.phase.rawValue)")
        if value.translation.height < -80 && abs(value.translation.height) > abs(value.translation.width) {
            panel.release(compact: compactHeight, expanded: fullHeight)
            Task {
                PlayerInteractionDiagnostics.log("detail swipe next begin")
                await model.next()
                PlayerInteractionDiagnostics.log("detail swipe next complete phase=\(panel.phase.rawValue) track=\(model.state.currentTrack?.id ?? "none")")
            }
            return
        }
        // 最后一帧也按绝对位移计算，处理快速松手。
        panel.drag(translation: value.translation.height, compact: compactHeight, expanded: fullHeight)
        let before = panel.phase
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
            panel.release(compact: compactHeight, expanded: fullHeight)
        }
        PlayerInteractionDiagnostics.log("drag end translation=\(value.translation.height) from=\(before.rawValue) to=\(panel.phase.rawValue) expansions=\(panel.expansionCount) frame=\(actualFrame)")
        if before == .expanded && panel.phase == .compact {
            queueRequest = 0
            dismiss()
        }
        if before != .expanded && panel.phase == .expanded { openNowPlaying() }
    }
}
