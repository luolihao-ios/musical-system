import CoreGraphics
import SwiftUI

// 根据窗口可用空间决定布局，不能用“这是 iPhone”推断始终是窄屏。
struct AdaptivePlayerLayout: Equatable {
    let isWide: Bool
    let columnWidth: CGFloat
    let artworkSide: CGFloat

    static func resolve(size: CGSize) -> Self {
        let width = size.width.isFinite ? max(0, size.width) : 0
        let height = size.height.isFinite ? max(0, size.height) : 0
        let wide = width >= 720 && height >= 420
        let column = wide ? min(720, max(0, (width - 96) / 2)) : max(0, width - 48)
        let artwork = height > 0 ? min(column, max(120, height - 330), wide ? 640 : 390) : 0
        return Self(isWide: wide, columnWidth: column, artworkSide: artwork)
    }

    static func menuClearance(window: CGRect, menu: CGRect?, bottomInset: CGFloat) -> CGFloat {
        let safeBottom = bottomInset.isFinite ? max(0, bottomInset) : 0
        let fallback = safeBottom + 8
        guard let menu, !menu.isEmpty, !window.isEmpty,
              menu.height < window.height * 0.4,
              menu.width > menu.height * 2,
              menu.maxY >= window.maxY - max(80, safeBottom + 32) else { return fallback }
        return max(fallback, window.maxY - menu.minY + 8)
    }
}

struct AdaptiveTabNavigation: ViewModifier {
    @ViewBuilder
    func body(content: Content) -> some View {
        // 保留系统默认页签，不主动开启侧栏；全局小播放器不能覆盖展开侧栏。
        content
    }
}
