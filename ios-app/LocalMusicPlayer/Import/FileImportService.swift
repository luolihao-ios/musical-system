import CryptoKit
import Foundation

@MainActor
protocol SecurityScopedAccessing {
    func beginAccessing(_ url: URL) -> Bool
    func endAccessing(_ url: URL)
}

@MainActor
final class URLSecurityScope: SecurityScopedAccessing {
    func beginAccessing(_ url: URL) -> Bool {
        url.startAccessingSecurityScopedResource()
    }

    func endAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }
}

@MainActor
final class FileImportService {
    static let supportedAudioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aif", "aiff"
    ]

    private let rootDirectory: URL
    private let metadataReader: any ImportedMetadataReading
    private let securityScope: any SecurityScopedAccessing
    private let fileManager: FileManager

    init(
        rootDirectory: URL? = nil,
        metadataReader: any ImportedMetadataReading = ImportedMetadataReader(),
        securityScope: any SecurityScopedAccessing = URLSecurityScope(),
        fileManager: FileManager = .default
    ) {
        self.rootDirectory = rootDirectory
            ?? Self.defaultImportRoot(fileManager: fileManager)
        self.metadataReader = metadataReader
        self.securityScope = securityScope
        self.fileManager = fileManager
    }

    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord] {
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        let lyricFiles = Dictionary(
            uniqueKeysWithValues: files
                .filter { $0.kind == .lyrics }
                .map {
                    (
                        $0.sourceURL.deletingPathExtension()
                            .lastPathComponent.lowercased(),
                        $0
                    )
                }
        )
        var tracks: [TrackRecord] = []
        for file in files where file.kind == .audio {
            let ext = file.sourceURL.pathExtension.lowercased()
            guard Self.supportedAudioExtensions.contains(ext) else {
                throw FileImportError.unsupportedExtension(ext)
            }
            let key = file.sourceURL.deletingPathExtension()
                .lastPathComponent.lowercased()
            let track = try await importAudio(
                file,
                lyrics: lyricFiles[key]
            )
            tracks.append(track)
        }
        return tracks
    }

    private func importAudio(
        _ audio: ImportedFile,
        lyrics: ImportedFile?
    ) async throws -> TrackRecord {
        let didAccessAudio = securityScope.beginAccessing(audio.sourceURL)
        defer {
            if didAccessAudio {
                securityScope.endAccessing(audio.sourceURL)
            }
        }

        let identifier = try fingerprint(audio.sourceURL)
        let destination = rootDirectory.appending(path: identifier)
        let staging = rootDirectory.appending(
            path: ".staging-\(identifier)-\(UUID().uuidString)"
        )
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: true
        )
        var keepStaging = false
        defer {
            if !keepStaging {
                try? fileManager.removeItem(at: staging)
            }
        }

        let audioExtension = audio.sourceURL.pathExtension.lowercased()
        let stagedAudio = staging.appending(path: "audio.\(audioExtension)")
        try fileManager.copyItem(at: audio.sourceURL, to: stagedAudio)

        var stagedLyrics: URL?
        if let lyrics {
            let didAccessLyrics = securityScope.beginAccessing(lyrics.sourceURL)
            defer {
                if didAccessLyrics {
                    securityScope.endAccessing(lyrics.sourceURL)
                }
            }
            let target = staging.appending(path: "lyrics.lrc")
            try fileManager.copyItem(at: lyrics.sourceURL, to: target)
            stagedLyrics = target
        }

        let metadata = try await metadataReader.read(stagedAudio)
        var stagedArtwork: URL?
        if let artwork = metadata.artworkData, !artwork.isEmpty {
            let target = staging.appending(path: "artwork")
            try artwork.write(to: target, options: .atomic)
            stagedArtwork = target
        }

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: staging, to: destination)
        keepStaging = true

        let finalAudio = destination.appending(path: stagedAudio.lastPathComponent)
        let finalLyrics = stagedLyrics.map {
            destination.appending(path: $0.lastPathComponent).path
        }
        let finalArtwork = stagedArtwork.map {
            destination.appending(path: $0.lastPathComponent).path
        }
        let fallbackTitle = audio.sourceURL.deletingPathExtension()
            .lastPathComponent
        let resolvedTitle = metadata.title
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return TrackRecord(
            id: identifier,
            title: resolvedTitle.isEmpty ? fallbackTitle : resolvedTitle,
            artist: metadata.artist,
            album: metadata.album,
            duration: metadata.duration,
            sourceKind: .importedFile,
            sourceReference: finalAudio.path,
            artworkReference: finalArtwork,
            lyricsReference: finalLyrics
        )
    }

    private func fingerprint(_ url: URL) throws -> String {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        var hasher = SHA256()
        hasher.update(data: data)
        var size = UInt64(data.count).bigEndian
        withUnsafeBytes(of: &size) { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func defaultImportRoot(fileManager: FileManager) -> URL {
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return applicationSupport.appending(path: "ImportedMusic")
    }
}

enum FileImportError: Error, Equatable {
    case unsupportedExtension(String)
}
