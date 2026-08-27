import SwiftUI

private enum NowPlayingContentMode {
    case record
    case lyrics
}

struct NowPlayingView: View {
    @Bindable var model: NowPlayingModel

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false
    @State private var contentMode: NowPlayingContentMode = .record

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
            .navigationTitle("正在播放")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showQueue = true
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel("播放队列")
                }
            }
        }
        .onAppear { model.reduceMotion = reduceMotion }
        .onChange(of: reduceMotion) { _, value in
            model.reduceMotion = value
        }
        .sheet(isPresented: $showQueue) {
            queueSheet
        }
    }

    @ViewBuilder
    private func mainContent(in size: CGSize) -> some View {
        let dimension = min(size.width - 48, 390)
        let recordDimension = model.hasLyrics
            ? dimension
            : min(dimension, 280)
        ZStack(alignment: .topTrailing) {
            if contentMode == .lyrics, model.hasLyrics {
                SyncedLyricsView(model: model)
                    .transition(
                        .opacity.combined(with: .scale(scale: 0.98))
                    )
                Button {
                    switchContent(to: .record)
                } label: {
                    Label("唱片", systemImage: "opticaldisc")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("切换到唱片")
            } else {
                VStack(spacing: 12) {
                    RecordVisual(model: model)
                        .frame(
                            width: recordDimension,
                            height: recordDimension
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
            height: model.hasLyrics
                ? max(dimension, 320)
                : recordDimension + 150
        )
        .padding(.top, 12)
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
        case .repeatAll: "列表循环"
        case .repeatOne: "单曲循环"
        case .shuffle: "随机播放"
        }
    }
}
