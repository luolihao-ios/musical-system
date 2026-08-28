import Foundation

public struct TransferItem: Codable, Equatable, Sendable {
    public let id: String
    public let relativePath: String
    public let size: Int64
    public let sha256: String

    public init(id: String, relativePath: String, size: Int64, sha256: String) {
        self.id = id; self.relativePath = relativePath; self.size = size; self.sha256 = sha256
    }
}

public struct MusicGroup: Codable, Equatable, Sendable {
    public let id: String
    public let itemIds: [String]

    public init(id: String, itemIds: [String]) { self.id = id; self.itemIds = itemIds }
}

public struct TransferManifest: Codable, Equatable, Sendable {
    public let protocolVersion: Int
    public let senderId: String
    public let items: [TransferItem]
    public let musicGroups: [MusicGroup]

    public init(protocolVersion: Int, senderId: String, items: [TransferItem], musicGroups: [MusicGroup]) {
        self.protocolVersion = protocolVersion; self.senderId = senderId; self.items = items; self.musicGroups = musicGroups
    }
}
