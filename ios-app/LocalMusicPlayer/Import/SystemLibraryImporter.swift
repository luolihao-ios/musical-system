import Foundation

enum SystemLibraryImportResult {
    case imported([TrackRecord])
    case permissionDenied
}

@MainActor
final class SystemLibraryImporter {
    private let gateway: any MediaLibraryGateway
    private let artworkDirectory: URL
    private let artworkGenerator: any ImportedArtworkGenerating
    private let fileManager: FileManager

    init(
        gateway: any MediaLibraryGateway = SystemMediaLibraryGateway(),
        artworkDirectory: URL? = nil,
        artworkGenerator: any ImportedArtworkGenerating =
            ProceduralArtworkGenerator(),
        fileManager: FileManager = .default
    ) {
        self.gateway = gateway
        self.artworkGenerator = artworkGenerator
        self.fileManager = fileManager
        let applicationSupport = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        self.artworkDirectory = artworkDirectory
            ?? applicationSupport.appending(path: "SystemArtwork")
    }

    func importAuthorizedItems() async throws -> SystemLibraryImportResult {
        guard await gateway.requestAuthorization() == .authorized else {
            return .permissionDenied
        }
        try fileManager.createDirectory(
            at: artworkDirectory,
            withIntermediateDirectories: true
        )
        let tracks = try gateway.playableItems().compactMap { item -> TrackRecord? in
            guard let assetURL = item.assetURL else { return nil }
            let id = "media-\(item.persistentID)"
            let artworkReference = try cacheArtwork(
                item.artworkData,
                id: id,
                title: item.title,
                artist: item.artist
            )
            return TrackRecord(
                id: id,
                title: item.title,
                artist: item.artist,
                album: item.album,
                duration: item.duration,
                sourceKind: .mediaLibrary,
                sourceReference: assetURL.absoluteString,
                artworkReference: artworkReference
            )
        }
        return .imported(tracks)
    }

    private func cacheArtwork(
        _ data: Data?,
        id: String,
        title: String,
        artist: String
    ) throws -> String? {
        if let data, !data.isEmpty {
            let target = artworkDirectory.appending(path: "\(id).jpg")
            try data.write(to: target, options: .atomic)
            return target.path
        }
        guard let generated = try? artworkGenerator.generateArtwork(
            title: title,
            artist: artist,
            seed: id
        ), !generated.isEmpty else {
            return nil
        }
        let target = artworkDirectory.appending(path: "\(id)-generated.jpg")
        try generated.write(to: target, options: .atomic)
        return target.path
    }
}
