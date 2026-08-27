# iOS Unified Playback and Player Interactions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every song-selection entry use one atomic playback path, keep audio and lyrics bound to the same Track ID, and complete the requested library, lyrics, Now Playing, Mini Player, and queue interactions.

**Architecture:** `PlaybackController` remains the only owner of the queue and current track. A new `playTrack(_:in:)` method performs every user-initiated transition, while generation checks prevent stale audio or lyric work from committing. Views receive observable state through their existing models and never keep a second current-song value.

**Tech Stack:** Swift 6, SwiftUI, Observation, AVFoundation/AVPlayer, SwiftData, XCTest, iOS 17, XcodeGen

**Spec:** `docs/superpowers/specs/2026-08-28-ios-playback-state-and-player-interactions-design.md`

## Global Constraints

- Minimum deployment target remains iOS 17.0.
- Do not add online song, lyric, or artwork search/download behavior.
- Do not add third-party dependencies.
- `PlaybackController.state.currentTrack` is the only current-track source.
- Every asynchronous result must validate its Track ID before changing visible state.
- The Windows WPF application is outside this plan.
- Xcode and iOS Simulator are unavailable on the Windows development host. Write each XCTest before its implementation, but run the listed XCTest commands on GitHub's macOS runner through `ios-app/scripts/verify.sh`; never claim local execution of those commands.

---

## File Map

- `ios-app/LocalMusicPlayer/Playback/PlaybackController.swift`: atomic track selection, queue mutation, generation validation, persistence.
- `ios-app/LocalMusicPlayer/Playback/PlaybackState.swift`: remains the value snapshot consumed by every UI model.
- `ios-app/LocalMusicPlayer/Playback/AudioEngine.swift`: adds explicit resource unloading.
- `ios-app/LocalMusicPlayer/Playback/AVPlayerEngine.swift`: unloads the current `AVPlayerItem` and completion observer.
- `ios-app/LocalMusicPlayer/Playback/NowPlayingBridge.swift`: exposes unified selection and queue mutations through `PlaybackControlling`.
- `ios-app/LocalMusicPlayer/Features/Library/LibraryModel.swift`: passes the visible list as selection context and observes the global current Track ID.
- `ios-app/LocalMusicPlayer/Features/Library/LibraryView.swift`: correct counts, correct contextual queues, and playing-row indicator.
- `ios-app/LocalMusicPlayer/Features/Playlists/PlaylistsModel.swift`: routes playlist selection through `playTrack(_:in:)`.
- `ios-app/LocalMusicPlayer/Import/FileImportService.swift`: metadata-first display with conservative filename fallback parsing.
- `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingModel.swift`: Track-ID-bound async lyric state, direct timestamp seek, and queue commands.
- `ios-app/LocalMusicPlayer/Features/NowPlaying/SyncedLyricsView.swift`: tap-to-seek and manual-browsing auto-follow suppression.
- `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingView.swift`: mutually exclusive record/lyrics modes, streamlined controls, editable queue.
- `ios-app/LocalMusicPlayer/Features/Shared/MiniPlayerView.swift`: full-strip navigation hit area with independent transport controls.
- `ios-app/LocalMusicPlayerTests/*.swift`: behavior-focused regression tests for every state transition.

---

