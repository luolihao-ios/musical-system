import XCTest
@testable import LocalMusicPlayer

@MainActor
final class NowPlayingModelTests: XCTestCase {
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
