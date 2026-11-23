import Foundation

enum CoverArtworkOrigin: String, Codable, Sendable {
    case generated, embedded, companion, manual, downloaded, existing
}

struct CoverSearchHistory: Codable, Equatable, Sendable {
    enum Status: String, Codable, Sendable { case pending, searching, found, notFound, failed }
    // 仅搜索策略真正改变时递增，不使用 App 版本号。
    static let currentRevision = 1
    var status: Status
    var queryKey: String
    var revision: Int
    var attemptedAt: Date?
    var retryAfter: Date?
    var failures: Int

    @MainActor
    static func queryKey(for track: TrackRecord) -> String {
        [CoverQueryPolicy.cleanedTitle(track.title), track.artist, track.album]
            .map(OnlineMusicResources.normalized).joined(separator: "|")
    }

    @MainActor
    static func read(_ track: TrackRecord) -> Self? {
        track.coverSearchHistoryData.flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    @MainActor
    static func origin(of track: TrackRecord) -> CoverArtworkOrigin {
        if let raw = track.artworkOriginRaw, let origin = CoverArtworkOrigin(rawValue: raw) { return origin }
        // 旧版未存来源，只能识别已知生成文件；其他已有图片一律保护。
        if CoverArtworkPolicy.needsSearch(path: track.artworkReference) { return .generated }
        if URL(fileURLWithPath: track.artworkReference ?? "").lastPathComponent == "artwork-online.jpg" { return .downloaded }
        return .existing
    }

    @MainActor
    static func isEligible(_ track: TrackRecord, now: Date = Date(), revision: Int = currentRevision) -> Bool {
        guard track.isAvailable, origin(of: track) == .generated else { return false }
        guard let history = read(track) else { return true }
        if history.queryKey != queryKey(for: track) || history.revision < revision { return true }
        switch history.status {
        case .pending: return true
        case .failed: return history.retryAfter.map { $0 <= now } ?? true
        case .searching, .found, .notFound: return false
        }
    }

    @MainActor
    static func write(_ status: Status, to track: TrackRecord, now: Date = Date()) throws {
        let previous = read(track)
        let failures = status == .failed ? (previous?.failures ?? 0) + 1
            : (status == .pending || status == .searching ? previous?.failures ?? 0 : 0)
        let delay = min(21_600.0, 60 * pow(5, Double(min(failures - 1, 4))))
        let history = Self(status: status, queryKey: queryKey(for: track), revision: currentRevision,
            attemptedAt: status == .pending ? previous?.attemptedAt : now,
            retryAfter: status == .failed ? now.addingTimeInterval(delay) : nil, failures: failures)
        track.coverSearchHistoryData = try JSONEncoder().encode(history)
        CoverSearchDiagnostics.log("搜索状态 track=\(track.id) status=\(status.rawValue) revision=\(history.revision) retry=\(history.retryAfter?.description ?? "none")")
    }
}
