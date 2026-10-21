import SwiftData
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class LibraryModelTests: XCTestCase {
    private var modelContainers: [ModelContainer] = []

    func testGeneratedCoverIsReplacedAfterImportAndSavedWithSource() async throws {
        let store = try makeStore()
        let incoming = track(id: "new-cover", title: "你好", artist: "歌手")
        incoming.artworkReference = "/music/artwork-generated.jpg"
        let started = expectation(description: "查询开始")
        let provider = ControlledCoverProvider(onStart: { started.fulfill() })
        let model = LibraryModel(store: store, fileImporter: ImportedCoverFixture(record: incoming),
            systemImporter: FakeSystemImporter(result: .imported([])), playback: FakeLibraryPlayback(), coverSearch: provider)
        await model.importFiles([])
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(model.tracks.first?.artworkReference, "/music/artwork-generated.jpg")
        await provider.finish()
        for _ in 0..<200 {
            if !model.isCompletingResources { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let path = try XCTUnwrap(store.track(id: "new-cover")?.artworkReference)
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: path)), Data("test-image".utf8))
        let source = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("source.json"))) as? [String: Any]
        XCTAssertEqual(source?["provider"] as? String, "测试来源")
        XCTAssertEqual(source?["imageURL"] as? String, "https://example.org/art.jpg")
        XCTAssertEqual(model.tracks.first?.artworkReference, path)
        XCTAssertNil(model.tracks.first?.lyricsReference)
    }

    func testImportReturnsWhileCoverSearchWaitsAndDoesNotFetchLyrics() async throws {
        let store = try makeStore()
        let incoming = track(id: "cover-test", title: "明天你好 (Live)", artist: "歌手")
        incoming.artworkReference = "/music/artwork-generated.jpg"
        let started = expectation(description: "后台封面查询开始")
        let provider = ControlledCoverProvider(onStart: { started.fulfill() })
        let model = LibraryModel(store: store, fileImporter: ImportedCoverFixture(record: incoming),
            systemImporter: FakeSystemImporter(result: .imported([])), playback: FakeLibraryPlayback(), coverSearch: provider)
        await model.importFiles([])
        XCTAssertFalse(model.isImporting)
        XCTAssertEqual(model.tracks.count, 1, "封面查询尚未完成时音乐必须已经导入")
        await fulfillment(of: [started], timeout: 2)
        XCTAssertTrue(model.isCompletingResources)
        try model.delete(model.tracks[0])
        await provider.finish()
        for _ in 0..<200 {
            if !model.isCompletingResources { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertFalse(model.isCompletingResources)
        XCTAssertTrue(model.tracks.isEmpty, "延迟封面结果不能复活已删除歌曲")
        XCTAssertNil(try store.track(id: "cover-test"))
    }

    func testExistingRealCoverIsNotSearched() async throws {
        let store = try makeStore()
        let incoming = track(id: "real-cover", title: "你好", artist: "歌手")
        incoming.artworkReference = "/music/custom-cover.jpg"
        let provider = ControlledCoverProvider(onStart: { XCTFail("自选封面不应查询") })
        let model = LibraryModel(store: store, fileImporter: ImportedCoverFixture(record: incoming),
            systemImporter: FakeSystemImporter(result: .imported([])), playback: FakeLibraryPlayback(), coverSearch: provider)
        await model.importFiles([])
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(model.tracks.first?.artworkReference, "/music/custom-cover.jpg")
        let count = await provider.count
        XCTAssertEqual(count, 0)
    }

    func testDifferentAlbumsDoNotReuseAnotherAlbumsCover() async throws {
        let store = try makeStore()
        let first = track(id: "album-one", title: "同名歌曲", artist: "同一歌手")
        first.album = "第一张专辑"; first.artworkReference = "/music/artwork-generated.jpg"
        let second = track(id: "album-two", title: "同名歌曲", artist: "同一歌手")
        second.album = "第二张专辑"; second.artworkReference = "/music/artwork-generated.jpg"
        try store.upsert(first); try store.upsert(second)
        let model = LibraryModel(store: store, fileImporter: FakeFileImporter(),
            systemImporter: FakeSystemImporter(result: .imported([])), playback: FakeLibraryPlayback(), coverSearch: AlbumCoverFixture())
        model.retryMissingCovers()
        for _ in 0..<200 {
            if let path = try store.track(id: "album-two")?.artworkReference, path.hasSuffix("artwork-online.jpg"), !model.isCompletingResources { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        let firstPath = try XCTUnwrap(store.track(id: "album-one")?.artworkReference)
        let secondPath = try XCTUnwrap(store.track(id: "album-two")?.artworkReference)
        defer {
            for path in [firstPath, secondPath] where path.hasSuffix("artwork-online.jpg") {
                try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
            }
        }
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: firstPath)), Data("第一张专辑".utf8))
        XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: secondPath)), Data("第二张专辑".utf8))
    }

    func testDelayedSearchDoesNotReplaceManuallyChangedCover() async throws {
        let store = try makeStore()
        let incoming = track(id: "manual-race", title: "你好", artist: "歌手")
        incoming.artworkReference = "/music/artwork-generated.jpg"
        let started = expectation(description: "封面查询已开始")
        let provider = ControlledCoverProvider(onStart: { started.fulfill() })
        let model = LibraryModel(store: store, fileImporter: ImportedCoverFixture(record: incoming),
            systemImporter: FakeSystemImporter(result: .imported([])), playback: FakeLibraryPlayback(), coverSearch: provider)
        await model.importFiles([])
        await fulfillment(of: [started], timeout: 2)
        let current = try XCTUnwrap(store.track(id: "manual-race"))
        current.artworkReference = "/music/my-cover.jpg"
        try store.upsert(current)
        try model.reload()
        await provider.finish()
        for _ in 0..<200 {
            if !model.isCompletingResources { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(try store.track(id: "manual-race")?.artworkReference, "/music/my-cover.jpg")
        XCTAssertEqual(model.tracks.first?.artworkReference, "/music/my-cover.jpg")
    }

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

    func testSecondImportRequestIsIgnoredWhileImportIsRunning() async throws {
        let importer = BlockingFileImporter()
        let started = expectation(description: "第一次导入已开始")
        importer.onStart = { started.fulfill() }
        let model = LibraryModel(
            store: try makeStore(),
            fileImporter: importer,
            systemImporter: FakeSystemImporter(result: .imported([])),
            playback: FakeLibraryPlayback()
        )

        let first = Task { await model.importFiles([]) }
        await fulfillment(of: [started], timeout: 1)
        let second = Task { await model.importFiles([]) }
        await Task.yield()

        XCTAssertEqual(importer.callCount, 1)
        importer.finishAll()
        await first.value
        await second.value
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

    func testDeletingTwoTracksInSuccessionKeepsLibraryConsistent() throws {
        let store = try makeStore()
        try store.upsert(track(id: "one", title: "第一首", artist: "歌手"))
        try store.upsert(track(id: "two", title: "第二首", artist: "歌手"))
        let model = LibraryModel(
            store: store,
            fileImporter: FakeFileImporter(),
            systemImporter: FakeSystemImporter(result: .imported([])),
            playback: FakeLibraryPlayback()
        )
        try model.reload()

        try model.delete(model.tracks[0])
        try model.delete(model.tracks[0])

        XCTAssertTrue(model.tracks.isEmpty)
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
            Set(["测试专辑", String(localized: "未知专辑")])
        )
        XCTAssertEqual(
            Set(model.groups(for: .artists).map(\.title)),
            Set(["测试歌手", String(localized: "未知歌手")])
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

private actor AlbumCoverFixture: CoverArtSearching {
    func isAvailable() -> Bool { true }
    func findCover(_ query: MusicResourceQuery) async throws -> CoverArtMatch? {
        CoverArtMatch(data: Data(query.album.utf8), imageURL: URL(string: "https://example.org/cover.jpg")!,
            pageURL: nil, title: query.title, artistFallback: false, provider: "测试来源")
    }
}

@MainActor
private struct ImportedCoverFixture: FileImporting {
    let record: TrackRecord
    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord] { [record] }
}

private actor ControlledCoverProvider: CoverArtSearching {
    let onStart: @Sendable () -> Void
    private var continuation: CheckedContinuation<CoverArtMatch?, Never>?
    private(set) var count = 0
    init(onStart: @escaping @Sendable () -> Void) { self.onStart = onStart }
    func isAvailable() -> Bool { true }
    func findCover(_ query: MusicResourceQuery) async throws -> CoverArtMatch? {
        count += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            onStart()
        }
    }
    func finish() {
        continuation?.resume(returning: CoverArtMatch(data: Data("test-image".utf8),
            imageURL: URL(string: "https://example.org/art.jpg")!, pageURL: nil, title: "封面", artistFallback: false, provider: "测试来源"))
        continuation = nil
    }
}

@MainActor
private struct FakeFileImporter: FileImporting {
    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord] {
        []
    }
}

@MainActor
private final class BlockingFileImporter: FileImporting {
    var onStart: (() -> Void)?
    private(set) var callCount = 0
    private var continuations: [CheckedContinuation<[TrackRecord], Error>] = []

    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord] {
        callCount += 1
        onStart?()
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func finishAll() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: [])
        }
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
