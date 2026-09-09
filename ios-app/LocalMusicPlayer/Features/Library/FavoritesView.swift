import SwiftUI

struct FavoritesView: View {
    @Bindable var model: LibraryModel

    private var favoriteTracks: [TrackSnapshot] {
        FavoriteTrackFilter.apply(model.tracks)
    }

    var body: some View {
        Group {
            if favoriteTracks.isEmpty {
                ContentUnavailableView(
                    "还没有收藏",
                    systemImage: "heart",
                    description: Text("在音乐库中点击心形即可收藏歌曲")
                )
            } else {
                List(favoriteTracks) { track in
                    TrackRow(
                        track: track,
                        isCurrent: model.currentTrackID == track.id,
                        isPlaying: model.isCurrentTrackPlaying
                    ) {
                        NotificationCenter.default.post(
                            name: .showMiniPlayer,
                            object: nil
                        )
                        Task {
                            try? await model.play(track, in: favoriteTracks)
                        }
                    } toggleLike: {
                        try? model.toggleLike(track)
                    } delete: {
                        try? model.delete(track)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("收藏")
    }
}
