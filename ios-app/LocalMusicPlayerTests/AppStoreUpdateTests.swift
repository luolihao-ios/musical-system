import XCTest
@testable import LocalMusicPlayer

final class AppStoreUpdateTests: XCTestCase {
    func testNewerStoreVersionIsAvailable() {
        XCTAssertTrue(AppStoreUpdate.isNewer(storeVersion: "1.2.0", than: "1.1.9"))
        XCTAssertFalse(AppStoreUpdate.isNewer(storeVersion: "1.1", than: "1.1.0"))
    }

    func testMalformedVersionsAreNotConsideredAnUpdate() {
        XCTAssertFalse(AppStoreUpdate.isNewer(storeVersion: "beta", than: "1.0"))
    }
}
