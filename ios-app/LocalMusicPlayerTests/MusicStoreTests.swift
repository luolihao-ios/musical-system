import SwiftData
import XCTest
@testable import LocalMusicPlayer

@MainActor
final class MusicStoreTests: XCTestCase {
    func testTrackLikeAndPlaybackPreferencesRoundTrip() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let track = makeTrack(id: "track-1", title: "落日之前")

        try store.upsert(track)
        try store.setLiked(trackID: track.id, isLiked: true)
        try store.recordPlay(
            trackID: track.id,
            at: Date(timeIntervalSince1970: 1_785_390_000)
        )
        let preferences = PlaybackPreferences(
            volume: 0.35,
            mode: .shuffle,
            lastTrackID: track.id,
            lastPosition: 73
        )
        try store.savePlaybackPreferences(preferences)

        let reopened = try MusicStore(context: container.mainContext)
        XCTAssertEqual(try reopened.tracks().map(\.id), ["track-1"])
        XCTAssertTrue(try reopened.tracks()[0].isLiked)
        XCTAssertNotNil(try reopened.tracks()[0].lastPlayedAt)
        XCTAssertEqual(try reopened.loadPlaybackPreferences(), preferences)
    }

    func testCustomPlaylistPreservesOrderAndLikedPlaylistIsProtected() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let first = makeTrack(id: "one", title: "第一首")
        let second = makeTrack(id: "two", title: "第二首")
        try store.upsert(first)
        try store.upsert(second)

        let playlist = try store.createPlaylist(name: "夜行歌单")
        try store.add(trackID: second.id, to: playlist.id, position: 0)
        try store.add(trackID: first.id, to: playlist.id, position: 1)

        XCTAssertEqual(
            try store.playlistTracks(playlistID: playlist.id).map(\.id),
            ["two", "one"]
        )
        try store.moveTracks(
            in: playlist.id,
            fromOffsets: IndexSet(integer: 0),
            toOffset: 2
        )
        XCTAssertEqual(
            try store.playlistTracks(playlistID: playlist.id).map(\.id),
            ["one", "two"]
        )
        XCTAssertTrue(try store.renamePlaylist(id: playlist.id, name: "深夜收藏"))
        XCTAssertFalse(
            try store.renamePlaylist(
                id: MusicStore.likedPlaylistID,
                name: "不能改名"
            )
        )
        XCTAssertFalse(try store.deletePlaylist(id: MusicStore.likedPlaylistID))
        XCTAssertTrue(try store.deletePlaylist(id: playlist.id))
    }

    func testUpsertUpdatesMetadataWithoutLosingLike() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let original = makeTrack(id: "stable", title: "旧标题")
        try store.upsert(original)
        try store.setLiked(trackID: original.id, isLiked: true)

        let moved = makeTrack(id: "stable", title: "新标题")
        moved.sourceReference = "ImportedMusic/stable/audio.m4a"
        try store.upsert(moved)

        let stored = try XCTUnwrap(store.track(id: "stable"))
        XCTAssertEqual(stored.title, "新标题")
        XCTAssertEqual(stored.sourceReference, "ImportedMusic/stable/audio.m4a")
        XCTAssertTrue(stored.isLiked)
    }

    func testAddingWithoutPositionAppendsToPlaylist() throws {
        let container = try ModelContainerFactory.make(inMemory: true)
        let store = try MusicStore(context: container.mainContext)
        let first = makeTrack(id: "first", title: "第一首")
        let second = makeTrack(id: "second", title: "第二首")
        try store.upsert(first)
        try store.upsert(second)
        let playlist = try store.createPlaylist(name: "顺序测试")

        try store.add(trackID: first.id, to: playlist.id)
        try store.add(trackID: second.id, to: playlist.id)

        XCTAssertEqual(
            try store.playlistTracks(playlistID: playlist.id).map(\.id),
            ["first", "second"]
        )
    }

    private func makeTrack(id: String, title: String) -> TrackRecord {
        TrackRecord(
            id: id,
            title: title,
            artist: "测试歌手",
            album: "测试专辑",
            duration: 180,
            sourceKind: .importedFile,
            sourceReference: "ImportedMusic/\(id)/audio.m4a"
        )
    }
}
