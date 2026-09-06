import XCTest
@testable import AiyueTransfer

final class WebFileStoreTests: XCTestCase {
    func testRejectsTraversalAndSymlinkAndInternalFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WebFileStore(root: root)
        for path in ["../escape", "/tmp/escape", "a/../../b", "a\\b", "待发送/test", ".secret"] { XCTAssertThrowsError(try store.resolve(path)) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: root.deletingLastPathComponent())
        XCTAssertThrowsError(try store.resolve("link/outside"))
    }
    func testConsecutiveUploadsPreserveChineseNamesAndNeverOverwrite() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try WebFileStore(root: root)
        for i in 0..<2 {
            let temporary = root.appendingPathComponent(".temp")
            try Data([UInt8(i)]).write(to: temporary)
            let saved = try store.save(temporary, as: "音乐/你好.mp3")
            XCTAssertEqual(saved, i == 0 ? "音乐/你好.mp3" : "音乐/你好 (1).mp3")
        }
        let listing = try store.list("音乐")
        XCTAssertEqual(listing.count, 2)
        XCTAssertEqual(try Data(contentsOf: store.resolve("音乐/你好.mp3")), Data([0]))
    }
}
