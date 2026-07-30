import Foundation
import MediaPlayer
import UIKit

enum MediaLibraryAuthorization: Equatable, Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined
}

struct MediaLibraryItem: Equatable, Sendable {
    let persistentID: UInt64
    let title: String
    let artist: String
    let album: String
    let duration: Double
    let assetURL: URL?
    let artworkData: Data?
}

@MainActor
protocol MediaLibraryGateway: AnyObject {
    func requestAuthorization() async -> MediaLibraryAuthorization
    func playableItems() -> [MediaLibraryItem]
}

@MainActor
final class SystemMediaLibraryGateway: MediaLibraryGateway {
    func requestAuthorization() async -> MediaLibraryAuthorization {
        let status = MPMediaLibrary.authorizationStatus()
        if status != .notDetermined {
            return Self.map(status)
        }
        return await withCheckedContinuation { continuation in
            MPMediaLibrary.requestAuthorization {
                continuation.resume(returning: Self.map($0))
            }
        }
    }

    func playableItems() -> [MediaLibraryItem] {
        (MPMediaQuery.songs().items ?? []).compactMap { item in
            guard let assetURL = item.assetURL else { return nil }
            return MediaLibraryItem(
                persistentID: item.persistentID,
                title: item.title ?? assetURL.deletingPathExtension().lastPathComponent,
                artist: item.artist ?? "",
                album: item.albumTitle ?? "",
                duration: max(item.playbackDuration, 0),
                assetURL: assetURL,
                artworkData: item.artwork?
                    .image(at: CGSize(width: 900, height: 900))?
                    .jpegData(compressionQuality: 0.88)
            )
        }
    }

    private static func map(
        _ status: MPMediaLibraryAuthorizationStatus
    ) -> MediaLibraryAuthorization {
        switch status {
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        case .notDetermined:
            .notDetermined
        @unknown default:
            .denied
        }
    }
}
