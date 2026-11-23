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
                        LazyVStack(spacing: 20) {
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
                                            ? .body.weight(.semibold)
                                            : .body
                                )
                                .foregroundStyle(
                                    foreground.opacity(
                                        isPlayingLine ? 1.0 : (isScrubTarget ? 0.88 : 0.42)
                                    )
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background {
                                    if isScrubTarget {
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .fill(foreground.opacity(0.08))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                    .stroke(foreground.opacity(0.24), lineWidth: 1)
                                            }
                                    }
                                }
                                .background {
                                    GeometryReader { rowGeo in
                                        Color.clear.preference(
                                            key: LyricRowMidYKey.self,
                                            value: [entry.offset: rowGeo.frame(in: .named("lyrics.scroll")).midY]
                                        )
                                    }
                                }
                                .contentShape(Rectangle())
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
        HStack(spacing: 8) {
            Text(formatTimestamp(targetLine.timestamp))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(foreground.opacity(0.16), in: Capsule())

            Rectangle()
                .fill(foreground.opacity(0.22))
                .frame(height: 1)

            Button {
                resumeFollowingTask?.cancel()
                try? model.seek(to: targetLine)
                withAnimation(.easeInOut(duration: 0.2)) {
                    isUserBrowsing = false
                }
                scroll(to: targetIndex, proxy: proxy)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.bold))
                }
                .foregroundStyle(Color(red: 0.08, green: 0.10, blue: 0.14))
                .frame(width: 34, height: 28)
                .background(foreground, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("定位播放到此句歌词")
            .accessibilityIdentifier("player.lyrics.scrubPlay")
        }
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
