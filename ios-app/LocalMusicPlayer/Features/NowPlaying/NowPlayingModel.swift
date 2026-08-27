import Foundation
import Observation

protocol LyricsReading: Sendable {
    func read(path: String) async throws -> String?
}

struct FileLyricsReader: LyricsReading {
    func read(path: String) async throws -> String? {
        try await Task.detached(priority: .utility) {
            let fileManager = FileManager()
            guard fileManager.fileExists(atPath: path) else { return nil }
            return try String(contentsOfFile: path, encoding: .utf8)
        }.value
    }
}

@MainActor
@Observable
final class NowPlayingModel {
    private(set) var state: PlaybackState
    private(set) var lyricLines: [LyricLine] = []
    private(set) var currentLyricIndex: Int?
    private(set) var lyricTrackID: String?
    var reduceMotion: Bool

    private let playback: any PlaybackControlling
    private let lyricsReader: any LyricsReading
    private var requestedLyricTrackID: String?
    private var lyricsTask: Task<Void, Never>?
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

    isolated deinit {
        lyricsTask?.cancel()
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

    func seek(to lyric: LyricLine) throws {
        try playback.seek(to: lyric.timestamp)
    }

    func setVolume(_ volume: Double) {
        try? playback.setVolume(volume)
    }

    func cycleMode() {
        let modes = PlaybackMode.allCases
        let current = modes.firstIndex(of: state.mode) ?? 0
        try? playback.setMode(modes[(current + 1) % modes.count])
    }

    func playQueueItem(at index: Int) async {
        try? await playback.playQueueItem(at: index)
    }

    func moveQueue(fromOffsets: IndexSet, toOffset: Int) {
        try? playback.moveQueue(
            fromOffsets: fromOffsets,
            toOffset: toOffset
        )
    }

    func removeQueueItems(atOffsets: IndexSet) async {
        try? await playback.removeQueueItems(atOffsets: atOffsets)
    }

    func clearQueue() {
        try? playback.clearQueue()
    }

    private func apply(_ state: PlaybackState) {
        self.state = state
        if requestedLyricTrackID != state.currentTrack?.id {
            loadLyrics(for: state.currentTrack)
        }
        updateCurrentLyricIndex()
    }

    private func updateCurrentLyricIndex() {
        currentLyricIndex = LRCParser.currentIndex(
            lines: lyricLines,
            position: state.position
        )
    }

    private func loadLyrics(for track: TrackSnapshot?) {
        lyricsTask?.cancel()
        requestedLyricTrackID = track?.id
        lyricTrackID = nil
        lyricLines = []
        currentLyricIndex = nil
        guard let track,
              let path = track.lyricsReference else {
            return
        }
        let requestedID = track.id
        let reader = lyricsReader
        lyricsTask = Task { [weak self] in
            let source = try? await reader.read(path: path)
            guard !Task.isCancelled,
                  let self,
                  self.state.currentTrack?.id == requestedID,
                  self.requestedLyricTrackID == requestedID else {
                return
            }
            self.lyricLines = LRCParser.parse(source ?? "")
            self.lyricTrackID = requestedID
            self.updateCurrentLyricIndex()
        }
    }
}
