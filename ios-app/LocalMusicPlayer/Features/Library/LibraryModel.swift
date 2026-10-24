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
    func pause() throws
    func play() async throws
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

enum CatalogDownloadState: Equatable {
    case downloading(Double?)
    case importing
    case completed
    case failed(String)

    var isBusy: Bool {
        switch self { case .downloading, .importing: true; default: false }
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
    private(set) var catalogDownloads: [String: CatalogDownloadState] = [:]
    private(set) var catalogPreviewLoadingID: String?

    let canImportFiles = true

    private let store: MusicStore
    private let fileImporter: any FileImporting
    private let systemImporter: any SystemLibraryImporting
    private let playback: any LibraryPlaybackControlling
    private var playbackObserverID: UUID?
    private let scansAuthorizedFolders: Bool
    private let coverSearch: (any CoverArtSearching)?
    private var coverTask: Task<Void, Never>?
    private var coverCache: [String: CoverArtMatch] = [:]
    private var coverRetryTask: Task<Void, Never>?
    private let catalog: any CatalogDownloading
    private var catalogPreviewGeneration = UUID()
    private var catalogDownloadGenerations: [String: UUID] = [:]

    init(
        store: MusicStore,
        fileImporter: any FileImporting,
        systemImporter: any SystemLibraryImporting,
        playback: any LibraryPlaybackControlling,
        scansAuthorizedFolders: Bool = false,
        coverSearch: (any CoverArtSearching)? = nil,
        catalog: any CatalogDownloading = OnlineCatalog.shared
    ) {
        self.store = store
        self.fileImporter = fileImporter
        self.systemImporter = systemImporter
        self.playback = playback
        self.scansAuthorizedFolders = scansAuthorizedFolders
        self.coverSearch = coverSearch
        self.catalog = catalog
        playbackObserverID = playback.observeState { [weak self] state in
            self?.currentTrackID = state.currentTrack?.id
            self?.isCurrentTrackPlaying = state.isPlaying
        }
    }

    isolated deinit {
        coverTask?.cancel()
        coverRetryTask?.cancel()
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

    func toggleCatalogPreview(_ track: CatalogTrack) async throws {
        guard let snapshot = track.previewSnapshot() else { return }
        if playback.state.currentTrack?.id == snapshot.id {
            if playback.state.isPlaying || catalogPreviewLoadingID == track.id {
                catalogPreviewGeneration = UUID()
                catalogPreviewLoadingID = nil
                try playback.pause()
            } else {
                try await playback.play()
            }
            return
        }
        let generation = UUID()
        catalogPreviewGeneration = generation
        catalogPreviewLoadingID = track.id
        defer {
            if catalogPreviewGeneration == generation { catalogPreviewLoadingID = nil }
        }
        do { try await playback.playTrack(snapshot, in: [snapshot]) }
        catch {
            guard catalogPreviewGeneration == generation else { return }
            throw error
        }
        guard playback.state.currentTrack?.id == snapshot.id else { return }
        if catalogPreviewGeneration == generation { catalogPreviewLoadingID = nil }
        // 封面晚到只更新仍在播放的同一首歌，不重新加载音频。
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiYueCatalogPreviews").appendingPathComponent(UUID().uuidString)
        if let artwork = try? await catalog.downloadArtwork(track, to: directory),
           let active = playback.state.currentTrack, active.id == snapshot.id {
            let updated = TrackSnapshot(id: active.id, title: active.title, artist: active.artist,
                album: active.album, duration: active.duration, sourceKind: active.sourceKind,
                sourceReference: active.sourceReference, artworkReference: artwork.path,
                lyricsReference: active.lyricsReference, isLiked: active.isLiked,
                isAvailable: active.isAvailable, lastPlayedAt: active.lastPlayedAt)
            playback.refreshTrackMetadata(updated)
        }
    }

    func downloadCatalogTrack(_ track: CatalogTrack) async {
        guard track.license.allowsDownload,
              catalogDownloads[track.id]?.isBusy != true,
              catalogDownloads[track.id] != .completed else { return }
        catalogDownloads[track.id] = .downloading(nil)
        let generation = UUID()
        catalogDownloadGenerations[track.id] = generation
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AiYueCatalogDownloads").appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            let url = try await catalog.download(track, to: directory) { [weak self] value in
                Task { @MainActor [weak self] in
                    guard self?.catalogDownloadGenerations[track.id] == generation,
                          case .downloading = self?.catalogDownloads[track.id] else { return }
                    self?.catalogDownloads[track.id] = .downloading(min(max(value, 0), 1))
                }
            }
            // 供应商无图或封面请求失败时，继续现有生成/后台搜索流程。
            catalogDownloads[track.id] = .importing
            let artwork = try? await catalog.downloadArtwork(track, to: directory)
            while isImporting { try await Task.sleep(for: .milliseconds(100)) }
            try Task.checkCancellation()
            try await importCatalogTrack(track, audioURL: url, artworkURL: artwork)
            catalogDownloads[track.id] = .completed
        } catch {
            catalogDownloads[track.id] = .failed(error.localizedDescription)
        }
    }

