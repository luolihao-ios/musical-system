import SwiftData
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class LibraryModelTests: XCTestCase {
    private var modelContainers: [ModelContainer] = []

    func testSearchIsAccentInsensitiveAndPlayUsesFilteredQueue() async throws {
        let store = try makeStore()
        try store.upsert(track(id: "one", title: "Lumière", artist: "Beyoncé"))
        try store.upsert(track(id: "two", title: "夜航星", artist: "测试歌手"))
        let playback = FakeLibraryPlayback()
        let model = LibraryModel(
            store: store,
            fileImporter: FakeFileImporter(),
            systemImporter: FakeSystemImporter(result: .imported([])),
            playback: playback
        )
        try model.reload()

        model.searchText = "beyonce"
        try await model.play(model.filteredTracks[0])

        XCTAssertEqual(model.filteredTracks.map(\.id), ["one"])
        XCTAssertEqual(playback.queue.map(\.id), ["one"])
        XCTAssertEqual(playback.selectedTrack?.id, "one")
    }

    func testDeniedSystemPermissionLeavesFilesImportAvailable() async throws {
        let model = LibraryModel(
            store: try makeStore(),
            fileImporter: FakeFileImporter(),
            systemImporter: FakeSystemImporter(result: .permissionDenied),
            playback: FakeLibraryPlayback()
        )

        await model.importSystemLibrary()

        XCTAssertTrue(model.systemPermissionDenied)
        XCTAssertTrue(model.canImportFiles)
    }

    func testToggleLikeUpdatesVisibleTrack() async throws {
        let store = try makeStore()
        try store.upsert(track(id: "one", title: "夜航星", artist: "歌手"))
        let model = LibraryModel(
            store: store,
            fileImporter: FakeFileImporter(),
            systemImporter: FakeSystemImporter(result: .imported([])),
            playback: FakeLibraryPlayback()
        )
        try model.reload()

        try model.toggleLike(model.tracks[0])

        XCTAssertTrue(model.tracks[0].isLiked)
    }

    func testGroupsTracksByAlbumAndArtistWithUnknownFallbacks() throws {
        let store = try makeStore()
        try store.upsert(
            TrackRecord(
                id: "known",
                title: "夜航星",
                artist: "测试歌手",
                album: "测试专辑",
                duration: 180,
                sourceKind: .importedFile,
                sourceReference: "/music/known.m4a"
            )
        )
        try store.upsert(
            TrackRecord(
                id: "unknown",
                title: "纯音乐",
                artist: "",
                album: "",
                duration: 120,
                sourceKind: .importedFile,
                sourceReference: "/music/unknown.m4a"
            )
        )
        let model = LibraryModel(
            store: store,
            fileImporter: FakeFileImporter(),
            systemImporter: FakeSystemImporter(result: .imported([])),
            playback: FakeLibraryPlayback()
        )
        try model.reload()

        XCTAssertEqual(
            Set(model.groups(for: .albums).map(\.title)),
            Set(["测试专辑", "未知专辑"])
        )
        XCTAssertEqual(
            Set(model.groups(for: .artists).map(\.title)),
            Set(["测试歌手", "未知歌手"])
        )
    }

    private func makeStore() throws -> MusicStore {
        let container = try ModelContainerFactory.make(inMemory: true)
        modelContainers.append(container)
        return try MusicStore(context: container.mainContext)
    }

    private func track(
        id: String,
        title: String,
        artist: String
    ) -> TrackRecord {
        TrackRecord(
            id: id,
            title: title,
            artist: artist,
            album: "测试专辑",
            duration: 180,
            sourceKind: .importedFile,
            sourceReference: "/music/\(id).m4a"
        )
    }
}

@MainActor
private struct FakeFileImporter: FileImporting {
    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord] {
        []
    }
}

@MainActor
private struct FakeSystemImporter: SystemLibraryImporting {
    let result: SystemLibraryImportResult

    func importAuthorizedItems() async throws -> SystemLibraryImportResult {
        result
    }
}

@MainActor
private final class FakeLibraryPlayback: LibraryPlaybackControlling {
    var state = PlaybackState()
    private(set) var queue: [TrackSnapshot] = []
    private(set) var selectedTrack: TrackSnapshot?
    private var observers: [UUID: (PlaybackState) -> Void] = [:]

    func playTrack(
        _ track: TrackSnapshot,
        in queue: [TrackSnapshot]
    ) async throws {
        selectedTrack = track
        self.queue = queue
    }

    func observeState(
        _ observer: @escaping (PlaybackState) -> Void
    ) -> UUID {
        let id = UUID()
        observers[id] = observer
        observer(state)
        return id
    }

    func removeStateObserver(_ id: UUID) {
        observers[id] = nil
    }
}
