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
    private let online: (any MusicResourceSearching)?

    init(
        rootDirectory: URL? = nil,
        metadataReader: any ImportedMetadataReading = ImportedMetadataReader(),
        securityScope: any SecurityScopedAccessing = URLSecurityScope(),
        fileManager: FileManager = .default,
        online: (any MusicResourceSearching)? = nil
    ) {
        self.rootDirectory = rootDirectory
            ?? Self.defaultImportRoot(fileManager: fileManager)
        self.metadataReader = metadataReader
        self.securityScope = securityScope
        self.fileManager = fileManager
        self.online = online
    }

    func importFiles(_ files: [ImportedFile]) async throws -> [TrackRecord] {
        var tracksFromPackages: [TrackRecord] = []
        for file in files where file.kind == .package {
            let access = securityScope.beginAccessing(file.sourceURL)
            defer { if access { securityScope.endAccessing(file.sourceURL) } }
            let temporary = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fileManager.removeItem(at: temporary) }
            let (manifest, urls) = try MusicPackage.extract(file.sourceURL, to: temporary)
            let audio = urls.first { $0.pathExtension.lowercased() == "mp3" }!
            // Normalize companion names to the audio stem for the existing importer.
            var resources = [ImportedFile(sourceURL: audio, kind: .audio)]
            for (path, kind) in [(manifest.lyricsPath, ImportedFile.Kind.lyrics), (manifest.coverPath, ImportedFile.Kind.cover)] {
                guard let path else { continue }
                let source = temporary.appendingPathComponent(path)
                let renamed = audio.deletingPathExtension().appendingPathExtension(source.pathExtension)
                if source != renamed { try fileManager.copyItem(at: source, to: renamed) }
                resources.append(ImportedFile(sourceURL: renamed, kind: kind))
            }
            tracksFromPackages += try await importFiles(resources)
        }
        try fileManager.createDirectory(
            at: rootDirectory,
            withIntermediateDirectories: true
        )
        var lyricFiles: [String: ImportedFile] = [:]
        for file in files where file.kind == .lyrics {
            let key = file.sourceURL.deletingPathExtension()
                .lastPathComponent.lowercased()
            lyricFiles[key] = file
        }
        var tracks: [TrackRecord] = tracksFromPackages
        for file in files where file.kind == .audio {
            let ext = file.sourceURL.pathExtension.lowercased()
            guard Self.supportedAudioExtensions.contains(ext) else {
                throw FileImportError.unsupportedExtension(ext)
            }
            let key = file.sourceURL.deletingPathExtension()
                .lastPathComponent.lowercased()
            let track = try await importAudio(
                file,
                lyrics: lyricFiles[key],
                cover: files.first { $0.kind == .cover && $0.sourceURL.deletingPathExtension().lastPathComponent.lowercased() == key }
            )
            tracks.append(track)
        }
        return tracks
    }

    private func importAudio(
        _ audio: ImportedFile,
        lyrics: ImportedFile?,
        cover: ImportedFile?
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

        if stagedArtwork == nil, let cover {
            let access = securityScope.beginAccessing(cover.sourceURL)
            defer { if access { securityScope.endAccessing(cover.sourceURL) } }
            let target = staging.appendingPathComponent("artwork")
            try fileManager.copyItem(at: cover.sourceURL, to: target); stagedArtwork = target
        }
        // Reimporting the same MP3 must not discard already downloaded resources.
        for (name, missing) in [("lyrics.lrc", stagedLyrics == nil), ("artwork", stagedArtwork == nil)] where missing {
            let previous = destination.appendingPathComponent(name)
            if fileManager.fileExists(atPath: previous.path) {
                let target = staging.appendingPathComponent(name)
                try fileManager.copyItem(at: previous, to: target)
                if name == "lyrics.lrc" { stagedLyrics = target } else { stagedArtwork = target }
            }
        }
        // Fill only missing resources; a failed lookup never rejects the audio.
        if let online, stagedLyrics == nil || stagedArtwork == nil {
            let fallback = fallbackMetadata(filename: audio.sourceURL.deletingPathExtension().lastPathComponent)
            let query = MusicResourceQuery(title: metadata.title.isEmpty ? fallback.title : metadata.title, artist: metadata.artist.isEmpty ? fallback.artist : metadata.artist, album: metadata.album, duration: metadata.duration)
            let found = await online.search(query, lyrics: stagedLyrics == nil, cover: stagedArtwork == nil)
            if stagedLyrics == nil, let text = found.lyrics, !text.isEmpty {
                let target = staging.appendingPathComponent("lyrics.lrc")
                if (try? text.write(to: target, atomically: true, encoding: .utf8)) != nil { stagedLyrics = target }
            }
            if stagedArtwork == nil, let data = found.cover {
                let target = staging.appendingPathComponent("artwork")
                if (try? data.write(to: target, options: .atomic)) != nil { stagedArtwork = target }
            }
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
        let fallback = fallbackMetadata(
            filename: audio.sourceURL.deletingPathExtension()
                .lastPathComponent
        )
        let embeddedTitle = metadata.title
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let embeddedArtist = metadata.artist
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let embeddedAlbum = metadata.album
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return TrackRecord(
            id: identifier,
            title: embeddedTitle.isEmpty ? fallback.title : embeddedTitle,
            artist: embeddedArtist.isEmpty ? fallback.artist : embeddedArtist,
            album: embeddedAlbum,
            duration: metadata.duration,
            sourceKind: .importedFile,
            sourceReference: finalAudio.path,
            artworkReference: finalArtwork,
            lyricsReference: finalLyrics
        )
    }

    private func fallbackMetadata(
        filename: String
    ) -> (title: String, artist: String) {
        let trimmed = filename.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard let separator = trimmed.lastIndex(of: "-") else {
            return (trimmed, "")
        }
        let title = String(trimmed[..<separator]).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        let artistStart = trimmed.index(after: separator)
        let artist = String(trimmed[artistStart...]).trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard !title.isEmpty, !artist.isEmpty else {
            return (trimmed, "")
        }
        return (title, artist)
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
