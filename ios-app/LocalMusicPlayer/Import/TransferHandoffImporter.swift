import CryptoKit
import Foundation

@MainActor
final class TransferHandoffImporter {
    private struct Document: Codable { let version: Int; let handoffId: String; let items: [Item] }
    private struct Item: Codable { let relativePath, sha256, kind: String }
    private let importer: FileImportService
    private let store: MusicStore
    private let defaults: UserDefaults
    private let fileManager: FileManager

    init(importer: FileImportService, store: MusicStore, defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        self.importer = importer; self.store = store; self.defaults = defaults; self.fileManager = fileManager
    }

    func importURL(_ url: URL) async throws {
        if url.isFileURL, url.pathExtension.lowercased() == "aiyuepack" {
            let imported = try await importer.importFiles([ImportedFile(sourceURL: url, kind: .package)])
            for track in imported { try store.upsert(track) }
            return
        }
        guard url.scheme == "musemusic", url.host == "import",
              let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "handoff" })?.value,
              id.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0.value == 45 }) else { return }
        let processedKey = "ProcessedMusicHandoff.\(id)"; guard !defaults.bool(forKey: processedKey) else { return }
        // App Store builds may not include the optional shared App Group entitlement.
        // Direct .aiyuepack imports remain supported; a URL handoff is ignored when
        // the shared container is unavailable rather than failing the app launch.
        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.aiyuetransfer") else { return }
        let root = group.appending(path: "MusicHandoff/\(id)", directoryHint: .isDirectory)
        let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: root.appending(path: "music-handoff-v1.json")))
        guard document.version == 1, document.handoffId == id else { return }
        var files: [ImportedFile] = []
        for item in document.items {
            let target = root.appending(path: item.relativePath).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/"), try hash(target).caseInsensitiveCompare(item.sha256) == .orderedSame else { return }
            files.append(ImportedFile(sourceURL: target, kind: item.kind == "lyrics" ? .lyrics : item.kind == "cover" ? .cover : .audio))
        }
        let tracks = try await importer.importFiles(files)
        for track in tracks { try store.upsert(track) }
        defaults.set(true, forKey: processedKey)
        try? fileManager.removeItem(at: root)
    }

    private func hash(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }; var hasher = SHA256()
        while let data = try handle.read(upToCount: 64 * 1024), !data.isEmpty { hasher.update(data: data) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
