import Foundation
import SwiftData

@MainActor
final class MusicStore {
    static let likedPlaylistID = "liked"

    private let context: ModelContext

    init(context: ModelContext) throws {
        self.context = context
        try seedBuiltInRecords()
    }

    func upsert(_ incoming: TrackRecord) throws {
        if let existing = try track(id: incoming.id) {
            let liked = existing.isLiked
            let lastPlayedAt = existing.lastPlayedAt
            existing.title = incoming.title
            existing.artist = incoming.artist
            existing.album = incoming.album
            existing.duration = incoming.duration
            existing.sourceKind = incoming.sourceKind
            existing.sourceReference = incoming.sourceReference
            existing.artworkReference = incoming.artworkReference
            existing.lyricsReference = incoming.lyricsReference
            existing.isAvailable = incoming.isAvailable
            existing.isLiked = liked
            existing.lastPlayedAt = lastPlayedAt
        } else {
            context.insert(incoming)
        }
        try context.save()
    }

    func tracks() throws -> [TrackRecord] {
        let records = try context.fetch(FetchDescriptor<TrackRecord>())
        return records.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func refreshAvailability(fileManager: FileManager = .default) throws {
        let records = try context.fetch(FetchDescriptor<TrackRecord>())
        for record in records {
            switch record.sourceKind {
            case .importedFile:
                record.isAvailable = fileManager.fileExists(
                    atPath: record.sourceReference
                )
            case .mediaLibrary:
                guard let url = URL(string: record.sourceReference) else {
                    record.isAvailable = false
                    continue
                }
                record.isAvailable = !url.isFileURL
                    || fileManager.fileExists(atPath: url.path)
            }
        }
        try context.save()
    }

    func track(id: String) throws -> TrackRecord? {
        let trackID = id
        var descriptor = FetchDescriptor<TrackRecord>(
            predicate: #Predicate { $0.id == trackID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    func setLiked(trackID: String, isLiked: Bool) throws {
        guard let track = try track(id: trackID) else { return }
        track.isLiked = isLiked
        try context.save()
    }

    func playlists() throws -> [PlaylistRecord] {
        let records = try context.fetch(FetchDescriptor<PlaylistRecord>())
        return records.sorted {
            if $0.isBuiltIn != $1.isBuiltIn { return $0.isBuiltIn }
            return $0.createdAt < $1.createdAt
        }
    }

    @discardableResult
    func createPlaylist(name: String) throws -> PlaylistRecord {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw MusicStoreError.emptyPlaylistName
        }
        let playlist = PlaylistRecord(name: trimmed)
        context.insert(playlist)
        try context.save()
        return playlist
    }

    @discardableResult
    func renamePlaylist(id: String, name: String) throws -> Bool {
        guard let playlist = try playlist(id: id), !playlist.isBuiltIn else {
            return false
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        playlist.name = trimmed
        try context.save()
        return true
    }

    @discardableResult
    func deletePlaylist(id: String) throws -> Bool {
        guard let playlist = try playlist(id: id), !playlist.isBuiltIn else {
            return false
        }
        let playlistID = id
        let entries = try context.fetch(
            FetchDescriptor<PlaylistEntryRecord>(
                predicate: #Predicate { $0.playlistID == playlistID }
            )
        )
        entries.forEach { context.delete($0) }
        context.delete(playlist)
        try context.save()
        return true
    }

    func add(
        trackID: String,
        to playlistID: String,
        position: Int? = nil
    ) throws {
        guard try track(id: trackID) != nil,
              try playlist(id: playlistID) != nil else {
            throw MusicStoreError.missingRecord
        }
        let entryID = "\(playlistID)|\(trackID)"
        var descriptor = FetchDescriptor<PlaylistEntryRecord>(
            predicate: #Predicate { $0.id == entryID }
        )
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        let resolvedPosition = position ?? (try nextPosition(playlistID: playlistID))
        if let existing {
            existing.position = resolvedPosition
        } else {
            context.insert(
                PlaylistEntryRecord(
                    playlistID: playlistID,
                    trackID: trackID,
                    position: resolvedPosition
                )
            )
        }
        try context.save()
    }

    func remove(trackID: String, from playlistID: String) throws {
        let entryID = "\(playlistID)|\(trackID)"
        let entries = try context.fetch(
            FetchDescriptor<PlaylistEntryRecord>(
                predicate: #Predicate { $0.id == entryID }
            )
        )
        entries.forEach { context.delete($0) }
        try context.save()
    }

    func moveTracks(
        in playlistID: String,
        fromOffsets: IndexSet,
        toOffset: Int
    ) throws {
        guard playlistID != Self.likedPlaylistID else { return }
        let requestedID = playlistID
        let entries = try context.fetch(
            FetchDescriptor<PlaylistEntryRecord>(
                predicate: #Predicate { $0.playlistID == requestedID },
                sortBy: [SortDescriptor(\.position)]
            )
        )
        var reordered = entries
        let moving = fromOffsets.sorted().map { reordered[$0] }
        for index in fromOffsets.sorted(by: >) {
            reordered.remove(at: index)
        }
        let removedBeforeTarget = fromOffsets.filter { $0 < toOffset }.count
        let insertionIndex = min(
            max(toOffset - removedBeforeTarget, 0),
            reordered.count
        )
        reordered.insert(contentsOf: moving, at: insertionIndex)
        for (position, entry) in reordered.enumerated() {
            entry.position = position
        }
        try context.save()
    }

    func playlistTracks(playlistID: String) throws -> [TrackRecord] {
        if playlistID == Self.likedPlaylistID {
            return try tracks().filter(\.isLiked)
        }
        let requestedID = playlistID
        let entries = try context.fetch(
            FetchDescriptor<PlaylistEntryRecord>(
                predicate: #Predicate { $0.playlistID == requestedID },
                sortBy: [SortDescriptor(\.position)]
            )
        )
        return try entries.compactMap { try track(id: $0.trackID) }
    }

    func recordPlay(trackID: String, at date: Date = .now) throws {
        guard let track = try track(id: trackID) else { return }
        track.lastPlayedAt = date
        try context.save()
    }

    func loadPlaybackPreferences() throws -> PlaybackPreferences {
        let records = try context.fetch(
            FetchDescriptor<PlaybackPreferencesRecord>()
        )
        guard let record = records.first else { return PlaybackPreferences() }
        return PlaybackPreferences(
            volume: min(max(record.volume, 0), 1),
            mode: PlaybackMode(rawValue: record.modeRaw) ?? .repeatAll,
            lastTrackID: record.lastTrackID,
            lastPosition: max(record.lastPosition, 0)
        )
    }

    func savePlaybackPreferences(_ preferences: PlaybackPreferences) throws {
        let records = try context.fetch(
            FetchDescriptor<PlaybackPreferencesRecord>()
        )
        let record = records.first ?? PlaybackPreferencesRecord()
        if records.isEmpty { context.insert(record) }
        record.volume = min(max(preferences.volume, 0), 1)
        record.modeRaw = preferences.mode.rawValue
        record.lastTrackID = preferences.lastTrackID
        record.lastPosition = max(preferences.lastPosition, 0)
        try context.save()
    }

    private func playlist(id: String) throws -> PlaylistRecord? {
        let playlistID = id
        var descriptor = FetchDescriptor<PlaylistRecord>(
            predicate: #Predicate { $0.id == playlistID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    private func nextPosition(playlistID: String) throws -> Int {
        let requestedID = playlistID
        let entries = try context.fetch(
            FetchDescriptor<PlaylistEntryRecord>(
                predicate: #Predicate { $0.playlistID == requestedID }
            )
        )
        return (entries.map(\.position).max() ?? -1) + 1
    }

    private func seedBuiltInRecords() throws {
        if try playlist(id: Self.likedPlaylistID) == nil {
            context.insert(
                PlaylistRecord(
                    id: Self.likedPlaylistID,
                    name: "我喜欢",
                    isBuiltIn: true,
                    createdAt: .distantPast
                )
            )
        }
        if try context.fetch(
            FetchDescriptor<PlaybackPreferencesRecord>()
        ).isEmpty {
            context.insert(PlaybackPreferencesRecord())
        }
        try context.save()
    }
}

enum MusicStoreError: Error {
    case emptyPlaylistName
    case missingRecord
}
