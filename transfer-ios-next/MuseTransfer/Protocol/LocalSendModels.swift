import Foundation

public struct DeviceInfo: Codable, Equatable, Sendable {
    public let alias: String
    public let version: String
    public let deviceModel: String
    public let deviceType: String
    public let fingerprint: String
    public let port: Int
    public let protocolName: String
    public let download: Bool
    public let announce: Bool

    enum CodingKeys: String, CodingKey { case alias, version, deviceModel, deviceType, fingerprint, port; case protocolName = "protocol"; case download, announce }
    public init(alias: String, version: String = "2.0", deviceModel: String, deviceType: String, fingerprint: String, port: Int = 53317, protocolName: String = "http", download: Bool = true, announce: Bool = true) {
        self.alias = alias; self.version = version; self.deviceModel = deviceModel; self.deviceType = deviceType; self.fingerprint = fingerprint; self.port = port; self.protocolName = protocolName; self.download = download; self.announce = announce
    }
}

public struct FileMetadata: Codable, Equatable, Sendable {
    public let id: String; public let fileName: String; public let size: Int64; public let fileType: String; public let sha256: String?
    public init(id: String, fileName: String, size: Int64, fileType: String, sha256: String? = nil) { self.id = id; self.fileName = fileName; self.size = size; self.fileType = fileType; self.sha256 = sha256 }
}

public struct PrepareUploadRequest: Codable, Equatable, Sendable {
    public let info: DeviceInfo; public let files: [String: FileMetadata]
    public init(info: DeviceInfo, files: [String: FileMetadata]) { self.info = info; self.files = files }
}

public struct PrepareUploadResponse: Codable, Equatable, Sendable {
    public let sessionId: String
    public let files: [String: String]
}
