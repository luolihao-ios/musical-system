import Foundation

public enum DiagnosticLog {
    private static let queue = DispatchQueue(label: "com.luolihao.aiyuetransfer.diagnostics")
    public static let fileURL: URL = {
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return folder.appendingPathComponent("aiyue-transfer-diagnostics.log")
    }()

    public static func write(_ message: String) {
        queue.async {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
            if FileManager.default.fileExists(atPath: fileURL.path), let handle = try? FileHandle(forWritingTo: fileURL) {
                defer { try? handle.close() }; try? handle.seekToEnd(); try? handle.write(contentsOf: Data(line.utf8))
            } else { try? Data(line.utf8).write(to: fileURL, options: .atomic) }
        }
    }
}
