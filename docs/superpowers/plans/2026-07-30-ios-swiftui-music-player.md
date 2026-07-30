# iOS SwiftUI Local Music Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an iOS 17+ native local music player in SwiftUI that imports local files, reads playable system-library items, supports synchronized lyrics and playlists, and produces an unsigned IPA on GitHub for Aisi signing.

**Architecture:** A SwiftUI application uses SwiftData repositories, protocol-isolated import and media-library gateways, and an AVFoundation playback controller. MediaPlayer bridges background metadata and remote commands, while GitHub macOS runners generate the Xcode project, test it, and package an unsigned device build.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, AVFoundation, MediaPlayer, UniformTypeIdentifiers, XCTest, XcodeGen, GitHub Actions.

## Global Constraints

- Minimum deployment target is iOS 17.
- Do not access an online music catalog or download/upload music.
- Keep iOS data fully independent from Windows data.
- Support MP3, M4A/AAC, FLAC, WAV, and AIFF; do not support OGG.
- Support both authorized system music-library items and Files-app imports.
- Testing uses a GitHub-generated unsigned IPA and Aisi signing, not Development or Ad Hoc signing.
- Production uses Apple Distribution and App Store Connect.
- Use original dark record-room styling; do not copy NetEase names, logos, copy, or assets.
- Preserve existing Flutter files until both native projects have a passing baseline build.

---

## File Map

```text
ios-app/
├─ project.yml
├─ LocalMusicPlayer/
│  ├─ App/
│  ├─ Domain/
│  ├─ Data/
│  ├─ Import/
│  ├─ Playback/
│  ├─ Lyrics/
│  ├─ Features/Library/
│  ├─ Features/Playlists/
│  ├─ Features/NowPlaying/
│  ├─ Resources/
│  └─ Info.plist
├─ LocalMusicPlayerTests/
└─ scripts/package-unsigned-ipa.sh
```

`Domain` contains Sendable value types, `Data` owns SwiftData, `Import` isolates platform permissions and files, `Playback` owns AVFoundation and MediaPlayer, and each feature folder owns one SwiftUI screen plus its observable model.

### Task 1: Create the XcodeGen project and SwiftUI shell

**Files:**
- Create: `ios-app/project.yml`
- Create: `ios-app/LocalMusicPlayer/App/LocalMusicPlayerApp.swift`
- Create: `ios-app/LocalMusicPlayer/App/AppShellView.swift`
- Create: `ios-app/LocalMusicPlayer/Info.plist`
- Create: `ios-app/LocalMusicPlayer/Resources/Assets.xcassets/Contents.json`
- Create: `ios-app/LocalMusicPlayerTests/AppIdentityTests.swift`

**Interfaces:**
- Produces: bundle identifier `com.luolihao.musicalsystem`, deployment target 17.0, and `AppIdentity.displayName`.

- [ ] **Step 1: Write the failing identity test**

```swift
import XCTest
@testable import LocalMusicPlayer

final class AppIdentityTests: XCTestCase {
    func testDisplayName() {
        XCTAssertEqual(AppIdentity.displayName, "暮色音乐")
    }
}
```

- [ ] **Step 2: Define the project and verify the test fails on macOS**

`project.yml` must define an iOS application target and an iOS unit-test target, use Swift 6, set `IPHONEOS_DEPLOYMENT_TARGET: 17.0`, and attach the test target to the `LocalMusicPlayer` scheme.

Run on a GitHub macOS runner or Mac:

```bash
xcodegen generate --spec ios-app/project.yml
xcodebuild test -project ios-app/LocalMusicPlayer.xcodeproj \
  -scheme LocalMusicPlayer -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: FAIL because `AppIdentity` does not exist.

- [ ] **Step 3: Implement the minimal app shell**

```swift
enum AppIdentity {
    static let displayName = "暮色音乐"
}

@main
struct LocalMusicPlayerApp: App {
    var body: some Scene {
        WindowGroup { AppShellView() }
    }
}
```

`AppShellView` contains three tabs: 音乐库, 歌单, and 设置.

- [ ] **Step 4: Verify build and tests**

Run:

```bash
xcodebuild test -project ios-app/LocalMusicPlayer.xcodeproj \
  -scheme LocalMusicPlayer -destination 'platform=iOS Simulator,name=iPhone 16'
