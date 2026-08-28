import CryptoKit
import XCTest
@testable import MuseTransferCore

final class CryptoVectorTests: XCTestCase {
    func testP256HKDFAESGCMAndVerificationCodeMatchSharedVector() throws {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "crypto-v2", withExtension: "json"))
        let vector = try JSONDecoder().decode(CryptoVector.self, from: Data(contentsOf: url))
        let receiver = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: vector.receiverPrivate)!)
        let sender = try P256.KeyAgreement.PrivateKey(rawRepresentation: Data(base64Encoded: vector.senderPrivate)!)
        XCTAssertEqual(receiver.publicKey.x963Representation.base64EncodedString(), vector.receiverPublic)
        XCTAssertEqual(sender.publicKey.x963Representation.base64EncodedString(), vector.senderPublic)

        let key = try TransferCrypto.deriveSessionKey(
            localPrivateKey: sender,
            remotePublicKey: Data(base64Encoded: vector.receiverPublic)!,
            receiverPublicKey: Data(base64Encoded: vector.receiverPublic)!,
            senderPublicKey: Data(base64Encoded: vector.senderPublic)!
        )
        XCTAssertEqual(TransferCrypto.data(of: key).base64EncodedString(), vector.derivedKey)
        let envelope = try TransferCrypto.encrypt(
            Data(base64Encoded: vector.plaintext)!, using: key,
            associatedData: Data(base64Encoded: vector.associatedData)!,
            nonce: Data(base64Encoded: vector.nonce)!
        )
        XCTAssertEqual(envelope.ciphertext.base64EncodedString(), vector.ciphertext)
        XCTAssertEqual(envelope.tag.base64EncodedString(), vector.tag)
        XCTAssertEqual(try TransferCrypto.decrypt(envelope, using: key, associatedData: Data(base64Encoded: vector.associatedData)!), Data(base64Encoded: vector.plaintext)!)
        XCTAssertEqual(TransferCrypto.verificationCode(sessionKey: key, manifestDigest: "manifest-digest"), vector.verificationCode)
    }

    private struct CryptoVector: Decodable {
        let receiverPrivate: String; let receiverPublic: String
        let senderPrivate: String; let senderPublic: String
        let derivedKey: String; let nonce: String; let plaintext: String
        let associatedData: String; let ciphertext: String; let tag: String
        let verificationCode: String
    }
}
