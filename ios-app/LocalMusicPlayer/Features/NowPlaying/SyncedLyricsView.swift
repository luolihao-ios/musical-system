import SwiftUI

private struct LyricRowMidYKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct SyncedLyricsView: View {
    @Bindable var model: NowPlayingModel
    var foreground: Color = .primary
    var onTapLyrics: (() -> Void)? = nil
    @State private var isUserBrowsing = false
    @State private var scrubbedIndex: Int?
    @State private var resumeFollowingTask: Task<Void, Never>?

    private var activePreviewIndex: Int? {
        if isUserBrowsing {
            return scrubbedIndex ?? model.currentLyricIndex ?? (model.lyricLines.isEmpty ? nil : 0)
        }
        return nil
    }

    var body: some View {
        GeometryReader { viewport in
            let centerY = viewport.size.height / 2
            ScrollViewReader { proxy in
                ZStack {
                    ScrollView {
                        LazyVStack(alignment: .center, spacing: 20) {
                            ForEach(
                                Array(model.lyricLines.enumerated()),
                                id: \.element.id
                            ) { entry in
                                let isPlayingLine = entry.offset == model.currentLyricIndex
                                let isScrubTarget = isUserBrowsing && entry.offset == activePreviewIndex
                                Text(
                                    entry.element.text.isEmpty
                                        ? " "
                                        : entry.element.text
                                )
                                .font(
                                    isPlayingLine
                                        ? .title3.weight(.bold)
                                        : isScrubTarget
                                            ? .title3.weight(.semibold)
                                            : .body
                                )
                                .foregroundStyle(
                                    foreground.opacity(
                                        isPlayingLine ? 1.0 : (isScrubTarget ? 0.95 : 0.40)
                                    )
                                )
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 6)
                                .background {
                                    GeometryReader { rowGeo in
                                        Color.clear.preference(
                                            key: LyricRowMidYKey.self,
                                            value: [entry.offset: rowGeo.frame(in: .named("lyrics.scroll")).midY]
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isUserBrowsing {
                                        resumeFollowingTask?.cancel()
                                        withAnimation(.easeInOut(duration: 0.18)) {
                                            isUserBrowsing = false
                                        }
                                    }
                                    onTapLyrics?()
                                }
                                .id(entry.offset)
                                .animation(.easeInOut(duration: 0.18), value: model.currentLyricIndex)
                                .accessibilityIdentifier("player.lyrics.line.\(entry.offset)")
                                .accessibilityAddTraits(isPlayingLine ? .isSelected : [])
                            }
                        }
                        .padding(.vertical, max(100, centerY - 24))
                    }
                    .coordinateSpace(name: "lyrics.scroll")
                    .scrollIndicators(.hidden)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if !isUserBrowsing {
                            onTapLyrics?()
                        }
                    }
                    .onPreferenceChange(LyricRowMidYKey.self) { positions in
                        guard isUserBrowsing, !positions.isEmpty else { return }
                        if let nearest = positions.min(by: { abs($0.value - centerY) < abs($1.value - centerY) })?.key,
                           nearest != scrubbedIndex {
                            scrubbedIndex = nearest
                        }
                    }
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4)
                            .onChanged { _ in
                                if !isUserBrowsing {
                                    if scrubbedIndex == nil {
                                        scrubbedIndex = model.currentLyricIndex ?? 0
                                    }
                                    withAnimation(.easeOut(duration: 0.15)) {
                                        isUserBrowsing = true
                                    }
                                }
                                resumeFollowingTask?.cancel()
                            }
                            .onEnded { _ in
                                scheduleAutoReturn(proxy: proxy)
                            }
                    )
                    .onChange(of: model.currentLyricIndex) { _, index in
                        guard let index, !isUserBrowsing else { return }
                        scroll(to: index, proxy: proxy)
                    }
                    .onChange(of: model.lyricTrackID) { _, _ in
                        resumeFollowingTask?.cancel()
                        isUserBrowsing = false
                        scrubbedIndex = nil
                        if let index = model.currentLyricIndex {
                            scroll(to: index, proxy: proxy)
                        }
                    }
                    .onAppear {
                        if let index = model.currentLyricIndex {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                    .onDisappear {
                        resumeFollowingTask?.cancel()
                    }

                    if isUserBrowsing,
                       let targetIndex = activePreviewIndex,
                       model.lyricLines.indices.contains(targetIndex) {
                        let targetLine = model.lyricLines[targetIndex]
                        scrubLocatorOverlay(targetLine: targetLine, targetIndex: targetIndex, proxy: proxy)
                            .transition(.opacity)
                    }
                }
            }
        }
    }

    private func scrubLocatorOverlay(
        targetLine: LyricLine,
        targetIndex: Int,
        proxy: ScrollViewProxy
    ) -> some View {
        HStack(spacing: 10) {
            Button {
                resumeFollowingTask?.cancel()
                try? model.seek(to: targetLine)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isUserBrowsing = false
                }
                scroll(to: targetIndex, proxy: proxy)
            } label: {
                Image(systemName: "play.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(foreground)
                    .frame(width: 28, height: 28)
                    .background(foreground.opacity(0.18), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("定位播放到此句歌词")
            .accessibilityIdentifier("player.lyrics.scrubPlay")

            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            foreground.opacity(0.32),
                            foreground.opacity(0.08),
                            foreground.opacity(0.32)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1)

            Text(formatTimestamp(targetLine.timestamp))
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundStyle(foreground.opacity(0.75))
        }
        .padding(.vertical, 4)
    }

    private func scheduleAutoReturn(proxy: ScrollViewProxy) {
        resumeFollowingTask?.cancel()
        resumeFollowingTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.22)) {
                isUserBrowsing = false
            }
            if let index = model.currentLyricIndex {
                scroll(to: index, proxy: proxy)
            }
        }
    }

    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite else { return "00:00" }
        let total = max(Int(seconds), 0)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func scroll(to index: Int, proxy: ScrollViewProxy) {
        if model.reduceMotion {
            proxy.scrollTo(index, anchor: .center)
        } else {
            withAnimation(.easeInOut(duration: 0.35)) {
                proxy.scrollTo(index, anchor: .center)
            }
        }
    }
}
