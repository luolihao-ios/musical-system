# Local Music Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Flutter Windows and iOS music player that indexes, imports, and plays only on-device music.

**Architecture:** A feature-first Flutter app owns the adaptive UI and local data. Windows directory indexing and iOS library/file import sit behind source adapters; one shared playback controller owns the queue.

**Tech Stack:** Flutter/Dart, Riverpod, Drift/SQLite, just_audio, audio_service, file_picker, permission_handler, metadata_god, GitHub Actions.

## Global Constraints

- Do not add online music search, streaming, downloading, uploading, analytics, or user accounts.
- Use original dark record-room visuals; never use NetEase Cloud Music names, assets, icons, copy, or trademarks.
- Windows scans user-selected folders recursively. iOS reads authorized system-library entries and imports user-selected files into its app sandbox.
- iOS device testing uses an Actions-built artifact that the owner signs and installs with Aisi Assistant; do not automate development certificates, Ad Hoc, or TestFlight.
- Persist library, likes, playlists, history, scan roots, and playback preferences locally.

---

## File Structure

- `lib/main.dart`: application bootstrap and provider scope.
- `lib/app.dart`: theme, router, adaptive shell, and global error surface.
- `lib/core/models/`: `Track`, `Playlist`, `LyricLine`, and playback state.
- `lib/core/database/`: Drift schema, migrations, and repositories.
- `lib/core/services/`: scanner, importer, lyrics parser, playback controller, and platform gateways.
- `lib/features/library/`: browsing, search, scanning, and importing UI.
- `lib/features/player/`: mini player, full player, queue, lyrics, and no-lyrics animation.
- `lib/features/playlists/`: likes and custom playlist UI.
- `ios/Runner/`: purpose string and native media-library bridge.
- `.github/workflows/`: unsigned iOS test artifact and Windows release artifact.

### Task 1: Scaffold the Flutter workspace and quality baseline

