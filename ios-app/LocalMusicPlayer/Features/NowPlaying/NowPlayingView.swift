import SwiftUI

enum NowPlayingContentMode: Equatable {
    case artwork
    case record
    case lyrics

    static func modeAfterArtworkTap(hasLyrics: Bool) -> Self {
        hasLyrics ? .lyrics : .record
    }

    static var modeAfterLyricsToggle: Self { .artwork }
}

struct NowPlayingView: View {
    @Bindable var model: NowPlayingModel
    var closePanel: (() -> Void)? = nil
    var panelDragChanged: ((DragGesture.Value) -> Void)? = nil
    var panelDragEnded: ((DragGesture.Value) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false
    @State private var contentMode: NowPlayingContentMode = .artwork

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.22, green: 0.07, blue: 0.11),
                        PlayerTheme.background,
                        Color.black
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    HStack {
                        Button("关闭") {
                            if let closePanel { closePanel() } else { dismiss() }
                        }
                        .accessibilityIdentifier("player.detail.close")
                        Spacer()
                        Text("正在播放").font(.headline)
                        Spacer()
                        Button { showQueue = true } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel("播放队列")
                        .accessibilityIdentifier("player.detail.queue")
                    }
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    .contentShape(Rectangle())
                    .accessibilityIdentifier("player.detail.header")
                    .highPriorityGesture(panelDrag)
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 22) {
                            mainContent(in: geometry.size)
                            trackIdentity
                            progressControls
                            transportControls
                            playbackOptions
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 28)
                        .frame(maxWidth: .infinity)
                    }
                    .scrollIndicators(.hidden)
                }
                }
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear { model.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in
            model.reduceMotion = value
        }
        .onChange(of: model.state.currentTrack?.id) { _, _ in
            contentMode = .artwork
        }
        .sheet(isPresented: $showQueue) {
            queueSheet
        }
    }

    @ViewBuilder
    private func mainContent(in size: CGSize) -> some View {
        let dimension = min(size.width - 48, 390)
        ZStack(alignment: .topTrailing) {
            if contentMode == .lyrics, model.hasLyrics {
                SyncedLyricsView(model: model)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98))
                    )
                Button {
                    switchContent(to: NowPlayingContentMode.modeAfterLyricsToggle)
                } label: {
                    Label("封面", systemImage: "photo")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换到封面")
                .accessibilityIdentifier("player.lyrics.artwork")
            } else if contentMode == .artwork,
                      model.state.currentTrack?.artworkReference != nil {
                VStack(spacing: 12) {
                    ZStack(alignment: .bottom) {
                        ArtworkView(
                            path: model.state.currentTrack?.artworkReference,
                            cornerRadius: 24
                        )
                        // 程序化封面本身已包含静态声波；播放时只在原位置
                        // 叠加动态波形，不在歌曲标题下方额外增加一组。
                        PlaybackWaveformView(isPlaying: model.state.isPlaying)
                            .frame(width: dimension * 0.56)
                            .padding(.bottom, dimension * 0.265)
                    }
                    .frame(width: dimension, height: dimension)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(
                        color: .black.opacity(0.35),
                        radius: 24,
                        y: 12
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .onTapGesture {
                        switchContent(
                            to: NowPlayingContentMode.modeAfterArtworkTap(
                                hasLyrics: model.hasLyrics
                            )
                        )
                    }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(
                        model.hasLyrics ? "查看歌词" : "切换到唱片"
                    )
                    .accessibilityIdentifier("player.artwork")
                    if model.hasLyrics {
                        Text("点击封面查看歌词")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .transition(
                    .opacity.combined(with: .scale(scale: 0.98))
                )
            } else {
                VStack(spacing: 12) {
                    RecordVisual(model: model)
                        .frame(
                            width: min(dimension, 280),
                            height: min(dimension, 280)
                        )
                        .contentShape(Circle())
                        .onTapGesture {
                            guard model.hasLyrics else { return }
                            switchContent(to: .lyrics)
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityLabel(
                            model.hasLyrics ? "查看歌词" : "唱片动画"
                        )
                    if !model.hasLyrics {
                        noLyrics
                    }
                }
                .transition(
                    .opacity.combined(with: .scale(scale: 0.98))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .frame(
            height: contentMode == .lyrics
                ? max(dimension, 320)
                : dimension + (model.hasLyrics ? 56 : 24)
        )
        .padding(.top, 12)
        .highPriorityGesture(panelDrag, including: contentMode == .lyrics ? .subviews : .all)
    }

    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { panelDragChanged?($0) }
            .onEnded { panelDragEnded?($0) }
    }

    private func switchContent(to mode: NowPlayingContentMode) {
        if model.reduceMotion {
            contentMode = mode
        } else {
            withAnimation(.easeInOut(duration: 0.3)) {
                contentMode = mode
            }
        }
    }

    private var trackIdentity: some View {
        VStack(spacing: 6) {
            Text(model.state.currentTrack?.title ?? "选择一首本地音乐")
                .font(.title2.weight(.bold))
                .lineLimit(1)
            Text(model.state.currentTrack?.artist ?? "爱乐之城")
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var noLyrics: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform.path")
                .font(.system(size: 38))
                .foregroundStyle(PlayerTheme.accent)
            Text("这一刻没有同步歌词")
                .font(.headline)
            Text("让唱片和光影陪音乐继续旋转")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(height: 150)
        .accessibilityElement(children: .combine)
    }

    private var progressControls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(
                    get: { model.progress },
                    set: { try? model.seek(fraction: $0) }
                ),
                in: 0...1
            )
            .tint(PlayerTheme.accent)
            .accessibilityLabel("播放进度")
            HStack {
                Text(format(model.state.position))
                Spacer()
                Text(format(model.state.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var transportControls: some View {
        HStack(spacing: 34) {
            Button {
                Task { await model.previous() }
            } label: {
                Image(systemName: "backward.end.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
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
                .font(.title2)
                .frame(width: 64, height: 64)
                .background(PlayerTheme.accent, in: Circle())
                .foregroundStyle(.white)
            }
            .accessibilityLabel(model.state.isPlaying ? "暂停" : "播放")

            Button {
                Task { await model.next() }
            } label: {
                Image(systemName: "forward.end.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("下一首")
        }
        .buttonStyle(.plain)
    }

    private var playbackOptions: some View {
        HStack {
            Spacer()
            Button {
                model.cycleMode()
            } label: {
                Label(modeLabel, systemImage: modeIcon)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("播放模式：\(modeLabel)")
            Spacer()
        }
    }

    private var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(
                    Array(model.state.queue.enumerated()),
                    id: \.element.id
                ) { entry in
                    Button {
                        Task { await model.playQueueItem(at: entry.offset) }
                    } label: {
                        HStack {
                            Image(
                                systemName: entry.offset
                                    == model.state.currentIndex
                                    ? "speaker.wave.2.fill"
                                    : "music.note"
                            )
                            .foregroundStyle(
                                entry.offset == model.state.currentIndex
                                    ? PlayerTheme.accent
                                    : Color.secondary
                            )
                            VStack(alignment: .leading) {
                                Text(entry.element.title)
                                    .foregroundStyle(
                                        entry.offset == model.state.currentIndex
                                            ? PlayerTheme.accent
                                            : Color.primary
                                    )
                                Text(entry.element.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onMove { offsets, destination in
                    model.moveQueue(
                        fromOffsets: offsets,
                        toOffset: destination
                    )
                }
                .onDelete { offsets in
                    Task { await model.removeQueueItems(atOffsets: offsets) }
                }
            }
            .navigationTitle("播放队列")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("清空", role: .destructive) {
                        model.clearQueue()
                        showQueue = false
                    }
                    .disabled(model.state.queue.isEmpty)
                    .accessibilityIdentifier("player.queue.clear")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func format(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let value = max(Int(seconds), 0)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private var modeIcon: String {
        switch model.state.mode {
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    private var modeLabel: String {
        switch model.state.mode {
        case .repeatAll: String(localized: "列表循环")
        case .repeatOne: String(localized: "单曲循环")
        case .shuffle: String(localized: "随机播放")
        }
    }
}
