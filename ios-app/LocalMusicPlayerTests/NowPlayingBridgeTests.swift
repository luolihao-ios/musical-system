import XCTest
@testable import LocalMusicPlayer

@MainActor
final class NowPlayingBridgeTests: XCTestCase {
    func testStateMapsMetadataTimelineAndPlaybackRate() {
        let controller = FakePlaybackController(
            state: state(isPlaying: true)
        )
        let session = FakeNowPlayingSession()

        let bridge = NowPlayingBridge(
            controller: controller,
            session: session
        )

        XCTAssertEqual(
            session.info,
            SystemNowPlayingInfo(
                title: "夜航星",
                artist: "测试歌手",
                album: "测试专辑",
                artworkPath: "/covers/night.jpg",
                duration: 240,
                elapsed: 23,
                playbackRate: 1
            )
        )
        withExtendedLifetime(bridge) {}
    }

    func testRemoteCommandsForwardExactlyOnce() async {
        let controller = FakePlaybackController(
            state: state(isPlaying: false)
        )
        let session = FakeNowPlayingSession()
        let bridge = NowPlayingBridge(
            controller: controller,
            session: session
        )

        await session.requestPlay()
        await session.requestPause()
        await session.requestNext()
        await session.requestPrevious()
        await session.requestSeek(67)

        XCTAssertEqual(controller.playCount, 1)
        XCTAssertEqual(controller.pauseCount, 1)
        XCTAssertEqual(controller.nextCount, 1)
        XCTAssertEqual(controller.previousCount, 1)
        XCTAssertEqual(controller.lastSeek, 67)
        withExtendedLifetime(bridge) {}
    }

    private func state(isPlaying: Bool) -> PlaybackState {
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
                    artworkReference: "/covers/night.jpg"
                )
            ],
            currentIndex: 0,
            isPlaying: isPlaying,
            position: 23,
            duration: 240,
            volume: 0.8,
            mode: .repeatAll
        )
    }
}

@MainActor
private final class FakePlaybackController: PlaybackControlling {
    var state: PlaybackState
    private var observers: [UUID: (PlaybackState) -> Void] = [:]
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var nextCount = 0
    private(set) var previousCount = 0
    private(set) var lastSeek: TimeInterval?

    init(state: PlaybackState) {
        self.state = state
    }

    func play() async throws {
        playCount += 1
    }

    func pause() throws {
        pauseCount += 1
    }

    func next() async throws {
        nextCount += 1
    }

    func previous() async throws {
        previousCount += 1
    }

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
}

@MainActor
private final class FakeNowPlayingSession: SystemNowPlayingSession {
    var onPlay: (() async -> Void)?
    var onPause: (() async -> Void)?
    var onNext: (() async -> Void)?
    var onPrevious: (() async -> Void)?
    var onSeek: ((TimeInterval) async -> Void)?
    private(set) var info = SystemNowPlayingInfo.empty

    func update(_ info: SystemNowPlayingInfo) {
        self.info = info
    }

    func requestPlay() async { await onPlay?() }
    func requestPause() async { await onPause?() }
    func requestNext() async { await onNext?() }
    func requestPrevious() async { await onPrevious?() }
    func requestSeek(_ position: TimeInterval) async {
        await onSeek?(position)
    }
}
