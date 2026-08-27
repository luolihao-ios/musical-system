import Foundation
import Observation

@MainActor
protocol PlaybackPreferencesStoring: AnyObject {
    func loadPlaybackPreferences() throws -> PlaybackPreferences
    func savePlaybackPreferences(_ preferences: PlaybackPreferences) throws
}

extension MusicStore: PlaybackPreferencesStoring {
}

@MainActor
protocol RandomIndexProviding {
    func index(upperBound: Int) -> Int
}

@MainActor
struct SystemRandomIndex: RandomIndexProviding {
    func index(upperBound: Int) -> Int {
        Int.random(in: 0..<upperBound)
    }
}

@MainActor
@Observable
final class PlaybackController: PlaybackControlling {
    private(set) var state = PlaybackState() {
        didSet {
            Array(stateObservers.values).forEach { $0(state) }
        }
    }
    @ObservationIgnored private var stateObservers:
        [UUID: (PlaybackState) -> Void] = [:]

    private let engine: any AudioEngine
    private let preferencesStore: any PlaybackPreferencesStoring
    private let random: any RandomIndexProviding
    private var preferences = PlaybackPreferences()
    private var loadedTrackID: String?
    private var restoredPositionApplied = false
    private var playbackGeneration = UUID()
    private var acceptsPositionUpdates = true

    init(
        engine: any AudioEngine = AVPlayerEngine(),
        preferencesStore: any PlaybackPreferencesStoring,
        random: any RandomIndexProviding = SystemRandomIndex()
    ) {
        self.engine = engine
        self.preferencesStore = preferencesStore
        self.random = random
        engine.onEnded = { [weak self] in
            try? await self?.handleCompletion()
        }
        engine.onPositionChanged = { [weak self] position in
            guard self?.acceptsPositionUpdates == true else { return }
            self?.state.position = position
        }
    }

    func initialize() throws {
        preferences = try preferencesStore.loadPlaybackPreferences()
        state.volume = min(max(preferences.volume, 0), 1)
        state.mode = preferences.mode
        engine.volume = Float(state.volume)
    }

    func loadQueue(
        _ tracks: [TrackSnapshot],
        startIndex: Int = 0
    ) throws {
        let restoredIndex = preferences.lastTrackID.flatMap { id in
            tracks.firstIndex(where: { $0.id == id })
        }
        let selectedIndex: Int? = tracks.isEmpty
            ? nil
            : restoredIndex ?? min(max(startIndex, 0), tracks.count - 1)
        loadedTrackID = nil
        restoredPositionApplied = false
        state.queue = tracks
        state.currentIndex = selectedIndex
        state.isPlaying = false
        state.position = 0
        state.duration = selectedIndex.map { tracks[$0].duration } ?? 0
    }

    func play() async throws {
        guard selectAvailableTrack() else { return }
        try await ensureCurrentLoaded()
        if !restoredPositionApplied,
           state.currentTrack?.id == preferences.lastTrackID,
           preferences.lastPosition > 0 {
            let restored = clamp(preferences.lastPosition)
            engine.seek(to: restored)
            state.position = restored
            restoredPositionApplied = true
        }
        engine.play()
        state.isPlaying = true
    }

    func playTrack(
        _ track: TrackSnapshot,
        in queue: [TrackSnapshot]
    ) async throws {
        let availableQueue = queue.filter(\.isAvailable)
        guard let index = availableQueue.firstIndex(where: {
            $0.id == track.id
        }) else {
            return
        }
        let generation = UUID()
        playbackGeneration = generation
        acceptsPositionUpdates = false
        engine.pause()
        loadedTrackID = nil
        restoredPositionApplied = true
        state.queue = availableQueue
        state.currentIndex = index
        state.isPlaying = false
        state.position = 0
        state.duration = availableQueue[index].duration

        try await loadCurrent(generation: generation)
        guard playbackGeneration == generation,
              state.currentTrack?.id == track.id else {
            return
        }
        acceptsPositionUpdates = true
        engine.seek(to: 0)
        engine.play()
        state.position = 0
        state.isPlaying = true
        try savePreferences()
    }