```

Expected: PASS and the app target builds for the simulator.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "chore: scaffold iOS SwiftUI player"
```

### Task 2: Define SwiftData entities and repositories

**Files:**
- Create: `ios-app/LocalMusicPlayer/Domain/TrackRecord.swift`
- Create: `ios-app/LocalMusicPlayer/Domain/PlaylistRecord.swift`
- Create: `ios-app/LocalMusicPlayer/Data/MusicStore.swift`
- Create: `ios-app/LocalMusicPlayer/Data/ModelContainerFactory.swift`
- Test: `ios-app/LocalMusicPlayerTests/MusicStoreTests.swift`

**Interfaces:**
- Produces: `TrackRecord`, `PlaylistRecord`, `PlaylistEntryRecord`.
- Produces: `MusicStore.upsert`, `tracks`, `setLiked`, `createPlaylist`, `renamePlaylist`, `deletePlaylist`, `add`, `remove`, `recordPlay`, `loadPlaybackPreferences`, and `savePlaybackPreferences`.

- [ ] **Step 1: Write in-memory SwiftData tests**

Create an in-memory `ModelContainer` and verify track upsert, like persistence, non-deletable built-in “我喜欢”, custom playlist ordering, last-played updates, and persistence of volume, playback mode, last track, and last position.

```swift
let track = TrackRecord(id: "track-1", title: "落日之前",
    artist: "雾岛乐队", album: "城市夜行", duration: 258,
    sourceKind: .importedFile, sourceReference: "Music/track-1.m4a")
try store.upsert(track)
XCTAssertEqual(try store.tracks().map(\.id), ["track-1"])
```

- [ ] **Step 2: Verify tests fail**

Run the `MusicStoreTests` class with `xcodebuild test`.

Expected: FAIL because the models and store do not exist.

- [ ] **Step 3: Implement models and store**

Use:

```swift
enum TrackSourceKind: String, Codable { case importedFile, mediaLibrary }

@Model
final class TrackRecord {
    @Attribute(.unique) var id: String
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var sourceKindRaw: String
    var sourceReference: String
    var lyricsReference: String?
    var isLiked: Bool
    var isAvailable: Bool
    var lastPlayedAt: Date?
}
```

Store playlist entries as separate models with an integer `position`; seed built-in playlist id `liked` during container initialization. Store one `PlaybackPreferencesRecord` containing volume, playback mode, last track id, and last position.

- [ ] **Step 4: Verify repository behavior**

Run `MusicStoreTests`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios-app/LocalMusicPlayer/Domain ios-app/LocalMusicPlayer/Data ios-app/LocalMusicPlayerTests/MusicStoreTests.swift
git commit -m "feat: persist iOS music library"
```

### Task 3: Import Files-app audio and matching LRC

**Files:**
- Create: `ios-app/LocalMusicPlayer/Import/ImportedFile.swift`
- Create: `ios-app/LocalMusicPlayer/Import/FileImportService.swift`
- Create: `ios-app/LocalMusicPlayer/Import/ImportedMetadataReader.swift`
- Create: `ios-app/LocalMusicPlayer/Import/DocumentPickerView.swift`
- Test: `ios-app/LocalMusicPlayerTests/FileImportServiceTests.swift`

**Interfaces:**
- Produces: `ImportedFile(sourceURL: URL, kind: ImportedFile.Kind)`.
- Produces: `ImportedMetadataReader.read(_:) async throws -> ImportedMetadata`.
- Produces: `FileImportService.importFiles(_:) async throws -> [TrackRecord]`.

- [ ] **Step 1: Write import tests using temporary files**

Verify supported extensions, rejection of OGG, security-scoped access cleanup, unique sandbox names for duplicate source filenames, title/artist/album/duration mapping, filename fallback for missing title, same-base-name LRC association, and cleanup after an interrupted copy.

- [ ] **Step 2: Verify tests fail**

Run `FileImportServiceTests`.

Expected: FAIL because import types do not exist.

- [ ] **Step 3: Implement sandbox copying**

Use `UTType.audio` plus a custom LRC type in the picker. Copy into:

```text
Application Support/ImportedMusic/<track-id>/audio.<extension>
Application Support/ImportedMusic/<track-id>/lyrics.lrc
```

Compute `track-id` from a SHA-256 digest of file bytes plus file size. Always balance `startAccessingSecurityScopedResource()` with `stopAccessingSecurityScopedResource()` using `defer`.

Read duration and common title/artist/album/artwork metadata with `AVURLAsset.load(_:)`; cache artwork under the track directory and fall back to the source filename when the title is empty.

- [ ] **Step 4: Verify imports**

Run `FileImportServiceTests`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "feat: import iOS local music files"
```

