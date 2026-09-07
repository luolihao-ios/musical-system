import Foundation

struct MiniPlayerVisibility: Sendable {
    private(set) var isVisible = true

    mutating func dismiss() { isVisible = false }
    mutating func show() { isVisible = true }
}

extension Notification.Name {
    static let showMiniPlayer = Notification.Name("LocalMusicPlayer.showMiniPlayer")
}
