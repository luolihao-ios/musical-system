import XCTest
@testable import AiyueTransfer

final class BrowserTransferPortTests: XCTestCase {
    func testNextPortIncrementsFrom8080AndWrapsAt8099() {
        XCTAssertEqual(BrowserTransferServer.nextPort(after: 8080), 8081)
        XCTAssertEqual(BrowserTransferServer.nextPort(after: 8081), 8082)
        XCTAssertEqual(BrowserTransferServer.nextPort(after: 8099), 8080)
        XCTAssertEqual(BrowserTransferServer.nextPort(after: 0), 8080)
    }
}
