import SwiftUI

enum NowPlayingContentMode: Equatable {
    case artwork
    case lyrics
}

enum NowPlayingLyricSnippet {
    static func lines(from lines: [LyricLine], currentIndex: Int?) -> [LyricLine] {
        let start = max(currentIndex ?? 0, 0)
        guard start < lines.count else { return [] }
        return Array(lines[start...].lazy.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.prefix(2))
    }
}

struct NowPlayingView: View {
    @Bindable var model: NowPlayingModel
    var queueRequest: Int = 0
    var closePanel: (() -> Void)? = nil
    var panelDragChanged: ((DragGesture.Value) -> Void)? = nil
    var panelDragEnded: ((DragGesture.Value) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false
    @State private var contentMode: NowPlayingContentMode = .artwork
    @State private var artworkTheme = NowPlayingArtworkTheme.fallback

    private struct ArtworkRequest: Equatable, Sendable {
        let trackID: String?
        let path: String?
    }

    private var artworkRequest: ArtworkRequest {
        .init(trackID: model.state.currentTrack?.id, path: model.state.currentTrack?.artworkReference)
    }

    private var foreground: Color { artworkTheme.foreground.color }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [artworkTheme.top.color, artworkTheme.bottom.color],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    GeometryReader { geometry in
                        let layout = AdaptivePlayerLayout.resolve(size: geometry.size)
                        if layout.isWide {
                            widePlayer(layout: layout)
                        } else {
                            VStack(spacing: 0) {
                                GeometryReader { viewport in
                                    ScrollView {
                                        VStack(spacing: 18) {
                                            mainContent(in: viewport.size, artworkSide: layout.artworkSide)
                                            trackIdentity
                                            if !model.hasLyrics { lyricsSearch }
                                        }
                                        .padding(.horizontal, 24)
                                        .padding(.bottom, 12)
                                        .frame(maxWidth: .infinity)
                                    }
                                    .scrollIndicators(.hidden)
                                }
                                playerControls
                                    .padding(.horizontal, 24)
                                    .padding(.top, 12)
                                    .padding(.bottom, 16)
                            }
                            .accessibilityIdentifier("player.layout.compact")
                        }
                    }
                }
                .foregroundStyle(foreground)
                .tint(foreground)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .onAppear {
            model.reduceMotion = reduceMotion
            if queueRequest > 0 { showQueue = true }
        }
        .onChange(of: reduceMotion) { _, value in model.reduceMotion = value }
        .onChange(of: model.state.currentTrack?.id) { _, _ in contentMode = .artwork }
        .onChange(of: queueRequest) { _, _ in showQueue = true }
        .task(id: artworkRequest) {
            let request = artworkRequest
            artworkTheme = .fallback
            let task = Task.detached(priority: .utility) {
                guard !Task.isCancelled else { return NowPlayingArtworkTheme.fallback }
                return NowPlayingArtworkTheme.load(atPath: request.path)
            }
            let theme = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            // 切歌或网络补图会取消旧请求，旧颜色绝不能覆盖新封面。
            guard !Task.isCancelled, artworkRequest == request else { return }
            if reduceMotion {
                artworkTheme = theme
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { artworkTheme = theme }
            }
        }
        .sheet(isPresented: $showQueue) { queueSheet }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                if let closePanel { closePanel() } else { dismiss() }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("收起播放器")
            .accessibilityIdentifier("player.detail.close")
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                contentTab("歌曲", mode: .artwork, identifier: "player.tab.song")
                contentTab("歌词", mode: .lyrics, identifier: "player.tab.lyrics")
            }
            .padding(4)
            .background(foreground.opacity(0.09), in: Capsule())
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 60)
        .contentShape(Rectangle())
        .highPriorityGesture(panelDrag)
    }

    private func contentTab(_ title: String, mode: NowPlayingContentMode, identifier: String) -> some View {
        Button { switchContent(to: mode) } label: {
            Text(title)
                .font(.subheadline.weight(contentMode == mode ? .bold : .medium))
                .frame(minWidth: 64, minHeight: 36)
                .background(foreground.opacity(contentMode == mode ? 0.15 : 0), in: Capsule())
        }
        .accessibilityAddTraits(contentMode == mode ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private func mainContent(in size: CGSize, artworkSide: CGFloat) -> some View {
        if contentMode == .lyrics {
            Group {
                if model.hasLyrics {
                    SyncedLyricsView(model: model, foreground: foreground)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "text.alignleft").font(.largeTitle)
                        Text("暂无歌词").font(.headline)
                        Text("可以查找歌词或导入同名 LRC 文件")
                            .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: max(120, size.height - (model.hasLyrics ? 90 : 150)))
            .accessibilityIdentifier("player.lyrics.full")
            .transition(.opacity)
        } else {
            VStack(spacing: 16) {
                artwork(side: artworkSide)
                if model.hasLyrics { lyricSnippet }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .transition(.opacity)
        }
    }

    private var playerControls: some View {
        VStack(spacing: 12) {
            progressControls
            transportControls
        }
    }

    private func artwork(side: CGFloat) -> some View {
        Group {
            if model.state.currentTrack?.artworkReference != nil {
                ArtworkView(path: model.state.currentTrack?.artworkReference, cornerRadius: 24)
            } else {
                RecordVisual(model: model)
            }
        }
        .frame(width: side, height: side)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.22), radius: 20, y: 10)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .highPriorityGesture(panelDrag)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("歌曲封面")
        .accessibilityIdentifier("player.artwork")
    }

    private func widePlayer(layout: AdaptivePlayerLayout) -> some View {
        HStack(spacing: 32) {
            VStack(spacing: 16) {
                Spacer(minLength: 0)
                artwork(side: layout.artworkSide)
                if model.hasLyrics { lyricSnippet }
                trackIdentity
                if !model.hasLyrics { lyricsSearch }
                Spacer(minLength: 12)
                playerControls
            }
            .frame(width: layout.columnWidth)
            VStack(alignment: .leading, spacing: 16) {
                Text(contentMode == .lyrics ? "同步歌词" : "播放队列")
                    .font(.title2.weight(.bold))
                if contentMode == .lyrics {
                    if model.hasLyrics {
                        SyncedLyricsView(model: model, foreground: foreground)
                            .accessibilityIdentifier("player.lyrics.full")
                    } else {
                        ContentUnavailableView("暂无歌词", systemImage: "text.alignleft")
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(model.state.queue.enumerated()), id: \.element.id) { entry in
                                Button { Task { await model.playQueueItem(at: entry.offset) } } label: {
                                    HStack(spacing: 12) {
                                        ArtworkView(path: entry.element.artworkReference, cornerRadius: 8)
                                            .frame(width: 44, height: 44)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(entry.element.title).font(.headline).lineLimit(2)
                                            Text(entry.element.artist).font(.subheadline).opacity(0.7).lineLimit(1)
                                        }
                                        Spacer(minLength: 0)
                                        if entry.offset == model.state.currentIndex {
                                            Image(systemName: "speaker.wave.2.fill")
                                        }
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(foreground.opacity(entry.offset == model.state.currentIndex ? 0.13 : 0.04), in: RoundedRectangle(cornerRadius: 12))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: layout.columnWidth, alignment: .leading)
            .frame(maxHeight: .infinity)
            .background(foreground.opacity(0.055), in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.layout.wide")
    }

    private var lyricSnippet: some View {
        let lines = NowPlayingLyricSnippet.lines(from: model.lyricLines, currentIndex: model.currentLyricIndex)
        return Button { switchContent(to: .lyrics) } label: {
            VStack(spacing: 7) {
                if lines.isEmpty {
                    Text(model.hasLyrics ? "点击查看完整歌词" : "暂无歌词 · 点击查看")
                        .font(.subheadline)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { entry in
                        Text(entry.element.text)
                            .font(entry.offset == 0 ? .body.weight(.medium) : .subheadline)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看完整歌词")
        .accessibilityIdentifier("player.lyrics.snippet")
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
            withAnimation(.easeInOut(duration: 0.25)) { contentMode = mode }
        }
    }

    private var trackIdentity: some View {
        VStack(spacing: 6) {
            Text(model.state.currentTrack?.title ?? "选择一首本地音乐")
                .font(.title2.weight(.bold))
                .lineLimit(1)
            Text(model.state.currentTrack?.artist ?? "爱乐之城")
                .font(.subheadline)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var lyricsSearch: some View {
        VStack(spacing: 6) {
            Button { Task { await model.findLyrics() } } label: {
                Label(model.isSearchingLyrics ? "正在查找歌词…" : "查找歌词", systemImage: "text.magnifyingglass")
            }
            .disabled(model.isSearchingLyrics)
            .accessibilityIdentifier("player.lyrics.search")
            if !model.lyricsSearchMessage.isEmpty {
                Text(model.lyricsSearchMessage).font(.caption)
            }
        }
    }

    private var progressControls: some View {
        VStack(spacing: 4) {
            Slider(
                value: Binding(get: { model.progress }, set: { try? model.seek(fraction: $0) }),
                in: 0...1
            )
            .accessibilityLabel("播放进度")
            .accessibilityIdentifier("player.detail.progress")
            HStack {
                Text(format(model.state.position))
                Spacer()
                Text(format(model.state.duration))
            }
            .font(.caption.monospacedDigit())
        }
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            Button { model.cycleMode() } label: {
                Image(systemName: modeIcon).font(.title3).frame(width: 44, height: 48)
            }
            .accessibilityLabel("播放模式：\(modeLabel)")
            .accessibilityIdentifier("player.detail.mode")
            Spacer(minLength: 0)
            Button { Task { await model.previous() } } label: {
                Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 48)
            }
            .accessibilityLabel("上一首")
            .accessibilityIdentifier("player.detail.previous")
            Spacer(minLength: 0)
            Button { Task { await model.togglePlayback() } } label: {
                Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2)
                    .frame(width: 64, height: 64)
                    .background(foreground, in: Circle())
                    .foregroundStyle(artworkTheme.top.color)
            }
            .accessibilityLabel(model.state.isPlaying ? "暂停" : "播放")
            .accessibilityIdentifier("player.detail.playPause")
            Spacer(minLength: 0)
            Button { Task { await model.next() } } label: {
                Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 48)
            }
            .accessibilityLabel("下一首")
            .accessibilityIdentifier("player.detail.next")
            Spacer(minLength: 0)
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet").font(.title3).frame(width: 44, height: 48)
            }
            .accessibilityLabel("播放队列")
            .accessibilityIdentifier("player.detail.queue")
        }
        .buttonStyle(.plain)
    }

    private var queueSheet: some View {
        NavigationStack {
            List {
                ForEach(Array(model.state.queue.enumerated()), id: \.element.id) { entry in
                    Button { Task { await model.playQueueItem(at: entry.offset) } } label: {
                        HStack {
                            Image(systemName: entry.offset == model.state.currentIndex ? "speaker.wave.2.fill" : "music.note")
                                .foregroundStyle(entry.offset == model.state.currentIndex ? PlayerTheme.accent : Color.secondary)
                            VStack(alignment: .leading) {
                                Text(entry.element.title)
                                    .foregroundStyle(entry.offset == model.state.currentIndex ? PlayerTheme.accent : Color.primary)
                                Text(entry.element.artist).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onMove { offsets, destination in model.moveQueue(fromOffsets: offsets, toOffset: destination) }
                .onDelete { offsets in Task { await model.removeQueueItems(atOffsets: offsets) } }
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
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
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
