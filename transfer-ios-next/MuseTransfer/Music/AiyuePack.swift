import Foundation

public struct AiyuePackManifest: Codable, Equatable, Sendable {
    public let title: String
    public let artist: String?
    public let album: String?
    public let audioPath: String
    public let lyricsPath: String?
    public let coverPath: String?

    public init(title: String, artist: String? = nil, album: String? = nil, audioPath: String, lyricsPath: String? = nil, coverPath: String? = nil) {
        self.title = title; self.artist = artist; self.album = album; self.audioPath = audioPath; self.lyricsPath = lyricsPath; self.coverPath = coverPath
    }
}

public enum AiyuePackError: Error { case unsupportedArchive, missingAudio, invalidManifest }

public enum AiyuePack {
    public static func manifestData(_ manifest: AiyuePackManifest) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(manifest)
    }

    public static func readManifest(from packageURL: URL) throws -> AiyuePackManifest {
        guard let archive = Archive(url: packageURL, accessMode: .read),
              let entry = archive["manifest.json"] else { throw AiyuePackError.invalidManifest }
        var data = Data()
        _ = try archive.extract(entry, consumer: { data.append($0) })
        let manifest = try JSONDecoder().decode(AiyuePackManifest.self, from: data)
        guard manifest.audioPath.hasPrefix("audio/"), !manifest.audioPath.contains("..") else { throw AiyuePackError.invalidManifest }
        return manifest
    }
}
