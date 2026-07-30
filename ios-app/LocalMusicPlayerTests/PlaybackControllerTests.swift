import Foundation
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class PlaybackControllerTests: XCTestCase {
    func testNextWrapsAndRepeatOneReplaysCurrentTrack() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        try controller.loadQueue([track("one"), track("two")])
        try await controller.play()
        try await controller.next()
        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        try await controller.next()
        XCTAssertEqual(controller.state.currentTrack?.id, "one")

        try controller.setMode(.repeatOne)
        await engine.finish()
        XCTAssertEqual(controller.state.currentTrack?.id, "one")
        XCTAssertEqual(engine.lastSeek, 0)
        XCTAssertEqual(engine.playCount, 4)
    }

    func testPlaySkipsUnavailableTrackAndPreviousRestartsAfterThreeSeconds() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        try controller.loadQueue([
            track("missing", available: false),
            track("available")
        ])

        try await controller.play()
        engine.position = 10
        try await controller.previous()

        XCTAssertEqual(controller.state.currentTrack?.id, "available")
        XCTAssertEqual(engine.lastSeek, 0)
    }

    func testPreferencesRestoreAndSeekClamps() async throws {
        let engine = FakeAudioEngine()
        engine.duration = 180
        let preferences = FakePreferencesStore(
            value: PlaybackPreferences(
                volume: 0.4,
                mode: .shuffle,
                lastTrackID: "two",
                lastPosition: 42
            )
        )
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: preferences,
            random: FixedRandomIndex()
        )

        try controller.initialize()
        try controller.loadQueue([track("one"), track("two")])
        try await controller.play()
        try controller.seek(to: 999)

        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertEqual(controller.state.volume, 0.4)
        XCTAssertEqual(controller.state.mode, .shuffle)
        XCTAssertEqual(engine.lastSeek, 180)
        XCTAssertEqual(preferences.saved.lastPosition, 180)
    }

    func testVolumeModeAndQueueSelectionAreApplied() async throws {
        let engine = FakeAudioEngine()
        let preferences = FakePreferencesStore()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: preferences
        )
        try controller.loadQueue([track("one"), track("two")])

        try controller.setVolume(0.25)
        try controller.setMode(.shuffle)
        try await controller.playQueueItem(at: 1)

        XCTAssertEqual(controller.state.volume, 0.25)
        XCTAssertEqual(controller.state.mode, .shuffle)
        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertEqual(engine.volume, 0.25)
        XCTAssertEqual(preferences.saved.lastTrackID, "two")
    }

    private func track(
        _ id: String,
        available: Bool = true
    ) -> TrackSnapshot {
        TrackSnapshot(
            id: id,
            title: id,
            artist: "测试歌手",
            album: "测试专辑",
            duration: 180,
            sourceKind: .importedFile,
            sourceReference: "/music/\(id).m4a",
            isAvailable: available
        )
    }
}

@MainActor
private final class FakeAudioEngine: AudioEngine {
    var onEnded: (() async -> Void)?
    var onPositionChanged: ((TimeInterval) -> Void)?
    var duration: TimeInterval = 180
    var position: TimeInterval = 0
    var volume: Float = 1
    var isPlaying = false
    private(set) var loadedURLs: [URL] = []
    private(set) var lastSeek: TimeInterval?
    private(set) var playCount = 0

    func load(url: URL) async throws {
        loadedURLs.append(url)
        position = 0
    }

    func play() {
        isPlaying = true
        playCount += 1
    }

    func pause() {
        isPlaying = false
    }

    func seek(to position: TimeInterval) {
        self.position = position
        lastSeek = position
        onPositionChanged?(position)
    }

    func finish() async {
        await onEnded?()
    }
}

@MainActor
private final class FakePreferencesStore: PlaybackPreferencesStoring {
    var value: PlaybackPreferences
    private(set) var saved = PlaybackPreferences()

    init(value: PlaybackPreferences = PlaybackPreferences()) {
        self.value = value
    }

    func loadPlaybackPreferences() throws -> PlaybackPreferences {
        value
    }

    func savePlaybackPreferences(_ preferences: PlaybackPreferences) throws {
        saved = preferences
        value = preferences
    }
}

@MainActor
private struct FixedRandomIndex: RandomIndexProviding {
    func index(upperBound: Int) -> Int {
        0
    }
}
