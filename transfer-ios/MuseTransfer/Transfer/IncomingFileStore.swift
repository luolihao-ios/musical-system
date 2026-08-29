import CryptoKit
import Foundation

public struct FileIntegrityError: Error, Equatable { public let message: String }

public actor IncomingFileStore {
    private let temporaryRoot: URL
    private let fileManager: FileManager

    public init(temporaryRoot: URL, fileManager: FileManager = .default) {
        self.temporaryRoot = temporaryRoot
        self.fileManager = fileManager
    }

    public func writeChunk(sessionID: String, item: TransferItem, index: Int, offset: Int64, bytes: AsyncThrowingStream<Data, Error>) async throws {
        guard index >= 0, offset >= 0 else { throw FileIntegrityError(message: "Invalid chunk position") }
        _ = try SafeRelativePath(item.relativePath)
        let fileURL = try temporaryURL(sessionID: sessionID, itemID: item.id)
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: fileURL.path) { fileManager.createFile(atPath: fileURL.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: fileURL)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        for try await data in bytes { try handle.write(contentsOf: data) }
        try handle.synchronize()
    }

    public func commit(sessionID: String, item: TransferItem, destination: URL) async throws -> URL {
        let temporary = try temporaryURL(sessionID: sessionID, itemID: item.id)
        let attributes = try fileManager.attributesOfItem(atPath: temporary.path)
        guard (attributes[.size] as? NSNumber)?.int64Value == item.size else {
            throw FileIntegrityError(message: "File size does not match manifest")
        }
        let actualHash = try hash(of: temporary)
        guard actualHash.caseInsensitiveCompare(item.sha256) == .orderedSame else {
            throw FileIntegrityError(message: "File hash does not match manifest")
        }
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        let final = try duplicateURL(for: SafeRelativePath(item.relativePath), below: destination)
        try fileManager.createDirectory(at: final.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: temporary, to: final)
        return final
    }

    private func temporaryURL(sessionID: String, itemID: String) throws -> URL {
        guard isSafeIdentifier(sessionID), isSafeIdentifier(itemID) else { throw FileIntegrityError(message: "Invalid session or item identifier") }
        return temporaryRoot.appending(path: sessionID, directoryHint: .isDirectory).appending(path: "\(itemID).part")
    }

    private func duplicateURL(for relativePath: SafeRelativePath, below destination: URL) throws -> URL {
        let original = try relativePath.resolved(below: destination)
        guard fileManager.fileExists(atPath: original.path) else { return original }
        let directory = original.deletingLastPathComponent()
        let stem = original.deletingPathExtension().lastPathComponent
        let suffix = original.pathExtension.isEmpty ? "" : ".\(original.pathExtension)"
        var copy = 2
        while true {
            let candidate = directory.appending(path: "\(stem) (\(copy))\(suffix)")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            copy += 1
        }
    }

    private func hash(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0.value == 45 || $0.value == 95 }
    }
}