### Task 1: Atomic Track Selection and Queue Ownership

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Playback/PlaybackController.swift`
- Modify: `ios-app/LocalMusicPlayer/Playback/AudioEngine.swift`
- Modify: `ios-app/LocalMusicPlayer/Playback/AVPlayerEngine.swift`
- Modify: `ios-app/LocalMusicPlayer/Playback/NowPlayingBridge.swift`
- Test: `ios-app/LocalMusicPlayerTests/PlaybackControllerTests.swift`
- Test: `ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift`
- Test: `ios-app/LocalMusicPlayerTests/NowPlayingBridgeTests.swift`

**Interfaces:**
- Consumes: `TrackSnapshot`, `PlaybackState`, `PlaybackPreferencesStoring`, and `AudioEngine`.
- Produces: `playTrack(_ track: TrackSnapshot, in queue: [TrackSnapshot]) async throws`, `moveQueue(fromOffsets: IndexSet, toOffset: Int) throws`, `removeQueueItems(atOffsets: IndexSet) async throws`, `clearQueue() throws`, and `AudioEngine.unload()`.

- [ ] **Step 1: Write regression tests for user-selected track priority**

Add a test whose preferences restore `one`, then explicitly select `two`:

```swift
func testPlayTrackOverridesRestoredTrackAndStartsAtZero() async throws {
    let engine = FakeAudioEngine()
    engine.position = 37
    let controller = PlaybackController(
        engine: engine,
        preferencesStore: FakePreferencesStore(
            value: PlaybackPreferences(lastTrackID: "one", lastPosition: 37)
        )
    )
    try controller.initialize()
    let queue = [track("one"), track("two")]

    try await controller.playTrack(queue[1], in: queue)

    XCTAssertEqual(controller.state.currentTrack?.id, "two")
    XCTAssertEqual(controller.state.position, 0)
    XCTAssertEqual(engine.loadedURLs.last?.lastPathComponent, "two.m4a")
    XCTAssertEqual(engine.lastSeek, 0)
    XCTAssertTrue(controller.state.isPlaying)
}
```

- [ ] **Step 2: Write queue mutation tests**

Cover these exact cases in `PlaybackControllerTests`:

```swift
func testMovingQueueKeepsCurrentTrackAndRepairsIndex() async throws
func testRemovingCurrentTrackPlaysNextTrack() async throws
func testRemovingLastCurrentTrackWrapsToFirstTrack() async throws
func testRemovingOnlyTrackStopsAndClearsPlayback() async throws
func testClearQueueStopsUnloadsAndClearsState() async throws
```

Assert Track IDs, queue order, `currentIndex`, `isPlaying`, position, duration, engine load URL, pause count, and unload count.

- [ ] **Step 3: Run the iOS suite on macOS to verify the new tests fail**

Run: `./ios-app/scripts/verify.sh`

Expected: compile failures for the new playback and queue APIs, proving the regression tests precede implementation.

- [ ] **Step 4: Extend the playback interfaces**

Add these requirements to `PlaybackControlling` and remove no-op defaults for state-changing operations so fake implementations must be explicit:

```swift
func playTrack(_ track: TrackSnapshot, in queue: [TrackSnapshot]) async throws
func moveQueue(fromOffsets: IndexSet, toOffset: Int) throws
func removeQueueItems(atOffsets: IndexSet) async throws
func clearQueue() throws
```

Add to `AudioEngine`:

```swift
func unload()
```

In `AVPlayerEngine.unload()`, pause, remove the completion observer, set it to `nil`, and call `player.replaceCurrentItem(with: nil)`.

- [ ] **Step 5: Implement the atomic playback transition**

Add a monotonically changing `UUID` generation in `PlaybackController`. `playTrack` must:

```swift
let availableQueue = queue.filter(\.isAvailable)
guard let index = availableQueue.firstIndex(where: { $0.id == track.id }) else {
    return
}
let generation = UUID()
playbackGeneration = generation
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
      state.currentTrack?.id == track.id else { return }
engine.seek(to: 0)
engine.play()
state.position = 0
state.isPlaying = true
try savePreferences()
```

Refactor next, previous, queue selection, and completion advancement to reuse a private generation-aware current-track loader. Keep `loadQueue` only for initial state restoration; it must not be called by user-selection pages after later tasks.

- [ ] **Step 6: Implement queue mutation semantics**

Use the current Track ID, not the old index, as the invariant during reorder. After moving, find the same Track ID in the reordered queue and assign its new index.

When deleting the current track, derive the successor from the original removal position. After deletion, choose the item now at that position; if the position equals the new count, choose index zero. Call the same private atomic loader and start playback. If no tracks remain, call `clearQueue()`.

`clearQueue()` must invalidate the generation, pause and unload the engine, reset `loadedTrackID`, clear queue/current index, set `isPlaying = false`, and zero position/duration before saving preferences.

- [ ] **Step 7: Update test fakes and run the suite**

Add deterministic `pauseCount` and `unloadCount` tracking to every `AudioEngine` fake and explicit no-op implementations of the new `PlaybackControlling` methods where a test does not exercise them.

Run: `./ios-app/scripts/verify.sh`

Expected: all playback, bridge, and existing tests pass.

- [ ] **Step 8: Commit the playback core**

```bash
git add ios-app/LocalMusicPlayer/Playback ios-app/LocalMusicPlayerTests/PlaybackControllerTests.swift ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift ios-app/LocalMusicPlayerTests/NowPlayingBridgeTests.swift
git commit -m "fix: unify iOS track selection and queue state"
```

---

### Task 2: Route Library, Search, Groups, and Playlists Through One Entry

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Features/Library/LibraryModel.swift`
- Modify: `ios-app/LocalMusicPlayer/Features/Library/LibraryView.swift`
- Modify: `ios-app/LocalMusicPlayer/Features/Playlists/PlaylistsModel.swift`
- Test: `ios-app/LocalMusicPlayerTests/LibraryModelTests.swift`
- Test: `ios-app/LocalMusicPlayerTests/PlaylistsModelTests.swift`

