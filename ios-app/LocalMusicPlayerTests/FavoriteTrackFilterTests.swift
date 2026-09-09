import XCTest
@testable import LocalMusicPlayer

final class FavoriteTrackFilterTests: XCTestCase {
    func testOnlyLikedTracksAreShownInFavorites() {
        let liked = TrackSnapshot(
            id: "liked",
            title: "已收藏",
            artist: "歌手",
            album: "专辑",
            duration: 180,
            sourceKind: .importedFile,
            sourceReference: "/tmp/liked.mp3",
            isAvailable: true,
            isLiked: true
        )
        let unliked = TrackSnapshot(
            id: "unliked",
            title: "未收藏",
            artist: "歌手",
            album: "专辑",
            duration: 180,
            sourceKind: .importedFile,
            sourceReference: "/tmp/unliked.mp3",
            isAvailable: true,
            isLiked: false
        )

        XCTAssertEqual(
            FavoriteTrackFilter.apply([unliked, liked]).map(\.id),
            ["liked"]
        )
    }
}
