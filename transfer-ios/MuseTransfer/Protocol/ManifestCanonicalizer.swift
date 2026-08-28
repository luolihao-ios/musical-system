import CryptoKit
import Foundation

public enum ManifestCanonicalizationError: Error { case unsupportedVersion(Int) }

public enum ManifestCanonicalizer {
    public static func canonicalData(_ manifest: TransferManifest) throws -> Data {
        guard manifest.protocolVersion == 2 else { throw ManifestCanonicalizationError.unsupportedVersion(manifest.protocolVersion) }
        var json = "{\"protocolVersion\":\(manifest.protocolVersion),\"senderId\":\(quoted(manifest.senderId)),\"items\":["
        json += manifest.items.map { item in
            "{\"id\":\(quoted(item.id)),\"relativePath\":\(quoted(item.relativePath)),\"size\":\(item.size),\"sha256\":\(quoted(item.sha256))}"
        }.joined(separator: ",")
        json += "],\"musicGroups\":["
        json += manifest.musicGroups.map { group in
            let ids = group.itemIds.map(quoted).joined(separator: ",")
            return "{\"id\":\(quoted(group.id)),\"itemIds\":[\(ids)]}"
        }.joined(separator: ",")
        json += "]}"
        return Data(json.utf8)
    }

    public static func sha256Hex(_ manifest: TransferManifest) throws -> String {
        SHA256.hash(data: try canonicalData(manifest)).map { String(format: "%02x", $0) }.joined()
    }

    private static func quoted(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return String(decoding: try! encoder.encode(value), as: UTF8.self)
    }
}
