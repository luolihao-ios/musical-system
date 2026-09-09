#if DEBUG
import SwiftUI

// 仅模拟器测试通过启动参数启用；复用生产播放器和停靠布局，不接触用户资料库。
struct PlayerInteractionTestHarness: View {
    @State private var model = NowPlayingModel(playback: InteractionTestPlayback())
    @State private var visible = true
    @State private var behindTapCount = 0

    var body: some View {
        PlayerDockContainer(model: model, isVisible: visible, dismiss: { visible = false }) {
            TabView {
                NavigationStack {
                    VStack {
                        Text("底层点击次数 \(behindTapCount)")
                        Button("重新显示播放器") { visible = true }
                        Spacer()
                        Button("底层按钮") { behindTapCount += 1 }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .navigationTitle("音乐库")
                }
                .tabItem { Label("音乐库", systemImage: "music.note") }
                Text("收藏").tabItem { Label("收藏", systemImage: "heart") }
            }
        }
    }
}

@MainActor
private final class InteractionTestPlayback: PlaybackControlling {
    var state = PlaybackState(queue: [TrackSnapshot(
        id: "gesture-fixture", title: "播放器交互测试", artist: "测试音频",
        album: "测试专辑", duration: 240, sourceKind: .importedFile,
        sourceReference: "/test/audio.m4a"
    )], currentIndex: 0, duration: 240)
    private var observer: ((PlaybackState) -> Void)?
    func play() async throws { state.isPlaying = true; observer?(state) }
    func pause() throws { state.isPlaying = false; observer?(state) }
    func next() async throws {}
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
