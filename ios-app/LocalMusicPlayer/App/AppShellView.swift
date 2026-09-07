import SwiftUI
import StoreKit
import UIKit

struct AppShellView: View {
    let container: AppContainer

    @Environment(\.scenePhase) private var scenePhase
    @State private var showNowPlaying = false
    @State private var miniPlayerVisibility = MiniPlayerVisibility()
    @State private var storeUpdate: AppStoreUpdate?
    @State private var didCheckStore = false

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

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
                        Text("联网仅用于补全缺失歌词与封面，不上传音乐文件。")
                    }
                    Section("关于") {
                        Button {
                            if let url = storeUpdate?.storeURL {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Text("版本")
                                Spacer()
                                Text(currentVersion)
                                if let storeUpdate, AppStoreUpdate.isNewer(storeVersion: storeUpdate.storeVersion, than: currentVersion) {
                                    Image(systemName: "arrow.down.app")
                                        .foregroundStyle(PlayerTheme.accent)
                                }
                            }
                        }
                        .foregroundStyle(Color.primary)
                        Button("去 App Store 评分") {
                            SKStoreReviewController.requestReview()
                        }
                    }
                }
                .navigationTitle("设置")
                .task {
                    guard !didCheckStore else { return }
                    didCheckStore = true
                    storeUpdate = await AppStoreUpdate.lookup(bundleIdentifier: AppIdentity.bundleIdentifier)
                }
            }
            .tabItem {
                Label("设置", systemImage: "gearshape")
            }
        }
        .tint(PlayerTheme.accent)
        .environment(\.showMiniPlayer) {
            miniPlayerVisibility.show()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if container.nowPlayingModel.state.currentTrack != nil,
               miniPlayerVisibility.isVisible {
                MiniPlayerView(
                    model: container.nowPlayingModel,
                    openNowPlaying: { showNowPlaying = true },
                    dismiss: { miniPlayerVisibility.dismiss() }
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
        .onChange(of: container.nowPlayingModel.state.currentTrack?.id) { _, _ in
            miniPlayerVisibility.show()
        }
    }
}
