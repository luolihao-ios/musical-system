import SwiftUI

struct FavoritesView: View {
    @Bindable var model: LibraryModel
    private var onlineHistory: OnlineHistoryStore { .shared }

    private var favoriteTracks: [TrackSnapshot] {
        let local = FavoriteTrackFilter.apply(model.tracks)
        let localIDs = Set(local.map(\.id))
        let online = onlineHistory.favorites.filter { !localIDs.contains($0.id) }
        return online + local
    }

    var body: some View {
        Group {
            if favoriteTracks.isEmpty {
                ContentUnavailableView(
                    "还没有收藏",
                    systemImage: "heart",
                    description: Text("播放本地或在线歌曲时点击心形即可收藏")
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
                        NotificationCenter.default.post(
                            name: .openNowPlayingPanel,
                            object: nil
                        )
                        Task {
                            if track.sourceKind == .onlinePreview {
                                await model.playOnlineHistoryTrack(track, in: favoriteTracks)
                            } else {
                                try? await model.play(track, in: favoriteTracks)
                            }
                        }
                    } toggleLike: {
                        if track.sourceKind == .onlinePreview {
                            onlineHistory.removeFavorite(track.id)
                            ToastCenter.shared.show(String(localized: "已取消收藏"), systemImage: "heart")
                        } else {
                            try? model.toggleLike(track)
                        }
                    } delete: {
                        if track.sourceKind == .onlinePreview {
                            onlineHistory.removeFavorite(track.id)
                        } else {
                            try? model.delete(track)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(RefreshBackdrop())
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
        .navigationTitle("收藏")
    }
}
