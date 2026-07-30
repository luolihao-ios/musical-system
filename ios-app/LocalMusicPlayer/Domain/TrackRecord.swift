import Foundation
import SwiftData

enum TrackSourceKind: String, Codable, Sendable {
    case importedFile
    case mediaLibrary
}

@Model
final class TrackRecord {
    @Attribute(.unique) var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var sourceKindRaw: String
    var sourceReference: String
    var artworkReference: String?
    var lyricsReference: String?
    var isLiked: Bool
    var isAvailable: Bool
    var lastPlayedAt: Date?

    var sourceKind: TrackSourceKind {
        get { TrackSourceKind(rawValue: sourceKindRaw) ?? .importedFile }
        set { sourceKindRaw = newValue.rawValue }
    }

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        sourceKind: TrackSourceKind,
        sourceReference: String,
        artworkReference: String? = nil,
        lyricsReference: String? = nil,
        isLiked: Bool = false,
        isAvailable: Bool = true,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.sourceKindRaw = sourceKind.rawValue
        self.sourceReference = sourceReference
        self.artworkReference = artworkReference
        self.lyricsReference = lyricsReference
        self.isLiked = isLiked
        self.isAvailable = isAvailable
        self.lastPlayedAt = lastPlayedAt
    }
}

struct TrackSnapshot: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let sourceKind: TrackSourceKind
    let sourceReference: String
    let artworkReference: String?
    let lyricsReference: String?
    let isLiked: Bool
    let isAvailable: Bool
    let lastPlayedAt: Date?

    init(
        id: String,
        title: String,
        artist: String,
        album: String,
        duration: Double,
        sourceKind: TrackSourceKind,
        sourceReference: String,
        artworkReference: String? = nil,
        lyricsReference: String? = nil,
        isLiked: Bool = false,
        isAvailable: Bool = true,
        lastPlayedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.sourceKind = sourceKind
        self.sourceReference = sourceReference
        self.artworkReference = artworkReference
        self.lyricsReference = lyricsReference
        self.isLiked = isLiked
        self.isAvailable = isAvailable
        self.lastPlayedAt = lastPlayedAt
    }

    @MainActor
    init(_ record: TrackRecord) {
        id = record.id
        title = record.title
        artist = record.artist
        album = record.album
        duration = record.duration
        sourceKind = record.sourceKind
        sourceReference = record.sourceReference
        artworkReference = record.artworkReference
        lyricsReference = record.lyricsReference
        isLiked = record.isLiked
        isAvailable = record.isAvailable
        lastPlayedAt = record.lastPlayedAt
    }
}
