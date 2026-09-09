import XCTest
@testable import LocalMusicPlayer

final class MiniPlayerDragStateTests: XCTestCase {
    func testUpwardDragTracksProgressFromCompactToExpanded() {
        XCTAssertEqual(
            MiniPlayerDragState.progress(
                translation: -180,
                availableDistance: 600
            ),
            0.3,
            accuracy: 0.001
        )
    }

    func testDownwardDragShrinksExpandedPanelWithFinger() {
        XCTAssertEqual(
            MiniPlayerDragState.progress(
                from: 1,
                translation: 180,
                availableDistance: 600
            ),
            0.7,
            accuracy: 0.001
        )
    }

    func testUpwardReleaseExpandsPanel() {
        XCTAssertEqual(
            MiniPlayerDragState.settle(
                progress: 0.45,
                translation: -270
            ),
            .expand
        )
    }

    func testSufficientDownwardReleaseDismissesPanel() {
        XCTAssertEqual(
            MiniPlayerDragState.settle(
                progress: 0,
                translation: 260
            ),
            .dismiss
        )
    }

    func testSmallDragReturnsToCompactPanel() {
        XCTAssertEqual(
            MiniPlayerDragState.settle(
                progress: 0.12,
                translation: 20
            ),
            .compact
        )
    }
}
