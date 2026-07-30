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
}
