import Foundation

struct MiniPlayerVisibility: Sendable {
    private(set) var isVisible = true

    mutating func dismiss() { isVisible = false }
    mutating func show() { isVisible = true }
}
