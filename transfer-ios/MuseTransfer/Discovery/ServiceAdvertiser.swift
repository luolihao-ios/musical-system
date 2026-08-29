import Foundation
import Network

public struct TransferServiceIdentity: Sendable {
    public let id: String
    public let name: String
    public let platform: String
    public let publicKey: Data

    public init(id: String, name: String, platform: String = "ios", publicKey: Data) {
        self.id = id; self.name = name; self.platform = platform; self.publicKey = publicKey
    }
}

public enum ServiceAdvertiser {
    public static func attach(identity: TransferServiceIdentity, to listener: NWListener) {
        let fingerprint = identity.publicKey.prefix(8).map { String(format: "%02x", $0) }.joined()
        let record = NWTXTRecord([
            "id": identity.id,
            "name": identity.name,
            "platform": identity.platform,
            "v": "2",
            "pk": identity.publicKey.base64EncodedString(),
            "kid": fingerprint
        ])
        listener.service = NWListener.Service(name: identity.name, type: "_musetransfer._tcp", domain: nil, txtRecord: record)
    }
}
