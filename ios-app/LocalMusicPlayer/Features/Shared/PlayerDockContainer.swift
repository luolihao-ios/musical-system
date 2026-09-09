import SwiftUI

// 安全区由外层测量；允许伸入底部的必须是可扩展的容器，而非固定高度的播放器。
struct PlayerDockContainer<Content: View>: View {
    let model: NowPlayingModel
    let isVisible: Bool
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { safeArea in
            content()
                .overlay {
                    GeometryReader { dock in
                        ZStack(alignment: .bottom) {
                            if isVisible {
                                MiniPlayerView(
                                    model: model,
                                    openNowPlaying: {},
                                    dismiss: dismiss,
                                    maximumHeight: dock.size.height,
                                    bottomInset: safeArea.safeAreaInsets.bottom
                                )
                            }
                        }
                        .frame(width: dock.size.width, height: dock.size.height, alignment: .bottom)
                        .onAppear {
                            PlayerInteractionDiagnostics.beginSession()
                            PlayerInteractionDiagnostics.log("dock frame=\(dock.frame(in: .global)) bottomInset=\(safeArea.safeAreaInsets.bottom)")
                        }
                    }
                    .ignoresSafeArea(.container, edges: .bottom)
                }
        }
    }
}
