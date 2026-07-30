import SwiftUI

struct SyncedLyricsView: View {
    @Bindable var model: NowPlayingModel

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(
                        Array(model.lyricLines.enumerated()),
                        id: \.element.id
                    ) { entry in
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
                                    : Color.secondary
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            .onChange(of: model.currentLyricIndex) { _, index in
                guard let index else { return }
                withAnimation(.easeInOut(duration: 0.35)) {
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
    }
}
