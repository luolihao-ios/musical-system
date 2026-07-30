import SwiftUI

struct SyncedLyricsView: View {
    @Bindable var model: NowPlayingModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(Array(model.lyricLines.enumerated()), id: \.element.id) {
                        index,
                        line in
                        Text(line.text.isEmpty ? " " : line.text)
                            .font(
                                index == model.currentLyricIndex
                                    ? .title3.weight(.semibold)
                                    : .body
                            )
                            .foregroundStyle(
                                index == model.currentLyricIndex
                                    ? PlayerTheme.accent
                                    : Color.secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                            .accessibilityAddTraits(
                                index == model.currentLyricIndex
                                    ? .isSelected
                                    : []
                            )
                    }
                }
                .padding(.vertical, 100)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.currentLyricIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}
