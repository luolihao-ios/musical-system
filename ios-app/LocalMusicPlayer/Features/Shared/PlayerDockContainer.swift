import SwiftUI
import UIKit

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
                        .background(PlayerWindowMetricsProbe().allowsHitTesting(false))
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

private struct PlayerWindowMetricsProbe: UIViewRepresentable {
    func makeUIView(context: Context) -> MetricsView { MetricsView() }
    func updateUIView(_ uiView: MetricsView, context: Context) {}

    final class MetricsView: UIView {
        private var previousBounds = CGRect.zero
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window, window.bounds != previousBounds else { return }
            previousBounds = window.bounds
            PlayerInteractionDiagnostics.log("window bounds=\(window.bounds) safeArea=\(window.safeAreaInsets)")
        }
    }
}
