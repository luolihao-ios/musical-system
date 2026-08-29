import SwiftData
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class PlaylistsModelTests: XCTestCase {
    func testCustomPlaylistMutationsAndBuiltInProtection() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let model = PlaylistsModel(store: store)
        try model.reload()

        let playlist = try model.create(name: " 夜行歌单 ")
        XCTAssertTrue(try model.rename(playlist, to: " 深夜收藏 "))
        XCTAssertTrue(try model.delete(
            model.playlists.first { $0.id == playlist.id }!
        ))
        let liked = try XCTUnwrap(
            model.playlists.first(where: \.isBuiltIn)
        )
        XCTAssertFalse(try model.rename(liked, to: "不能改名"))
        XCTAssertFalse(try model.delete(liked))
    }

    func testPlayForwardsSelectedTrackAndWholePlaylistQueue() async throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        try store.upsert(track(id: "one"))
        try store.upsert(track(id: "two"))
        let playback = FakePlaylistPlayback()
        let model = PlaylistsModel(store: store, playback: playback)
        try model.reload()
        let playlist = try model.create(name: "测试歌单")
        try model.add(trackID: "one", to: playlist.id)
        try model.add(trackID: "two", to: playlist.id)
        let tracks = try model.tracks(in: playlist)

        try await model.play(tracks[1], in: playlist)

        XCTAssertEqual(playback.selectedTrack?.id, "two")
        XCTAssertEqual(playback.queue.map(\.id), ["one", "two"])
    }

    private func track(id: String) -> TrackRecord {
        TrackRecord(
            id: id,
            title: id,
            artist: "测试歌手",
            album: "测试专辑",
            duration: 180,
            sourceKind: .importedFile,
            sourceReference: "/music/\(id).m4a"
        )
    }
}

@MainActor
private final class FakePlaylistPlayback: LibraryPlaybackControlling {
    var state = PlaybackState()
    private(set) var selectedTrack: TrackSnapshot?
    private(set) var queue: [TrackSnapshot] = []
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
