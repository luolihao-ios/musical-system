import XCTest
@testable import AiyueTransfer

final class BrowserOutboundTaskTests: XCTestCase {
    func testOutboundTaskIsOneShot() {
        let task = BrowserOutboundTask(id: "task-1", name: "测试.pdf", bytes: 12, url: "/tmp/test.pdf")
        XCTAssertEqual(task.id, "task-1")
        XCTAssertEqual(task.name, "测试.pdf")
        XCTAssertEqual(task.bytes, 12)
    }
}
