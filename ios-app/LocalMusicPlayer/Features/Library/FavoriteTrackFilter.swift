import Foundation

enum FavoriteTrackFilter {
    static func apply(_ tracks: [TrackSnapshot]) -> [TrackSnapshot] {
        tracks.filter(\.isLiked)
    }
}
