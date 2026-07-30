import Foundation

enum SystemLibraryImportResult {
    case imported([TrackRecord])
    case permissionDenied
}

@MainActor
final class SystemLibraryImporter {
    private let gateway: any MediaLibraryGateway
    private let artworkDirectory: URL
    private let fileManager: FileManager

    init(
        gateway: any MediaLibraryGateway = SystemMediaLibraryGateway(),
        artworkDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.gateway = gateway
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
            let artworkReference = try cacheArtwork(item.artworkData, id: id)
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

    private func cacheArtwork(_ data: Data?, id: String) throws -> String? {
        guard let data, !data.isEmpty else { return nil }
        let target = artworkDirectory.appending(path: "\(id).jpg")
        try data.write(to: target, options: .atomic)
        return target.path
    }
}
