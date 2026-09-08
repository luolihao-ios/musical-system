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
    private let online: (any MusicResourceSearching)?
    private let scansAuthorizedFolders: Bool

    init(
        store: MusicStore,
        fileImporter: any FileImporting,
        systemImporter: any SystemLibraryImporting,
        playback: any LibraryPlaybackControlling,
        online: (any MusicResourceSearching)? = nil,
        scansAuthorizedFolders: Bool = false
    ) {
        self.store = store
        self.fileImporter = fileImporter
        self.systemImporter = systemImporter
        self.playback = playback
        self.online = online
        self.scansAuthorizedFolders = scansAuthorizedFolders
        playbackObserverID = playback.observeState { [weak self] state in
            self?.currentTrackID = state.currentTrack?.id
            self?.isCurrentTrackPlaying = state.isPlaying
        }
    }

    isolated deinit {
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
    func completeMissingResources() async {
        guard !isImporting, !isCompletingResources, let online else { return }
        isCompletingResources = true; defer { isCompletingResources = false }
        do {
            let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("OnlineMusicResources")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for snapshot in try store.tracks().map(TrackSnapshot.init) where snapshot.lyricsReference == nil || snapshot.artworkReference == nil {
                let result = await online.search(MusicResourceQuery(title: snapshot.title, artist: snapshot.artist, album: snapshot.album, duration: snapshot.duration), lyrics: snapshot.lyricsReference == nil, cover: snapshot.artworkReference == nil)
                guard let track = try store.track(id: snapshot.id) else { continue }
                let directory = root.appendingPathComponent(track.id)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if track.lyricsReference == nil, let lyrics = result.lyrics, !lyrics.isEmpty {
                    let url = directory.appendingPathComponent("lyrics.lrc")
                    try lyrics.write(to: url, atomically: true, encoding: .utf8); track.lyricsReference = url.path
                }
                if track.artworkReference == nil, let cover = result.cover {
                    let url = directory.appendingPathComponent("artwork")
                    try cover.write(to: url, options: .atomic); track.artworkReference = url.path
                }
                try store.upsert(track)
            }
            try reload()
        } catch { errorMessage = error.localizedDescription }
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
        try await playback.playTrack(track, in: queue)
        try store.recordPlay(trackID: track.id)
        try reload()
    }

    private func performImport(
        _ operation: () async throws -> [TrackRecord]
    ) async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            for record in try await operation() {
                try store.upsert(record)
            }
            try reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
