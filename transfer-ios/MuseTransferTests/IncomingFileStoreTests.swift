import CryptoKit
import XCTest
@testable import MuseTransferCore

final class IncomingFileStoreTests: XCTestCase {
    func testUnsafePathsAreRejected() {
        for path in ["../escape.mp3", "/root/song.mp3", "C:\\song.mp3", "album/CON/song.mp3"] {
            XCTAssertThrowsError(try SafeRelativePath(path))
        }
    }

    func testVerifiedChunksCommitAtomicallyAndUseDuplicateNames() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "destination", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: destination.appending(path: "song.mp3"))
        let bytes = Data(repeating: 0x5A, count: 512 * 1024)
        let item = TransferItem(id: "f1", relativePath: "song.mp3", size: Int64(bytes.count), sha256: SHA256.hash(data: bytes).hex)
        let store = IncomingFileStore(temporaryRoot: root.appending(path: "incoming", directoryHint: .isDirectory))

        try await store.writeChunk(sessionID: "session-a", item: item, index: 0, offset: 0, bytes: stream(bytes))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["song.mp3"])
        let committed = try await store.commit(sessionID: "session-a", item: item, destination: destination)

        XCTAssertEqual(committed.lastPathComponent, "song (2).mp3")
        XCTAssertEqual(try Data(contentsOf: committed), bytes)
    }

    func testWrongHashNeverPublishesFinalFile() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appending(path: "destination", directoryHint: .isDirectory)
        let bytes = Data("damaged".utf8)
        let item = TransferItem(id: "f1", relativePath: "song.mp3", size: Int64(bytes.count), sha256: String(repeating: "0", count: 64))
        let store = IncomingFileStore(temporaryRoot: root.appending(path: "incoming", directoryHint: .isDirectory))
        try await store.writeChunk(sessionID: "session-b", item: item, index: 0, offset: 0, bytes: stream(bytes))

        do {
            _ = try await store.commit(sessionID: "session-b", item: item, destination: destination)
            XCTFail("Expected integrity verification to fail")
        } catch is FileIntegrityError {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appending(path: "song.mp3").path))
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "MuseTransferTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    private func stream(_ data: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in continuation.yield(data); continuation.finish() }
    }
}

private extension SHA256.Digest {
    var hex: String { map { String(format: "%02x", $0) }.joined() }
}
