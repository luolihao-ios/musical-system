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
}
