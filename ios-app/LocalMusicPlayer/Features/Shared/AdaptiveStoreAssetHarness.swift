#if DEBUG
import SwiftUI
import AVFoundation

// 隔离的内存资料库：正式 AppShell、播放器和音频引擎，演示内容不进入发布包。
@MainActor
struct AdaptiveStoreAssetHarness: View {
    @State private var container: AppContainer?
    @State private var error = ""

    var body: some View {
        Group {
            if let container {
                AppShellView(container: container, initialOnlineResults: samples)
                    .overlay(alignment: .topLeading) {
                        PlaybackEvidence(model: container.nowPlayingModel, engineID: String(describing: ObjectIdentifier(container.playback)))
                    }
            } else if !error.isEmpty { Text(error) }
            else { ProgressView() }
        }
        .task {
            guard container == nil else { return }
            do {
                let value = try AppContainer(inMemory: true)
                try Self.seed(value)
                container = value
                let tracks = value.libraryModel.tracks
                if let first = tracks.first { try await value.playback.playTrack(first, in: tracks) }
            } catch { self.error = "演示资料准备失败：\(error.localizedDescription)" }
        }
    }

    private var samples: [CatalogTrack] {
        ["夜色慢行", "海边来信", "晴空序曲", "城市微光"].enumerated().map { index, title in
            CatalogTrack(id: "demo-online-\(index)", title: title, artist: "爱乐之城 · 演示音乐",
                audioURL: FileManager.default.temporaryDirectory.appendingPathComponent("adaptive-store-assets/demo.wav"),
                license: .unknown, provider: "演示搜索结果",
                previewURL: FileManager.default.temporaryDirectory.appendingPathComponent("adaptive-store-assets/demo.wav"))
        }
    }

    private static func seed(_ container: AppContainer) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("adaptive-store-assets", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let audio = root.appendingPathComponent("demo.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 22050, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 22050)!
        buffer.frameLength = buffer.frameCapacity
        buffer.floatChannelData![0].initialize(repeating: 0, count: Int(buffer.frameLength))
        let file = try AVAudioFile(forWriting: audio, settings: format.settings)
        for _ in 0..<120 { try file.write(from: buffer) }
        let titles = ["夜色慢行", "海边来信", "晴空序曲", "城市微光", "午后散步", "远方的风"]
        for (index, title) in titles.enumerated() {
            let cover = root.appendingPathComponent("cover-\(index).jpg")
            try ProceduralArtworkGenerator().generateArtwork(title: title, artist: "爱乐之城", seed: "store-\(index)").write(to: cover)
            let lyrics = root.appendingPathComponent("lyrics-\(index).lrc")
            try "[00:00.00]晚风经过安静的街\n[00:10.00]耳边是熟悉的旋律\n[00:20.00]把今天慢慢收进歌里\n[00:30.00]让心情随音乐远行\n[00:40.00]灯光落在回家的路\n[00:50.00]喜欢的歌一直在身边".write(to: lyrics, atomically: true, encoding: .utf8)
            let track = TrackRecord(id: "store-demo-\(index)", title: title, artist: "爱乐之城 · 演示音乐",
                album: "随身珍藏", duration: 120, sourceKind: .importedFile, sourceReference: audio.path,
                artworkReference: cover.path, lyricsReference: lyrics.path, isLiked: index < 2)
            try container.store.upsert(track)
        }
        try container.libraryModel.reload()
    }
}

private struct PlaybackEvidence: View {
    @Bindable var model: NowPlayingModel
    let engineID: String
    var body: some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier("fixture.realPlayback")
            .accessibilityValue("\(engineID)|\(model.state.position)|\(model.state.isPlaying)")
            .allowsHitTesting(false)
    }
}
#endif
