import Foundation
import ZIPFoundation

struct MusicPackageManifest: Codable {
    let title: String
    let artist: String?
    let album: String?
    let audioPath: String
    let lyricsPath: String?
    let coverPath: String?
}
enum MusicPackageError: LocalizedError {
    case invalid
    var errorDescription: String? { "音乐包无效：需要 MP3，歌词和封面可以缺少。" }
}
enum MusicPackage {
    static func create(files: [URL], destination: URL) throws -> [URL] {
        let audios = files.filter { $0.pathExtension.lowercased() == "mp3" }
        guard !audios.isEmpty else { throw MusicPackageError.invalid }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        return try audios.map { audio in
            let stem = audio.deletingPathExtension().lastPathComponent
            let companion: (Set<String>) -> URL? = { extensions in files.first {
                $0.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(stem) == .orderedSame && extensions.contains($0.pathExtension.lowercased())
            } }
            let lyrics = companion(["lrc"])
            let cover = companion(["jpg", "jpeg", "png", "webp"]) ?? files.first { $0.deletingPathExtension().lastPathComponent.lowercased() == "cover" && ["jpg", "jpeg", "png", "webp"].contains($0.pathExtension.lowercased()) }
            let manifest = MusicPackageManifest(title: stem, artist: nil, album: nil, audioPath: "audio/" + audio.lastPathComponent, lyricsPath: lyrics.map { "lyrics/" + $0.lastPathComponent }, coverPath: cover.map { "cover/" + $0.lastPathComponent })
            let staging = destination.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: staging) }
            for (source, path) in [(Optional(audio), Optional(manifest.audioPath)), (lyrics, manifest.lyricsPath), (cover, manifest.coverPath)] {
                guard let source, let path else { continue }
                let target = staging.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: source, to: target)
            }
            try JSONEncoder().encode(manifest).write(to: staging.appendingPathComponent("manifest.json"))
            let output = destination.appendingPathComponent(stem + "-" + UUID().uuidString.prefix(8) + ".aiyuepack")
            try FileManager.default.zipItem(at: staging, to: output, shouldKeepParent: false)
            return output
        }
    }
    static func extract(_ package: URL, to root: URL) throws -> (MusicPackageManifest, [URL]) {
        let archive = try Archive(url: package, accessMode: .read)
        guard let entry = archive["manifest.json"], entry.type == .file, entry.uncompressedSize <= 65536 else { throw MusicPackageError.invalid }
        var data = Data()
        let checksum = try archive.extract(entry) { chunk in
            guard data.count + chunk.count <= 65536 else { throw MusicPackageError.invalid }
            data.append(chunk)
        }
        guard checksum == entry.checksum else { throw MusicPackageError.invalid }
        let manifest = try JSONDecoder().decode(MusicPackageManifest.self, from: data)
        guard manifest.audioPath.lowercased().hasSuffix(".mp3") else { throw MusicPackageError.invalid }
        let paths = [Optional(manifest.audioPath), manifest.lyricsPath, manifest.coverPath].compactMap { $0 }
        guard Set(paths).count == paths.count else { throw MusicPackageError.invalid }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let urls = try paths.map { path -> URL in
            guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.split(separator: "/").contains(".."),
                  let file = archive[path], file.type == .file, file.uncompressedSize <= 4 * 1024 * 1024 * 1024 else { throw MusicPackageError.invalid }
            if path == manifest.lyricsPath, !path.lowercased().hasSuffix(".lrc") { throw MusicPackageError.invalid }
            if path == manifest.coverPath, !["jpg", "jpeg", "png", "webp"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) { throw MusicPackageError.invalid }
            let target = root.appendingPathComponent(path).standardizedFileURL
            guard target.path.hasPrefix(root.standardizedFileURL.path + "/") else { throw MusicPackageError.invalid }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            let checksum = try archive.extract(file, to: target)
            guard checksum == file.checksum else { throw MusicPackageError.invalid }
            return target
        }
        return (manifest, urls)
    }
}
