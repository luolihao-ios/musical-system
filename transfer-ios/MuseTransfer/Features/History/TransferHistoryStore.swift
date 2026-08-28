import Foundation

public struct TransferHistoryRecord: Identifiable, Codable, Equatable, Sendable {
    public enum Direction: String, Codable, Sendable { case sent, received }
    public enum Result: String, Codable, Sendable { case completed, rejected, cancelled, failed }
    public let id: UUID
    public let deviceName: String
    public let date: Date
    public let fileNames: [String]
    public let totalBytes: Int64
    public let direction: Direction
    public let result: Result
}

public actor TransferHistoryStore {
    private struct Document: Codable { let version: Int; var records: [TransferHistoryRecord] }
    private let url: URL
    private var records: [TransferHistoryRecord] = []

    public init(url: URL) { self.url = url }
    public func load() throws -> [TransferHistoryRecord] {
        guard FileManager.default.fileExists(atPath: url.path) else { return records }
        records = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url)).records
        return records
    }
    public func append(_ record: TransferHistoryRecord) throws {
        records.insert(record, at: 0); if records.count > 500 { records.removeLast(records.count - 500) }; try persist()
    }
    public func clear() throws { records.removeAll(); try persist() }
    private func persist() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(Document(version: 1, records: records))
        try data.write(to: url, options: .atomic)
    }
}
