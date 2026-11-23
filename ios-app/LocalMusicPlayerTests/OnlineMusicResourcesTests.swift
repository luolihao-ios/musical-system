import XCTest
@testable import LocalMusicPlayer

final class OnlineMusicResourcesTests: XCTestCase {
    func testMatchingRejectsOtherArtistsAndVersions() {
        let query = MusicResourceQuery(title: "你好", artist: "歌手", album: "", duration: 180)
        XCTAssertTrue(OnlineMusicResources.matches(query, title: "你好", artist: "歌手", duration: 181))
        XCTAssertFalse(OnlineMusicResources.matches(query, title: "你好", artist: "其他歌手", duration: 180))
        XCTAssertFalse(OnlineMusicResources.matches(query, title: "你好 (Live)", artist: "歌手", duration: 180))
        XCTAssertFalse(OnlineMusicResources.matches(query, title: "你好", artist: "歌手", duration: 220))
    }

    func testMatchingAcceptsBenignReleaseSuffixWithoutArtistMetadata() {
        let query = MusicResourceQuery(title: "游京", artist: "", album: "", duration: 189.9)
        XCTAssertTrue(OnlineMusicResources.matches(query, title: "游京 (Album Version)", artist: "海伦", duration: 189.882))
    }
}
