import Foundation

@MainActor
protocol AudioEngine: AnyObject {
    var onEnded: (() async -> Void)? { get set }
    var onPositionChanged: ((TimeInterval) -> Void)? { get set }
    var duration: TimeInterval { get }
    var position: TimeInterval { get }
    var volume: Float { get set }
    var isPlaying: Bool { get }

    func load(url: URL) async throws
    func play()
    func pause()
    func seek(to position: TimeInterval)
}
