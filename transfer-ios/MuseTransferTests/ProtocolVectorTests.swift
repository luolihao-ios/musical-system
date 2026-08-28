import CryptoKit
import XCTest
@testable import MuseTransferCore

final class ProtocolVectorTests: XCTestCase {
    func testCanonicalManifestMatchesSharedVectorByteForByte() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "manifest-v2", withExtension: "json"))
        let vector = try JSONDecoder().decode(ManifestVector.self, from: Data(contentsOf: url))

        let canonical = try ManifestCanonicalizer.canonicalData(vector.manifest)

        XCTAssertEqual(String(decoding: canonical, as: UTF8.self), vector.canonicalUtf8)
        XCTAssertEqual(try ManifestCanonicalizer.sha256Hex(vector.manifest), vector.canonicalSha256)
    }

    private struct ManifestVector: Decodable {
        let manifest: TransferManifest
        let canonicalUtf8: String
        let canonicalSha256: String
    }
}
