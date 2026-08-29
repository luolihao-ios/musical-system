import XCTest
@testable import MuseTransferCore

final class TransferSessionTests: XCTestCase {
    func testPendingSessionRequiresExplicitAcceptanceBeforeUpload() throws {
        let clock = MutableTransferClock(now: Date(timeIntervalSince1970: 1_000))
        let store = TransferSessionStore(clock: clock, tokenSecret: Data(repeating: 7, count: 32))
        let manifest = fixtureManifest

        let request = try store.propose(manifest: manifest, senderName: "Windows PC", proposalKey: "proposal-key")

        XCTAssertEqual(request.status, .pending)
        XCTAssertThrowsError(try store.authorizeChunk(sessionID: request.id, token: "", fileID: "f1", chunkIndex: 0))
        let decision = try store.accept(sessionID: request.id, destination: URL(fileURLWithPath: "/tmp/incoming"))
        XCTAssertEqual(decision.status, .accepted)
        XCTAssertNotNil(decision.token)
        XCTAssertNoThrow(try store.authorizeChunk(sessionID: request.id, token: decision.token!, fileID: "f1", chunkIndex: 0))
    }

    func testRejectedSessionCannotBeAccepted() throws {
        let store = TransferSessionStore(tokenSecret: Data(repeating: 9, count: 32))
        let request = try store.propose(manifest: fixtureManifest, senderName: "iPhone", proposalKey: "key")
        try store.reject(sessionID: request.id)
        XCTAssertThrowsError(try store.accept(sessionID: request.id, destination: URL(fileURLWithPath: "/tmp/incoming")))
    }

    func testTokenExpiresAndIsBoundToManifest() throws {
        let clock = MutableTransferClock(now: Date(timeIntervalSince1970: 2_000))
        let store = TransferSessionStore(clock: clock, tokenSecret: Data(repeating: 3, count: 32))
        let request = try store.propose(manifest: fixtureManifest, senderName: "Windows", proposalKey: "key")
        let token = try store.accept(sessionID: request.id, destination: URL(fileURLWithPath: "/tmp/incoming")).token!

        clock.now = clock.now.addingTimeInterval(301)
        XCTAssertThrowsError(try store.authorizeChunk(sessionID: request.id, token: token, fileID: "f1", chunkIndex: 0))
    }

    func testResumeMapContainsOnlyPersistedChunks() throws {
        let store = TransferSessionStore(tokenSecret: Data(repeating: 5, count: 32))
        let request = try store.propose(manifest: fixtureManifest, senderName: "Windows", proposalKey: "key")
        let token = try store.accept(sessionID: request.id, destination: URL(fileURLWithPath: "/tmp/incoming")).token!
        try store.authorizeChunk(sessionID: request.id, token: token, fileID: "f1", chunkIndex: 2)
        try store.recordPersistedChunk(sessionID: request.id, fileID: "f1", chunkIndex: 2)

        XCTAssertEqual(try store.resumeMap(sessionID: request.id, proposalKey: "key"), ["f1": [2]])
    }

    private var fixtureManifest: TransferManifest {
        TransferManifest(protocolVersion: 2, senderId: "sender-a", items: [
            TransferItem(id: "f1", relativePath: "song.mp3", size: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        ], musicGroups: [])
    }
}
