import SwiftUI

struct SyncedLyricsView: View {
    @Bindable var model: NowPlayingModel
    var foreground: Color = .primary
    @State private var isUserBrowsing = false
    @State private var resumeFollowingTask: Task<Void, Never>?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(
                        Array(model.lyricLines.enumerated()),
                        id: \.element.id
                    ) { entry in
                        let isActive = entry.offset == model.currentLyricIndex
                        Text(
                            entry.element.text.isEmpty
                                ? " "
                                : entry.element.text
                        )
                        .font(
                            isActive
                                ? .title3.weight(.bold)
                                : .body
                        )
                        .foregroundStyle(foreground.opacity(isActive ? 1.0 : 0.42))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                        .id(entry.offset)
                        .animation(.easeInOut(duration: 0.2), value: model.currentLyricIndex)
                        .accessibilityIdentifier("player.lyrics.line.\(entry.offset)")
                        .accessibilityAddTraits(isActive ? .isSelected : [])
                    }
                }
                .padding(.vertical, 100)
            }
            .scrollIndicators(.hidden)
            .simultaneousGesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { _ in
                        isUserBrowsing = true
                        resumeFollowingTask?.cancel()
                    }
                    .onEnded { _ in
                        resumeFollowingTask?.cancel()
                        resumeFollowingTask = Task { @MainActor in
                            try? await Task.sleep(for: .seconds(2))
                            guard !Task.isCancelled else { return }
                            isUserBrowsing = false
                            if let index = model.currentLyricIndex {
                                scroll(to: index, proxy: proxy)
                            }
                        }
                    }
            )
            .onChange(of: model.currentLyricIndex) { _, index in
                guard let index, !isUserBrowsing else { return }
                scroll(to: index, proxy: proxy)
            }
            .onChange(of: model.lyricTrackID) { _, _ in
                resumeFollowingTask?.cancel()
                isUserBrowsing = false
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
        }
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