**Interfaces:**
- Consumes: `PlaybackControlling.playTrack(_:in:)` and playback state observation from Task 1.
- Produces: `LibraryModel.play(_ track: TrackSnapshot, in queue: [TrackSnapshot]) async throws` and observable `LibraryModel.currentTrackID`/`isPlaying` values.

- [ ] **Step 1: Replace the old library fake expectation with contextual selection tests**

Change `FakeLibraryPlayback` to capture `selectedTrack` and `queue` from:

```swift
func playTrack(_ track: TrackSnapshot, in queue: [TrackSnapshot]) async throws {
    selectedTrack = track
    self.queue = queue
}
```

Test that searching for `beyonce` passes only the filtered result, while selecting a song in an album detail passes every available track in that album in displayed order.

- [ ] **Step 2: Add a playlist routing regression test**

In `PlaylistsModelTests`, construct a playlist containing two tracks, select the second, and assert the fake receives the second Track ID plus both playlist tracks. Assert the old `loadQueue` and separate `play()` counters no longer exist.

- [ ] **Step 3: Run the iOS suite on macOS to verify routing tests fail**

Run: `./ios-app/scripts/verify.sh`

Expected: failures because the models still call `loadQueue` followed by `play()`.

- [ ] **Step 4: Change the library playback protocol and model**

Replace `LibraryPlaybackControlling.loadQueue/play` with:

```swift
var state: PlaybackState { get }
func playTrack(_ track: TrackSnapshot, in queue: [TrackSnapshot]) async throws
@discardableResult
func observeState(_ observer: @escaping (PlaybackState) -> Void) -> UUID
func removeStateObserver(_ id: UUID)
```

Have `LibraryModel` observe playback and publish:

```swift
private(set) var currentTrackID: String?
private(set) var isCurrentTrackPlaying = false
```

Implement `play(_:in:)` by filtering unavailable tracks, forwarding the explicit context to `playTrack`, recording play history, and reloading the library. Keep `play(_:)` as a convenience that passes `filteredTracks` for the homepage/search list.

- [ ] **Step 5: Pass each visible collection as its playback queue**

In `LibraryTracksView`, call:

```swift
Task { try? await model.play(track, in: tracks) }
```

Keep homepage/search rows calling `model.play(track)`. Change `PlaylistsModel.play(_:in:)` to pass `tracks(in:)` directly to `playTrack`.

- [ ] **Step 6: Add the current-song row indicator and correct count labels**

Add `isCurrent` and `isPlaying` inputs to `TrackRow`. For the current row, use `PlayerTheme.accent` on the title and show `speaker.wave.2.fill` when playing or `pause.circle.fill` when paused. Other rows retain their normal artwork and title colors.

Change `LibraryEntranceCard` to receive a display string instead of appending `项` internally. Supply `"专辑 \(count)"`, `"歌手 \(count)"`, `"文件夹 \(count)"`, and `"最近播放 \(count) 首"` semantics without describing a group count as a song count.

- [ ] **Step 7: Run the iOS suite**

Run: `./ios-app/scripts/verify.sh`

Expected: all library and playlist routing tests pass, including existing grouping and permission tests.

- [ ] **Step 8: Commit all selection entry points**

```bash
git add ios-app/LocalMusicPlayer/Features/Library ios-app/LocalMusicPlayer/Features/Playlists ios-app/LocalMusicPlayerTests/LibraryModelTests.swift ios-app/LocalMusicPlayerTests/PlaylistsModelTests.swift
git commit -m "fix: route iOS song lists through shared playback"
```

---

### Task 3: Metadata-First Titles With Filename Fallback

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Import/FileImportService.swift`
- Test: `ios-app/LocalMusicPlayerTests/FileImportServiceTests.swift`

**Interfaces:**
- Consumes: `ImportedMetadata` returned by `ImportedMetadataReading`.
- Produces: private `fallbackMetadata(filename: String) -> (title: String, artist: String)` used only when embedded metadata fields are empty.

- [ ] **Step 1: Write filename fallback tests**

Add cases with empty embedded metadata:

```swift
// "明天你好 (Live)-薛之谦,李玉刚.mp3"
XCTAssertEqual(track.title, "明天你好 (Live)")
XCTAssertEqual(track.artist, "薛之谦,李玉刚")

