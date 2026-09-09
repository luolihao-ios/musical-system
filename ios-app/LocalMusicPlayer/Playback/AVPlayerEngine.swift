import AVFoundation
import Foundation

@MainActor
final class AVPlayerEngine: AudioEngine {
    var onEnded: (() async -> Void)?
    var onPositionChanged: ((TimeInterval) -> Void)?

    private let player = AVPlayer()
    private var periodicObserver: Any?
    private var completionObserver: NSObjectProtocol?

    init() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.25, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                self?.onPositionChanged?(max(time.seconds, 0))
            }
        }
    }

    isolated deinit {
        if let periodicObserver {
            player.removeTimeObserver(periodicObserver)
        }
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
        }
    }

    var duration: TimeInterval {
        let seconds = player.currentItem?.duration.seconds ?? 0
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    var position: TimeInterval {
        let seconds = player.currentTime().seconds
        return seconds.isFinite ? max(seconds, 0) : 0
    }

    var volume: Float {
        get { player.volume }
        set { player.volume = min(max(newValue, 0), 1) }
    }

    var isPlaying: Bool {
        player.timeControlStatus == .playing
    }

    func load(url: URL) async throws {
        guard !url.isFileURL || FileManager.default.fileExists(atPath: url.path) else {
            PlaybackDiagnostics.log("AVPlayer 找不到音频资源：\(url.path)")
            throw PlaybackError.invalidSource
        }
        PlaybackDiagnostics.log("AVPlayer 准备加载：\(url.path)")
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
        }
        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        completionObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.onEnded?()
            }
        }
        do {
            _ = try await item.asset.load(.isPlayable)
        } catch {
            PlaybackDiagnostics.log(
                "AVPlayer 资源不可播放：\(url.path)，错误=\(error.localizedDescription)"
            )
            player.replaceCurrentItem(with: nil)
            throw error
        }
        PlaybackDiagnostics.log("AVPlayer 资源可播放：\(url.path)")
    }

    func play() {
        player.play()
    }

    func pause() {
        player.pause()
    }

    func seek(to position: TimeInterval) {
        player.seek(
            to: CMTime(
                seconds: max(position, 0),
                preferredTimescale: 600
            ),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    func unload() {
        player.pause()
        if let completionObserver {
            NotificationCenter.default.removeObserver(completionObserver)
            self.completionObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }
}
