import Foundation

@MainActor enum DeviceMusicFolders {
    private static let key = "AuthorizedMusicFolders.v1"
    static func authorize(_ urls: [URL]) throws {
        var saved = UserDefaults.standard.array(forKey: key) as? [Data] ?? []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil)
            if !saved.contains(bookmark) { saved.append(bookmark) }
        }
        UserDefaults.standard.set(saved, forKey: key)
    }
    static func scan(using importer: any FileImporting) async -> [TrackRecord] {
        var roots: [URL] = []
        for data in UserDefaults.standard.array(forKey: key) as? [Data] ?? [] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale) { roots.append(url) }
        }
        if let shared = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.luolihao.aiyuetransfer") { roots.append(shared.appendingPathComponent("MusicHandoff")) }
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first { roots.append(documents) }
        var tracks: [TrackRecord] = []
        var seen: Set<URL> = []
        for root in roots where seen.insert(root.standardizedFileURL).inserted {
            let access = root.startAccessingSecurityScopedResource()
            defer { if access { root.stopAccessingSecurityScopedResource() } }
            guard let iterator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles]) else { continue }
            var folders: [URL: [ImportedFile]] = [:]
            for case let url as URL in iterator {
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
}
