import XCTest
@testable import LocalMusicPlayer

final class MiniPlayerGestureTests: XCTestCase {
    func testDraggingDownDismissesMiniPlayer() {
        XCTAssertEqual(
            MiniPlayerGestureAction.resolve(translation: CGSize(width: 0, height: 80)),
            .dismiss
        )
    }

    func testDraggingUpOpensNowPlaying() {
        XCTAssertEqual(
            MiniPlayerGestureAction.resolve(translation: CGSize(width: 0, height: -80)),
            .openNowPlaying
        )
    }

    func testShortDragDoesNothing() {
        XCTAssertEqual(
            MiniPlayerGestureAction.resolve(translation: CGSize(width: 0, height: 12)),
            .none
        )
    }
}
