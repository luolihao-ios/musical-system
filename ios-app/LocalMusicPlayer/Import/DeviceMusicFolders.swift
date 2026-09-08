import Foundation

@MainActor enum DeviceMusicFolders {
    static func scan(using importer: any FileImporting) async -> [TrackRecord] {
        let fileManager = FileManager.default
        let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // The transfer app writes the shared handoff files below its App Group
        // container. Scan the container root instead of only MusicHandoff so
        // older builds and files placed directly in the shared folder remain
        // discoverable as well.
        var roots = [documents]
        if let authorized = AuthorizedMusicFolderAccess.resolve() {
            roots.insert(authorized, at: 0)
            log("已加载授权音乐文件夹：\(authorized.path)")
        } else {
            log("未找到授权音乐文件夹；请先通过文件夹选择器授权。")
        }
        if let group = fileManager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.aiyuetransfer") {
            roots.insert(group, at: 0)
            log("App Group 容器：\(group.path)")
        } else {
            log("App Group 容器不可用：group.com.luolihao.aiyuetransfer")
        }
        log("开始扫描本地音频，目录数：\(roots.count)")
        var tracks: [TrackRecord] = []
        var seen: Set<URL> = []
        for root in roots where seen.insert(root.standardizedFileURL).inserted {
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            let urls = enumerateFiles(in: root)
            log("扫描目录：\(root.path)，文件数：\(urls.count)")
            var folders: [URL: [ImportedFile]] = [:]
            for url in urls {
                let extensionName = url.pathExtension.isEmpty ? "（无）" : url.pathExtension
                log("扫描条目：\(url.path)，扩展名：\(extensionName)")
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey]) else {
                    log("跳过条目（无法读取属性）：\(url.path)")
                    continue
                }
                guard values.isDirectory != true, values.isSymbolicLink != true else {
                    continue
                }
                let ext = url.pathExtension.lowercased()
                let kind: ImportedFile.Kind
                if FileImportService.supportedAudioExtensions.contains(ext) { kind = .audio }
                else if ext == "lrc" { kind = .lyrics }
                else if ext == "aiyuepack" { kind = .package }
                else if ["jpg", "jpeg", "png", "webp"].contains(ext) { kind = .cover }
                else { continue }
                log("发现可导入文件：\(url.lastPathComponent)，类型：\(kind)，扩展名：\(ext)")
                folders[url.deletingLastPathComponent(), default: []].append(ImportedFile(sourceURL: url, kind: kind))
            }
            log("本目录可导入文件数：\(folders.values.reduce(0) { $0 + $1.count })")
            for files in folders.values {
                let companions = files.filter { $0.kind == .lyrics || $0.kind == .cover }
                for file in files where file.kind == .audio || file.kind == .package {
                    do {
                        tracks += try await importer.importFiles([file] + companions)
                    } catch {
                        log("导入失败：\(file.sourceURL.lastPathComponent)，\(error.localizedDescription)")
                    }
                }
            }
        }
        log("扫描完成，导入记录数：\(tracks.count)")
        return tracks
    }

    private static func enumerateFiles(in root: URL) -> [URL] {
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        return iterator.compactMap { $0 as? URL }
    }

    private static func log(_ message: String) {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let url = documents.appendingPathComponent("music-import-diagnostics.log")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("\(Date()) \(message)\n".utf8))
    }
}
