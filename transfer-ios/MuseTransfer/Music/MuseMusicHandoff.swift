import CryptoKit
import Foundation
import UIKit

public struct MusicHandoffItem: Codable, Equatable, Sendable {
    public let relativePath: String
    public let sha256: String
    public let kind: String
}

public struct MusicHandoffDocument: Codable, Equatable, Sendable {
    public let version: Int
    public let handoffId: String
    public let createdAt: Date
    public let items: [MusicHandoffItem]
}

@MainActor
public final class MuseMusicHandoff {
    private let fileManager: FileManager
    public init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    public func handoff(files: [OutgoingFile]) async throws -> Bool {
        let supported = Set(["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "lrc"])
        let selected = files.filter { supported.contains($0.url.pathExtension.lowercased()) }
        guard selected.contains(where: { $0.url.pathExtension.lowercased() != "lrc" }) else { return false }
        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.musetransfer") else { return false }
        let id = UUID().uuidString.lowercased()
        let root = group.appending(path: "MusicHandoff/\(id)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        var items: [MusicHandoffItem] = []
        for file in selected {
            let safe = try SafeRelativePath(file.relativePath)
            let target = try safe.resolved(below: root)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let scoped = file.url.startAccessingSecurityScopedResource(); defer { if scoped { file.url.stopAccessingSecurityScopedResource() } }
            try fileManager.copyItem(at: file.url, to: target)
            items.append(MusicHandoffItem(relativePath: file.relativePath, sha256: try hash(target),
                kind: file.url.pathExtension.lowercased() == "lrc" ? "lyrics" : "audio"))
        }
        let document = MusicHandoffDocument(version: 1, handoffId: id, createdAt: Date(), items: items)
        try JSONEncoder().encode(document).write(to: root.appending(path: "music-handoff-v1.json"), options: .atomic)
        guard let url = URL(string: "musemusic://import?handoff=\(id)") else { return false }
        return await UIApplication.shared.open(url)
    }

    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
