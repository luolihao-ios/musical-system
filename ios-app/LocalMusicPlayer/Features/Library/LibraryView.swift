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
                List(model.filteredTracks) { track in
                    TrackRow(track: track) {
                        Task { try? await model.play(track) }
                    } toggleLike: {
                        try? model.toggleLike(track)
                    } addToPlaylist: { playlistID in
                        try? playlists.add(
                            trackID: track.id,
                            to: playlistID
                        )
                    } playlists: {
                        playlists.playlists.filter { !$0.isBuiltIn }
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
}

private struct TrackRow: View {
    let track: TrackSnapshot
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
                    VStack(alignment: .leading, spacing: 4) {
                        Text(track.title)
                            .font(.body.weight(.semibold))
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
