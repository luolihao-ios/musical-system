import Foundation

enum MiniPlayerDragDecision: Equatable {
    case compact
    case expand
    case dismiss
}

enum MiniPlayerDragState {
    static func progress(
        from start: CGFloat,
        translation: CGFloat,
        availableDistance: CGFloat
    ) -> CGFloat {
        guard availableDistance > 0 else { return start }
        return min(
            max(start - translation / availableDistance, 0),
            1
        )
    }

    static func progress(
        translation: CGFloat,
        availableDistance: CGFloat
    ) -> CGFloat {
        progress(
            from: 0,
            translation: translation,
            availableDistance: availableDistance
        )
    }

    static func settle(
        progress: CGFloat,
        translation: CGFloat,
        availableDistance: CGFloat = 600
    ) -> MiniPlayerDragDecision {
        if translation > max(availableDistance / 3, 1) {
            return .dismiss
        }
        if translation <= -80 || progress >= 0.28 {
            return .expand
        }
        return .compact
    }
}
