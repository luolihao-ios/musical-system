import XCTest
import SwiftUI
import SwiftData
@testable import LocalMusicPlayer

@MainActor
final class NowPlayingModelTests: XCTestCase {
    func testDownloadedLyricsArePublishedBeforeReturningWithoutReadingSavedFileAgain() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let track = TrackSnapshot(id: "immediate-lyrics", title: "即时歌词", artist: "歌手", album: "",
            duration: 120, sourceKind: .onlinePreview, sourceReference: "https://example.org/a.mp3")
        let playback = FakeNowPlayingController(state: PlaybackState(queue: [track], currentIndex: 0))
        let reader = CountingLyricsReader()
        let resources = RequestedLyricsFixture()
        let model = NowPlayingModel(playback: playback, lyricsReader: reader, online: resources, store: store)
        await model.findLyrics()
        let path = try XCTUnwrap(playback.state.currentTrack?.lyricsReference)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent()) }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "[00:01.00]按需歌词")
        XCTAssertEqual(model.lyricLines.map(\.text), ["按需歌词"], "已取得的文本必须立即显示，不等待磁盘二次读取")
        XCTAssertEqual(model.lyricTrackID, track.id)
        XCTAssertFalse(model.isSearchingLyrics)
        let reads = await reader.calls
        XCTAssertEqual(reads, 0)
        await model.findLyrics()
        let requests = await resources.requests
        XCTAssertEqual(requests, 1, "已有歌词不能重复搜索")
    }

    func testOnlinePreviewCanLoadLyricsWithoutCreatingLibraryRecord() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let track = TrackSnapshot(id: "preview-lyrics", title: "试听歌曲", artist: "歌手", album: "",
            duration: 120, sourceKind: .onlinePreview, sourceReference: "https://example.org/a.mp3")
        let playback = FakeNowPlayingController(state: PlaybackState(queue: [track], currentIndex: 0))
        let model = NowPlayingModel(playback: playback, online: RequestedLyricsFixture(), store: store)
        await model.findLyrics()
        for _ in 0..<200 {
            if model.hasLyrics { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.hasLyrics)
        XCTAssertNil(try store.track(id: track.id))
        XCTAssertFalse(model.lyricsSearchMessage.contains("正在"))
        if let path = playback.state.currentTrack?.lyricsReference {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent())
        }
    }

    func testNetworkLyricsAreRequestedOnlyAfterExplicitAction() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let record = TrackRecord(id: "on-demand", title: "测试歌", artist: "测试歌手", album: "", duration: 120,
                                 sourceKind: .importedFile, sourceReference: "/music/fixture.mp3")
        try store.upsert(record)
        let playback = FakeNowPlayingController(state: PlaybackState(queue: [TrackSnapshot(record)], currentIndex: 0))
        let resources = RequestedLyricsFixture()
        let model = NowPlayingModel(playback: playback, online: resources, store: store)
        await Task.yield()
        let before = await resources.requests
        XCTAssertEqual(before, 0, "打开播放页不能自动搜索歌词")
        await model.findLyrics()
        for _ in 0..<200 {
            if model.hasLyrics { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.hasLyrics)
        XCTAssertEqual(model.lyricLines.map(\.text), ["按需歌词"])
        let after = await resources.requests
        let askedForCover = await resources.askedForCover
        XCTAssertEqual(after, 1)
        XCTAssertFalse(askedForCover)
        let path = try XCTUnwrap(store.track(id: "on-demand")?.lyricsReference)
        defer { try? FileManager.default.removeItem(at: URL(fileURLWithPath: path).deletingLastPathComponent()) }
        XCTAssertEqual(try String(contentsOfFile: path, encoding: .utf8), "[00:01.00]按需歌词")
        await model.findLyrics()
        let repeated = await resources.requests
        XCTAssertEqual(repeated, 1, "已有歌词不应再次查询")
    }

    func testMiniPlayerKeepsCompactHeightWhenGivenFullScreenProposal() {
        let playback = FakeNowPlayingController(
            state: state(position: 10, isPlaying: true)
        )
        let model = NowPlayingModel(
            playback: playback,
            lyricsReader: FakeLyricsReader(source: nil)
        )
        let controller = UIHostingController(
            rootView: MiniPlayerView(model: model, openNowPlaying: {}, menuClearance: 0)
        )

        let size = controller.sizeThatFits(
            in: CGSize(width: 390, height: 844)
        )

        XCTAssertEqual(size.height, 60, accuracy: 0.5)
    }

    func testLyricsSwitchAndRotationFollowPlaybackAndReduceMotion() async {
        let playback = FakeNowPlayingController(
            state: state(position: 5, isPlaying: true)
        )
        let model = NowPlayingModel(
            playback: playback,
            lyricsReader: FakeLyricsReader(
                source: "[00:01.00]第一句\n[00:10.00]第二句"
            ),
            reduceMotion: false
        )
        await Task.yield()
        XCTAssertEqual(model.currentLyricIndex, 0)
        XCTAssertTrue(model.isRecordRotating)

        playback.publish(state(position: 12, isPlaying: false))

        XCTAssertEqual(model.currentLyricIndex, 1)
        XCTAssertFalse(model.isRecordRotating)

        let reduced = NowPlayingModel(
            playback: FakeNowPlayingController(
                state: state(position: 5, isPlaying: true)
            ),
            lyricsReader: FakeLyricsReader(source: nil),
            reduceMotion: true
        )
        XCTAssertFalse(reduced.isRecordRotating)
        XCTAssertFalse(reduced.hasLyrics)
    }

    func testSeekFractionForwardsToPlayback() throws {
        let playback = FakeNowPlayingController(
            state: state(position: 0, isPlaying: false)
        )
        let model = NowPlayingModel(
            playback: playback,
            lyricsReader: FakeLyricsReader(source: nil),
            reduceMotion: false
        )

        try model.seek(fraction: 0.5)

        XCTAssertEqual(playback.lastSeek, 120)
    }

    func testSeekLyricForwardsExactTimestampWithoutChangingPlayback() throws {
        let playback = FakeNowPlayingController(
            state: state(position: 0, isPlaying: false)
        )
        let model = NowPlayingModel(
            playback: playback,
            lyricsReader: FakeLyricsReader(source: nil)
        )

        try model.seek(
            to: LyricLine(timestamp: 42, text: "副歌")
        )

        XCTAssertEqual(playback.lastSeek, 42)
        XCTAssertFalse(playback.state.isPlaying)
    }

    func testStaleLyricsCannotReplaceCurrentTrackLyrics() async {
        let playback = FakeNowPlayingController(
            state: state(
                trackID: "A",
                position: 0,
                isPlaying: true
            )
        )
        let reader = DelayedLyricsReader(
            responses: [
                "/music/A.lrc": .init(
                    delay: .milliseconds(120),
                    source: "[00:01.00]A歌词"
                ),
                "/music/B.lrc": .init(
                    delay: .milliseconds(10),
                    source: "[00:01.00]B歌词"
                )
            ]
        )
        let model = NowPlayingModel(
            playback: playback,
            lyricsReader: reader
        )

        playback.publish(
            state(trackID: "B", position: 0, isPlaying: true)
        )
        XCTAssertTrue(model.lyricLines.isEmpty)
        XCTAssertNil(model.currentLyricIndex)
        try? await Task.sleep(for: .milliseconds(160))

        XCTAssertEqual(model.lyricTrackID, "B")
        XCTAssertEqual(model.lyricLines.map(\.text), ["B歌词"])
    }

    func testQueueEditingForwardsExactArguments() async {
        let playback = FakeNowPlayingController(
            state: state(position: 0, isPlaying: true)
        )
        let model = NowPlayingModel(
            playback: playback,
            lyricsReader: FakeLyricsReader(source: nil)
        )
        let offsets = IndexSet(integer: 0)

        model.moveQueue(fromOffsets: offsets, toOffset: 2)
        await model.removeQueueItems(atOffsets: offsets)
        model.clearQueue()

        XCTAssertEqual(playback.lastMoveOffsets, offsets)
        XCTAssertEqual(playback.lastMoveDestination, 2)
        XCTAssertEqual(playback.lastRemovedOffsets, offsets)
        XCTAssertEqual(playback.clearQueueCount, 1)
    }

    private func state(
        trackID: String = "night",
        position: TimeInterval,
        isPlaying: Bool
    ) -> PlaybackState {
        PlaybackState(
            queue: [
                TrackSnapshot(
                    id: trackID,
                    title: "夜航星",
                    artist: "测试歌手",
                    album: "测试专辑",
                    duration: 240,
                    sourceKind: .importedFile,
                    sourceReference: "/music/\(trackID).m4a",
                    lyricsReference: "/music/\(trackID).lrc"
                )
            ],
            currentIndex: 0,
            isPlaying: isPlaying,
            position: position,
            duration: 240,
            volume: 1,
            mode: .repeatAll
        )
    }
}