### Task 4: Read authorized playable system-library items

**Files:**
- Create: `ios-app/LocalMusicPlayer/Import/MediaLibraryGateway.swift`
- Create: `ios-app/LocalMusicPlayer/Import/SystemLibraryImporter.swift`
- Test: `ios-app/LocalMusicPlayerTests/SystemLibraryImporterTests.swift`
- Modify: `ios-app/LocalMusicPlayer/Info.plist`

**Interfaces:**
- Produces: `MediaLibraryItem`.
- Produces: `MediaLibraryGateway.requestAuthorization()` and `playableItems()`.
- Produces: `SystemLibraryImporter.importAuthorizedItems() async throws -> [TrackRecord]`.

- [ ] **Step 1: Write importer tests against a fake gateway**

Verify denied authorization returns a recoverable permission result, only items with a non-nil local `assetURL` are imported, metadata is preserved, and persistent IDs create stable track ids.

- [ ] **Step 2: Verify tests fail**

Run `SystemLibraryImporterTests`.

Expected: FAIL because gateway/importer types do not exist.

- [ ] **Step 3: Implement MediaPlayer gateway**

Request `MPMediaLibrary` authorization and query `MPMediaQuery.songs()`. Map title, artist, album, playback duration, persistent id, artwork, and `MPMediaItemPropertyAssetURL`. Filter out cloud/protected items whose asset URL is unavailable.

Add `NSAppleMusicUsageDescription` explaining that the app reads music already on the device.

- [ ] **Step 4: Verify importer logic**

Run `SystemLibraryImporterTests`.

Expected: PASS using the fake gateway; physical-device access remains a manual test.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "feat: import iOS system music library"
```

### Task 5: Parse synchronized lyrics

**Files:**
- Create: `ios-app/LocalMusicPlayer/Lyrics/LyricLine.swift`
- Create: `ios-app/LocalMusicPlayer/Lyrics/LRCParser.swift`
- Test: `ios-app/LocalMusicPlayerTests/LRCParserTests.swift`

**Interfaces:**
- Produces: `LyricLine(timestamp: TimeInterval, text: String)`.
- Produces: `LRCParser.parse(_:) -> [LyricLine]` and `currentIndex(lines:position:) -> Int?`.

- [ ] **Step 1: Write parser tests**

Cover two/three fractional digits, multiple timestamps, metadata tags, invalid input, sorting, and current-line lookup.

- [ ] **Step 2: Verify tests fail**

Run `LRCParserTests`.

Expected: FAIL because `LRCParser` does not exist.

- [ ] **Step 3: Implement parser with Swift Regex**

Match `\[(\d{1,3}):(\d{2})(?:\.(\d{2,3}))?\]`, strip all timestamps from the text, emit one line per match, and return a timestamp-sorted array. Return an empty array for corrupt input.

- [ ] **Step 4: Verify tests pass**

Run `LRCParserTests`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios-app/LocalMusicPlayer/Lyrics ios-app/LocalMusicPlayerTests/LRCParserTests.swift
git commit -m "feat: parse iOS LRC lyrics"
```

### Task 6: Implement AVFoundation playback queue

