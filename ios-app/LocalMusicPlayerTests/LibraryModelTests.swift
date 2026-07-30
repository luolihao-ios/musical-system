import SwiftData
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class LibraryModelTests: XCTestCase {
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
        XCTAssertEqual(playback.startIndex, 0)
        XCTAssertEqual(playback.playCount, 1)
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

    private func makeStore() throws -> MusicStore {
        let container = try ModelContainerFactory.make(inMemory: true)
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
    private(set) var queue: [TrackSnapshot] = []
    private(set) var startIndex = 0
    private(set) var playCount = 0

    func loadQueue(_ tracks: [TrackSnapshot], startIndex: Int) throws {
        queue = tracks
        self.startIndex = startIndex
    }

    func play() async throws {
        playCount += 1
    }
}