private actor RequestedLyricsFixture: MusicResourceSearching {
    private(set) var requests = 0
    private(set) var askedForCover = false
    func search(_ query: MusicResourceQuery, lyrics: Bool, cover: Bool) async -> MusicResourceResult {
        requests += 1
        askedForCover = cover
        return MusicResourceResult(lyrics: "[00:01.00]按需歌词", cover: nil)
    }
}

private actor CountingLyricsReader: LyricsReading {
    private(set) var calls = 0
    func read(path: String) async throws -> String? {
        calls += 1
        return nil
    }
}

private struct FakeLyricsReader: LyricsReading {
    let source: String?

    func read(path: String) async throws -> String? {
        source
    }
}

private struct DelayedLyricsReader: LyricsReading {
    struct Response: Sendable {
        let delay: Duration
        let source: String
    }

    let responses: [String: Response]

    func read(path: String) async throws -> String? {
        guard let response = responses[path] else { return nil }
        try await Task.sleep(for: response.delay)
        return response.source
    }
}

@MainActor
private final class FakeNowPlayingController: PlaybackControlling {
    var state: PlaybackState
    private var observers: [UUID: (PlaybackState) -> Void] = [:]
    private(set) var lastSeek: TimeInterval?
    private(set) var lastMoveOffsets: IndexSet?
    private(set) var lastMoveDestination: Int?
    private(set) var lastRemovedOffsets: IndexSet?
    private(set) var clearQueueCount = 0

    init(state: PlaybackState) {
        self.state = state
    }

    func play() async throws {}
    func pause() throws {}
    func next() async throws {}
    func previous() async throws {}

    func seek(to position: TimeInterval) throws {
        lastSeek = position
    }

    func setVolume(_ volume: Double) throws {}
    func setMode(_ mode: PlaybackMode) throws {}

    func playTrack(
        _ track: TrackSnapshot,
        in queue: [TrackSnapshot]
    ) async throws {}

    func playQueueItem(at index: Int) async throws {}

    func refreshTrackMetadata(_ track: TrackSnapshot) {
        var updated = state
        for index in updated.queue.indices where updated.queue[index].id == track.id {
            updated.queue[index] = track
        }
        publish(updated)
    }

    func moveQueue(fromOffsets: IndexSet, toOffset: Int) throws {
        lastMoveOffsets = fromOffsets
        lastMoveDestination = toOffset
    }

    func removeQueueItems(atOffsets: IndexSet) async throws {
        lastRemovedOffsets = atOffsets
    }

    func clearQueue() throws {
        clearQueueCount += 1
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

    func publish(_ state: PlaybackState) {
        self.state = state
        observers.values.forEach { $0(state) }
    }
}
