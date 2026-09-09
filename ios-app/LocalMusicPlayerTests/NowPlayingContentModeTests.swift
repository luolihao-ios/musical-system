import XCTest
@testable import LocalMusicPlayer

final class NowPlayingContentModeTests: XCTestCase {
    func testArtworkTapWithLyricsShowsLyrics() {
        XCTAssertEqual(
            NowPlayingContentMode.modeAfterArtworkTap(hasLyrics: true),
            .lyrics
        )
    }

    func testLyricsToggleReturnsToArtwork() {
        XCTAssertEqual(
            NowPlayingContentMode.modeAfterLyricsToggle,
            .artwork
        )
    }
}
