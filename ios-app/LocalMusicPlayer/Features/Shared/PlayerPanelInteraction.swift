import Foundation

// 手指坐标来自固定的全局坐标系；高度只减去一次绝对位移。
struct PlayerPanelInteraction: Equatable {
    enum Phase: String { case compact, expanded, hidden }
    private(set) var phase: Phase = .compact
    private(set) var startHeight: CGFloat?
    private(set) var dragHeight: CGFloat?
    private(set) var expansionCount = 0
    private(set) var acceptsGesture = true

    var isDragging: Bool { startHeight != nil }

    func height(compact: CGFloat, expanded: CGFloat) -> CGFloat {
        if let dragHeight { return dragHeight }
        switch phase {
        case .compact: return compact
        case .expanded: return expanded
        case .hidden: return 0
        }
    }

    mutating func drag(translation: CGFloat, compact: CGFloat, expanded: CGFloat) {
        guard acceptsGesture, phase == .expanded else { return }
        if startHeight == nil { startHeight = height(compact: compact, expanded: expanded) }
        dragHeight = min(expanded, max(compact, (startHeight ?? expanded) - translation))
    }

    mutating func release(compact: CGFloat, expanded: CGFloat) {
        guard let startHeight, let dragHeight else { return }
        let next: Phase
        if startHeight - dragHeight > startHeight / 3 {
            next = .compact
        } else if phase == .expanded || dragHeight - compact >= min(80, (expanded - compact) * 0.28) {
            next = .expanded
        } else {
            next = .compact
        }
        self.startHeight = nil
        self.dragHeight = nil
        setPhase(next)
    }

    mutating func expand() {
        guard !isDragging, phase == .compact else { return }
        setPhase(.expanded)
    }

    mutating func close() {
        startHeight = nil
        dragHeight = nil
        setPhase(.compact)
    }

    // 旋转、分屏或折叠改变坐标空间时，旧手势高度不能继续覆盖新窗口。
    mutating func cancelDragForResize() {
        if isDragging { acceptsGesture = false }
        startHeight = nil
        dragHeight = nil
    }

    mutating func finishGestureSession() {
        acceptsGesture = true
        startHeight = nil
        dragHeight = nil
    }

    private mutating func setPhase(_ next: Phase) {
        if phase != .expanded && next == .expanded { expansionCount += 1 }
        phase = next
    }
}
