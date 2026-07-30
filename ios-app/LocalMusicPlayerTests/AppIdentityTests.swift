import XCTest
@testable import LocalMusicPlayer

final class AppIdentityTests: XCTestCase {
    func testDisplayName() {
        XCTAssertEqual(AppIdentity.displayName, "暮色音乐")
    }
}
