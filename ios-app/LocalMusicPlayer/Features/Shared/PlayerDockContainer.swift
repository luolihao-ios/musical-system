import SwiftUI
import UIKit

// 安全区由外层测量；允许伸入底部的必须是可扩展的容器，而非固定高度的播放器。
struct PlayerDockContainer<Content: View>: View {
    let model: NowPlayingModel
    let isVisible: Bool
    let dismiss: () -> Void
    @ViewBuilder let content: () -> Content
    @State private var menuClearance: CGFloat = 90

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
                                    bottomInset: safeArea.safeAreaInsets.bottom,
                                    menuClearance: menuClearance
                                )
                            }
                        }
                        .frame(width: dock.size.width, height: dock.size.height, alignment: .bottom)
                        .background(PlayerWindowMetricsProbe(clearance: $menuClearance).allowsHitTesting(false))
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
    @Binding var clearance: CGFloat
    func makeUIView(context: Context) -> MetricsView { MetricsView() }
    func updateUIView(_ uiView: MetricsView, context: Context) {
        uiView.report = { value in if abs(clearance - value) > 1 { clearance = value } }
        uiView.setNeedsLayout()
    }

    final class MetricsView: UIView {
        private var previousBounds = CGRect.zero
        var report: ((CGFloat) -> Void)?
        private func tabBar(in view: UIView) -> UITabBar? {
            if let bar = view as? UITabBar, !bar.isHidden { return bar }
            return view.subviews.lazy.compactMap { self.tabBar(in: $0) }.first
        }
        override func layoutSubviews() {
            super.layoutSubviews()
            guard let window else { return }
            let menu = tabBar(in: window).map { $0.convert($0.bounds, to: window) }
            let clearance = AdaptivePlayerLayout.menuClearance(
                window: window.bounds, menu: menu, bottomInset: window.safeAreaInsets.bottom
            )
            DispatchQueue.main.async { [weak self] in self?.report?(clearance) }
            guard window.bounds != previousBounds else { return }
            previousBounds = window.bounds
            PlayerInteractionDiagnostics.log("window bounds=\(window.bounds) safeArea=\(window.safeAreaInsets)")
        }
    }
}
