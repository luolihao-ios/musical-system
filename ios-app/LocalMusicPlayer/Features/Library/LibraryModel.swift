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

enum LibraryGroupKind: String, CaseIterable, Identifiable, Sendable {
    case albums
    case artists
    case folders

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: "专辑"
        case .artists: "歌手"
        case .folders: "文件夹"
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

    init(
        store: MusicStore,
        fileImporter: any FileImporting,
        systemImporter: any SystemLibraryImporting,
        playback: any LibraryPlaybackControlling
    ) {
        self.store = store
        self.fileImporter = fileImporter
        self.systemImporter = systemImporter
        self.playback = playback
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
                return track.album.isEmpty ? "未知专辑" : track.album
            case .artists:
                return track.artist.isEmpty ? "未知歌手" : track.artist
            case .folders:
                if track.sourceKind == .mediaLibrary {
                    return "系统音乐资料库"
                }
                return "“文件”App 导入"
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