    func pause() throws {
        engine.pause()
        state.isPlaying = false
        state.position = engine.position
        try savePreferences()
    }

    func seek(to position: TimeInterval) throws {
        let clamped = clamp(position)
        engine.seek(to: clamped)
        state.position = clamped
        try savePreferences()
    }

    func setVolume(_ volume: Double) throws {
        state.volume = min(max(volume, 0), 1)
        engine.volume = Float(state.volume)
        try savePreferences()
    }

    func setMode(_ mode: PlaybackMode) throws {
        state.mode = mode
        try savePreferences()
    }

    func persistCurrentState() throws {
        state.position = engine.position
        try savePreferences()
    }

    func playQueueItem(at index: Int) async throws {
        guard state.queue.indices.contains(index),
              state.queue[index].isAvailable else {
            return
        }
        try await playTrack(state.queue[index], in: state.queue)
    }

    func moveQueue(fromOffsets: IndexSet, toOffset: Int) throws {
        guard !fromOffsets.isEmpty else { return }
        let currentTrackID = state.currentTrack?.id
        let moving = fromOffsets.sorted().compactMap { index in
            state.queue.indices.contains(index) ? state.queue[index] : nil
        }
        let remaining = state.queue.enumerated().compactMap { index, track in
            fromOffsets.contains(index) ? nil : track
        }
        let removedBeforeDestination = fromOffsets.filter {
            $0 < toOffset
        }.count
        let insertionIndex = min(
            max(toOffset - removedBeforeDestination, 0),
            remaining.count
        )
        var reordered = remaining
        reordered.insert(contentsOf: moving, at: insertionIndex)
        state.queue = reordered
        state.currentIndex = currentTrackID.flatMap { id in
            reordered.firstIndex(where: { $0.id == id })
        }
        try savePreferences()
    }

    func removeQueueItems(atOffsets: IndexSet) async throws {
        var validOffsets = IndexSet()
        for offset in atOffsets where state.queue.indices.contains(offset) {
            validOffsets.insert(offset)
        }
        guard !validOffsets.isEmpty else { return }
        let oldCurrentIndex = state.currentIndex
        let currentWasRemoved = oldCurrentIndex.map {
            validOffsets.contains($0)
        } ?? false
        let currentTrackID = state.currentTrack?.id
        var remaining = state.queue
        for index in validOffsets.sorted(by: >) {
            remaining.remove(at: index)
        }
        guard !remaining.isEmpty else {
            try clearQueue()
            return
        }

        if currentWasRemoved, let oldCurrentIndex {
            let removedBeforeCurrent = validOffsets.filter {
                $0 < oldCurrentIndex
            }.count
            let successorIndex = oldCurrentIndex - removedBeforeCurrent
            let wrappedIndex = successorIndex < remaining.count
                ? successorIndex
                : 0
            try await playTrack(remaining[wrappedIndex], in: remaining)
            return
        }

        state.queue = remaining
        state.currentIndex = currentTrackID.flatMap { id in
            remaining.firstIndex(where: { $0.id == id })
        }
        try savePreferences()
    }

    func clearQueue() throws {
        playbackGeneration = UUID()
        acceptsPositionUpdates = false
        engine.pause()
        engine.unload()
        loadedTrackID = nil
        restoredPositionApplied = true
        state.queue = []
        state.currentIndex = nil
        state.isPlaying = false
        state.position = 0
        state.duration = 0
        try savePreferences()
    }

    func next() async throws {
        guard moveToNextAvailable() else { return }
        try await loadAndPlayCurrent()
    }

    func previous() async throws {
        if engine.position > 3 {
            try seek(to: 0)
            return
        }
        guard moveToPreviousAvailable() else { return }
        try await loadAndPlayCurrent()
    }

    @discardableResult
    func observeState(
        _ observer: @escaping (PlaybackState) -> Void
    ) -> UUID {
        let id = UUID()
        stateObservers[id] = observer
        observer(state)
        return id
    }

    func removeStateObserver(_ id: UUID) {
        stateObservers[id] = nil
    }