**Files:**
- Create: `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `lib/app.dart`, `test/app_test.dart`, `.gitignore`

**Interfaces:** Produces `LocalMusicApp`, the top-level widget used by every widget test.

- [ ] **Step 1: Create targets and dependencies**

```powershell
flutter create --platforms=windows,ios --org com.localrecordroom --project-name local_music_player .
flutter pub add flutter_riverpod go_router drift sqlite3_flutter_libs just_audio audio_service file_picker permission_handler metadata_god path_provider
flutter pub add --dev mocktail build_runner drift_dev
```

- [ ] **Step 2: Write the failing app test**

```dart
testWidgets('renders the local-music empty state', (tester) async {
  await tester.pumpWidget(const LocalMusicApp());
  expect(find.text('导入本地音乐'), findsOneWidget);
});
```

- [ ] **Step 3: Run test, then implement bootstrap**

Run: `flutter test test/app_test.dart`

Expected: FAIL because `LocalMusicApp` does not exist.

```dart
void main() => runApp(const ProviderScope(child: LocalMusicApp()));
class LocalMusicApp extends StatelessWidget {
  const LocalMusicApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(home: Scaffold(body: Center(child: Text('导入本地音乐'))));
}
```

- [ ] **Step 4: Verify and commit**

Run: `dart format lib test; flutter analyze; flutter test test/app_test.dart; git init; git add .; git commit -m "chore: scaffold Flutter music player"`

Expected: analysis and test pass; the baseline is committed.

### Task 2: Persist library, likes, and custom playlists

**Files:**
- Create: `lib/core/models/track.dart`, `lib/core/models/playlist.dart`
- Create: `lib/core/database/app_database.dart`, `lib/core/database/library_repository.dart`
- Create: `test/core/database/library_repository_test.dart`

**Interfaces:** Produces `Track`, `Playlist`, `LibraryRepository.upsertTrack(Track)`, `likedTracks()`, `toggleLike(String)`, and `createPlaylist(String)`.

- [ ] **Step 1: Write the failing repository test**

```dart
test('liked tracks persist and are returned', () async {
  final repo = LibraryRepository(AppDatabase.inMemory());
  await repo.upsertTrack(Track(id: 'a', title: '晨光', source: TrackSource.file));
  await repo.toggleLike('a');
  expect((await repo.likedTracks()).single.id, 'a');
});
```

- [ ] **Step 2: Run test, then implement data model and schema**

Run: `flutter test test/core/database/library_repository_test.dart`

Expected: FAIL because the repository is absent.

```dart
enum TrackSource { file, iosMediaLibrary }
class Track {
  const Track({required this.id, required this.title, required this.source, this.uri, this.artist = '未知歌手'});
  final String id; final String title; final String artist; final TrackSource source; final String? uri;
}
```

Create Drift tables for tracks, playlists, playlist-track order, scan roots, and preferences. Store title, artist, album, source, URI/reference, duration, artwork path, like state, import time, and last-played time. Make the built-in “我喜欢” playlist non-deletable in repository rules.

- [ ] **Step 3: Generate, verify, and commit**

Run: `dart run build_runner build --delete-conflicting-outputs; flutter test test/core/database/library_repository_test.dart; git add lib test pubspec.*; git commit -m "feat: persist local music library"`

Expected: generated code compiles and the test passes.

### Task 3: Index local audio and discover adjacent LRC files

**Files:**
- Create: `lib/core/services/music_scanner.dart`, `lib/core/services/audio_metadata_reader.dart`, `lib/core/services/lyrics_locator.dart`
- Create: `test/core/services/music_scanner_test.dart`

**Interfaces:** Consumes `LibraryRepository.upsertTrack`. Produces `MusicScanner.scanDirectory(Directory)` and `LyricsLocator.findForAudio(File)`.

- [ ] **Step 1: Write the failing scanner test**

```dart
test('indexes supported audio and finds an adjacent lrc', () async {
  final result = await scanner.scanDirectory(Directory('test/fixtures/library'));
  expect(result.indexedCount, 1);
  expect(result.tracks.single.lyricFile?.path, endsWith('dawn.lrc'));
});
```

- [ ] **Step 2: Run test, then implement scanning**

Run: `flutter test test/core/services/music_scanner_test.dart`

Expected: FAIL because `MusicScanner` is undefined.

```dart
static const supportedExtensions = {'.mp3', '.m4a', '.aac', '.flac', '.wav', '.ogg'};
Future<ScanResult> scanDirectory(Directory root) async {
  final entries = await root.list(recursive: true).where((item) => item is File).cast<File>().toList();
  return ScanResult.fromFiles(entries.where((file) => supportedExtensions.contains(p.extension(file.path).toLowerCase())));
}
```

Read tags and embedded artwork using the metadata adapter. Use normalized absolute path as Windows file identity and look for an `.lrc` file with the same basename. Mark missing or unsupported files unplayable without interrupting other tracks.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/core/services/music_scanner_test.dart; flutter analyze; git add lib test; git commit -m "feat: scan local music and lyrics"`

Expected: test and analysis pass.

### Task 4: Add iOS media-library and file-import sources

**Files:**
- Create: `lib/core/services/music_source_gateway.dart`, `lib/core/services/file_importer.dart`
- Modify: `ios/Runner/Info.plist`, `ios/Runner/Runner.entitlements`
- Create: `test/core/services/file_importer_test.dart`

**Interfaces:** Produces `requestMediaLibraryAccess()`, `listDeviceTracks()`, and `FileImporter.importPath(String)`.

- [ ] **Step 1: Write failing import and denial tests**

```dart
test('copies an imported audio file into app storage', () async {
  final track = await importer.importPath('test/fixtures/dawn.mp3');
  expect(File(track.uri!).existsSync(), isTrue);
  expect(track.source, TrackSource.file);
});
test('file import remains available after media-library denial', () async {
  gateway.stubAuthorization(MediaLibraryAccess.denied);
  expect(await gateway.requestMediaLibraryAccess(), MediaLibraryAccess.denied);
  expect(importer.isAvailable, isTrue);
});
```

- [ ] **Step 2: Run tests, then implement platform-safe sources**

Run: `flutter test test/core/services/file_importer_test.dart`

Expected: FAIL because importer and gateway are absent.

