import XCTest
@testable import LocalMusicPlayer

@MainActor
final class NowPlayingModelTests: XCTestCase {
    func testLyricsSwitchAndRotationFollowPlaybackAndReduceMotion() {
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

    private func state(
        position: TimeInterval,
        isPlaying: Bool
    ) -> PlaybackState {
        PlaybackState(
            queue: [
                TrackSnapshot(
                    id: "night",
                    title: "夜航星",
                    artist: "测试歌手",
                    album: "测试专辑",
                    duration: 240,
                    sourceKind: .importedFile,
                    sourceReference: "/music/night.m4a",
                    lyricsReference: "/music/night.lrc"
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

    func read(path: String) throws -> String? {
        source
    }
}

@MainActor
private final class FakeNowPlayingController: PlaybackControlling {
    var state: PlaybackState
    private var observers: [UUID: (PlaybackState) -> Void] = [:]
    private(set) var lastSeek: TimeInterval?

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
