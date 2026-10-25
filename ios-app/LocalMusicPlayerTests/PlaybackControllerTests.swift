import Foundation
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class PlaybackControllerTests: XCTestCase {
    func testLateFailedLoadDoesNotStopNewerPlayback() async throws {
        let engine = FakeAudioEngine()
        engine.suspendsLoads = true
        let controller = PlaybackController(engine: engine, preferencesStore: FakePreferencesStore())
        let queue = [track("one"), track("two")]
        let first = Task { try await controller.playTrack(queue[0], in: queue) }
        while engine.loadedURLs.count < 1 { await Task.yield() }
        let second = Task { try await controller.playTrack(queue[1], in: queue) }
        while engine.loadedURLs.count < 2 { await Task.yield() }
        engine.completeLoad(trackID: "two")
        try await second.value
        engine.failLoad(trackID: "one")
        _ = try? await first.value
        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertTrue(controller.state.isPlaying)
        XCTAssertEqual(engine.unloadCount, 0)
    }

    func testPauseDuringLoadDoesNotAutoplayWhenLoadFinishes() async throws {
        let engine = FakeAudioEngine()
        engine.suspendsLoads = true
        let controller = PlaybackController(engine: engine, preferencesStore: FakePreferencesStore())
        let song = track("one")
        let pending = Task { try await controller.playTrack(song, in: [song]) }
        while engine.loadedURLs.isEmpty { await Task.yield() }
        try controller.pause()
        engine.completeLoad(trackID: "one")
        try await pending.value
        XCTAssertFalse(controller.state.isPlaying)
        XCTAssertEqual(engine.playCount, 0)
    }

    func testOnlinePreviewReplacesLocalTrackInSharedPlayback() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(engine: engine, preferencesStore: FakePreferencesStore())
        let local = track("local")
        try await controller.playTrack(local, in: [local])
        let preview = CatalogTrack(id: "jamendo-7", title: "雨夜", artist: "歌手",
            audioURL: URL(string: "https://example.org/song.mp3")!, license: .publicDomain,
            previewURL: URL(string: "https://example.org/preview.mp3")!).previewSnapshot()
        let song = try XCTUnwrap(preview)
        try await controller.playTrack(song, in: [song])
        XCTAssertEqual(controller.state.currentTrack?.title, "雨夜")
        XCTAssertEqual(controller.state.queue.count, 1)
        XCTAssertEqual(engine.loadedURLs.last?.absoluteString, "https://example.org/preview.mp3")
        XCTAssertFalse(engine.loadedURLs.last!.isFileURL)
        XCTAssertTrue(controller.state.isPlaying)
        try await controller.playTrack(local, in: [local])
        XCTAssertEqual(controller.state.currentTrack?.id, "local")
    }

    func testStreamDurationUpdatesAfterMetadataArrives() async throws {
        let engine = FakeAudioEngine()
        engine.duration = 0
        let controller = PlaybackController(engine: engine, preferencesStore: FakePreferencesStore())
        let stream = TrackSnapshot(id: "stream", title: "在线", artist: "歌手", album: "", duration: 0,
            sourceKind: .onlinePreview, sourceReference: "https://example.org/audio.mp3")
        try await controller.playTrack(stream, in: [stream])
        XCTAssertEqual(controller.state.duration, 0)
        engine.duration = 123
        engine.onPositionChanged?(5)
        XCTAssertEqual(controller.state.duration, 123)
        XCTAssertEqual(controller.state.position, 5)
    }

    func testCoverRefreshPreservesAudioAndPlaybackProgress() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(engine: engine, preferencesStore: FakePreferencesStore())
        let original = track("one")
        try await controller.playTrack(original, in: [original])
        try controller.seek(to: 40)
        let before = controller.state
        let loadCount = engine.loadedURLs.count
        let updated = TrackSnapshot(id: original.id, title: original.title, artist: original.artist,
            album: original.album, duration: original.duration, sourceKind: original.sourceKind,
            sourceReference: original.sourceReference, artworkReference: "/music/artwork-downloaded.jpg")
        controller.refreshTrackMetadata(updated)
        XCTAssertEqual(controller.state.currentTrack?.artworkReference, "/music/artwork-downloaded.jpg")
        XCTAssertEqual(controller.state.position, before.position)
        XCTAssertEqual(controller.state.isPlaying, before.isPlaying)
        XCTAssertEqual(engine.loadedURLs.count, loadCount)
    }
    func testPlayTrackOverridesRestoredTrackAndStartsAtZero() async throws {
        let engine = FakeAudioEngine()
        engine.position = 37
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore(
                value: PlaybackPreferences(
                    volume: 1,
                    mode: .repeatAll,
                    lastTrackID: "one",
                    lastPosition: 37
                )
            )
        )
        try controller.initialize()
        let queue = [track("one"), track("two")]

        try await controller.playTrack(queue[1], in: queue)

        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertEqual(controller.state.position, 0)
        XCTAssertEqual(
            engine.loadedURLs.last?.lastPathComponent,
            "two.m4a"
        )
        XCTAssertEqual(engine.lastSeek, 0)
        XCTAssertTrue(controller.state.isPlaying)
    }

    func testStaleAudioLoadCannotStartAfterNewerTrack() async throws {
        let engine = FakeAudioEngine()
        engine.suspendsLoads = true
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("one"), track("two")]

        let first = Task {
            try await controller.playTrack(queue[0], in: queue)
        }
        await Task.yield()
        let second = Task {
            try await controller.playTrack(queue[1], in: queue)
        }
        await Task.yield()
        engine.completeLoad(trackID: "two")
        try await second.value
        engine.completeLoad(trackID: "one")
        try await first.value

        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertEqual(engine.playedURLs.map(\.lastPathComponent), ["two.m4a"])
    }

    func testPlayTrackPublishesOnlyConsistentTargetSnapshots() async throws {
        let controller = PlaybackController(
            engine: FakeAudioEngine(),
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("one"), track("two")]
        try await controller.playTrack(queue[0], in: queue)
        var snapshots: [PlaybackState] = []
        let observerID = controller.observeState { snapshots.append($0) }
        snapshots.removeAll()

        try await controller.playTrack(queue[1], in: queue)

        XCTAssertFalse(snapshots.isEmpty)
        XCTAssertTrue(snapshots.allSatisfy { snapshot in
            guard snapshot.currentTrack?.id == "two" else { return false }
            return snapshot.currentIndex == 1
                && snapshot.position == 0
                && snapshot.duration == 180
        })
        controller.removeStateObserver(observerID)
    }

    func testFailedAudioLoadDoesNotLeaveTrackMarkedAsPlaying() async throws {
        let engine = FakeAudioEngine()
        engine.loadError = PlaybackTestError.failedToLoad
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("broken")]

        do {
            try await controller.playTrack(queue[0], in: queue)
            XCTFail("Expected the audio load error to be propagated")
        } catch {
            XCTAssertEqual(error as? PlaybackTestError, .failedToLoad)
        }

        XCTAssertNil(controller.state.currentTrack)
        XCTAssertFalse(controller.state.isPlaying)
        XCTAssertEqual(controller.state.position, 0)
        XCTAssertEqual(controller.state.duration, 0)
        XCTAssertGreaterThanOrEqual(engine.unloadCount, 1)
    }

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
        try controller.restoreQueueIfPossible([track("one"), track("two")])
        try await controller.play()
        try controller.seek(to: 999)

        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertEqual(controller.state.volume, 0.4)
        XCTAssertEqual(controller.state.mode, .shuffle)
        XCTAssertEqual(engine.lastSeek, 180)
        XCTAssertEqual(preferences.saved.lastPosition, 180)
    }

    func testRestoreQueueDoesNothingWithoutSavedTrack() throws {
        let controller = PlaybackController(
            engine: FakeAudioEngine(),
            preferencesStore: FakePreferencesStore()
        )
        try controller.initialize()

        try controller.restoreQueueIfPossible([track("one")])

        XCTAssertNil(controller.state.currentTrack)
        XCTAssertTrue(controller.state.queue.isEmpty)
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

    func testMovingQueueKeepsCurrentTrackAndRepairsIndex() async throws {
        let controller = PlaybackController(
            engine: FakeAudioEngine(),
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("one"), track("two"), track("three")]
        try await controller.playTrack(queue[1], in: queue)

        try controller.moveQueue(
            fromOffsets: IndexSet(integer: 0),
            toOffset: 3
        )

        XCTAssertEqual(controller.state.queue.map(\.id), ["two", "three", "one"])
        XCTAssertEqual(controller.state.currentTrack?.id, "two")
        XCTAssertEqual(controller.state.currentIndex, 0)
    }

    func testRemovingCurrentTrackPlaysNextTrack() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("one"), track("two"), track("three")]
        try await controller.playTrack(queue[1], in: queue)

        try await controller.removeQueueItems(
            atOffsets: IndexSet(integer: 1)
        )

        XCTAssertEqual(controller.state.queue.map(\.id), ["one", "three"])
        XCTAssertEqual(controller.state.currentTrack?.id, "three")
        XCTAssertEqual(engine.loadedURLs.last?.lastPathComponent, "three.m4a")
        XCTAssertTrue(controller.state.isPlaying)
    }

    func testRemovingCurrentTrackSkipsUnavailableSuccessor() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        try controller.loadQueue([
            track("one"),
            track("missing", available: false),
            track("three")
        ])
        try await controller.play()

        try await controller.removeQueueItems(
            atOffsets: IndexSet(integer: 0)
        )

        XCTAssertEqual(controller.state.currentTrack?.id, "three")
        XCTAssertEqual(controller.state.queue.map(\.id), ["three"])
        XCTAssertEqual(engine.loadedURLs.last?.lastPathComponent, "three.m4a")
    }

    func testRemovingLastCurrentTrackWrapsToFirstTrack() async throws {
        let controller = PlaybackController(
            engine: FakeAudioEngine(),
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("one"), track("two"), track("three")]
        try await controller.playTrack(queue[2], in: queue)

        try await controller.removeQueueItems(
            atOffsets: IndexSet(integer: 2)
        )

        XCTAssertEqual(controller.state.currentTrack?.id, "one")
        XCTAssertEqual(controller.state.currentIndex, 0)
    }

    func testRemovingOnlyTrackStopsAndClearsPlayback() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        let only = track("only")
        try await controller.playTrack(only, in: [only])

        try await controller.removeQueueItems(
            atOffsets: IndexSet(integer: 0)
        )

        XCTAssertTrue(controller.state.queue.isEmpty)
        XCTAssertNil(controller.state.currentTrack)
        XCTAssertFalse(controller.state.isPlaying)
        XCTAssertEqual(controller.state.position, 0)
        XCTAssertEqual(controller.state.duration, 0)
        XCTAssertEqual(engine.unloadCount, 1)
    }

    func testClearQueueStopsUnloadsAndClearsState() async throws {
        let engine = FakeAudioEngine()
        let controller = PlaybackController(
            engine: engine,
            preferencesStore: FakePreferencesStore()
        )
        let queue = [track("one"), track("two")]
        try await controller.playTrack(queue[0], in: queue)

        try controller.clearQueue()

        XCTAssertTrue(controller.state.queue.isEmpty)
        XCTAssertNil(controller.state.currentIndex)
        XCTAssertFalse(controller.state.isPlaying)
        XCTAssertEqual(controller.state.position, 0)
        XCTAssertEqual(controller.state.duration, 0)
        XCTAssertGreaterThanOrEqual(engine.pauseCount, 1)
        XCTAssertEqual(engine.unloadCount, 1)
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
    private(set) var playedURLs: [URL] = []
    private(set) var lastSeek: TimeInterval?
    private(set) var playCount = 0
    private(set) var pauseCount = 0
    private(set) var unloadCount = 0
    var suspendsLoads = false
    var loadError: Error?
    private var currentURL: URL?
    private var loadContinuations:
        [String: CheckedContinuation<Void, Error>] = [:]

    func load(url: URL) async throws {
        loadedURLs.append(url)
        currentURL = url
        position = 0
        if let loadError {
            throw loadError
        }
        if suspendsLoads {
            let trackID = url.deletingPathExtension().lastPathComponent
            try await withCheckedThrowingContinuation { continuation in
                loadContinuations[trackID] = continuation
            }
        }
    }

    func play() {
        isPlaying = true
        playCount += 1
        if let currentURL {
            playedURLs.append(currentURL)
        }
    }

    func pause() {
        isPlaying = false
        pauseCount += 1
    }

    func seek(to position: TimeInterval) {
        self.position = position
        lastSeek = position
        onPositionChanged?(position)
    }

    func unload() {
        isPlaying = false
        position = 0
        unloadCount += 1
    }

    func completeLoad(trackID: String) {
        loadContinuations.removeValue(forKey: trackID)?.resume()
    }

    func failLoad(trackID: String) {
        loadContinuations.removeValue(forKey: trackID)?.resume(throwing: PlaybackTestError.failedToLoad)
    }

    func finish() async {
        await onEnded?()
    }
}

private enum PlaybackTestError: Error, Equatable {
    case failedToLoad
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