Use a method channel behind `MusicSourceGateway` to request and enumerate iOS `MPMediaLibrary` items. Set `NSAppleMusicUsageDescription` to `用于显示并播放您允许访问的设备音乐资料库。`. Use `file_picker`; copy selections to `ApplicationDocumentsDirectory/music/` with UUID filenames before indexing them. Do not request network permission.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/core/services/file_importer_test.dart; git add lib ios test pubspec.*; git commit -m "feat: import iOS local music sources"`

Expected: all source tests pass.

### Task 5: Own playback, queue, and system media controls

**Files:**
- Create: `lib/core/services/playback_controller.dart`, `lib/core/models/playback_state.dart`
- Create: `test/core/services/playback_controller_test.dart`

**Interfaces:** Produces `PlaybackController.state`, `play(Track)`, `next()`, `previous()`, `seek(Duration)`, `setMode(PlayMode)`, and `toggleShuffle()`.

- [ ] **Step 1: Write the failing single-loop test**

```dart
test('single loop restarts the current track on completion', () async {
  controller.setQueue([trackA, trackB]);
  await controller.play(trackA);
  controller.setMode(PlayMode.singleLoop);
  fakePlayer.completeCurrent();
  expect(controller.state.value.currentTrack?.id, 'a');
  expect(fakePlayer.seekCalls.single, Duration.zero);
});
```

- [ ] **Step 2: Run test, then implement controller**

Run: `flutter test test/core/services/playback_controller_test.dart`

Expected: FAIL because the controller is absent.

Wrap `just_audio` and `audio_service` in one controller. Keep queue and `PlayMode` in controller state, save volume/mode/history/last-played through the repository, and expose `ValueNotifier<PlaybackSnapshot>` so widgets never call player plugins directly.

- [ ] **Step 3: Verify Windows playback build and commit**

Run: `flutter test test/core/services/playback_controller_test.dart; flutter build windows --debug; git add lib test pubspec.*; git commit -m "feat: add local playback queue"`

Expected: test passes and a Windows debug executable is built.

### Task 6: Build library, search, likes, and playlist management UI

**Files:**
- Create: `lib/features/library/library_page.dart`, `lib/features/library/scan_import_sheet.dart`
- Create: `lib/features/playlists/playlists_page.dart`, `lib/features/playlists/playlist_detail_page.dart`
- Create: `test/features/library/library_page_test.dart`, `test/features/playlists/playlists_page_test.dart`

**Interfaces:** Consumes repository, scanner, importer, and playback controller. Produces `LibraryPage` and `PlaylistsPage`.

- [ ] **Step 1: Write failing library and playlist tests**

```dart
testWidgets('filters local tracks by title and artist', (tester) async {
  await tester.pumpWidget(testApp(tracks: [trackNamed('海风', '陈晓'), trackNamed('晨光', '林雨')]));
  await tester.enterText(find.byType(TextField), '陈晓');
  expect(find.text('海风'), findsOneWidget);
  expect(find.text('晨光'), findsNothing);
});
testWidgets('does not offer delete for the built-in liked playlist', (tester) async {
  await tester.pumpWidget(testApp(playlists: [Playlist.liked]));
  expect(find.byTooltip('删除歌单'), findsNothing);
});
```

- [ ] **Step 2: Run tests, then implement pages**

Run: `flutter test test/features/library test/features/playlists`

Expected: FAIL because library and playlist pages are absent.

Show songs, albums, artists, folders, recent plays, likes, and custom playlists. Filter tracks by title, artist, and album. Offer add-folder scanning only on Windows and file import on iOS. Allow custom playlist create, rename, delete, add, remove, and reorder; never render a delete action for “我喜欢”.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/features/library test/features/playlists; git add lib test; git commit -m "feat: manage local library and playlists"`

Expected: both widget test suites pass.

### Task 7: Create the adaptive original player experience and synchronized lyrics

**Files:**
- Modify: `lib/app.dart`
- Create: `lib/features/shell/adaptive_shell.dart`
- Create: `lib/features/player/mini_player.dart`, `lib/features/player/now_playing_page.dart`, `lib/features/player/no_lyrics_visual.dart`, `lib/features/player/synced_lyrics.dart`
- Create: `lib/core/models/lyric_line.dart`, `lib/core/services/lrc_parser.dart`
- Create: `test/features/shell/adaptive_shell_test.dart`, `test/core/services/lrc_parser_test.dart`, `test/features/player/synced_lyrics_test.dart`

