import Foundation
import Observation

struct DecayedAffinity: Sendable, Codable, Equatable {
    var score: Double
    var updatedAt: Date
}

struct TrackFeedback: Sendable, Codable, Equatable {
    var playCount: Int = 0
    var completeCount: Int = 0
    var quickSkipCount: Int = 0
    var isDisliked: Bool = false
    var lastPlayedAt: Date? = nil
    var lastShownAt: Date? = nil
}

struct TasteSnapshot: Sendable, Equatable {
    let artistAffinities: [String: Double]
    let artistDisplayNames: [String: String]
    let tagAffinities: [String: Double]
    let tagDisplayNames: [String: String]
    let recentSearchTerms: [String]
    let trackFeedback: [String: TrackFeedback]
    let dislikedTrackIDs: Set<String>
    let seedDayOffset: Int
    let currentHour: Int

    static func neutral(now: Date = .now) -> Self {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        let hour = Calendar.current.component(.hour, from: now)
        return Self(
            artistAffinities: [:],
            artistDisplayNames: [:],
            tagAffinities: [:],
            tagDisplayNames: [:],
            recentSearchTerms: [],
            trackFeedback: [:],
            dislikedTrackIDs: [],
            seedDayOffset: day,
            currentHour: hour
        )
    }
}

@MainActor
@Observable
final class TasteProfileStore {
    static let shared = TasteProfileStore()

    private struct StoragePayload: Codable {
        var artists: [String: DecayedAffinity] = [:]
        var artistDisplayNames: [String: String] = [:]
        var tags: [String: DecayedAffinity] = [:]
        var tagDisplayNames: [String: String] = [:]
        var recentSearchTerms: [String] = []
        var trackFeedback: [String: TrackFeedback] = [:]
        var didSeedLocalLibrary: Bool = false
    }

    private(set) var needsHomeRefresh = false

