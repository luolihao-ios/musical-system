import CryptoKit
import Foundation

public struct TransferEncryptedEnvelope: Codable, Equatable, Sendable {
    public let nonce: Data
    public let ciphertext: Data
    public let tag: Data
}

public enum TransferCrypto {
    public static func deriveSessionKey(
        localPrivateKey: P256.KeyAgreement.PrivateKey,
        remotePublicKey: Data,
        receiverPublicKey: Data,
        senderPublicKey: Data
    ) throws -> SymmetricKey {
        let remote = try P256.KeyAgreement.PublicKey(x963Representation: remotePublicKey)
        let secret = try localPrivateKey.sharedSecretFromKeyAgreement(with: remote)
        let salt = Data(SHA256.hash(data: receiverPublicKey + senderPublicKey))
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: Data("muse-transfer-v2".utf8),
            outputByteCount: 32
        )
    }

    public static func encrypt(_ plaintext: Data, using key: SymmetricKey, associatedData: Data, nonce: Data? = nil) throws -> TransferEncryptedEnvelope {
        let aesNonce = try nonce.map(AES.GCM.Nonce.init(data:)) ?? AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: aesNonce, authenticating: associatedData)
        return TransferEncryptedEnvelope(nonce: Data(aesNonce), ciphertext: sealed.ciphertext, tag: sealed.tag)
    }

    public static func decrypt(_ envelope: TransferEncryptedEnvelope, using key: SymmetricKey, associatedData: Data) throws -> Data {
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: envelope.nonce), ciphertext: envelope.ciphertext, tag: envelope.tag)
        return try AES.GCM.open(box, using: key, authenticating: associatedData)
    }

    public static func verificationCode(sessionKey: SymmetricKey, manifestDigest: String) -> String {
        let code = HMAC<SHA256>.authenticationCode(for: Data(manifestDigest.utf8), using: sessionKey)
        let bytes = Array(code.prefix(4))
        let value = UInt32(bytes[0]) | UInt32(bytes[1]) << 8 | UInt32(bytes[2]) << 16 | UInt32(bytes[3]) << 24
        return String(format: "%06u", value % 1_000_000)
    }

    public static func data(of key: SymmetricKey) -> Data { key.withUnsafeBytes { Data($0) } }
}
