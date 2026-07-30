import Foundation
import SwiftData

enum PlaybackMode: String, Codable, CaseIterable, Sendable {
    case repeatAll
    case repeatOne
    case shuffle
}

struct PlaybackPreferences: Equatable, Sendable {
    var volume: Double = 1
    var mode: PlaybackMode = .repeatAll
    var lastTrackID: String?
    var lastPosition: Double = 0
}

@Model
final class PlaybackPreferencesRecord {
    @Attribute(.unique) var id: String
    var volume: Double
    var modeRaw: String
    var lastTrackID: String?
    var lastPosition: Double

    init(
        id: String = "playback",
        volume: Double = 1,
        modeRaw: String = PlaybackMode.repeatAll.rawValue,
        lastTrackID: String? = nil,
        lastPosition: Double = 0
    ) {
        self.id = id
        self.volume = volume
        self.modeRaw = modeRaw
        self.lastTrackID = lastTrackID
        self.lastPosition = lastPosition
    }
}