    private var payload = StoragePayload()
    private var refreshNonce = 0
    private let fileURL: URL

    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.fileURL = support.appendingPathComponent("AiYueTasteProfile.json")
        }
        load()
    }

    nonisolated static func canonicalTrackID(_ raw: String) -> String {
        if raw.hasPrefix("online-preview-") {
            return String(raw.dropFirst("online-preview-".count))
        }
        return raw
    }

    nonisolated static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    nonisolated static func isGenericArtist(_ artist: String) -> Bool {
        let key = normalizedKey(artist)
        if key.isEmpty { return true }
        return [
            "爱乐之城", "internet archive", "酷狗音乐", "本地播放",
            "未知歌手", "unknown artist", "various artists"
        ].contains(key)
    }

    nonisolated static func decayed(
        _ entry: DecayedAffinity,
        at now: Date,
        halfLifeDays: Double = 14
    ) -> Double {
        let elapsedDays = max(0, now.timeIntervalSince(entry.updatedAt) / 86_400)
        return entry.score * pow(0.5, elapsedDays / max(1, halfLifeDays))
    }

    func recordFavorite(artist: String, trackID: String, isLiked: Bool, now: Date = .now) {
        let canonical = Self.canonicalTrackID(trackID)
        if isLiked {
            adjustArtist(artist, delta: 6.0, now: now)
            if var feedback = payload.trackFeedback[canonical] {
                feedback.isDisliked = false
                payload.trackFeedback[canonical] = feedback
            }
            needsHomeRefresh = true
        } else {
            adjustArtist(artist, delta: -3.0, now: now)
        }
        save()
    }

    func recordDownload(artist: String, trackID: String, now: Date = .now) {
        let canonical = Self.canonicalTrackID(trackID)
        adjustArtist(artist, delta: 5.0, now: now)
        var feedback = payload.trackFeedback[canonical] ?? TrackFeedback()
        feedback.isDisliked = false
        payload.trackFeedback[canonical] = feedback
        needsHomeRefresh = true
        save()
    }

    func recordSearchQuery(_ query: String, now: Date = .now) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }
        var terms = payload.recentSearchTerms.filter { $0.caseInsensitiveCompare(trimmed) != .orderedSame }
        terms.insert(trimmed, at: 0)
        payload.recentSearchTerms = Array(terms.prefix(8))
        adjustScore(
            in: &payload.tags,
            displayNames: &payload.tagDisplayNames,
            rawName: trimmed,
            delta: 2.5,
            maxCount: 80,
            now: now
        )
        save()
    }

    func recordSearchPlay(artist: String, trackID: String, searchQuery: String?, now: Date = .now) {
        adjustArtist(artist, delta: 4.0, now: now)
        if let searchQuery {
            let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.count >= 2 {
                adjustScore(
                    in: &payload.tags,
                    displayNames: &payload.tagDisplayNames,
                    rawName: trimmed,
                    delta: 3.5,
                    maxCount: 80,
                    now: now
                )
            }
        }
        let canonical = Self.canonicalTrackID(trackID)
        var feedback = payload.trackFeedback[canonical] ?? TrackFeedback()
        feedback.isDisliked = false
        payload.trackFeedback[canonical] = feedback
        needsHomeRefresh = true
        save()
    }

    func recordPlaybackOutcome(
        trackID: String,
        artist: String,
        playedSeconds: TimeInterval,
        duration: TimeInterval,
        wasManualSkip: Bool,
        now: Date = .now
    ) {
        let canonical = Self.canonicalTrackID(trackID)
        var feedback = payload.trackFeedback[canonical] ?? TrackFeedback()
        let completionRatio = duration > 10 ? (playedSeconds / duration) : 0
        var didChange = false

        if completionRatio >= 0.75 || playedSeconds >= 90 {
            feedback.completeCount += 1
            feedback.playCount += 1
            feedback.lastPlayedAt = now
            adjustArtist(artist, delta: 4.0, now: now)
            didChange = true
        } else if playedSeconds >= 30 {
            feedback.playCount += 1
            feedback.lastPlayedAt = now
            adjustArtist(artist, delta: 1.5, now: now)
            didChange = true
        } else if wasManualSkip && playedSeconds >= 1.5 && playedSeconds < 15 {
            feedback.quickSkipCount += 1
            feedback.lastPlayedAt = now
            adjustArtist(artist, delta: -3.5, now: now)
            needsHomeRefresh = true
            didChange = true
        } else if playedSeconds >= 5 {
            feedback.playCount += 1
            feedback.lastPlayedAt = now
            didChange = true
        }

        guard didChange else { return }
        payload.trackFeedback[canonical] = feedback
        pruneTrackFeedback()
        save()
    }

    func recordDislike(trackID: String, artist: String, now: Date = .now) {
        let canonical = Self.canonicalTrackID(trackID)
        var feedback = payload.trackFeedback[canonical] ?? TrackFeedback()
        feedback.isDisliked = true
        payload.trackFeedback[canonical] = feedback
        adjustArtist(artist, delta: -8.0, now: now)
        needsHomeRefresh = true
        pruneTrackFeedback()
        save()
    }

    func recordHomeImpressions(_ trackIDs: [String], now: Date = .now) {
        guard !trackIDs.isEmpty else { return }
        for raw in trackIDs {
            let canonical = Self.canonicalTrackID(raw)
            guard !canonical.isEmpty else { continue }
            var feedback = payload.trackFeedback[canonical] ?? TrackFeedback()
            feedback.lastShownAt = now
            payload.trackFeedback[canonical] = feedback
        }
        pruneTrackFeedback()
        save()
    }

    func seedFromLocalLibrary(_ tracks: [TrackSnapshot], now: Date = .now) {
        guard !payload.didSeedLocalLibrary, !tracks.isEmpty else { return }
        var weights: [String: (name: String, score: Double)] = [:]
        for track in tracks {
            guard !Self.isGenericArtist(track.artist) else { continue }
            let trimmed = track.artist.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = Self.normalizedKey(trimmed)
            var entry = weights[key] ?? (trimmed, 0)
            entry.score += track.isLiked ? 3.0 : 1.0
            weights[key] = entry
        }
        let topArtists = weights.values.sorted { $0.score > $1.score }.prefix(8)
        for item in topArtists {
            adjustArtist(item.name, delta: min(5.0, item.score), now: now)
        }
        payload.didSeedLocalLibrary = true
        save()
    }

    func snapshot(
        now: Date = .now,
        refreshNonce: Int? = nil,
        includeOnlineFavorites: Bool = true
    ) -> TasteSnapshot {
        var artistAffinities: [String: Double] = [:]
        var artistNames = payload.artistDisplayNames
        for (key, entry) in payload.artists {
            let value = Self.decayed(entry, at: now)
            if abs(value) >= 0.05 {
                artistAffinities[key] = value
            }
        }

        if includeOnlineFavorites {
            for fav in OnlineHistoryStore.shared.favorites {
                guard !Self.isGenericArtist(fav.artist) else { continue }
                let trimmed = fav.artist.trimmingCharacters(in: .whitespacesAndNewlines)
                let key = Self.normalizedKey(trimmed)
                artistAffinities[key] = max(artistAffinities[key] ?? 0, 5.0)
                if artistNames[key] == nil { artistNames[key] = trimmed }
            }
        }

        var tagAffinities: [String: Double] = [:]
        for (key, entry) in payload.tags {
            let value = Self.decayed(entry, at: now)
            if abs(value) >= 0.05 {
                tagAffinities[key] = value
            }
        }

        let dislikedIDs = Set(payload.trackFeedback.compactMap { key, value in
            value.isDisliked ? key : nil
        })
        let day = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        let hour = Calendar.current.component(.hour, from: now)

        return TasteSnapshot(
            artistAffinities: artistAffinities,
            artistDisplayNames: artistNames,
            tagAffinities: tagAffinities,
            tagDisplayNames: payload.tagDisplayNames,
            recentSearchTerms: payload.recentSearchTerms,
            trackFeedback: payload.trackFeedback,
            dislikedTrackIDs: dislikedIDs,
            seedDayOffset: day + (refreshNonce ?? self.refreshNonce),
            currentHour: hour
        )
    }

    func snapshotForFeedRefresh(now: Date = .now) -> TasteSnapshot {
        refreshNonce += 1
        needsHomeRefresh = false
        return snapshot(now: now, refreshNonce: refreshNonce)
    }

    private func adjustArtist(_ artist: String, delta: Double, now: Date) {
        guard !Self.isGenericArtist(artist) else { return }
        adjustScore(
            in: &payload.artists,
            displayNames: &payload.artistDisplayNames,
            rawName: artist,
            delta: delta,
            maxCount: 120,
            now: now
        )
    }

    private func adjustScore(
        in dict: inout [String: DecayedAffinity],
        displayNames: inout [String: String],
        rawName: String,
        delta: Double,
        maxCount: Int,
        now: Date
    ) {
        let trimmed = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let key = Self.normalizedKey(trimmed)
        let current = dict[key].map { Self.decayed($0, at: now) } ?? 0
        let updated = min(60, max(-20, current + delta))
        dict[key] = DecayedAffinity(score: updated, updatedAt: now)
        displayNames[key] = trimmed

        if dict.count > maxCount {
            let kept = dict
                .mapValues { Self.decayed($0, at: now) }
                .filter { abs($0.value) >= 0.15 }
                .sorted { abs($0.value) > abs($1.value) }
                .prefix(maxCount)
            let keepKeys = Set(kept.map(\.key))
            dict = dict.filter { keepKeys.contains($0.key) }
            displayNames = displayNames.filter { keepKeys.contains($0.key) }
        }
    }

    private func pruneTrackFeedback() {
        let maxFeedbackCount = 300
        guard payload.trackFeedback.count > maxFeedbackCount else { return }
        let disliked = payload.trackFeedback.filter { $0.value.isDisliked }
        let remainingCapacity = max(0, maxFeedbackCount - disliked.count)
        let recent = payload.trackFeedback
            .filter { !$0.value.isDisliked }
            .sorted {
                let lhs = $0.value.lastPlayedAt ?? $0.value.lastShownAt ?? .distantPast
                let rhs = $1.value.lastPlayedAt ?? $1.value.lastShownAt ?? .distantPast
                return lhs > rhs
            }
            .prefix(remainingCapacity)
        var pruned = disliked
        for (key, value) in recent {
            pruned[key] = value
        }
        payload.trackFeedback = pruned
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode(StoragePayload.self, from: data) else {
            return
        }
        payload = decoded
    }

    private func save() {
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(payload) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
