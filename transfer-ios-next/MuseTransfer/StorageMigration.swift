import Foundation

enum TransferStorage {
    static let appGroupID = "group.com.luolihao.aiyuetransfer"
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static func mirrorForMusicPlayer(_ source: URL, relativePath: String) {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        let targetRoot = group.appendingPathComponent("MusicHandoff", isDirectory: true)
        let target = targetRoot.appendingPathComponent(relativePath)
        try? FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: source, to: target)
    }

    /// Earlier builds created Documents/爱乐互传 inside the app Documents container.
    /// Files already presents that container as 爱乐互传, so flatten the legacy folder.
    static func normalize() {
        let legacy = documents.appendingPathComponent("爱乐互传", isDirectory: true)
        for entry in (try? FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)) ?? [] {
            if entry.lastPathComponent.hasPrefix("aiyue-transfer-diagnostics") { try? FileManager.default.removeItem(at: entry) }
        }
        guard FileManager.default.fileExists(atPath: legacy.path) else { return }
        guard let entries = try? FileManager.default.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil) else { return }
        for entry in entries {
            if entry.lastPathComponent.hasPrefix("aiyue-transfer-diagnostics") { try? FileManager.default.removeItem(at: entry); continue }
            var target = documents.appendingPathComponent(entry.lastPathComponent)
            var index = 1
            while FileManager.default.fileExists(atPath: target.path) {
                let base = entry.deletingPathExtension().lastPathComponent
                let suffix = entry.pathExtension.isEmpty ? "" : "." + entry.pathExtension
                target = documents.appendingPathComponent("\(base) (\(index))\(suffix)")
                index += 1
            }
            try? FileManager.default.moveItem(at: entry, to: target)
        }
        try? FileManager.default.removeItem(at: legacy)
        syncDocumentsToMusicPlayer()
    }

    /// Copies files received by older builds into the shared handoff container
    /// so the music player can discover them without accessing this app's
    /// private Documents directory.
    private static func syncDocumentsToMusicPlayer() {
        let fileManager = FileManager.default
        guard let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else {
            DiagnosticLog.write("Shared music handoff container unavailable during migration.")
            return
        }
        let handoffRoot = group.appendingPathComponent("MusicHandoff", isDirectory: true)
        try? fileManager.createDirectory(at: handoffRoot, withIntermediateDirectories: true)
        guard let iterator = fileManager.enumerator(
            at: documents,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return }
        let supported = Set(["mp3", "m4a", "aac", "flac", "wav", "aif", "aiff", "lrc", "jpg", "jpeg", "png", "webp", "aiyuepack"])
        var copied = 0
        for case let source as URL in iterator {
            guard supported.contains(source.pathExtension.lowercased()),
                  let values = try? source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            let relative = String(source.path.dropFirst(documents.path.count + 1))
            guard !relative.hasPrefix("待发送/"), !relative.hasPrefix("爱乐互传/"), !relative.hasPrefix("music-import-diagnostics") else { continue }
            let target = handoffRoot.appendingPathComponent(relative)
            do {
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: source, to: target)
                    copied += 1
                }
            } catch {
                DiagnosticLog.write("Shared music migration failed: \(source.lastPathComponent); \(error.localizedDescription)")
            }
        }
        DiagnosticLog.write("Shared music migration completed; copied=\(copied).")
    }
}
