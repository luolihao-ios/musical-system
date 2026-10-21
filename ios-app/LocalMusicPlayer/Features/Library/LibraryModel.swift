import Foundation
import Observation

@MainActor
protocol FileImporting {
    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord]
}

extension FileImportService: FileImporting {
}

@MainActor
protocol SystemLibraryImporting {
    func importAuthorizedItems() async throws -> SystemLibraryImportResult
}

extension SystemLibraryImporter: SystemLibraryImporting {
}

@MainActor
protocol LibraryPlaybackControlling: AnyObject {
    var state: PlaybackState { get }
    func removeTrack(id: String) throws
    func refreshTrackMetadata(_ track: TrackSnapshot)
    func playTrack(
        _ track: TrackSnapshot,
        in queue: [TrackSnapshot]
    ) async throws
    @discardableResult
    func observeState(
        _ observer: @escaping (PlaybackState) -> Void
    ) -> UUID
    func removeStateObserver(_ id: UUID)
}

extension PlaybackController: LibraryPlaybackControlling {
}

extension LibraryPlaybackControlling {
    func removeTrack(id: String) throws {}
    func refreshTrackMetadata(_ track: TrackSnapshot) {}
}

enum LibraryGroupKind: String, CaseIterable, Identifiable, Sendable {
    case albums
    case artists
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: String(localized: "专辑")
        case .artists: String(localized: "歌手")
        case .folders: String(localized: "文件夹")
        }
    }

    var systemImage: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .folders: "folder"
        }
    }
}

struct LibraryTrackGroup: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let tracks: [TrackSnapshot]
}

@MainActor
@Observable
final class LibraryModel {
    private(set) var tracks: [TrackSnapshot] = []
    var searchText = ""
    private(set) var isImporting = false
    private(set) var isCompletingResources = false
    private(set) var coverSearchMessage = ""
    var systemPermissionDenied = false
    private(set) var errorMessage: String?
    private(set) var currentTrackID: String?
    private(set) var isCurrentTrackPlaying = false

    let canImportFiles = true

    private let store: MusicStore
    private let fileImporter: any FileImporting
    private let systemImporter: any SystemLibraryImporting
    private let playback: any LibraryPlaybackControlling
    private var playbackObserverID: UUID?
    private let scansAuthorizedFolders: Bool
    private let coverSearch: (any CoverArtSearching)?
    private var coverTask: Task<Void, Never>?
    private var coverAttempts: [String: Date] = [:]
    private var coverCache: [String: CoverArtMatch] = [:]

    init(
        store: MusicStore,
        fileImporter: any FileImporting,
        systemImporter: any SystemLibraryImporting,
        playback: any LibraryPlaybackControlling,
        scansAuthorizedFolders: Bool = false,
        coverSearch: (any CoverArtSearching)? = nil
    ) {
        self.store = store
        self.fileImporter = fileImporter
        self.systemImporter = systemImporter
        self.playback = playback
        self.scansAuthorizedFolders = scansAuthorizedFolders
        self.coverSearch = coverSearch
        playbackObserverID = playback.observeState { [weak self] state in
            self?.currentTrackID = state.currentTrack?.id
            self?.isCurrentTrackPlaying = state.isPlaying
        }
    }

    isolated deinit {
        coverTask?.cancel()
        if let playbackObserverID {
            playback.removeStateObserver(playbackObserverID)
        }
    }

