import Foundation

// 串行后台写入，避免磁盘 I/O 卡住拖拽。文件可在“文件 > 我的 iPhone > 爱乐之城”导出。
enum PlayerInteractionDiagnostics {
    private static let queue = DispatchQueue(label: "music.player.interaction.log", qos: .utility)
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("music-player-interaction.log")
    }

    static func log(_ message: String) {
        let line = "\(Date().timeIntervalSince1970) \(message)\n"
        let url = fileURL
        queue.async {
            let fm = FileManager.default
            if let attributes = try? fm.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber, size.intValue > 2_000_000 {
                let previous = url.appendingPathExtension("previous")
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: url, to: previous)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: Data(line.utf8))
            } catch { /* 日志失败不影响播放。 */ }
        }
    }

    static func beginSession() {
        let info = Bundle.main.infoDictionary ?? [:]
        log("session version=\(info["CFBundleShortVersionString"] ?? "?") build=\(info["CFBundleVersion"] ?? "?") implementation=single-panel-v1 os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
    }
}
