import SwiftUI

struct AppShellView: View {
    let container: AppContainer

    @Environment(\.scenePhase) private var scenePhase
    @State private var showNowPlaying = false

    var body: some View {
        TabView {
            NavigationStack {
                LibraryView(
                    model: container.libraryModel,
                    playlists: container.playlistsModel
                )
            }
            .tabItem {
                Label("音乐库", systemImage: "music.note.house")
            }

            NavigationStack {
                PlaylistsView(model: container.playlistsModel)
            }
            .tabItem {
                Label("歌单", systemImage: "rectangle.stack")
            }

            NavigationStack {
                List {
                    Section("播放") {
                        LabeledContent("来源", value: "仅本机文件")
                        LabeledContent("后台播放", value: "已启用")
                    }
                    Section("格式") {
                        Text("MP3 · M4A/AAC · FLAC · WAV · AIFF")
                        Text("iOS 版不支持 OGG")
                            .foregroundStyle(.secondary)
                    }
                    Section("隐私") {
                        Text("不接入在线曲库，不下载或上传音乐。")
                    }
                }
                .navigationTitle("设置")
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .tint(PlayerTheme.accent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if container.nowPlayingModel.state.currentTrack != nil {
                MiniPlayerView(
                    model: container.nowPlayingModel,
                    openNowPlaying: { showNowPlaying = true }
                )
            }
        }
        .sheet(isPresented: $showNowPlaying) {
            NowPlayingView(model: container.nowPlayingModel)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                try? container.playback.persistCurrentState()
            }
        }
    }
}
