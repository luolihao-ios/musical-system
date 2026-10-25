import XCTest
@testable import LocalMusicPlayer

final class CoverArtworkPolicyTests: XCTestCase {
    func testGeneratedArtworkRemainsEligibleButEmbeddedArtworkDoesNot() {
        XCTAssertTrue(CoverArtworkPolicy.needsSearch(path: "/music/artwork-generated.jpg"))
        XCTAssertTrue(CoverArtworkPolicy.needsSearch(path: nil))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/music/artwork"))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/music/artwork-downloaded.jpg"))
    }

    func testSystemLibraryGeneratedCoverIsEligibleWithoutReplacingCustomImages() {
        XCTAssertTrue(CoverArtworkPolicy.needsSearch(path: "/support/SystemArtwork/media-123-generated.jpg"))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/support/SystemArtwork/media-123.jpg"))
        XCTAssertFalse(CoverArtworkPolicy.needsSearch(path: "/music/my-generated.jpg"))
    }
}
