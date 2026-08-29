import SwiftUI

struct SyncedLyricsView: View {
    @Bindable var model: NowPlayingModel
    @State private var isUserBrowsing = false
    @State private var resumeFollowingTask: Task<Void, Never>?
    @State private var selectedLyricID: LyricLine.ID?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(
                        Array(model.lyricLines.enumerated()),
                        id: \.element.id
                    ) { entry in
                        Button {
                            selectedLyricID = entry.element.id
                            try? model.seek(to: entry.element)
                            isUserBrowsing = false
                            resumeFollowingTask?.cancel()
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(entry.offset, anchor: .center)
                            }
                        } label: {
                            Text(
                                entry.element.text.isEmpty
                                    ? " "
                                    : entry.element.text
                            )
                            .font(
                                entry.offset == model.currentLyricIndex
                                    ? .title3.weight(.semibold)
                                    : .body
                            )
                            .foregroundStyle(
                                entry.offset == model.currentLyricIndex
                                    ? PlayerTheme.accent
                                    : selectedLyricID == entry.element.id
                                        ? Color.primary
                                        : Color.secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .id(entry.offset)
                        .accessibilityAddTraits(
                            entry.offset == model.currentLyricIndex
                                ? .isSelected
                                : []
                        )
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
                                withAnimation(.easeInOut(duration: 0.35)) {
                                    proxy.scrollTo(index, anchor: .center)
                                }
                            }
                        }
                    }
            )
            .onChange(of: model.currentLyricIndex) { _, index in
                guard let index, !isUserBrowsing else { return }
                selectedLyricID = model.lyricLines.indices.contains(index)
                    ? model.lyricLines[index].id
                    : nil
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
            .onChange(of: model.lyricTrackID) { _, _ in
                resumeFollowingTask?.cancel()
                isUserBrowsing = false
                selectedLyricID = nil
            }
            .onDisappear {
                resumeFollowingTask?.cancel()
            }
        }
    }
}