// "夜航星.mp3"
XCTAssertEqual(track.title, "夜航星")
XCTAssertEqual(track.artist, "")
```

Add a metadata-precedence case proving embedded title and artist remain unchanged even when the filename contains a hyphen.

- [ ] **Step 2: Run the iOS suite on macOS to verify the fallback test fails**

Run: `./ios-app/scripts/verify.sh`

Expected: the first fallback title still contains the artist suffix.

- [ ] **Step 3: Implement conservative fallback parsing**

Trim the extension and whitespace. Split only at the final `-` whose left and right trimmed components are both non-empty. Use the left side only when metadata title is empty and the right side only when metadata artist is empty. Never infer an album from the filename.

Resolve fields independently:

```swift
let title = embeddedTitle.isEmpty ? fallback.title : embeddedTitle
let artist = embeddedArtist.isEmpty ? fallback.artist : embeddedArtist
```

- [ ] **Step 4: Run the iOS suite**

Run: `./ios-app/scripts/verify.sh`

Expected: file import, metadata precedence, artwork, lyrics association, and cleanup tests all pass.

- [ ] **Step 5: Commit metadata display behavior**

```bash
git add ios-app/LocalMusicPlayer/Import/FileImportService.swift ios-app/LocalMusicPlayerTests/FileImportServiceTests.swift
git commit -m "fix: improve imported track metadata fallback"
```

---

### Task 4: Track-ID-Safe Lyrics and Timestamp Seeking

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingModel.swift`
- Test: `ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift`

**Interfaces:**
- Consumes: `PlaybackControlling.seek(to:)`, observed `PlaybackState`, and `TrackSnapshot.lyricsReference`.
- Produces: async `LyricsReading.read(path:)`, `NowPlayingModel.seek(to lyric: LyricLine)`, and Track-ID-bound lyric state.

- [ ] **Step 1: Make the lyric reader fake controllably asynchronous**

Change the protocol to:

```swift
protocol LyricsReading: Sendable {
    func read(path: String) async throws -> String?
}
```

Create an actor-backed test reader that holds continuations by path so tests can complete B before A.

- [ ] **Step 2: Write the stale-lyric regression test**

Publish track A, publish track B before A completes, then complete B with `B歌词` and A with `A歌词`. Await task processing and assert:

```swift
XCTAssertEqual(model.lyricTrackID, "B")
XCTAssertEqual(model.lyricLines.map(\.text), ["B歌词"])
```

Immediately after publishing B, assert `lyricLines.isEmpty` and `currentLyricIndex == nil` before completing either read.

- [ ] **Step 3: Write direct timestamp seek tests**

Construct `LyricLine(timestamp: 42, text: "副歌")`, call `model.seek(to: line)`, and assert the fake playback receives exactly 42 seconds. Test both playing and paused states and assert seeking does not toggle playback state.

- [ ] **Step 4: Run the iOS suite on macOS to verify lyric tests fail**

Run: `./ios-app/scripts/verify.sh`

Expected: compile failure for async lyrics and missing Track-ID/timestamp-seek APIs.

- [ ] **Step 5: Implement cancellation and result validation**

Store `lyricsTask: Task<Void, Never>?` and `private(set) var lyricTrackID: String?`. On Track ID change:

```swift
lyricsTask?.cancel()
lyricLines = []
currentLyricIndex = nil
lyricTrackID = nil
guard let track = state.currentTrack,
      let path = track.lyricsReference else { return }
let requestedID = track.id
lyricsTask = Task { [weak self] in
    let source = try? await self?.lyricsReader.read(path: path)
    guard !Task.isCancelled,
          self?.state.currentTrack?.id == requestedID else { return }
    self?.lyricLines = LRCParser.parse(source ?? "")
    self?.lyricTrackID = requestedID
    self?.updateCurrentLyricIndex()
}
```

Implement `FileLyricsReader.read` with a detached file read so disk I/O does not block the main actor, then return to `NowPlayingModel` for state mutation.

- [ ] **Step 6: Implement lyric timestamp seeking**

Add:

```swift
func seek(to lyric: LyricLine) throws {
    try playback.seek(to: lyric.timestamp)
}
```

