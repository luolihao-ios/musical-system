import Foundation

enum CoverSearchDiagnostics {
    private static let queue = DispatchQueue(label: "music.cover.log", qos: .utility)
    static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("music-cover-diagnostics.log")
    }
    static func log(_ message: String) {
        let url = fileURL
        let line = Data("\(Date()) \(message.replacingOccurrences(of: "\n", with: " "))\n".utf8)
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let attributes = try? fm.attributesOfItem(atPath: url.path),
               let size = attributes[.size] as? NSNumber, size.intValue > 2_000_000 {
                let previous = url.appendingPathExtension("previous")
                try? fm.removeItem(at: previous)
                try? fm.moveItem(at: url, to: previous)
            }
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil) }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
        }
    }
}
