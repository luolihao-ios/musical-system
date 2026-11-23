import SwiftUI
import StoreKit
import UIKit

@MainActor
struct AppShellView: View {
    let container: AppContainer
    let initialOnlineResults: [CatalogTrack]

    @Environment(\.scenePhase) private var scenePhase
    @State private var storeUpdate: AppStoreUpdate?
    @State private var didCheckStore = false
    @State private var selectedTab = 0
    @State private var discovery: DiscoveryModel

    init(container: AppContainer, initialOnlineResults: [CatalogTrack] = []) {
        self.container = container
        self.initialOnlineResults = initialOnlineResults
        _discovery = State(initialValue: DiscoveryModel(
            fixtureTracks: initialOnlineResults.isEmpty ? nil : initialOnlineResults,
            feedLoader: { market in await OnlineCatalog.shared.discoveryFeed(for: market) }
        ))
    }

    private var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1"
    }

    var body: some View {
        PlayerDockContainer(
            model: container.nowPlayingModel,
            isVisible: container.nowPlayingModel.state.currentTrack != nil,
            dismiss: { selectedTab = 0 }
        ) { tabs }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { try? container.playback.persistCurrentState() }
            else { container.nowPlayingModel.expireSleepTimer() }
        }
        .onChange(of: container.nowPlayingModel.state.currentTrack?.id) { _, _ in
            PlayerInteractionDiagnostics.log("shell show reason=track-change")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showMiniPlayer)) { _ in
            PlayerInteractionDiagnostics.log("shell show reason=notification")
        }
        .onReceive(NotificationCenter.default.publisher(for: .libraryFavoritesChanged)) { _ in
            try? container.libraryModel.reload()
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                DiscoveryView(recommendations: discovery, library: container.libraryModel) { selectedTab = 2 }
            }
            .tabItem {
                Label("首页", systemImage: "house")
            }
            .tag(0)

            NavigationStack {
                LibraryView(model: container.libraryModel, personalLibrary: true, title: "我的音乐")
            }
            .tabItem { Label("音乐库", systemImage: "music.note.list") }.tag(1)

            OnlineCatalogSearchView(model: container.libraryModel, initialResults: initialOnlineResults)
                .tabItem { Label("搜索", systemImage: "magnifyingglass") }.tag(2)

            NavigationStack {
                List {
                    NavigationLink {
                        LibraryView(model: container.libraryModel, personalLibrary: true, title: "我的音乐")
                    } label: {
                        Label("我的音乐", systemImage: "music.note.list")
                    }
                    NavigationLink {
                        FavoritesView(model: container.libraryModel)
                    } label: {
                        Label("收藏", systemImage: "heart.fill")
                    }
                    NavigationLink {
                        LibraryTracksView(title: String(localized: "最近播放"),
                                          tracks: container.libraryModel.recentlyPlayed, model: container.libraryModel)
                    } label: {
                        Label("最近播放", systemImage: "clock.arrow.circlepath")
                    }
                    NavigationLink {
                        PlayerPersonalizationView()
                    } label: {
                        Label("主题与个性化", systemImage: "paintpalette")
                    }
                    NavigationLink {
                        settings
                    } label: {
                        Label("设置", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("personal.settings")
                }
                .navigationTitle("我的")
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .tag(3)
        }
        .tint(PlayerTheme.accent)
        .modifier(AdaptiveTabNavigation())
    }

    private var settings: some View {
        List {
                    Section("播放") {
                        LabeledContent("来源", value: String(localized: "本地文件与开放许可音乐"))
                        LabeledContent("后台播放", value: String(localized: "已启用"))
                    }
                    Section("格式") {
                        Text("MP3 · M4A/AAC · FLAC · WAV · AIFF")
                        Text("iOS 版不支持 OGG")
                            .foregroundStyle(.secondary)
                    }
                    Section("隐私") {
                        Text("联网用于在线音乐搜索、后台补全封面、主动查找歌词和版本检查，不上传音乐文件。")
                        NavigationLink("封面搜索设置") {
                            CoverSearchSettingsView(library: container.libraryModel)
                        }
                    }
                    Section("关于") {
                        ShareLink(item: PlayerInteractionDiagnostics.fileURL) {
                            Label("导出播放器诊断日志", systemImage: "square.and.arrow.up")
                        }
                        ShareLink(item: CrashExceptionDiagnostics.fileURL) {
                            Label("导出异常堆栈（若已记录）", systemImage: "doc.text.magnifyingglass")
                        }
                        Button {
                            if let url = storeUpdate?.storeURL {
                                UIApplication.shared.open(url)
                            }
                        } label: {
                            HStack {
                                Text("版本")
                                Spacer()
                                Text("\(currentVersion) (\(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))")
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
                .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 72) }
                .task {
                    guard !didCheckStore else { return }
                    didCheckStore = true
                    storeUpdate = await AppStoreUpdate.lookup(bundleIdentifier: AppIdentity.bundleIdentifier)
                }
    }
}