**Files:**
- Create: `ios-app/LocalMusicPlayer/Playback/PlaybackMode.swift`
- Create: `ios-app/LocalMusicPlayer/Playback/PlaybackState.swift`
- Create: `ios-app/LocalMusicPlayer/Playback/AudioEngine.swift`
- Create: `ios-app/LocalMusicPlayer/Playback/AVPlayerEngine.swift`
- Create: `ios-app/LocalMusicPlayer/Playback/PlaybackController.swift`
- Test: `ios-app/LocalMusicPlayerTests/PlaybackControllerTests.swift`

**Interfaces:**
- Consumes: `TrackRecord`.
- Produces: `PlaybackController.loadQueue`, `play`, `pause`, `seek`, `next`, `previous`, and published `state`.

- [ ] **Step 1: Write state-machine tests against a fake engine**

Use a fake preferences store and verify empty queue safety, repeat-all wrap, repeat-one completion, deterministic shuffle, seek clamping, previous-song restart after three seconds, unavailable-track skipping, and restoration/persistence of volume, playback mode, last track, and last position.

- [ ] **Step 2: Verify tests fail**

Run `PlaybackControllerTests`.

Expected: FAIL because playback types do not exist.

- [ ] **Step 3: Implement the state machine and AVPlayer adapter**

```swift
enum PlaybackMode: String, Codable { case repeatAll, repeatOne, shuffle }

struct PlaybackState: Equatable {
    var queueIDs: [String] = []
    var currentIndex: Int? = nil
    var isPlaying = false
    var position: TimeInterval = 0
    var duration: TimeInterval = 0
    var volume: Float = 1
    var mode: PlaybackMode = .repeatAll
}
```

Resolve imported sandbox URLs and media-library asset URLs into `AVPlayerItem`. Add a periodic time observer at 250 ms and remove it on deinit. Configure `AVAudioSession` with `.playback`.

- [ ] **Step 4: Verify controller tests**

Run `PlaybackControllerTests`.

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "feat: add iOS local playback queue"
```

### Task 7: Add lock-screen metadata and remote controls

**Files:**
- Create: `ios-app/LocalMusicPlayer/Playback/NowPlayingBridge.swift`
- Modify: `ios-app/LocalMusicPlayer/Info.plist`
- Test: `ios-app/LocalMusicPlayerTests/NowPlayingBridgeTests.swift`

**Interfaces:**
- Consumes: `PlaybackController` state and current `TrackRecord`.
- Produces: Now Playing metadata and play/pause/next/previous/seek command handlers.

- [ ] **Step 1: Write bridge tests around a protocol fake**

Verify title/artist/duration/elapsed/rate mapping and that each remote command calls exactly one controller action.

- [ ] **Step 2: Verify tests fail**

Run `NowPlayingBridgeTests`.

Expected: FAIL because the bridge does not exist.

- [ ] **Step 3: Implement the MediaPlayer bridge**

Update `MPNowPlayingInfoCenter.default().nowPlayingInfo` on track, position, and play-state changes. Register `MPRemoteCommandCenter` handlers once and remove their targets on teardown. Add `audio` to `UIBackgroundModes`.

- [ ] **Step 4: Verify tests and background configuration**

Run all iOS tests and inspect the generated Info.plist.

Expected: PASS and background audio is present.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "feat: integrate iOS media controls"
```

### Task 8: Build library, playlists, and import UI

**Files:**
- Create: `ios-app/LocalMusicPlayer/Features/Library/LibraryModel.swift`
- Create: `ios-app/LocalMusicPlayer/Features/Library/LibraryView.swift`
- Create: `ios-app/LocalMusicPlayer/Features/Library/ImportMenu.swift`
- Create: `ios-app/LocalMusicPlayer/Features/Playlists/PlaylistsModel.swift`
- Create: `ios-app/LocalMusicPlayer/Features/Playlists/PlaylistsView.swift`
- Create: `ios-app/LocalMusicPlayer/Features/Shared/MiniPlayerView.swift`
- Modify: `ios-app/LocalMusicPlayer/App/AppShellView.swift`
- Test: `ios-app/LocalMusicPlayerTests/LibraryModelTests.swift`
- Test: `ios-app/LocalMusicPlayerTests/PlaylistsModelTests.swift`

**Interfaces:**
- Consumes: `MusicStore`, file importer, system-library importer, and playback controller.
- Produces: searchable library, favorites, editable playlists, import actions, and mini-player navigation.

