import Foundation

enum PlaybackDiagnostics {
    private static let lock = NSLock()
    static func log(_ message: String) {
        #if DEBUG
        // 云端单元测试也保留边界证据；真机仍自动写 Documents 文件。
        print("[PlaybackDiagnostics] \(message)")
        #endif
        lock.lock()
        defer { lock.unlock() }
        guard let documents = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return
        }
        let url = documents.appendingPathComponent("music-playback-diagnostics.log")
        try? FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? NSNumber, size.intValue > 2_000_000 {
            let previous = url.appendingPathExtension("previous")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: url, to: previous)
        }
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(DiagnosticTimestamp.string()) \(message)\n".utf8))
    }
}