**Interfaces:** Produces `AdaptiveShell`, `MiniPlayer`, `NowPlayingPage`, `LrcParser.parse(String)`, and `SyncedLyrics(position, lines)`.

- [ ] **Step 1: Write failing adaptive and LRC tests**

```dart
testWidgets('uses rail on desktop and bottom navigation on phone', (tester) async {
  await tester.pumpWidget(testApp(width: 1200));
  expect(find.byType(NavigationRail), findsOneWidget);
  await tester.pumpWidget(testApp(width: 390));
  expect(find.byType(NavigationBar), findsOneWidget);
});
test('parses multiple timestamps in chronological order', () {
  final lines = LrcParser().parse('[00:01.20][00:03.40]晨光');
  expect(lines.map((line) => line.at), [const Duration(milliseconds: 1200), const Duration(milliseconds: 3400)]);
});
```

- [ ] **Step 2: Run tests, then implement UI and parser**

Run: `flutter test test/features/shell/adaptive_shell_test.dart test/core/services/lrc_parser_test.dart`

Expected: FAIL because shell and parser are absent.

At width `>= 800`, use a `NavigationRail`; below it, use `NavigationBar`. Keep a mini player fixed above mobile navigation or on the desktop window bottom. Expand it into a page with artwork, title, progress, transport controls, queue, and lyrics. Use a deep gray theme with one warm-red emphasis color. Parse `[mm:ss.xx]` and `[mm:ss.xxx]`, expand multiple timestamps, sort them, and return empty list on invalid lyrics. Empty lyrics show a rotating record plus subtle cover pulse; honor `MediaQuery.disableAnimations`.

- [ ] **Step 3: Verify and commit**

Run: `flutter test test/features/shell test/core/services/lrc_parser_test.dart test/features/player; git add lib test; git commit -m "feat: add adaptive lyrics player"`

Expected: all lyrics and adaptive-shell tests pass.

### Task 8: Create build artifacts and complete release checks

**Files:**
- Create: `.github/workflows/ios-artifact.yml`, `.github/workflows/windows-build.yml`
- Create: `README.md`

**Interfaces:** Produces downloadable unsigned iOS Runner.app and Windows release artifacts. No secret, certificate, or private-key value is committed.

- [ ] **Step 1: Create iOS test artifact workflow**

```yaml
name: iOS test artifact
on: { workflow_dispatch: {} }
jobs:
  build:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test
      - run: flutter build ios --release --no-codesign
      - uses: actions/upload-artifact@v4
        with: { name: ios-unsigned-runner, path: build/ios/iphoneos/Runner.app }
```

- [ ] **Step 2: Create Windows workflow**

```yaml
name: Windows build
on: [push, workflow_dispatch]
jobs:
  build:
    runs-on: windows-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter test
      - run: flutter build windows --release
      - uses: actions/upload-artifact@v4
        with: { name: windows-release, path: build/windows/x64/runner/Release }
```

- [ ] **Step 3: Document and run final verification**

Document that iOS testing artifact is re-signed locally through Aisi Assistant and that App Store submissions use a separate Apple distribution-signing release process. Run: `dart format --set-exit-if-changed lib test; flutter analyze; flutter test; flutter build windows --release`.

Expected: all checks pass and the release executable exists.

- [ ] **Step 4: Inspect for private material and commit**

Run: `rg -n "BEGIN .*PRIVATE KEY|\.p12|\.mobileprovision|password:|token:" . -g '!build' -g '!docs'; git add .github README.md lib test; git commit -m "ci: build local music player artifacts"`

Expected: search finds no committed secrets or signing files.

## Final verification checklist

- [ ] Scan nested Windows folders with supported audio, adjacent `.lrc`, missing files, and unsupported formats.
- [ ] On physical iPhone after Aisi signing, test media-library denial and file import.
- [ ] Verify playback, seek, queue, sequential/single-loop/shuffle, and restart persistence.
- [ ] Verify background, lock-screen, and headset controls on both targets.
- [ ] Verify LRC sync, reduced-motion behavior, likes, custom playlists, and offline-only operation.
