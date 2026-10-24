import XCTest
@testable import LocalMusicPlayer

final class AdaptivePlayerLayoutTests: XCTestCase {
    func testShortPositiveWindowKeepsArtworkVisibleInsideScrollablePane() {
        for height: CGFloat in [200, 300, 330, 350] {
            XCTAssertGreaterThanOrEqual(AdaptivePlayerLayout.resolve(size: CGSize(width: 844, height: height)).artworkSide, 120)
        }
        XCTAssertEqual(AdaptivePlayerLayout.resolve(size: CGSize(width: 100, height: 200)).artworkSide, 52)
        XCTAssertEqual(AdaptivePlayerLayout.resolve(size: CGSize(width: 844, height: 0)).artworkSide, 0)
    }
    func testIPhoneAndNarrowWindowRemainSingleColumn() {
        XCTAssertFalse(AdaptivePlayerLayout.resolve(size: CGSize(width: 393, height: 700)).isWide)
        XCTAssertFalse(AdaptivePlayerLayout.resolve(size: CGSize(width: 700, height: 900)).isWide)
        XCTAssertFalse(AdaptivePlayerLayout.resolve(size: CGSize(width: 900, height: 350)).isWide)
    }

    func testIPadUsesTwoColumnsAndLargerArtwork() {
        let layout = AdaptivePlayerLayout.resolve(size: CGSize(width: 1024, height: 1200))
        XCTAssertTrue(layout.isWide)
        XCTAssertGreaterThan(layout.artworkSide, 390)
        XCTAssertLessThanOrEqual(layout.artworkSide, layout.columnWidth)
    }

    func testDuoResolvesByAvailableSpaceRatherThanPhoneIdiom() {
        XCTAssertFalse(AdaptivePlayerLayout.resolve(size: CGSize(width: 466, height: 678)).isWide)
        XCTAssertTrue(AdaptivePlayerLayout.resolve(size: CGSize(width: 956, height: 669)).isWide)
    }

    func testWideBoundaryAndInvalidSizes() {
        XCTAssertFalse(AdaptivePlayerLayout.resolve(size: CGSize(width: 719, height: 900)).isWide)
        XCTAssertTrue(AdaptivePlayerLayout.resolve(size: CGSize(width: 720, height: 900)).isWide)
        for size in [CGSize.zero, CGSize(width: -1, height: 0), CGSize(width: CGFloat.infinity, height: CGFloat.nan)] {
            let layout = AdaptivePlayerLayout.resolve(size: size)
            XCTAssertFalse(layout.isWide)
            XCTAssertTrue(layout.artworkSide.isFinite)
            XCTAssertGreaterThanOrEqual(layout.artworkSide, 0)
        }
    }

    func testBottomMenuAndSideMenuUseDifferentClearance() {
        let window = CGRect(x: 0, y: 0, width: 1024, height: 1366)
        XCTAssertEqual(AdaptivePlayerLayout.menuClearance(window: window,
            menu: CGRect(x: 100, y: 1260, width: 824, height: 80), bottomInset: 20), 114)
        XCTAssertEqual(AdaptivePlayerLayout.menuClearance(window: window,
            menu: CGRect(x: 0, y: 0, width: 80, height: 1366), bottomInset: 20), 28)
        XCTAssertEqual(AdaptivePlayerLayout.menuClearance(window: window,
            menu: nil, bottomInset: 20), 28)
        XCTAssertEqual(AdaptivePlayerLayout.menuClearance(window: window,
            menu: CGRect(x: 0, y: 0, width: 1024, height: 60), bottomInset: 20), 28)
    }
}
