import AVFoundation
import Foundation

struct ImportedMetadataReader: ImportedMetadataReading {
    func read(_ url: URL) async throws -> ImportedMetadata {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let metadata = try await asset.load(.commonMetadata)

        return ImportedMetadata(
            title: await stringValue(
                identifier: .commonIdentifierTitle,
                in: metadata
            ) ?? "",
            artist: await stringValue(
                identifier: .commonIdentifierArtist,
                in: metadata
            ) ?? "",
            album: await stringValue(
                identifier: .commonIdentifierAlbumName,
                in: metadata
            ) ?? "",
            duration: max(duration.seconds, 0),
            artworkData: await dataValue(
                identifier: .commonIdentifierArtwork,
                in: metadata
            )
        )
    }

    private func stringValue(
        identifier: AVMetadataIdentifier,
        in metadata: [AVMetadataItem]
    ) async -> String? {
        guard let item = metadata.first(where: {
            $0.identifier == identifier
        }) else {
            return nil
        }
        return try? await item.load(.stringValue)
    }

    private func dataValue(
        identifier: AVMetadataIdentifier,
        in metadata: [AVMetadataItem]
    ) async -> Data? {
        guard let item = metadata.first(where: {
            $0.identifier == identifier
        }) else {
            return nil
        }
        return try? await item.load(.dataValue)
    }
}
