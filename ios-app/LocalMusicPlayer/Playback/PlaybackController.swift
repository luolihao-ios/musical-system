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
        var initializedState = state
        initializedState.volume = min(max(preferences.volume, 0), 1)
        initializedState.mode = preferences.mode
        state = initializedState
        engine.volume = Float(initializedState.volume)
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
        playbackGeneration = UUID()
        acceptsPositionUpdates = false
        loadedTrackID = nil
        restoredPositionApplied = false
        var restoredState = state
        restoredState.queue = tracks
        restoredState.currentIndex = selectedIndex
        restoredState.isPlaying = false
        restoredState.position = 0
        restoredState.duration = selectedIndex.map {
            tracks[$0].duration
        } ?? 0
        state = restoredState
    }

    func restoreQueueIfPossible(_ tracks: [TrackSnapshot]) throws {
        let availableTracks = tracks.filter(\.isAvailable)
        guard let lastTrackID = preferences.lastTrackID,
              let index = availableTracks.firstIndex(where: {
                  $0.id == lastTrackID
              }) else {
            return
        }
        try loadQueue(availableTracks, startIndex: index)
    }

    func play() async throws {
        guard let index = availableTrackIndex() else { return }
        if state.currentIndex != index {
            var selectedState = state
            selectedState.currentIndex = index
            selectedState.isPlaying = false
            selectedState.position = 0
            selectedState.duration = state.queue[index].duration
            state = selectedState
        }
        guard try await ensureCurrentLoaded() else { return }
        if !restoredPositionApplied,
           state.currentTrack?.id == preferences.lastTrackID,
           preferences.lastPosition > 0 {
            let restored = clamp(preferences.lastPosition)
            engine.seek(to: restored)
            var restoredState = state
            restoredState.position = restored
            state = restoredState
            restoredPositionApplied = true
        }
        engine.play()
        var playingState = state
        playingState.isPlaying = true
        state = playingState
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
        var loadingState = state
        loadingState.queue = availableQueue
        loadingState.currentIndex = index
        loadingState.isPlaying = false
        loadingState.position = 0
        loadingState.duration = availableQueue[index].duration
        state = loadingState

        try await loadCurrent(generation: generation)
        guard playbackGeneration == generation,
              state.currentTrack?.id == track.id else {
            return
        }
        acceptsPositionUpdates = true
        engine.seek(to: 0)
        engine.play()
        var playingState = state
        playingState.position = 0
        playingState.isPlaying = true
        state = playingState
        try savePreferences()
    }

    func pause() throws {
        engine.pause()
        var pausedState = state
        pausedState.isPlaying = false
        pausedState.position = engine.position
        state = pausedState
        try savePreferences()
    }

    func seek(to position: TimeInterval) throws {
        let clamped = clamp(position)
        engine.seek(to: clamped)
        var seekState = state
        seekState.position = clamped
        state = seekState
        try savePreferences()
    }

    func setVolume(_ volume: Double) throws {
        var volumeState = state
        volumeState.volume = min(max(volume, 0), 1)
        state = volumeState
        engine.volume = Float(volumeState.volume)
        try savePreferences()
    }

    func setMode(_ mode: PlaybackMode) throws {
        var modeState = state
        modeState.mode = mode
        state = modeState
        try savePreferences()
    }

    func persistCurrentState() throws {
        var persistedState = state
        persistedState.position = engine.position
        state = persistedState
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
        var reorderedState = state
        reorderedState.queue = reordered
        reorderedState.currentIndex = currentTrackID.flatMap { id in
            reordered.firstIndex(where: { $0.id == id })
        }
        state = reorderedState
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
            let startIndex = successorIndex < remaining.count
                ? successorIndex
                : 0
            let successor = (0..<remaining.count).compactMap { offset in
                let index = (startIndex + offset) % remaining.count
                return remaining[index].isAvailable
                    ? remaining[index]
                    : nil
            }.first
            guard let successor else {
                try clearQueue()
                return
            }
            try await playTrack(successor, in: remaining)
            return
        }

        var remainingState = state
        remainingState.queue = remaining
        remainingState.currentIndex = currentTrackID.flatMap { id in
            remaining.firstIndex(where: { $0.id == id })
        }
        state = remainingState
        try savePreferences()
    }

    func clearQueue() throws {
        playbackGeneration = UUID()
        acceptsPositionUpdates = false
        engine.pause()
        engine.unload()
        loadedTrackID = nil
        restoredPositionApplied = true
        var clearedState = state
        clearedState.queue = []
        clearedState.currentIndex = nil
        clearedState.isPlaying = false
        clearedState.position = 0
        clearedState.duration = 0
        state = clearedState
        try savePreferences()
    }

    func next() async throws {
        guard let index = nextAvailableIndex() else { return }
        try await playTrack(state.queue[index], in: state.queue)
    }

    func previous() async throws {
        if engine.position > 3 {
            try seek(to: 0)
            return
        }
        guard let index = previousAvailableIndex() else { return }
        try await playTrack(state.queue[index], in: state.queue)
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
            var repeatedState = state
            repeatedState.position = 0
            repeatedState.isPlaying = true
            state = repeatedState
            return
        }
        try await next()
    }

    private func ensureCurrentLoaded() async throws -> Bool {
        guard let track = state.currentTrack,
              loadedTrackID != track.id else {
            return state.currentTrack != nil
        }
        let generation = UUID()
        playbackGeneration = generation
        acceptsPositionUpdates = false
        try await loadCurrent(generation: generation)
        guard playbackGeneration == generation,
              state.currentTrack?.id == track.id else {
            return false
        }
        acceptsPositionUpdates = true
        return true
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
        var loadedState = state
        loadedState.position = 0
        loadedState.duration = engine.duration > 0
            ? engine.duration
            : track.duration
        state = loadedState
    }

    private func availableTrackIndex() -> Int? {
        if state.currentTrack?.isAvailable == true {
            return state.currentIndex
        }
        guard !state.queue.isEmpty else { return nil }
        let current = state.currentIndex ?? -1
        for offset in 1...state.queue.count {
            let candidate = (current + offset) % state.queue.count
            if state.queue[candidate].isAvailable {
                return candidate
            }
        }
        return nil
    }

    private func nextAvailableIndex() -> Int? {
        guard !state.queue.isEmpty else { return nil }
        if state.mode == .shuffle {
            let candidates = state.queue.indices.filter {
                state.queue[$0].isAvailable && $0 != state.currentIndex
            }
            guard !candidates.isEmpty else {
                return state.currentTrack?.isAvailable == true
                    ? state.currentIndex
                    : nil
            }
            return candidates[
                random.index(upperBound: candidates.count)
            ]
        }
        let current = state.currentIndex ?? -1
        for offset in 1...state.queue.count {
            let candidate = (current + offset) % state.queue.count
            if state.queue[candidate].isAvailable {
                return candidate
            }
        }
        return nil
    }

    private func previousAvailableIndex() -> Int? {
        guard !state.queue.isEmpty else { return nil }
        let current = state.currentIndex ?? 0
        for offset in 1...state.queue.count {
            let candidate = (
                current - offset + state.queue.count
            ) % state.queue.count
            if state.queue[candidate].isAvailable {
                return candidate
            }
        }
        return nil
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
