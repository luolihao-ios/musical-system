import XCTest
@testable import LocalMusicPlayer

final class AdaptivePlayerLayoutTests: XCTestCase {
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
        for size in [CGSize.zero, CGSize(width: -1, height: 0), CGSize(width: .infinity, height: .nan)] {
            let layout = AdaptivePlayerLayout.resolve(size: size)
            XCTAssertFalse(layout.isWide)
            XCTAssertTrue(layout.artworkSide.isFinite)
            XCTAssertGreaterThanOrEqual(layout.artworkSide, 0)
        }
    }
}