Keep fractional progress seek as a separate method.

- [ ] **Step 7: Run the iOS suite**

Run: `./ios-app/scripts/verify.sh`

Expected: stale A lyrics never replace B lyrics, immediate clearing passes, and direct timestamp seek passes.

- [ ] **Step 8: Commit lyric state safety**

```bash
git add ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingModel.swift ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift
git commit -m "fix: bind iOS lyrics to current track"
```

---

### Task 5: Interactive Full-Size Lyrics and Record Toggle

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Features/NowPlaying/SyncedLyricsView.swift`
- Modify: `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingView.swift`

**Interfaces:**
- Consumes: `NowPlayingModel.lyricLines`, `currentLyricIndex`, `seek(to:)`, `hasLyrics`, `reduceMotion`, and `RecordVisual`.
- Produces: private `NowPlayingContentMode` with `.record` and `.lyrics`, plus lyrics browsing state scoped to `SyncedLyricsView`.

- [ ] **Step 1: Introduce mutually exclusive content modes**

Add:

```swift
private enum NowPlayingContentMode {
    case record
    case lyrics
}

@State private var contentMode: NowPlayingContentMode = .record
```

Replace the simultaneous record plus 210-point lyric block with one main content container sized from available geometry. Show `RecordVisual` in record mode and `SyncedLyricsView` in lyrics mode. If `hasLyrics` is false, keep record mode and show the no-lyrics message without switching to an empty lyrics view.

- [ ] **Step 2: Add accessible animated switching**

Tap the record to enter lyrics mode. In lyrics mode, provide a clearly labeled `唱片` control in the content corner so lyric-line taps remain reserved for seek. Use `.transition(.opacity.combined(with: .scale(scale: 0.98)))`; disable the animation when `reduceMotion` is true.

- [ ] **Step 3: Implement manual lyrics browsing**

In `SyncedLyricsView`, add:

```swift
@State private var isUserBrowsing = false
@State private var resumeFollowingTask: Task<Void, Never>?
@State private var selectedLyricID: LyricLine.ID?
```

Attach a simultaneous drag gesture that marks manual browsing on change and schedules auto-follow restoration two seconds after drag end. Guard automatic `scrollTo` with `!isUserBrowsing`.

Make each line a plain button. On tap, set the selected ID, call `model.seek(to:)`, set `isUserBrowsing = false`, cancel the delayed task, and scroll the selected line to center. The playback-time observer remains responsible for subsequent highlight changes.

- [ ] **Step 4: Remove volume controls and compact playback options**

Delete the speaker icons and volume Slider from `NowPlayingView`. Keep the playback mode as one 44-point minimum button near the transport controls. Retain progress, previous, play/pause, next, mode, and queue actions.

- [ ] **Step 5: Perform SwiftUI source checks**

Run on Windows:

```powershell
rg -n "setVolume|speaker\.wave\.3|accessibilityLabel\(\"音量\"" ios-app/LocalMusicPlayer/Features/NowPlaying
```

Expected: no matches in the Now Playing views. Inspect that record and lyrics are in opposite branches of one switch.

- [ ] **Step 6: Run the iOS suite on macOS**

Run: `./ios-app/scripts/verify.sh`

Expected: the app target and all tests compile and pass on iOS 17 Simulator.

- [ ] **Step 7: Commit player interaction changes**

```bash
git add ios-app/LocalMusicPlayer/Features/NowPlaying/SyncedLyricsView.swift ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingView.swift
git commit -m "feat: add interactive full-size iOS lyrics"
```

---

### Task 6: Editable Queue and Full-Width Mini Player

**Files:**
- Modify: `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingModel.swift`
- Modify: `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingView.swift`
- Modify: `ios-app/LocalMusicPlayer/Features/Shared/MiniPlayerView.swift`
- Test: `ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift`

**Interfaces:**
- Consumes: queue mutation APIs from Task 1.
- Produces: `NowPlayingModel.moveQueue(fromOffsets:toOffset:)`, `removeQueueItems(atOffsets:)`, and `clearQueue()` wrappers.

- [ ] **Step 1: Write model forwarding tests**

Use `FakeNowPlayingController` call capture to assert:

```swift
model.moveQueue(fromOffsets: IndexSet(integer: 0), toOffset: 2)
await model.removeQueueItems(atOffsets: IndexSet(integer: 1))
model.clearQueue()
```

Each operation must forward the exact offsets and destination once.

- [ ] **Step 2: Run the iOS suite on macOS to verify forwarding tests fail**

Run: `./ios-app/scripts/verify.sh`

Expected: missing wrapper APIs.

- [ ] **Step 3: Add queue wrappers to `NowPlayingModel`**

Use throwing controller calls internally and preserve the existing UI policy of not crashing on an operation error:

```swift
func moveQueue(fromOffsets: IndexSet, toOffset: Int) {
    try? playback.moveQueue(fromOffsets: fromOffsets, toOffset: toOffset)
}

