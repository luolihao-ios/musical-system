import SwiftUI
import UIKit

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
    var topSafeInset: CGFloat = 0
    var bottomSafeInset: CGFloat = 0
    var closePanel: (() -> Void)? = nil
    var panelDragChanged: ((DragGesture.Value) -> Void)? = nil
    var panelDragEnded: ((DragGesture.Value) -> Void)? = nil
    var panelGestureFinished: (() -> Void)? = nil
    @GestureState private var panelGestureActive = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showQueue = false
    @State private var contentMode: NowPlayingContentMode = .artwork
    @State private var artworkTheme = NowPlayingArtworkTheme.fallback
    @AppStorage("player.visualMode") private var visualMode = PlayerVisualMode.cover
    @State private var showSleepTimer = false
    @State private var showSkinPicker = false
    @State private var scrubbingProgress: Double?

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
                immersiveBackdrop

                VStack(spacing: 0) {
                    header
                        .padding(.top, topSafeInset)

                    GeometryReader { geometry in
                        let layout = AdaptivePlayerLayout.resolve(size: geometry.size)
                        if #available(iOS 27.1, *), !geometry.reservedRegions(kind: .division, options: .includeInactive).isEmpty {
                            duoPlayer
                        } else if layout.isWide {
                            widePlayer(layout: layout)
                        } else if visualMode == .classic && contentMode == .artwork {
                            ClassicPlayerVisual(model: model, showQueue: { showQueue = true })
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .padding(.bottom, 16)
                                .accessibilityIdentifier("player.artwork")
                                .accessibilityElement(children: .contain)
                                .accessibilityIdentifier("player.layout.compact")
                        } else {
                            compactPlayer(in: geometry.size, artworkSide: layout.artworkSide)
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
        .onChange(of: panelGestureActive) { _, active in
            if !active { panelGestureFinished?() }
        }
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
            guard !Task.isCancelled, artworkRequest == request else { return }
            if reduceMotion {
                artworkTheme = theme
            } else {
                withAnimation(.easeInOut(duration: 0.3)) { artworkTheme = theme }
            }
        }
        .sheet(isPresented: $showQueue) { queueSheet }
        .sheet(isPresented: $showSkinPicker) {
            PlayerAppearanceSheet(visualMode: $visualMode)
        }
        .confirmationDialog("定时暂停", isPresented: $showSleepTimer, titleVisibility: .visible) {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button {
                    model.scheduleSleepTimer(minutes: minutes)
                } label: {
                    Text(String(format: NSLocalizedString("%lld 分钟", comment: ""), Int64(minutes)))
                }
            }
            if model.sleepDeadline != nil {
                Button("关闭定时暂停", role: .destructive) { model.scheduleSleepTimer(minutes: nil) }
            }
        }
    }

    private var immersiveBackdrop: some View {
        LinearGradient(
            colors: [
                artworkTheme.top.color,
                artworkTheme.bottom.color,
                artworkTheme.top.mixed(with: .black, amount: 0.22).color
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .accessibilityHidden(true)
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

            HStack(spacing: 18) {
                contentTab("歌曲", mode: .artwork, identifier: "player.tab.song")
                Rectangle()
                    .fill(foreground.opacity(0.25))
                    .frame(width: 1, height: 12)
                contentTab("歌词", mode: .lyrics, identifier: "player.tab.lyrics")
            }

            Spacer(minLength: 0)

            Button {
                showSkinPicker = true
            } label: {
                Image(systemName: "record.circle")
                    .font(.title3.weight(.medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("切换播放器外观")
            .accessibilityIdentifier("player.appearance.mode")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .frame(height: 60)
        .contentShape(Rectangle())
        .highPriorityGesture(panelDrag)
    }

    private func contentTab(_ title: String, mode: NowPlayingContentMode, identifier: String) -> some View {
        Button { switchContent(to: mode) } label: {
            Text(LocalizedStringKey(title))
                .font(.subheadline.weight(contentMode == mode ? .bold : .regular))
                .foregroundStyle(foreground.opacity(contentMode == mode ? 1.0 : 0.55))
                .frame(minWidth: 44, minHeight: 36)
        }
        .accessibilityAddTraits(contentMode == mode ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    private func compactPlayer(in size: CGSize, artworkSide: CGFloat) -> some View {
        VStack(spacing: 0) {
            GeometryReader { viewport in
                if contentMode == .lyrics {
                    lyricsContent(in: viewport.size)
                        .padding(.horizontal, 26)
                } else {
                    VStack(spacing: 18) {
                        Spacer(minLength: 4)
                        artwork(side: min(artworkSide, viewport.size.width - 48, viewport.size.height - (model.hasLyrics ? 96 : 36)))
                        if model.hasLyrics {
                            lyricSnippet
                        } else if model.isSearchingLyrics || !model.lyricsSearchMessage.isEmpty {
                            Text(model.isSearchingLyrics ? String(localized: "正在查找歌词…") : model.lyricsSearchMessage)
                                .font(.caption)
                                .foregroundStyle(foreground.opacity(0.65))
                        }
                        Spacer(minLength: 4)
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }

            VStack(spacing: 20) {
                trackIdentityBar
                progressControls
                transportControls
            }
            .padding(.horizontal, 26)
            .padding(.top, 10)
            .padding(.bottom, max(24, bottomSafeInset + 10))
        }
        .contentShape(Rectangle())
        .simultaneousGesture(bodyPanelDrag)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.layout.compact")
    }

    @ViewBuilder
    private func lyricsContent(in size: CGSize) -> some View {
        Group {
            if model.hasLyrics {
                SyncedLyricsView(
                    model: model,
                    foreground: foreground,
                    onTapLyrics: { switchContent(to: .artwork) },
                    onSwipeNext: { Task { await model.next() } }
                )
            } else {
                VStack(spacing: 14) {
                    Spacer()
                    Image(systemName: "text.alignleft")
                        .font(.largeTitle)
                        .foregroundStyle(foreground.opacity(0.5))
                    Text("暂无歌词")
                        .font(.headline)
                    Text("可以查找歌词或导入同名 LRC 文件")
                        .font(.subheadline)
                        .foregroundStyle(foreground.opacity(0.65))
                    lyricsSearch
                        .padding(.top, 4)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("player.lyrics.full")
        .transition(.opacity)
    }

    private var trackIdentityBar: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.state.currentTrack?.title ?? String(localized: "选择一首本地音乐"))
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(model.state.currentTrack?.artist ?? String(localized: "爱乐之城"))
                        .font(.subheadline)
                        .foregroundStyle(foreground.opacity(0.72))
                        .lineLimit(1)
                    if let deadline = model.sleepDeadline {
                        let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
                        Label("\(minutes)m", systemImage: "timer")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(foreground.opacity(0.16), in: Capsule())
                    }
                }
            }
            Spacer(minLength: 0)
            Button { model.toggleCurrentFavorite() } label: {
                Image(systemName: model.state.currentTrack?.isLiked == true ? "heart.fill" : "heart")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(model.state.currentTrack?.isLiked == true ? Color.pink : foreground.opacity(model.canFavoriteCurrentTrack ? 0.92 : 0.35))
                    .frame(width: 40, height: 40)
            }
            .disabled(!model.canFavoriteCurrentTrack)
            .accessibilityLabel(model.state.currentTrack?.isLiked == true ? String(localized: "取消收藏") : String(localized: "收藏"))

            Menu {
                Button {
                    showSkinPicker = true
                } label: {
                    Label("播放器外观（封面 / 黑胶 / iPod）", systemImage: "record.circle")
                }
                Button {
                    showSleepTimer = true
                } label: {
                    Label(model.sleepDeadline == nil ? String(localized: "定时暂停") : sleepTimerLabel, systemImage: "timer")
                }
                if !model.hasLyrics {
                    Button {
                        Task { await model.findLyrics() }
                    } label: {
                        Label("查找歌词", systemImage: "text.magnifyingglass")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(foreground.opacity(0.85))
                    .frame(width: 40, height: 40)
            }
            .accessibilityIdentifier("player.sleepTimer")
        }
        .buttonStyle(.plain)
    }

    private var sleepTimerLabel: String {
        guard let deadline = model.sleepDeadline else { return String(localized: "定时") }
        let minutes = max(1, Int(ceil(deadline.timeIntervalSinceNow / 60)))
        return String(format: NSLocalizedString("%lld 分钟", comment: ""), Int64(minutes))
    }

    private func artwork(side: CGFloat) -> some View {
        let clampedSide = max(140, side)
        return Group {
            switch visualMode {
            case .cover:
                if model.state.currentTrack?.artworkReference != nil {
                    ArtworkView(path: model.state.currentTrack?.artworkReference, cornerRadius: 22)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: .black.opacity(0.38), radius: 26, y: 14)
                } else {
                    RecordVisual(model: model)
                }
            case .vinyl:
                RecordVisual(model: model)
                    .padding(8)
                    .overlay(alignment: .topTrailing) {
                        VinylTonearm(isPlaying: model.state.isPlaying)
                            .frame(width: clampedSide * 0.34, height: clampedSide * 0.57)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
            case .classic:
                ClassicPlayerVisual(model: model, showQueue: { showQueue = true })
            }
        }
        .frame(width: clampedSide, height: clampedSide)
        .contentShape(Rectangle())
        .onTapGesture {
            if visualMode != .classic {
                switchContent(to: .lyrics)
            }
        }
        .highPriorityGesture(panelDrag)
        .accessibilityElement(children: visualMode == .classic ? .contain : .ignore)
        .accessibilityLabel(Text(visualMode.title))
        .accessibilityIdentifier("player.artwork")
    }

    private func widePlayer(layout: AdaptivePlayerLayout) -> some View {
        HStack(spacing: 32) {
            GeometryReader { pane in
                primaryPane(size: pane.size)
            }
            .frame(width: layout.columnWidth)
            secondaryPane
                .frame(width: layout.columnWidth)
        }
        .padding(.horizontal, 32)
        .padding(.top, 12)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.layout.wide")
    }

    @available(iOS 27.1, *)
    private var duoPlayer: some View {
        ArrangementView {
            GeometryReader { pane in primaryPane(size: pane.size) }
        } secondary: {
            secondaryPane
        }
        .arrangementViewStyle(.split)
        .padding(16)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("player.layout.wide")
    }

    private func primaryPane(size: CGSize) -> some View {
        let side = min(max(0, size.width), max(120, size.height - 290), 560)
        return ScrollView {
            VStack(spacing: 18) {
                Spacer(minLength: 0)
                artwork(side: side)
                if model.hasLyrics { lyricSnippet }
                trackIdentityBar
                Spacer(minLength: 10)
                progressControls
                transportControls
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: max(0, size.height))
        }
        .scrollIndicators(.hidden)
    }

    private var secondaryPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(contentMode == .lyrics ? String(localized: "同步歌词") : String(localized: "播放队列"))
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
                                .background(foreground.opacity(entry.offset == model.state.currentIndex ? 0.16 : 0.06), in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(foreground.opacity(0.08), in: RoundedRectangle(cornerRadius: 24))
    }

    private var lyricSnippet: some View {
        let lines = NowPlayingLyricSnippet.lines(from: model.lyricLines, currentIndex: model.currentLyricIndex)
        return Button { switchContent(to: .lyrics) } label: {
            VStack(spacing: 6) {
                if lines.isEmpty {
                    Text(model.hasLyrics ? String(localized: "点击查看完整歌词") : String(localized: "暂无歌词 · 点击查看"))
                        .font(.subheadline)
                        .foregroundStyle(foreground.opacity(0.7))
                } else {
                    ForEach(Array(lines.enumerated()), id: \.element.id) { entry in
                        Text(entry.element.text)
                            .font(entry.offset == 0 ? .subheadline.weight(.semibold) : .caption)
                            .foregroundStyle(foreground.opacity(entry.offset == 0 ? 0.95 : 0.55))
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("查看完整歌词")
        .accessibilityIdentifier("player.lyrics.snippet")
    }

    private var panelDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .updating($panelGestureActive) { _, active, _ in active = true }
            .onChanged { panelDragChanged?($0) }
            .onEnded { panelDragEnded?($0) }
    }

    private var bodyPanelDrag: some Gesture {
        DragGesture(minimumDistance: 18, coordinateSpace: .global)
            .updating($panelGestureActive) { _, active, _ in
                if contentMode == .artwork { active = true }
            }
            .onChanged { value in
                guard contentMode == .artwork else { return }
                panelDragChanged?(value)
            }
            .onEnded { value in
                guard contentMode == .artwork else { return }
                panelDragEnded?(value)
            }
    }

    private func switchContent(to mode: NowPlayingContentMode) {
        if model.reduceMotion {
            contentMode = mode
        } else {
            withAnimation(.easeInOut(duration: 0.25)) { contentMode = mode }
        }
        if mode == .lyrics && !model.hasLyrics && !model.isSearchingLyrics {
            Task { await model.findLyrics() }
        }
    }

    private var lyricsSearch: some View {
        VStack(spacing: 6) {
            Button { Task { await model.findLyrics() } } label: {
                Label(model.isSearchingLyrics ? String(localized: "正在查找歌词…") : String(localized: "查找歌词"), systemImage: "text.magnifyingglass")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(foreground.opacity(0.18), in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(model.isSearchingLyrics)
            .accessibilityIdentifier("player.lyrics.search")
            if !model.lyricsSearchMessage.isEmpty {
                Text(model.lyricsSearchMessage)
                    .font(.caption)
                    .foregroundStyle(foreground.opacity(0.7))
            }
        }
    }

    private var progressControls: some View {
        let isDragging = scrubbingProgress != nil
        let displayedProgress = min(max(scrubbingProgress ?? model.progress, 0), 1)
        let displayedPosition = scrubbingProgress.map { $0 * model.state.duration } ?? model.state.position
        return VStack(spacing: 8) {
            GeometryReader { bar in
                let trackHeight: CGFloat = isDragging ? 8 : 4
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(foreground.opacity(0.24))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(foreground.opacity(isDragging ? 1.0 : 0.90))
                        .frame(width: max(trackHeight, bar.size.width * displayedProgress), height: trackHeight)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = min(max(value.location.x / max(1, bar.size.width), 0), 1)
                            scrubbingProgress = fraction
                        }
                        .onEnded { value in
                            let fraction = min(max(value.location.x / max(1, bar.size.width), 0), 1)
                            scrubbingProgress = nil
                            try? model.seek(fraction: fraction)
                        }
                )
            }
            .frame(height: 24)
            .animation(.easeOut(duration: 0.15), value: isDragging)
            .accessibilityElement()
            .accessibilityLabel("播放进度")
            .accessibilityIdentifier("player.detail.progress")

            HStack {
                Text(format(displayedPosition))
                Spacer()
                Text(format(model.state.duration))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(foreground.opacity(0.68))
        }
    }

    private var transportControls: some View {
        HStack(spacing: 0) {
            Button { model.cycleMode() } label: {
                Image(systemName: modeIcon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(foreground.opacity(0.82))
                    .frame(width: 44, height: 48)
            }
            .accessibilityLabel("播放模式：\(modeLabel)")
            .accessibilityIdentifier("player.detail.mode")
            Spacer(minLength: 0)
            Button { Task { await model.previous() } } label: {
                Image(systemName: "backward.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("上一首")
            .accessibilityIdentifier("player.detail.previous")
            Spacer(minLength: 0)
            Button { Task { await model.togglePlayback() } } label: {
                Image(systemName: model.state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 68, height: 68)
                    .background(PlayerTheme.accent, in: Circle())
                    .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
            }
            .accessibilityLabel(model.state.isPlaying ? String(localized: "暂停") : String(localized: "播放"))
            .accessibilityIdentifier("player.detail.playPause")
            Spacer(minLength: 0)
            Button { Task { await model.next() } } label: {
                Image(systemName: "forward.fill")
                    .font(.title2)
                    .frame(width: 48, height: 48)
            }
            .accessibilityLabel("下一首")
            .accessibilityIdentifier("player.detail.next")
            Spacer(minLength: 0)
            Button { showQueue = true } label: {
                Image(systemName: "list.bullet")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(foreground.opacity(0.82))
                    .frame(width: 44, height: 48)
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
