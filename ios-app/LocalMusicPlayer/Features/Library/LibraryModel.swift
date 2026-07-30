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
    func loadQueue(_ tracks: [TrackSnapshot], startIndex: Int) throws
    func play() async throws
}

extension PlaybackController: LibraryPlaybackControlling {
}

@MainActor
@Observable
final class LibraryModel {
    private(set) var tracks: [TrackSnapshot] = []
    var searchText = ""
    private(set) var isImporting = false
    var systemPermissionDenied = false
    private(set) var errorMessage: String?

    let canImportFiles = true

    private let store: MusicStore
    private let fileImporter: any FileImporting
    private let systemImporter: any SystemLibraryImporting
    private let playback: any LibraryPlaybackControlling

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
        let queue = filteredTracks.filter(\.isAvailable)
        guard let index = queue.firstIndex(where: { $0.id == track.id }) else {
            return
        }
        try playback.loadQueue(queue, startIndex: index)
        try await playback.play()
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
