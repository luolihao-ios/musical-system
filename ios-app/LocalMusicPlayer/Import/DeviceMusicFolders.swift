import Foundation

@MainActor enum DeviceMusicFolders {
    static func scan(using importer: any FileImporting) async -> [TrackRecord] {
        let roots: [URL] = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.aiyuetransfer").map { [$0.appendingPathComponent("MusicHandoff")] } ?? []
        var tracks: [TrackRecord] = []
        var seen: Set<URL> = []
        for root in roots where seen.insert(root.standardizedFileURL).inserted {
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            let urls = enumerateFiles(in: root)
            var folders: [URL: [ImportedFile]] = [:]
            for url in urls {
                guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]), values.isRegularFile == true, values.isSymbolicLink != true else { continue }
                let ext = url.pathExtension.lowercased()
                let kind: ImportedFile.Kind
                if FileImportService.supportedAudioExtensions.contains(ext) { kind = .audio }
                else if ext == "lrc" { kind = .lyrics }
                else if ext == "aiyuepack" { kind = .package }
                else if ["jpg", "jpeg", "png", "webp"].contains(ext) { kind = .cover }
                else { continue }
                folders[url.deletingLastPathComponent(), default: []].append(ImportedFile(sourceURL: url, kind: kind))
            }
            for files in folders.values {
                let companions = files.filter { $0.kind == .lyrics || $0.kind == .cover }
                for file in files where file.kind == .audio || file.kind == .package {
                    let imported = try? await importer.importFiles([file] + companions)
                    if let imported { tracks += imported }
                }
            }
        }
        return tracks
    }

    private static func enumerateFiles(in root: URL) -> [URL] {
        guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { return [] }
        return iterator.compactMap { $0 as? URL }
    }
}