    var filteredTracks: [TrackSnapshot] {
        let query = searchText.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tracks }
        return tracks.filter { track in
            [track.title, track.artist, track.album].contains { value in
                value.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: .current
                ).localizedStandardContains(query)
            }
        }
    }

    var recentlyPlayed: [TrackSnapshot] {
        tracks
            .filter { $0.lastPlayedAt != nil }
            .sorted {
                ($0.lastPlayedAt ?? .distantPast)
                    > ($1.lastPlayedAt ?? .distantPast)
            }
    }

    func groups(for kind: LibraryGroupKind) -> [LibraryTrackGroup] {
        let grouped = Dictionary(grouping: tracks) { track in
            switch kind {
            case .albums:
                return track.album.isEmpty ? String(localized: "未知专辑") : track.album
            case .artists:
                return track.artist.isEmpty ? String(localized: "未知歌手") : track.artist
            case .folders:
                if track.sourceKind == .mediaLibrary {
                    return String(localized: "系统音乐资料库")
                }
                return String(localized: "“文件”App 导入")
            }
        }
        return grouped.map { key, value in
            LibraryTrackGroup(
                id: "\(kind.rawValue)|\(key)",
                title: key,
                tracks: value.sorted {
                    $0.title.localizedStandardCompare($1.title)
                        == .orderedAscending
                }
            )
        }
        .sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    func reload() throws {
        tracks = try store.tracks().map(TrackSnapshot.init)
    }

    func importFiles(_ files: [ImportedFile]) async {
        await performImport {
            try await fileImporter.importFiles(files)
        }
    }

    func scanLocalAudio() async {
        await performImport {
            await DeviceMusicFolders.scan(using: fileImporter)
        }
    }

    func importSystemLibrary() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            switch try await systemImporter.importAuthorizedItems() {
            case let .imported(records):
                for record in records { try store.upsert(record) }
                try reload()
                scheduleMissingCoverSearch()
            case .permissionDenied:
                systemPermissionDenied = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleLike(_ track: TrackSnapshot) throws {
        try store.setLiked(trackID: track.id, isLiked: !track.isLiked)
        try reload()
    }

    func clearError() {
        errorMessage = nil
    }

    func delete(_ track: TrackSnapshot) throws {
        try playback.removeTrack(id: track.id)
        try store.deleteTrack(id: track.id)
        try reload()
    }
    func showImportError(_ message: String) { errorMessage = message }
    func scheduleMissingCoverSearch() {
        guard coverTask == nil, let coverSearch else { return }
        coverTask = Task { [weak self] in
            guard let self else { return }
            defer { self.isCompletingResources = false; self.coverTask = nil }
            guard await coverSearch.isAvailable() else {
                self.coverSearchMessage = "封面搜索暂时不可用，可稍后重试"
                return
            }
            self.isCompletingResources = true
            var completed = 0
            var found = 0
            do {
                // 每轮重新读取，包含搜索期间新导入的歌曲；相同歌曲失败后一小时内不自动重试。
                while !Task.isCancelled {
                    guard let track = try self.store.tracks().first(where: {
                        CoverArtworkPolicy.needsSearch(path: $0.artworkReference) &&
                        (self.coverAttempts[$0.id].map { Date().timeIntervalSince($0) > 3600 } ?? true)
                    }) else { break }
                    let snapshot = TrackSnapshot(track)
                    self.coverAttempts[snapshot.id] = Date()
                    self.coverSearchMessage = "正在后台查找封面，已处理 \(completed) 首，可继续播放"
                    let query = MusicResourceQuery(title: snapshot.title, artist: snapshot.artist,
                                                   album: snapshot.album, duration: snapshot.duration)
                    let cacheKey = [CoverQueryPolicy.cleanedTitle(query.title), query.artist, query.album]
                        .map(OnlineMusicResources.normalized).joined(separator: "|")
                    CoverSearchDiagnostics.log("队列 track=\(snapshot.id) title=\(snapshot.title) 缓存命中=\(self.coverCache[cacheKey] != nil)")
                    let match: CoverArtMatch?
                    if let cached = self.coverCache[cacheKey] { match = cached }
                    else {
                        do { match = try await coverSearch.findCover(query) }
                        catch let error as CoverSearchError { throw error }
                        catch { match = nil }
                    }
                    try Task.checkCancellation()
                    completed += 1
                    guard let match else {
                        PlayerInteractionDiagnostics.log("cover completion result=not-found processed=\(completed)")
                        continue
                    }
                    if self.coverCache.count >= 16, let oldest = self.coverCache.keys.first { self.coverCache[oldest] = nil }
                    self.coverCache[cacheKey] = match
                    // 查询期间可能删除、重新导入或手动换封面；不恢复被删除的歌，也不覆盖新封面。
                    guard let current = try self.store.track(id: snapshot.id),
                          current.sourceReference == snapshot.sourceReference,
                          current.artworkReference == snapshot.artworkReference,
                          CoverArtworkPolicy.needsSearch(path: current.artworkReference) else { continue }
                    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    let directory = base.appendingPathComponent("ImportedMusic").appendingPathComponent(UUID().uuidString)
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let url = directory.appendingPathComponent("artwork-online.jpg")
                    try match.data.write(to: url, options: .atomic)
                    let metadata: [String: Any] = ["provider": match.provider, "title": match.title,
                        "imageURL": match.imageURL.absoluteString, "pageURL": match.pageURL?.absoluteString ?? "",
                        "matchKind": match.artistFallback ? "artist-album" : "song", "savedAt": Date().timeIntervalSince1970]
                    try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("source.json"), options: .atomic)
                    current.artworkReference = url.path
                    try self.store.upsert(current)
                    self.playback.refreshTrackMetadata(TrackSnapshot(current))
                    try self.reload()
                    found += 1
                    CoverSearchDiagnostics.log("已保存 track=\(snapshot.id) provider=\(match.provider) file=\(url.lastPathComponent)")
                    PlayerInteractionDiagnostics.log("cover completion result=saved fallback=\(match.artistFallback) processed=\(completed)")
                }
                self.coverSearchMessage = "封面搜索完成：处理 \(completed) 首，补齐 \(found) 首"
            } catch is CancellationError {
                self.coverSearchMessage = "封面搜索已暂停"
                CoverSearchDiagnostics.log("队列已暂停")
            } catch {
                self.coverSearchMessage = error.localizedDescription
                PlayerInteractionDiagnostics.log("cover completion stopped reason=\(String(describing: type(of: error)))")
            }
        }
    }

    func retryMissingCovers() {
        guard coverTask == nil else { return }
        coverAttempts.removeAll()
        scheduleMissingCoverSearch()
    }

    func cancelCoverSearch() {
        coverTask?.cancel()
    }

    func play(_ track: TrackSnapshot) async throws {
        try await play(track, in: filteredTracks)
    }

    func play(
        _ track: TrackSnapshot,
        in tracks: [TrackSnapshot]
    ) async throws {
        let queue = tracks.filter(\.isAvailable)
        guard queue.contains(where: { $0.id == track.id }) else {
            return
        }
        do {
            try await playback.playTrack(track, in: queue)
            try store.recordPlay(trackID: track.id)
            try reload()
        } catch {
            PlaybackDiagnostics.log(
                "音乐库播放失败：id=\(track.id)，标题=\(track.title)，错误=\(error.localizedDescription)"
            )
            errorMessage = "无法播放《\(track.title)》：\(error.localizedDescription)"
            throw error
        }
    }

    private func performImport(
        _ operation: () async throws -> [TrackRecord]
    ) async {
        guard !isImporting else { return }
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            for record in try await operation() {
                try store.upsert(record)
            }
            try reload()
            scheduleMissingCoverSearch()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
