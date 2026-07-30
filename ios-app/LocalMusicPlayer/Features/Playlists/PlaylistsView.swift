import SwiftUI

struct PlaylistsView: View {
    @Bindable var model: PlaylistsModel

    @State private var showCreate = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(model.playlists) { playlist in
                NavigationLink {
                    PlaylistDetailView(
                        playlist: playlist,
                        model: model
                    )
                } label: {
                    Label(
                        playlist.name,
                        systemImage: playlist.isBuiltIn
                            ? "heart.fill"
                            : "music.note.list"
                    )
                    .foregroundStyle(
                        playlist.isBuiltIn ? PlayerTheme.accent : Color.primary
                    )
                }
                .swipeActions {
                    if !playlist.isBuiltIn {
                        Button("删除", role: .destructive) {
                            _ = try? model.delete(playlist)
                        }
                    }
                }
            }
        }
        .overlay {
            if model.playlists.isEmpty {
                ContentUnavailableView(
                    "还没有歌单",
                    systemImage: "music.note.list"
                )
            }
        }
        .navigationTitle("歌单")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showCreate = true
                } label: {
                    Label("新建歌单", systemImage: "plus")
                }
            }
        }
        .alert("新建歌单", isPresented: $showCreate) {
            TextField("歌单名称", text: $newName)
            Button("取消", role: .cancel) { newName = "" }
            Button("创建") {
                _ = try? model.create(name: newName)
                newName = ""
            }
        }
    }
}

private struct PlaylistDetailView: View {
    let playlist: PlaylistSnapshot
    @Bindable var model: PlaylistsModel

    @State private var tracks: [TrackSnapshot] = []
    @State private var renameText = ""
    @State private var showRename = false

    var body: some View {
        Group {
            if tracks.isEmpty {
                ContentUnavailableView(
                    "歌单还是空的",
                    systemImage: "music.note",
                    description: Text("可从音乐库的歌曲菜单添加")
                )
            } else {
                List(tracks) { track in
                    Button {
                        Task { try? await model.play(track, in: playlist) }
                    } label: {
                        HStack(spacing: 12) {
                            ArtworkView(path: track.artworkReference)
                                .frame(width: 48, height: 48)
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .foregroundStyle(.primary)
                                Text(track.artist)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        if !playlist.isBuiltIn {
                            Button("移除", role: .destructive) {
                                try? model.remove(
                                    trackID: track.id,
                                    from: playlist.id
                                )
                                reload()
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(playlist.name)
        .toolbar {
            if !playlist.isBuiltIn {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("改名") {
                        renameText = playlist.name
                        showRename = true
                    }
                }
            }
        }
        .alert("修改歌单名称", isPresented: $showRename) {
            TextField("歌单名称", text: $renameText)
            Button("取消", role: .cancel) {}
            Button("保存") {
                _ = try? model.rename(playlist, to: renameText)
            }
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        tracks = (try? model.tracks(in: playlist)) ?? []
    }
}
