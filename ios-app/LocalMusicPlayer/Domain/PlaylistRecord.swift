import Foundation
import SwiftData

@Model
final class PlaylistRecord {
    @Attribute(.unique) var id: String
    var name: String
    var isBuiltIn: Bool
    var createdAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        isBuiltIn: Bool = false,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
    }
}

@Model
final class PlaylistEntryRecord {
    @Attribute(.unique) var id: String
    var playlistID: String
    var trackID: String
    var position: Int

    init(playlistID: String, trackID: String, position: Int) {
        id = "\(playlistID)|\(trackID)"
        self.playlistID = playlistID
        self.trackID = trackID
        self.position = position
    }
}
