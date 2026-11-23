import XCTest
@testable import LocalMusicPlayer

final class MiniPlayerVisibilityTests: XCTestCase {
    func testPlayingAgainShowsMiniPlayer() {
        var visibility = MiniPlayerVisibility()
        visibility.dismiss()
        XCTAssertFalse(visibility.isVisible)
        visibility.show()
        XCTAssertTrue(visibility.isVisible)
    }
}