func removeQueueItems(atOffsets: IndexSet) async {
    try? await playback.removeQueueItems(atOffsets: atOffsets)
}

func clearQueue() {
    try? playback.clearQueue()
}
```

- [ ] **Step 4: Add queue editing UI**

Keep current-row speaker highlighting. Add `.onMove` and `.onDelete` to the queue `ForEach`, an `EditButton` in the queue toolbar, and a destructive `清空` toolbar button disabled when the queue is empty. The row tap continues to use the shared selection flow through `playQueueItem(at:)`.

After clearing the queue, dismiss the queue sheet because there is no current item.

- [ ] **Step 5: Expand Mini Player navigation without nesting buttons**

Use a `ZStack` with a full-size transparent `Button(action: openNowPlaying)` as the back layer. Put the visible HStack in the front layer: artwork and text use `.allowsHitTesting(false)`, while play/pause and next remain independent front-layer buttons that intercept their own areas. Add `.contentShape(Rectangle())` to the background button and an accessibility label of `打开正在播放`.

Retain the top two-point progress bar and independent play/pause and next actions.

- [ ] **Step 6: Run the iOS suite**

Run: `./ios-app/scripts/verify.sh`

Expected: model forwarding, controller queue behavior, application compilation, and existing tests pass.

- [ ] **Step 7: Commit queue and Mini Player behavior**

```bash
git add ios-app/LocalMusicPlayer/Features/NowPlaying ios-app/LocalMusicPlayer/Features/Shared/MiniPlayerView.swift ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift
git commit -m "feat: complete iOS queue and mini player controls"
```

---

### Task 7: Final Consistency Audit and CI Handoff

**Files:**
- Modify only files required by failures found in this task.
- Verify: all files under `ios-app/LocalMusicPlayer` and `ios-app/LocalMusicPlayerTests`.

**Interfaces:**
- Consumes: all APIs and UI behavior from Tasks 1–6.
- Produces: one verified iOS source tree with every song-selection entry sharing `PlaybackController`.

- [ ] **Step 1: Audit for legacy split selection paths**

Run:

```powershell
rg -n "loadQueue\(|currentSong|currentTrack\s*=" ios-app/LocalMusicPlayer
rg -n "playTrack\(" ios-app/LocalMusicPlayer
```

Expected: `loadQueue` remains only in initial restoration/setup and core tests; user-facing library, search, groups, playlists, and queue selection reach `playTrack`. No page-level current-song property exists.

- [ ] **Step 2: Audit Track-ID lyric safety and removed volume UI**

Run:

```powershell
rg -n "requestedID|lyricTrackID|Task\.isCancelled" ios-app/LocalMusicPlayer/Features/NowPlaying
rg -n "accessibilityLabel\(\"音量\"|speaker\.wave\.3" ios-app/LocalMusicPlayer/Features/NowPlaying
```

Expected: lyric guards are present and no volume UI matches remain.

- [ ] **Step 3: Check formatting and unintended workspace changes**

Run:

```powershell
git diff --check
git status --short
git diff --stat
```

Expected: no whitespace errors. Preserve the user's unrelated untracked `.github/workflows/ios-artifact.yml` and `.github/workflows/windows-build.yml` files.

- [ ] **Step 4: Run final macOS verification**

Run on GitHub macOS: `./ios-app/scripts/verify.sh`

Expected: XcodeGen succeeds, the app compiles for an available iPhone Simulator, and all XCTest cases pass.

- [ ] **Step 5: Commit only verification fixes if needed**

```bash
git add ios-app
git commit -m "test: verify unified iOS playback experience"
```

Skip this commit when Step 4 requires no corrective source changes.

- [ ] **Step 6: Push the completed branch once**

Run: `git push origin feature/local-music-player`

Report the pushed commit hash and ask the user to send the GitHub build result when convenient; do not continuously poll the workflow.
