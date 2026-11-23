import Foundation
import Observation

@MainActor
@Observable
final class OnlineHistoryStore {
    static let shared = OnlineHistoryStore()

    private struct StoragePayload: Codable {
        var favorites: [TrackSnapshot]
        var recentlyPlayed: [TrackSnapshot]
    }

    private(set) var favorites: [TrackSnapshot] = []
    private(set) var recentlyPlayed: [TrackSnapshot] = []

    private let fileURL: URL
    private let maxRecentCount = 50

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = support.appendingPathComponent("AiYueOnlineHistory.json")
        }
        load()
    }

    func isFavorite(_ trackID: String) -> Bool {
        favorites.contains { $0.id == trackID }
    }

    @discardableResult
    func toggleFavorite(_ track: TrackSnapshot, fallbackArtworkURL: String? = nil) -> Bool {
        if let index = favorites.firstIndex(where: { $0.id == track.id }) {
            favorites.remove(at: index)
            if let recentIndex = recentlyPlayed.firstIndex(where: { $0.id == track.id }) {
                let item = recentlyPlayed[recentIndex]
                recentlyPlayed[recentIndex] = TrackSnapshot(
                    id: item.id, title: item.title, artist: item.artist, album: item.album,
                    duration: item.duration, sourceKind: item.sourceKind, sourceReference: item.sourceReference,
                    artworkReference: item.artworkReference, lyricsReference: item.lyricsReference,
                    isLiked: false, isAvailable: true, lastPlayedAt: item.lastPlayedAt
                )
            }
            save()
            return false
        } else {
            let existingRecentArtwork = recentlyPlayed.first(where: { $0.id == track.id })?.artworkReference
            let saved = TrackSnapshot(
                id: track.id,
                title: track.title,
                artist: track.artist,
                album: track.album,
                duration: track.duration,
                sourceKind: .onlinePreview,
                sourceReference: track.sourceReference,
                artworkReference: track.artworkReference ?? fallbackArtworkURL ?? existingRecentArtwork,
                lyricsReference: track.lyricsReference,
                isLiked: true,
                isAvailable: true,
                lastPlayedAt: track.lastPlayedAt ?? .now
            )
            favorites.insert(saved, at: 0)
            save()
            return true
        }
    }

    func removeFavorite(_ trackID: String) {
        favorites.removeAll { $0.id == trackID }
        save()
    }

    func recordPlayed(_ track: TrackSnapshot, fallbackArtworkURL: String? = nil, at date: Date = .now) {
        guard track.sourceKind == .onlinePreview else { return }
        let existingArt = recentlyPlayed.first(where: { $0.id == track.id })?.artworkReference
            ?? favorites.first(where: { $0.id == track.id })?.artworkReference
        let resolvedArtwork = track.artworkReference ?? fallbackArtworkURL ?? existingArt
        let liked = isFavorite(track.id)
        let entry = TrackSnapshot(
            id: track.id,
            title: track.title,
            artist: track.artist,
            album: track.album,
            duration: track.duration,
            sourceKind: .onlinePreview,
            sourceReference: track.sourceReference,
            artworkReference: resolvedArtwork,
            lyricsReference: track.lyricsReference,
            isLiked: liked,
            isAvailable: true,
            lastPlayedAt: date
        )
        recentlyPlayed.removeAll { $0.id == track.id }
        recentlyPlayed.insert(entry, at: 0)
        if recentlyPlayed.count > maxRecentCount {
            recentlyPlayed = Array(recentlyPlayed.prefix(maxRecentCount))
        }
        if let favIndex = favorites.firstIndex(where: { $0.id == track.id }) {
            let existing = favorites[favIndex]
            favorites[favIndex] = TrackSnapshot(
                id: existing.id,
                title: existing.title,
                artist: existing.artist,
                album: existing.album,
                duration: track.duration > 0 ? track.duration : existing.duration,
                sourceKind: .onlinePreview,
                sourceReference: track.sourceReference,
                artworkReference: resolvedArtwork,
                lyricsReference: track.lyricsReference ?? existing.lyricsReference,
                isLiked: true,
                isAvailable: true,
                lastPlayedAt: date
            )
        }
        save()
    }

    func updateSourceReference(trackID: String, sourceReference: String, artworkReference: String?) {
        var changed = false
        if let index = favorites.firstIndex(where: { $0.id == trackID }) {
            let item = favorites[index]
            favorites[index] = TrackSnapshot(
                id: item.id, title: item.title, artist: item.artist, album: item.album,
                duration: item.duration, sourceKind: item.sourceKind, sourceReference: sourceReference,
                artworkReference: artworkReference ?? item.artworkReference,
                lyricsReference: item.lyricsReference, isLiked: true, isAvailable: true, lastPlayedAt: item.lastPlayedAt
            )
            changed = true
        }
        if let index = recentlyPlayed.firstIndex(where: { $0.id == trackID }) {
            let item = recentlyPlayed[index]
            recentlyPlayed[index] = TrackSnapshot(
                id: item.id, title: item.title, artist: item.artist, album: item.album,
                duration: item.duration, sourceKind: item.sourceKind, sourceReference: sourceReference,
                artworkReference: artworkReference ?? item.artworkReference,
                lyricsReference: item.lyricsReference, isLiked: item.isLiked, isAvailable: true, lastPlayedAt: item.lastPlayedAt
            )
            changed = true
        }
        if changed { save() }
    }

    func updateArtwork(trackID: String, artworkReference: String) {
        var changed = false
        if let index = favorites.firstIndex(where: { $0.id == trackID }) {
            let item = favorites[index]
            favorites[index] = TrackSnapshot(
                id: item.id, title: item.title, artist: item.artist, album: item.album,
                duration: item.duration, sourceKind: item.sourceKind, sourceReference: item.sourceReference,
                artworkReference: artworkReference, lyricsReference: item.lyricsReference,
                isLiked: true, isAvailable: true, lastPlayedAt: item.lastPlayedAt
            )
            changed = true
        }
        if let index = recentlyPlayed.firstIndex(where: { $0.id == trackID }) {
            let item = recentlyPlayed[index]
            recentlyPlayed[index] = TrackSnapshot(
                id: item.id, title: item.title, artist: item.artist, album: item.album,
                duration: item.duration, sourceKind: item.sourceKind, sourceReference: item.sourceReference,
                artworkReference: artworkReference, lyricsReference: item.lyricsReference,
                isLiked: item.isLiked, isAvailable: true, lastPlayedAt: item.lastPlayedAt
            )
            changed = true
        }
        if changed { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(StoragePayload.self, from: data) else {
            return
        }
        favorites = payload.favorites
        recentlyPlayed = payload.recentlyPlayed
    }

    private func save() {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let payload = StoragePayload(favorites: favorites, recentlyPlayed: recentlyPlayed)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
