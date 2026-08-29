import SwiftUI

struct LibraryView: View {
    @Bindable var model: LibraryModel
    @Bindable var playlists: PlaylistsModel

    @State private var showDocumentPicker = false

    var body: some View {
        Group {
            if model.tracks.isEmpty {
                ContentUnavailableView {
                    Label("还没有本地音乐", systemImage: "music.note.list")
                } description: {
                    Text("从“文件”或设备音乐资料库导入")
                } actions: {
                    Button("从“文件”导入") {
                        showDocumentPicker = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PlayerTheme.accent)
                }
            } else {
                List {
                    Section {
                        libraryEntrances
                            .listRowInsets(
                                EdgeInsets(
                                    top: 8,
                                    leading: 0,
                                    bottom: 8,
                                    trailing: 0
                                )
                            )
                            .listRowBackground(Color.clear)
                    }
                    Section("全部歌曲 · \(model.filteredTracks.count)") {
                        ForEach(model.filteredTracks) { track in
                            trackRow(track)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("音乐库")
        .searchable(
            text: $model.searchText,
            prompt: "搜索歌曲、歌手或专辑"
        )
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ImportMenu {
                    showDocumentPicker = true
                } importSystemLibrary: {
                    Task { await model.importSystemLibrary() }
                }
            }
        }
        .overlay {
            if model.isImporting {
                ProgressView("正在整理本地音乐…")
                    .padding(22)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
        .sheet(isPresented: $showDocumentPicker) {
            DocumentPickerView { files in
                showDocumentPicker = false
                Task { await model.importFiles(files) }
            }
        }
        .alert(
            "无法导入",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("好", role: .cancel) { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .alert(
            "未获音乐资料库权限",
            isPresented: $model.systemPermissionDenied
        ) {
            Button("好", role: .cancel) {}
        } message: {
            Text("仍可继续使用“文件”导入本地音乐。")
        }
    }

    private var libraryEntrances: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(LibraryGroupKind.allCases) { kind in
                    NavigationLink {
                        LibraryGroupsView(
                            title: kind.title,
                            groups: model.groups(for: kind),
                            model: model,
                            playlists: playlists
                        )
                    } label: {
                        LibraryEntranceCard(
                            title: kind.title,
                            systemImage: kind.systemImage,
                            countText: "\(model.groups(for: kind).count)"
                        )
                    }
                    .buttonStyle(.plain)
                }
                NavigationLink {
                    LibraryTracksView(
                        title: "最近播放",
                        tracks: model.recentlyPlayed,
                        model: model,
                        playlists: playlists
                    )
                } label: {
                    LibraryEntranceCard(
                        title: "最近播放",
                        systemImage: "clock.arrow.circlepath",
                        countText: "\(model.recentlyPlayed.count) 首"
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private func trackRow(_ track: TrackSnapshot) -> some View {
        TrackRow(
            track: track,
            isCurrent: model.currentTrackID == track.id,
            isPlaying: model.isCurrentTrackPlaying
        ) {
            Task { try? await model.play(track) }
        } toggleLike: {
            try? model.toggleLike(track)
        } addToPlaylist: { playlistID in
            try? playlists.add(trackID: track.id, to: playlistID)
        } playlists: {
            playlists.playlists.filter { !$0.isBuiltIn }
        }
    }
}

private struct LibraryEntranceCard: View {
    let title: String
    let systemImage: String
    let countText: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title2)
                .foregroundStyle(PlayerTheme.accent)
            Text(title)
                .font(.headline)
            Text(countText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 112, alignment: .leading)
        .padding(14)
        .background(
            PlayerTheme.panel,
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
    }
}

private struct LibraryGroupsView: View {
    let title: String
    let groups: [LibraryTrackGroup]
    @Bindable var model: LibraryModel
    @Bindable var playlists: PlaylistsModel

    var body: some View {
        List(groups) { group in
            NavigationLink {
                LibraryTracksView(
                    title: group.title,
                    tracks: group.tracks,
                    model: model,
                    playlists: playlists
                )
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(group.title)
                    Text("\(group.tracks.count) 首")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(title)
        .overlay {
            if groups.isEmpty {
                ContentUnavailableView(
                    "暂无\(title)",
                    systemImage: "music.note.list"
                )
            }
        }
    }
}

private struct LibraryTracksView: View {
    let title: String
    let tracks: [TrackSnapshot]
    @Bindable var model: LibraryModel
    @Bindable var playlists: PlaylistsModel

    var body: some View {
        List(tracks) { track in
            TrackRow(
                track: track,
                isCurrent: model.currentTrackID == track.id,
                isPlaying: model.isCurrentTrackPlaying
            ) {
                Task { try? await model.play(track, in: tracks) }
            } toggleLike: {
                try? model.toggleLike(track)
            } addToPlaylist: { playlistID in
                try? playlists.add(trackID: track.id, to: playlistID)
            } playlists: {
                playlists.playlists.filter { !$0.isBuiltIn }
            }
        }
        .navigationTitle(title)
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "暂无歌曲",
                    systemImage: "music.note"
                )
            }
        }
    }
}

private struct TrackRow: View {
    let track: TrackSnapshot
    let isCurrent: Bool
    let isPlaying: Bool
    let play: () -> Void
    let toggleLike: () -> Void
    let addToPlaylist: (String) -> Void
    let playlists: () -> [PlaylistSnapshot]

    var body: some View {
        HStack(spacing: 12) {
            Button(action: play) {
                HStack(spacing: 12) {
                    ArtworkView(path: track.artworkReference)
                        .frame(width: 52, height: 52)
                        .overlay(alignment: .bottomTrailing) {
                            if isCurrent {
                                Image(
                                    systemName: isPlaying
                                        ? "speaker.wave.2.fill"
                                        : "pause.fill"
                                )
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(5)
                                .background(PlayerTheme.accent, in: Circle())
                                .accessibilityHidden(true)
                            }
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(
                                isCurrent ? PlayerTheme.accent : Color.primary
                            )
                            .lineLimit(1)
                        Text(
                            [track.artist, track.album]
                                .filter { !$0.isEmpty }
                                .joined(separator: " · ")
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer()
            Menu {
                Button(action: toggleLike) {
                    Label(
                        track.isLiked ? "取消喜欢" : "我喜欢",
                        systemImage: track.isLiked ? "heart.slash" : "heart"
                    )
                }
                if playlists().isEmpty {
                    Text("先创建一个自建歌单")
                } else {
                    Menu("添加到歌单") {
                        ForEach(playlists()) { playlist in
                            Button(playlist.name) {
                                addToPlaylist(playlist.id)
                            }
                        }
                    }
                }
            } label: {
                Image(systemName: track.isLiked ? "heart.fill" : "ellipsis")
                    .foregroundStyle(
                        track.isLiked ? PlayerTheme.accent : Color.secondary
                    )
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("歌曲操作")
        }
        .opacity(track.isAvailable ? 1 : 0.45)
    }
}