- [ ] **Step 1: Write observable-model tests**

Verify title/artist/album search, denied library permission leaving Files import enabled, like toggling, custom playlist mutations, built-in playlist protection, and queue creation from filtered results.

- [ ] **Step 2: Verify tests fail**

Run `LibraryModelTests` and `PlaylistsModelTests`.

Expected: FAIL because feature models do not exist.

- [ ] **Step 3: Implement SwiftUI feature screens**

Use `NavigationStack`, `searchable`, `TabView`, `ContentUnavailableView`, and sheets for import/create/rename actions. Keep SwiftData fetches and platform permission calls inside `@MainActor @Observable` models. Place `MiniPlayerView` above the tab bar with `safeAreaInset(edge: .bottom)`.

- [ ] **Step 4: Verify tests and simulator behavior**

Run all tests and launch the simulator build. Confirm empty state, search, import menu, favorites, playlist editing, and mini-player navigation.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "feat: add iOS music library UI"
```

### Task 9: Build immersive playback, synced lyrics, and record animation

**Files:**
- Create: `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingModel.swift`
- Create: `ios-app/LocalMusicPlayer/Features/NowPlaying/NowPlayingView.swift`
- Create: `ios-app/LocalMusicPlayer/Features/NowPlaying/SyncedLyricsView.swift`
- Create: `ios-app/LocalMusicPlayer/Features/NowPlaying/RecordVisual.swift`
- Create: `ios-app/LocalMusicPlayer/Resources/PlayerTheme.swift`
- Test: `ios-app/LocalMusicPlayerTests/NowPlayingModelTests.swift`

**Interfaces:**
- Consumes: playback state, current track, and `LRCParser`.
- Produces: current lyric index, record animation state, progress seeking, and queue presentation.

- [ ] **Step 1: Write now-playing model tests**

Verify lyric switching at timestamp boundaries, empty/corrupt LRC fallback, seeking, and animation pause when playback pauses or Reduce Motion is enabled.

- [ ] **Step 2: Verify tests fail**

Run `NowPlayingModelTests`.

Expected: FAIL because `NowPlayingModel` does not exist.

- [ ] **Step 3: Implement the immersive player**

Use a large circular record with album art, `TimelineView(.animation)` rotation, material/gradient background, `ScrollViewReader` lyric scrolling, a native `Slider` for progress, and queue presentation in a bottom sheet. Respect Reduce Motion by replacing continuous rotation with a static record and subtle opacity.

- [ ] **Step 4: Verify lyric and no-lyric states**

Run all tests and inspect both states in an iPhone simulator. Confirm VoiceOver labels for every control and minimum 44-point touch targets.

- [ ] **Step 5: Commit**

```bash
git add ios-app
git commit -m "feat: add iOS immersive player"
```

### Task 10: Build unsigned IPA and production archive workflows

**Files:**
- Create: `ios-app/scripts/package-unsigned-ipa.sh`
- Create: `.github/workflows/ios-native.yml`
- Create: `.github/workflows/ios-app-store.yml`
- Modify: `README.md`

**Interfaces:**
- Produces: `LocalMusicPlayer-unsigned.ipa`.
- Produces: a manually triggered signed App Store archive when production secrets are present.

- [ ] **Step 1: Implement unsigned IPA packaging**

The script must:

```bash
set -euo pipefail
xcodegen generate --spec ios-app/project.yml
xcodebuild build -project ios-app/LocalMusicPlayer.xcodeproj \
  -scheme LocalMusicPlayer -configuration Release -sdk iphoneos \
  -derivedDataPath ios-app/build CODE_SIGNING_ALLOWED=NO
rm -rf ios-app/build/ipa/Payload
mkdir -p ios-app/build/ipa/Payload
cp -R ios-app/build/Build/Products/Release-iphoneos/LocalMusicPlayer.app \
  ios-app/build/ipa/Payload/