    private func handleCompletion() async throws {
        if state.mode == .repeatOne {
            engine.seek(to: 0)
            engine.play()
            state.position = 0
            state.isPlaying = true
            return
        }
        try await next()
    }

    private func ensureCurrentLoaded() async throws {
        guard let track = state.currentTrack,
              loadedTrackID != track.id else {
            return
        }
        guard let url = sourceURL(for: track) else {
            throw PlaybackError.invalidSource
        }
        acceptsPositionUpdates = false
        try await engine.load(url: url)
        engine.volume = Float(state.volume)
        loadedTrackID = track.id
        state.position = 0
        state.duration = engine.duration > 0
            ? engine.duration
            : track.duration
        acceptsPositionUpdates = true
    }

    private func loadAndPlayCurrent() async throws {
        let generation = UUID()
        playbackGeneration = generation
        acceptsPositionUpdates = false
        loadedTrackID = nil
        restoredPositionApplied = true
        try await loadCurrent(generation: generation)
        guard playbackGeneration == generation else { return }
        acceptsPositionUpdates = true
        engine.seek(to: 0)
        engine.play()
        state.position = 0
        state.isPlaying = true
        try savePreferences()
    }

    private func loadCurrent(generation: UUID) async throws {
        guard let track = state.currentTrack,
              let url = sourceURL(for: track) else {
            throw PlaybackError.invalidSource
        }
        try await engine.load(url: url)
        guard playbackGeneration == generation,
              state.currentTrack?.id == track.id else {
            return
        }
        engine.volume = Float(state.volume)
        loadedTrackID = track.id
        state.position = 0
        state.duration = engine.duration > 0
            ? engine.duration
            : track.duration
    }

    private func selectAvailableTrack() -> Bool {
        if state.currentTrack?.isAvailable == true { return true }
        guard !state.queue.isEmpty else { return false }
        let current = state.currentIndex ?? -1
        for offset in 1...state.queue.count {
            let candidate = (current + offset) % state.queue.count
            if state.queue[candidate].isAvailable {
                state.currentIndex = candidate
                return true
            }
        }
        return false
    }

    private func moveToNextAvailable() -> Bool {
        guard !state.queue.isEmpty else { return false }
        if state.mode == .shuffle {
            let candidates = state.queue.indices.filter {
                state.queue[$0].isAvailable && $0 != state.currentIndex
            }
            guard !candidates.isEmpty else {
                return state.currentTrack?.isAvailable == true
            }
            state.currentIndex = candidates[
                random.index(upperBound: candidates.count)
            ]
            return true
        }
        let current = state.currentIndex ?? -1
        for offset in 1...state.queue.count {
            let candidate = (current + offset) % state.queue.count
            if state.queue[candidate].isAvailable {
                state.currentIndex = candidate
                return true
            }
        }
        return false
    }

    private func moveToPreviousAvailable() -> Bool {
        guard !state.queue.isEmpty else { return false }
        let current = state.currentIndex ?? 0
        for offset in 1...state.queue.count {
            let candidate = (
                current - offset + state.queue.count
            ) % state.queue.count
            if state.queue[candidate].isAvailable {
                state.currentIndex = candidate
                return true
            }
        }
        return false
    }

    private func clamp(_ position: TimeInterval) -> TimeInterval {
        let duration = engine.duration > 0 ? engine.duration : state.duration
        return min(max(position, 0), max(duration, 0))
    }

    private func savePreferences() throws {
        preferences = PlaybackPreferences(
            volume: state.volume,
            mode: state.mode,
            lastTrackID: state.currentTrack?.id,
            lastPosition: state.position
        )
        try preferencesStore.savePlaybackPreferences(preferences)
    }

    private func sourceURL(for track: TrackSnapshot) -> URL? {
        switch track.sourceKind {
        case .importedFile:
            return URL(fileURLWithPath: track.sourceReference)
        case .mediaLibrary:
            return URL(string: track.sourceReference)
        }
    }
}

enum PlaybackError: Error {
    case invalidSource
}
