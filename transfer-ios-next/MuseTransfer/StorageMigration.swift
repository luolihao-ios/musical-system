import Foundation

enum TransferStorage {
    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
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
    }
}