    func importCatalogTrack(_ track: CatalogTrack, audioURL: URL, artworkURL: URL?) async throws {
        guard !isImporting else {
            throw NSError(domain: "AiYueCatalog", code: 1, userInfo: [NSLocalizedDescriptionKey: String(localized: "正在导入其他歌曲，请稍后重试")])
        }
        isImporting = true
        defer { isImporting = false }
        let records = try await fileImporter.importFiles([ImportedFile(sourceURL: audioURL, kind: .audio)])
        guard records.count == 1, let record = records.first else {
            throw NSError(domain: "AiYueCatalog", code: 2, userInfo: [NSLocalizedDescriptionKey: String(localized: "下载的歌曲未能导入，请重试")])
        }
        record.title = track.title
        record.artist = track.artist
        if let artworkURL {
            let directory = URL(fileURLWithPath: record.sourceReference).deletingLastPathComponent()
            let destination = directory.appendingPathComponent("artwork-provider")
            try Data(contentsOf: artworkURL).write(to: destination, options: .atomic)
            record.artworkReference = destination.path
            record.artworkOriginRaw = CoverArtworkOrigin.downloaded.rawValue
        }
        try store.upsert(record)
        playback.refreshTrackMetadata(TrackSnapshot(record))
        try reload()
        scheduleMissingCoverSearch()
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
        coverRetryTask?.cancel()
        coverRetryTask = nil
        coverTask = Task { [weak self] in
            guard let self else { return }
            defer {
                self.isCompletingResources = false
                self.coverTask = nil
                if !Task.isCancelled { self.scheduleCoverRetry() }
            }
            guard await coverSearch.isAvailable() else {
                self.coverSearchMessage = String(localized: "封面搜索暂时不可用，可稍后重试")
                return
            }
            self.isCompletingResources = true
            var completed = 0
            var found = 0
            var activeTrackID: String?
            do {
                // 每首歌的结果保存在资料库；重启、更新不能丢失未找到/失败的区别。
                while !Task.isCancelled {
                    guard let track = try self.store.tracks().first(where: {
                        CoverSearchHistory.isEligible($0)
                    }) else { break }
                    let snapshot = TrackSnapshot(track)
                    activeTrackID = snapshot.id
                    let queryKey = CoverSearchHistory.queryKey(for: track)
                    try self.store.saveCoverHistory(.searching, track: track)
                    self.coverSearchMessage = String(format: NSLocalizedString("正在后台查找封面，已处理 %lld 首，可继续播放", comment: ""), Int64(completed))
                    let query = MusicResourceQuery(title: snapshot.title, artist: snapshot.artist,
                                                   album: snapshot.album, duration: snapshot.duration)
                    let cacheKey = [CoverQueryPolicy.cleanedTitle(query.title), query.artist, query.album]
                        .map(OnlineMusicResources.normalized).joined(separator: "|")
                    CoverSearchDiagnostics.log("队列 track=\(snapshot.id) title=\(snapshot.title) 缓存命中=\(self.coverCache[cacheKey] != nil)")
                    let match: CoverArtMatch?
                    if let cached = self.coverCache[cacheKey] { match = cached }
                    else {
                        do { match = try await coverSearch.findCover(query) }
                        catch {
                            if let current = try self.store.track(id: snapshot.id),
                               CoverSearchHistory.queryKey(for: current) == queryKey {
                                try self.store.saveCoverHistory(Task.isCancelled || error is CancellationError ? .pending : .failed, track: current)
                            }
                            try Task.checkCancellation()
                            if error is CancellationError { throw error }
                            completed += 1
                            CoverSearchDiagnostics.log("查询失败，延迟重试 track=\(snapshot.id) error=\(error.localizedDescription)")
                            continue
                        }
                    }
                    if Task.isCancelled {
                        if let current = try self.store.track(id: snapshot.id) { try self.store.saveCoverHistory(.pending, track: current) }
                        throw CancellationError()
                    }
                    completed += 1
                    guard let current = try self.store.track(id: snapshot.id) else { continue }
                    guard current.sourceReference == snapshot.sourceReference,
                          current.artworkReference == snapshot.artworkReference,
                          CoverSearchHistory.queryKey(for: current) == queryKey else {
                        if CoverSearchHistory.read(current)?.status == .searching {
                            try self.store.saveCoverHistory(.pending, track: current)
                        }
                        continue
                    }
                    guard let match else {
                        try self.store.saveCoverHistory(.notFound, track: current)
                        PlayerInteractionDiagnostics.log("cover completion result=not-found processed=\(completed)")
                        continue
                    }
                    if self.coverCache.count >= 16, let oldest = self.coverCache.keys.first { self.coverCache[oldest] = nil }
                    self.coverCache[cacheKey] = match
                    // 查询期间可能删除、重新导入或手动换封面；不恢复被删除的歌，也不覆盖新封面。
                    guard CoverSearchHistory.origin(of: current) == .generated else { continue }
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
                    current.artworkOriginRaw = CoverArtworkOrigin.downloaded.rawValue
                    try self.store.saveCoverHistory(.found, track: current)
                    try self.store.upsert(current)
                    self.playback.refreshTrackMetadata(TrackSnapshot(current))
                    try self.reload()
                    found += 1
                    CoverSearchDiagnostics.log("已保存 track=\(snapshot.id) provider=\(match.provider) file=\(url.lastPathComponent)")
                    PlayerInteractionDiagnostics.log("cover completion result=saved fallback=\(match.artistFallback) processed=\(completed)")
                }
                self.coverSearchMessage = String(format: NSLocalizedString("封面搜索完成：处理 %lld 首，补齐 %lld 首", comment: ""), Int64(completed), Int64(found))
            } catch is CancellationError {
                if let id = activeTrackID, let track = try? self.store.track(id: id),
                   CoverSearchHistory.read(track)?.status == .searching {
                    try? self.store.saveCoverHistory(.pending, track: track)
                }
                self.coverSearchMessage = String(localized: "封面搜索已暂停")
                CoverSearchDiagnostics.log("队列已暂停")
            } catch {
                if let id = activeTrackID, let track = try? self.store.track(id: id),
                   CoverSearchHistory.read(track)?.status == .searching {
                    try? self.store.saveCoverHistory(.failed, track: track)
                }
                self.coverSearchMessage = error.localizedDescription
                PlayerInteractionDiagnostics.log("cover completion stopped reason=\(String(describing: type(of: error)))")
            }
        }
    }

    func retryMissingCovers() {
        guard coverTask == nil else { return }
        do {
            for track in try store.tracks() where CoverSearchHistory.origin(of: track) == .generated {
                try store.saveCoverHistory(.pending, track: track)
            }
        } catch { errorMessage = error.localizedDescription; return }
        scheduleMissingCoverSearch()
    }

    private func scheduleCoverRetry() {
        let next = (try? store.tracks())?.filter { $0.isAvailable && CoverSearchHistory.origin(of: $0) == .generated }
            .compactMap { CoverSearchHistory.read($0)?.retryAfter }.filter { $0 > Date() }.min()
        guard let next else { return }
        coverRetryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.1, next.timeIntervalSinceNow))) }
            catch { return }
            self?.scheduleMissingCoverSearch()
        }
    }

    func cancelCoverSearch() {
        coverTask?.cancel()
        coverRetryTask?.cancel()
        coverRetryTask = nil
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
            errorMessage = String(format: NSLocalizedString("无法播放《%@》：%@", comment: ""), track.title, error.localizedDescription)
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
