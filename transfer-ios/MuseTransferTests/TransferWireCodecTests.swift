import XCTest
@testable import MuseTransferCore

final class TransferWireCodecTests: XCTestCase {
    func testRequestParserRejectsOversizedHeaders() {
        let data = Data(("GET /v2/sessions/id HTTP/1.1\r\nX-Large: " + String(repeating: "a", count: 17_000) + "\r\n\r\n").utf8)
        XCTAssertThrowsError(try TransferHTTPRequest.parse(data, maximumHeaderBytes: 16_384, maximumBodyBytes: 1024))
    }

    func testEnvelopeBinaryPackingMatchesProtocolLayout() throws {
        let envelope = TransferEncryptedEnvelope(nonce: Data(repeating: 1, count: 12), ciphertext: Data([4, 5, 6]), tag: Data(repeating: 2, count: 16))
        let packed = try TransferEnvelopeCodec.pack(envelope)
        XCTAssertEqual(packed.count, 31)
        XCTAssertEqual(try TransferEnvelopeCodec.unpack(packed), envelope)
    }

    func testManualEndpointRequiresHostAndValidPort() throws {
        XCTAssertEqual(try TransferEndpoint(manualAddress: "192.168.1.2:53317").port, 53_317)
        XCTAssertThrowsError(try TransferEndpoint(manualAddress: "192.168.1.2"))
        XCTAssertThrowsError(try TransferEndpoint(manualAddress: "host:70000"))
    }
}
