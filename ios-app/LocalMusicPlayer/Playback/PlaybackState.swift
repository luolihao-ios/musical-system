import Foundation

struct PlaybackState: Equatable, Sendable {
    var queue: [TrackSnapshot] = []
    var currentIndex: Int?
    var isPlaying = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Double = 1
    var mode: PlaybackMode = .repeatAll

    var currentTrack: TrackSnapshot? {
        guard let currentIndex,
              queue.indices.contains(currentIndex) else {
            return nil
        }
        return queue[currentIndex]
    }
}
