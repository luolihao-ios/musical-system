import Foundation
import Observation

protocol LyricsReading: Sendable {
    func read(path: String) throws -> String?
}

struct FileLyricsReader: LyricsReading {
    func read(path: String) throws -> String? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        return try String(contentsOfFile: path, encoding: .utf8)
    }
}

@MainActor
@Observable
final class NowPlayingModel {
    private(set) var state: PlaybackState
    private(set) var lyricLines: [LyricLine] = []
    private(set) var currentLyricIndex: Int?
    var reduceMotion: Bool

    private let playback: any PlaybackControlling
    private let lyricsReader: any LyricsReading
    private var loadedTrackID: String?
    private var observerID: UUID?

    init(
        playback: any PlaybackControlling,
        lyricsReader: any LyricsReading = FileLyricsReader(),
        reduceMotion: Bool = false
    ) {
        self.playback = playback
        self.lyricsReader = lyricsReader
        self.reduceMotion = reduceMotion
        state = playback.state
        observerID = playback.observeState { [weak self] state in
            self?.apply(state)
        }
    }

    deinit {
        if let observerID {
            playback.removeStateObserver(observerID)
        }
    }

    var hasLyrics: Bool { !lyricLines.isEmpty }

    var isRecordRotating: Bool {
        state.isPlaying && !reduceMotion
    }

    var progress: Double {
        guard state.duration > 0 else { return 0 }
        return min(max(state.position / state.duration, 0), 1)
    }

    func togglePlayback() async {
        if state.isPlaying {
            try? playback.pause()
        } else {
            try? await playback.play()
        }
    }

    func next() async {
        try? await playback.next()
    }

    func previous() async {
        try? await playback.previous()
    }

    func seek(fraction: Double) throws {
        try playback.seek(
            to: state.duration * min(max(fraction, 0), 1)
        )
    }

    private func apply(_ state: PlaybackState) {
        self.state = state
        if loadedTrackID != state.currentTrack?.id {
            loadedTrackID = state.currentTrack?.id
            loadLyrics(path: state.currentTrack?.lyricsReference)
        }
        currentLyricIndex = LRCParser.currentIndex(
            lines: lyricLines,
            position: state.position
        )
    }

    private func loadLyrics(path: String?) {
        guard let path else {
            lyricLines = []
            return
        }
        do {
            lyricLines = LRCParser.parse(
                try lyricsReader.read(path: path) ?? ""
            )
        } catch {
            lyricLines = []
        }
    }
}
