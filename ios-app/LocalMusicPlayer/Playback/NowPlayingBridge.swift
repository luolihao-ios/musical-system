import Foundation
import MediaPlayer
import UIKit

@MainActor
protocol PlaybackControlling: AnyObject {
    var state: PlaybackState { get }

    func play() async throws
    func pause() throws
    func next() async throws
    func previous() async throws
    func seek(to position: TimeInterval) throws
    func setVolume(_ volume: Double) throws
    func setMode(_ mode: PlaybackMode) throws
    func playTrack(
        _ track: TrackSnapshot,
        in queue: [TrackSnapshot]
    ) async throws
    func playQueueItem(at index: Int) async throws
    func moveQueue(fromOffsets: IndexSet, toOffset: Int) throws
    func removeQueueItems(atOffsets: IndexSet) async throws
    func clearQueue() throws
    @discardableResult
    func observeState(
        _ observer: @escaping (PlaybackState) -> Void
    ) -> UUID
    func removeStateObserver(_ id: UUID)
}

struct SystemNowPlayingInfo: Equatable, Sendable {
    let title: String
    let artist: String
    let album: String
    let artworkPath: String?
    let duration: TimeInterval
    let elapsed: TimeInterval
    let playbackRate: Double

    static let empty = SystemNowPlayingInfo(
        title: "",
        artist: "",
        album: "",
        artworkPath: nil,
        duration: 0,
        elapsed: 0,
        playbackRate: 0
    )
}

@MainActor
protocol SystemNowPlayingSession: AnyObject {
    var onPlay: (() async -> Void)? { get set }
    var onPause: (() async -> Void)? { get set }
    var onNext: (() async -> Void)? { get set }
    var onPrevious: (() async -> Void)? { get set }
    var onSeek: ((TimeInterval) async -> Void)? { get set }

    func update(_ info: SystemNowPlayingInfo)
}

@MainActor
final class NowPlayingBridge {
    private let controller: any PlaybackControlling
    private let session: any SystemNowPlayingSession
    private var stateObserverID: UUID?

    init(
        controller: any PlaybackControlling,
        session: any SystemNowPlayingSession = MPNowPlayingSession()
    ) {
        self.controller = controller
        self.session = session
        session.onPlay = { [weak controller] in
            try? await controller?.play()
        }
        session.onPause = { [weak controller] in
            try? controller?.pause()
        }
        session.onNext = { [weak controller] in
            try? await controller?.next()
        }
        session.onPrevious = { [weak controller] in
            try? await controller?.previous()
        }
        session.onSeek = { [weak controller] position in
            try? controller?.seek(to: position)
        }
        stateObserverID = controller.observeState { [weak self] state in
            self?.update(state)
        }
    }

    isolated deinit {
        if let stateObserverID {
            controller.removeStateObserver(stateObserverID)
        }
        session.onPlay = nil
        session.onPause = nil
        session.onNext = nil
        session.onPrevious = nil
        session.onSeek = nil
    }

    private func update(_ state: PlaybackState) {
        guard let track = state.currentTrack else {
            session.update(.empty)
            return
        }
        session.update(
            SystemNowPlayingInfo(
                title: track.title,
                artist: track.artist,
                album: track.album,
                artworkPath: track.artworkReference,
                duration: max(state.duration, 0),
                elapsed: min(max(state.position, 0), max(state.duration, 0)),
                playbackRate: state.isPlaying ? 1 : 0
            )
        )
    }
}

@MainActor
final class MPNowPlayingSession: SystemNowPlayingSession {
    var onPlay: (() async -> Void)?
    var onPause: (() async -> Void)?
    var onNext: (() async -> Void)?
    var onPrevious: (() async -> Void)?
    var onSeek: ((TimeInterval) async -> Void)?

    private var commandTargets: [(MPRemoteCommand, Any)] = []

    init() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true

        add(commands.playCommand) { [weak self] _ in
            Task { @MainActor in await self?.onPlay?() }
            return .success
        }
        add(commands.pauseCommand) { [weak self] _ in
            Task { @MainActor in await self?.onPause?() }
            return .success
        }
        add(commands.nextTrackCommand) { [weak self] _ in
            Task { @MainActor in await self?.onNext?() }
            return .success
        }
        add(commands.previousTrackCommand) { [weak self] _ in
            Task { @MainActor in await self?.onPrevious?() }
            return .success
        }
        add(commands.changePlaybackPositionCommand) { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            Task { @MainActor in
                await self?.onSeek?(event.positionTime)
            }
            return .success
        }
    }

    isolated deinit {
        commandTargets.forEach { command, target in
            command.removeTarget(target)
        }
    }

    func update(_ info: SystemNowPlayingInfo) {
        var values: [String: Any] = [
            MPMediaItemPropertyTitle: info.title,
            MPMediaItemPropertyArtist: info.artist,
            MPMediaItemPropertyAlbumTitle: info.album,
            MPMediaItemPropertyPlaybackDuration: info.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: info.elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: info.playbackRate
        ]
        if let path = info.artworkPath,
           let image = UIImage(contentsOfFile: path) {
            values[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(
                boundsSize: image.size
            ) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = values
    }

    private func add(
        _ command: MPRemoteCommand,
        handler: @escaping (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus
    ) {
        let target = command.addTarget(handler: handler)
        commandTargets.append((command, target))
    }
}
