import Foundation

enum WebFailure: Error { case invalidPath, invalidRequest, unauthorized, conflict }

struct WebFileEntry: Codable {
    let name: String
    let path: String
    let directory: Bool
    let size: Int64
}

final class WebFileStore {
    let root: URL
    init(root: URL) throws {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
    }
    func resolve(_ path: String) throws -> URL {
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.unicodeScalars.contains(where: { $0.value < 32 }),
              !path.split(separator: "/").contains(where: { $0 == ".." || $0.hasPrefix(".") || $0 == "待发送" }) else { throw WebFailure.invalidPath }
        guard !containsSymlink(in: path) else { throw WebFailure.invalidPath }
        let url = root.appendingPathComponent(path).standardizedFileURL.resolvingSymlinksInPath()
        guard url == root || url.path.hasPrefix(root.path + "/") else { throw WebFailure.invalidPath }
        return url
    }

    private func containsSymlink(in path: String) -> Bool {
        var current = root
        for component in path.split(separator: "/") {
            current.appendPathComponent(String(component))
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: current.path)) != nil { return true }
        }
        return false
    }
    func list(_ path: String) throws -> [WebFileEntry] {
        let folder = try resolve(path)
        return try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]).compactMap { url in
            let relative = String(url.path.dropFirst(root.path.count + 1))
            guard (try? resolve(relative)) != nil else { return nil }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            return WebFileEntry(name: url.lastPathComponent, path: relative, directory: values.isDirectory == true, size: Int64(values.fileSize ?? 0))
        }.sorted { $0.directory != $1.directory ? $0.directory : $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    func createFolder(_ path: String) throws {
        let url = try resolve(path)
        guard url != root, !FileManager.default.fileExists(atPath: url.path) else { throw WebFailure.conflict }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    func save(_ temporary: URL, as path: String) throws -> String {
        let original = try resolve(path)
        guard original != root else { throw WebFailure.invalidPath }
        try FileManager.default.createDirectory(at: original.deletingLastPathComponent(), withIntermediateDirectories: true)
        var target = original
        var index = 1
        while FileManager.default.fileExists(atPath: target.path) {
            let ext = original.pathExtension
            target = original.deletingLastPathComponent().appendingPathComponent(original.deletingPathExtension().lastPathComponent + " (\(index))" + (ext.isEmpty ? "" : "." + ext))
            index += 1
        }
        try FileManager.default.moveItem(at: temporary, to: target)
        return String(target.path.dropFirst(root.path.count + 1))
    }
}