cd ios-app/build/ipa
ditto -c -k --sequesterRsrc --keepParent Payload LocalMusicPlayer-unsigned.ipa
```

- [ ] **Step 2: Add the unsigned workflow**

On `macos-latest`, install XcodeGen, generate the project, run simulator tests, run the packaging script, and upload only the unsigned IPA. Do not import certificates or provisioning profiles.

- [ ] **Step 3: Add the production workflow without exposing secrets**

Use manual dispatch only. Reference these repository secrets without printing them:

- `IOS_DISTRIBUTION_P12_BASE64`
- `IOS_DISTRIBUTION_P12_PASSWORD`
- `IOS_APP_STORE_PROFILE_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY_BASE64`

Import signing material into a temporary keychain, archive with Apple Distribution, export for App Store Connect, upload, then delete the keychain and temporary files in an `always()` cleanup step.

- [ ] **Step 4: Run the unsigned workflow and test on the physical phone**

Download `LocalMusicPlayer-unsigned.ipa`, sign it with Aisi, install it, and verify Files import, music-library permission, background playback, lock-screen controls, lyrics, no-lyrics animation, favorites, playlists, and restart persistence.

- [ ] **Step 5: Commit**

```bash
git add ios-app .github/workflows/ios-native.yml .github/workflows/ios-app-store.yml README.md
git commit -m "build: package iOS native music player"
```

### Task 11: Remove Flutter only after both native baselines pass

**Files:**
- Delete after gate: `lib/`
- Delete after gate: `test/`
- Delete after gate: `pubspec.yaml`
- Delete after gate: `pubspec.lock`
- Delete after gate: `analysis_options.yaml`
- Delete after gate: `.metadata`
- Delete after gate: Flutter-generated `ios/`
- Delete after gate: Flutter-generated `windows/`
- Delete after gate: old `.github/workflows/ios-artifact.yml`
- Delete after gate: old `.github/workflows/windows-build.yml`
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Consumes: passing Windows local installer build and passing iOS GitHub unsigned-IPA build.
- Produces: a repository containing only the two native applications and their shared documentation/workflows.

- [ ] **Step 1: Verify the removal gate**

Required evidence:

```text
Windows: verify.ps1 PASS
Windows: package.ps1 PASS
iOS: simulator XCTest workflow PASS
iOS: unsigned IPA workflow PASS
```

If any line is missing, do not remove Flutter.

- [ ] **Step 2: Record exact Flutter paths to remove**

Run `git status --short` and `git ls-files` for each path. Confirm no unrelated user file is nested in a generated Flutter directory.

- [ ] **Step 3: Remove only the verified Flutter paths**

Use explicit repository-relative paths. Do not remove `docs/`, `ios-app/`, `windows-app/`, or the native workflows.

- [ ] **Step 4: Re-run both native verification paths**

Run Windows local verification/package scripts and the iOS GitHub workflows.

Expected: both native applications remain green without Flutter.

- [ ] **Step 5: Update root documentation and commit**

Document the two project folders, local Windows commands, GitHub iOS workflow, Aisi testing, and App Store flow.

```bash
git add -A
git commit -m "refactor: replace Flutter app with native players"
```

### Task 12: Final iOS and repository verification checkpoint

**Files:**
- Verify only; fix only failures directly caused by this plan.

- [ ] **Step 1: Run iOS automated verification**

Trigger the GitHub iOS native workflow from a clean commit.

Expected: project generation, simulator tests, device build, and unsigned IPA packaging PASS.

- [ ] **Step 2: Run the physical-device acceptance pass**

Install the Aisi-signed IPA on an iOS 17+ iPhone. Test imported MP3/M4A/AAC/FLAC/WAV/AIFF, system-library items, denied permission fallback, lock-screen commands, background playback, LRC scrolling, no-lyrics animation, playlists, and restart persistence.

- [ ] **Step 3: Re-run Windows verification**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File windows-app/scripts/verify.ps1
powershell -ExecutionPolicy Bypass -File windows-app/scripts/package.ps1
```

Expected: PASS after Flutter cleanup.

- [ ] **Step 4: Record final evidence**

Update `README.md` with the tested iOS version/device, workflow run link, Windows installer path, and Windows version used for the clean install test.

- [ ] **Step 5: Commit verification documentation**

```bash
git add README.md
git commit -m "docs: record native app verification"
```
