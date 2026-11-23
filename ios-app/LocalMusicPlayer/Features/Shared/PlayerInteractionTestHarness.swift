#if DEBUG
import SwiftUI

// 仅模拟器测试通过启动参数启用；复用生产播放器和停靠布局，不接触用户资料库。
struct PlayerInteractionTestHarness: View {
    @State private var model = NowPlayingModel(playback: InteractionTestPlayback())
    @State private var visible = true
    @State private var behindTapCount = 0

    var body: some View {
        PlayerDockContainer(model: model, isVisible: visible, dismiss: {}) {
            TabView {
                NavigationStack {
                    VStack {
                        Text("底层点击次数 \(behindTapCount)")
                        Button("重新显示播放器") { visible = true }
                        TrackRow(track: model.state.currentTrack!, isCurrent: false, isPlaying: false,
                            play: { behindTapCount += 1 }, toggleLike: {}, delete: {})
                            .accessibilityIdentifier("fixture.songRow")
                        Spacer()
                        Button("底层按钮") { behindTapCount += 1 }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("音乐库")
                }
                .tabItem { Label("音乐库", systemImage: "music.note") }
                Text("收藏").tabItem { Label("收藏", systemImage: "heart") }
            }
            .modifier(AdaptiveTabNavigation())
        }
    }
}

@MainActor
private final class InteractionTestPlayback: PlaybackControlling {
    var state: PlaybackState
    init() {
        let storeAssets = ProcessInfo.processInfo.arguments.contains("--store-assets")
        let title = storeAssets ? "夜色慢行" : "播放器交互测试"
        let artist = storeAssets ? "爱乐之城 · 演示音乐" : "测试音频"
        let root = FileManager.default.temporaryDirectory
        let artwork = root.appendingPathComponent("gesture-fixture.jpg")
        let lyrics = root.appendingPathComponent("gesture-fixture.lrc")
        let data = try? ProceduralArtworkGenerator().generateArtwork(
            title: title, artist: artist, seed: "gesture-fixture"
        )
        try? data?.write(to: artwork)
        let lyricText = storeAssets
            ? "[00:00.00]晚风经过安静的街\n[00:10.00]耳边是熟悉的旋律\n[00:20.00]把今天慢慢收进歌里\n[00:30.00]让心情随音乐远行\n[00:40.00]灯光落在回家的路\n[00:50.00]喜欢的歌一直在身边"
            : "[00:00.00]第一句测试歌词\n[00:10.00]第二句测试歌词"
        try? lyricText.write(to: lyrics, atomically: true, encoding: .utf8)
        state = PlaybackState(queue: [TrackSnapshot(
            id: "gesture-fixture", title: title, artist: artist,
            album: "测试专辑", duration: 240, sourceKind: .importedFile,
            sourceReference: "/test/audio.m4a", artworkReference: artwork.path,
            lyricsReference: lyrics.path
        )], currentIndex: 0, duration: 240)
    }
    private var observer: ((PlaybackState) -> Void)?
    func play() async throws { state.isPlaying = true; observer?(state) }
    func pause() throws { state.isPlaying = false; observer?(state) }
    func next() async throws {
        state.position = 10
        observer?(state)
    }
    func previous() async throws {}
    func seek(to position: TimeInterval) throws { state.position = position; observer?(state) }
    func setVolume(_ volume: Double) throws {}
    func setMode(_ mode: PlaybackMode) throws { state.mode = mode; observer?(state) }
    func playTrack(_ track: TrackSnapshot, in queue: [TrackSnapshot]) async throws {}
    func playQueueItem(at index: Int) async throws {}
    func moveQueue(fromOffsets: IndexSet, toOffset: Int) throws {}
    func removeQueueItems(atOffsets: IndexSet) async throws {}
    func clearQueue() throws {}
    func observeState(_ observer: @escaping (PlaybackState) -> Void) -> UUID {
        self.observer = observer
        observer(state)
        return UUID()
    }
    func removeStateObserver(_ id: UUID) { observer = nil }
}
#endif
