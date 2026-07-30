# Windows WPF Local Music Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Windows 10/11 x64 local music player in C# and WPF that can be compiled, run, tested, published, and packaged locally without the Windows SDK or administrator privileges.

**Architecture:** A .NET 10 WPF application uses MVVM at the presentation boundary, focused application services for scanning and playback, SQLite repositories for persistence, and NAudio for decoding/output. The app publishes self-contained and Inno Setup produces a per-user installer.

**Tech Stack:** C# 14, .NET 10, WPF, CommunityToolkit.Mvvm, Microsoft.Data.Sqlite, Dapper, NAudio, NAudio.Vorbis, TagLibSharp, xUnit, FluentAssertions, Inno Setup.

## Global Constraints

- Support Windows 10/11 x64.
- Do not require Visual Studio or a separately installed Windows SDK.
- Do not access an online music catalog or download/upload music.
- Keep Windows data fully independent from iOS data.
- Support MP3, M4A/AAC, FLAC, WAV, and OGG Vorbis.
- Install for the current user without elevation and allow choosing the install directory.
- Use original dark record-room styling; do not copy NetEase names, logos, copy, or assets.
- Preserve existing Flutter files until both native projects have a passing baseline build.

---

## File Map

```text
windows-app/
├─ LocalMusicPlayer.slnx
├─ Directory.Build.props
├─ src/LocalMusicPlayer/
│  ├─ LocalMusicPlayer.csproj
│  ├─ App.xaml(.cs)
│  ├─ MainWindow.xaml(.cs)
│  ├─ Domain/
│  ├─ Data/
│  ├─ Library/
│  ├─ Playback/
│  ├─ Lyrics/
│  ├─ ViewModels/
│  ├─ Views/
│  └─ Themes/
├─ tests/LocalMusicPlayer.Tests/
├─ installer/LocalMusicPlayer.iss
└─ scripts/
   ├─ verify.ps1
   └─ package.ps1
```

`Domain` owns stable types, `Data` owns SQLite, `Library` owns file discovery and metadata, `Playback` owns the audio state machine, `Lyrics` owns LRC parsing, and `ViewModels` expose UI state without directly touching storage or NAudio.

### Task 1: Create the WPF solution and testable app shell

**Files:**
- Create: `windows-app/Directory.Build.props`
- Create: `windows-app/LocalMusicPlayer.slnx`
- Create: `windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj`
- Create: `windows-app/src/LocalMusicPlayer/App.xaml`
- Create: `windows-app/src/LocalMusicPlayer/App.xaml.cs`
- Create: `windows-app/src/LocalMusicPlayer/MainWindow.xaml`
- Create: `windows-app/src/LocalMusicPlayer/MainWindow.xaml.cs`
- Create: `windows-app/tests/LocalMusicPlayer.Tests/LocalMusicPlayer.Tests.csproj`
- Create: `windows-app/tests/LocalMusicPlayer.Tests/AppSmokeTests.cs`

**Interfaces:**
- Produces: `AppInfo.DisplayName`, the WPF executable, and an xUnit test project.

- [ ] **Step 1: Write the failing smoke test**

```csharp
using FluentAssertions;
using LocalMusicPlayer;

namespace LocalMusicPlayer.Tests;

public sealed class AppSmokeTests
{
    [Fact]
    public void DisplayName_UsesProductName() =>
        AppInfo.DisplayName.Should().Be("暮色音乐");
}
```

- [ ] **Step 2: Create the projects and verify the test initially fails**

Run:

```powershell
dotnet new sln -n LocalMusicPlayer --format slnx -o windows-app
dotnet new wpf -n LocalMusicPlayer -o windows-app/src/LocalMusicPlayer -f net10.0
dotnet new xunit -n LocalMusicPlayer.Tests -o windows-app/tests/LocalMusicPlayer.Tests -f net10.0
dotnet sln windows-app/LocalMusicPlayer.slnx add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj windows-app/tests/LocalMusicPlayer.Tests/LocalMusicPlayer.Tests.csproj
dotnet add windows-app/tests/LocalMusicPlayer.Tests/LocalMusicPlayer.Tests.csproj reference windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj
dotnet add windows-app/tests/LocalMusicPlayer.Tests/LocalMusicPlayer.Tests.csproj package FluentAssertions
dotnet test windows-app/LocalMusicPlayer.slnx
```

Expected: FAIL because `AppInfo` does not exist.

- [ ] **Step 3: Add shared build settings and the minimal app API**

```xml
<!-- windows-app/Directory.Build.props -->
<Project>
  <PropertyGroup>
    <Nullable>enable</Nullable>
    <ImplicitUsings>enable</ImplicitUsings>
    <TreatWarningsAsErrors>true</TreatWarningsAsErrors>
    <LangVersion>14.0</LangVersion>
  </PropertyGroup>
</Project>
```

```csharp
namespace LocalMusicPlayer;

public static class AppInfo
{
    public const string DisplayName = "暮色音乐";
}
```

Set `TargetFramework` to `net10.0-windows10.0.19041.0`, `UseWPF` to `true`, and `RuntimeIdentifier` to `win-x64` in the app project.

- [ ] **Step 4: Run tests and launch the empty window**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx
dotnet run --project windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj
```

Expected: tests PASS and a window titled “暮色音乐” opens.

- [ ] **Step 5: Commit**

```powershell
git add windows-app
git commit -m "chore: scaffold Windows WPF player"
```

### Task 2: Define domain models and SQLite persistence

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/Domain/Track.cs`
- Create: `windows-app/src/LocalMusicPlayer/Domain/Playlist.cs`
- Create: `windows-app/src/LocalMusicPlayer/Data/LibraryDatabase.cs`
- Create: `windows-app/src/LocalMusicPlayer/Data/LibraryRepository.cs`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/Data/LibraryRepositoryTests.cs`

**Interfaces:**
- Produces: `Track`, `Playlist`, and `ILibraryRepository`.
- Produces: `InitializeAsync`, `UpsertTrackAsync`, `GetTracksAsync`, `SetLikedAsync`, `CreatePlaylistAsync`, `AddTrackToPlaylistAsync`, `RecordPlayAsync`, `AddScanRootAsync`, `GetScanRootsAsync`, `GetSettingAsync`, and `SetSettingAsync`.

- [ ] **Step 1: Add SQLite packages and write repository tests**

Run:

```powershell
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package Microsoft.Data.Sqlite
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package Dapper
```

Write tests using a temporary database path. Assert that an upsert survives reopening, “我喜欢” cannot be deleted, custom playlist order is preserved, `RecordPlayAsync` updates `LastPlayedAt`, scan roots are de-duplicated, and volume/playback-mode settings survive reopening.

```csharp
var track = new Track("track-1", audioPath, "落日之前", "雾岛乐队",
    "城市夜行", TimeSpan.FromSeconds(258), null, null, false, true, null);
await repository.UpsertTrackAsync(track);
(await reopened.GetTracksAsync()).Should().ContainSingle(t => t.Id == "track-1");
```

- [ ] **Step 2: Run the persistence tests**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter LibraryRepositoryTests
```

Expected: FAIL because the domain and repository types do not exist.

- [ ] **Step 3: Implement schema version 1 and repository methods**

Use these stable records:

```csharp
public sealed record Track(
    string Id, string FilePath, string Title, string Artist, string Album,
    TimeSpan Duration, string? CoverCachePath, string? LyricsPath,
    bool IsLiked, bool IsAvailable, DateTimeOffset? LastPlayedAt);

public sealed record Playlist(long Id, string Name, bool IsBuiltIn);
```

Create tables `tracks`, `playlists`, `playlist_tracks`, `scan_roots`, and `settings`. Seed playlist id `1` as “我喜欢” with `is_built_in = 1`. Use transactions for playlist mutation and parameterized Dapper commands for every user value.

- [ ] **Step 4: Verify persistence**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter LibraryRepositoryTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows-app/src/LocalMusicPlayer/Domain windows-app/src/LocalMusicPlayer/Data windows-app/tests/LocalMusicPlayer.Tests/Data windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj
git commit -m "feat: persist Windows music library"
```

### Task 3: Scan folders, read metadata, and reconcile missing files

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/Library/AudioFileDiscovery.cs`
- Create: `windows-app/src/LocalMusicPlayer/Library/TrackMetadataReader.cs`
- Create: `windows-app/src/LocalMusicPlayer/Library/LibraryScanner.cs`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/Library/LibraryScannerTests.cs`

**Interfaces:**
- Consumes: `ILibraryRepository.UpsertTrackAsync` and `GetTracksAsync`.
- Produces: `IAudioFileDiscovery.FindAsync`, `ITrackMetadataReader.ReadAsync`, and `LibraryScanner.ScanAsync`.

- [ ] **Step 1: Add metadata package and write scanner tests**

Run:

```powershell
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package TagLibSharp
```

Test recursive extension matching case-insensitively, same-name `.lrc` discovery, stable content fingerprinting, continuing after one metadata failure or inaccessible child directory, recovering playlist identity after a file moves, and marking previously indexed missing files unavailable.

- [ ] **Step 2: Run scanner tests**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter LibraryScannerTests
```

Expected: FAIL because scanner services do not exist.

- [ ] **Step 3: Implement discovery and metadata mapping**

```csharp
private static readonly HashSet<string> Supported =
    new(StringComparer.OrdinalIgnoreCase) { ".mp3", ".m4a", ".aac", ".flac", ".wav", ".ogg" };

public async IAsyncEnumerable<string> FindAsync(
    string root, [EnumeratorCancellation] CancellationToken cancellationToken)
{
    var pending = new Stack<string>();
    pending.Push(root);
    while (pending.TryPop(out var directory))
    {
        cancellationToken.ThrowIfCancellationRequested();
        string[] files;
        string[] children;
        try {
            files = Directory.GetFiles(directory);
            children = Directory.GetDirectories(directory);
        } catch (UnauthorizedAccessException) {
            continue;
        } catch (IOException) {
            continue;
        }
        foreach (var child in children) pending.Push(child);
        foreach (var path in files)
            if (Supported.Contains(Path.GetExtension(path))) yield return path;
        await Task.Yield();
    }
}
```

Use `TagLib.File.Create(path)` inside `TrackMetadataReader`, fall back to the filename for an empty title, and locate lyrics with `Path.ChangeExtension(path, ".lrc")`. Generate a SHA-256 identity from file size plus the first and last 64 KiB so moving a file does not break favorites or playlists; keep the normalized path only as the current location.

- [ ] **Step 4: Verify scan reconciliation**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter LibraryScannerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows-app
git commit -m "feat: scan Windows local music folders"
```

### Task 4: Parse synchronized LRC lyrics

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/Lyrics/LyricLine.cs`
- Create: `windows-app/src/LocalMusicPlayer/Lyrics/LrcParser.cs`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/Lyrics/LrcParserTests.cs`

**Interfaces:**
- Produces: `LyricLine(TimeSpan Timestamp, string Text)`.
- Produces: `IReadOnlyList<LyricLine> LrcParser.Parse(string source)` and `int FindCurrentLine(IReadOnlyList<LyricLine>, TimeSpan)`.

- [ ] **Step 1: Write parser tests**

Cover `[01:02.34]`, `[01:02.345]`, multiple timestamps on one line, metadata lines, malformed input, stable sorting, and current-line lookup before/after the final timestamp.

- [ ] **Step 2: Verify tests fail**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter LrcParserTests
```

Expected: FAIL because `LrcParser` does not exist.

- [ ] **Step 3: Implement the parser**

Use a compiled regex:

```csharp
private static readonly Regex Timestamp =
    new(@"\[(?<m>\d{1,3}):(?<s>\d{2})(?:\.(?<f>\d{2,3}))?\]",
        RegexOptions.Compiled | RegexOptions.CultureInvariant);
```

Convert two fractional digits to centiseconds and three to milliseconds. Remove all timestamp matches from the lyric text, emit one `LyricLine` per match, and sort by `Timestamp`.

- [ ] **Step 4: Verify parser behavior**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter LrcParserTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows-app/src/LocalMusicPlayer/Lyrics windows-app/tests/LocalMusicPlayer.Tests/Lyrics
git commit -m "feat: parse Windows LRC lyrics"
```

### Task 5: Build the playback queue and NAudio engine

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/Playback/PlaybackMode.cs`
- Create: `windows-app/src/LocalMusicPlayer/Playback/PlaybackSnapshot.cs`
- Create: `windows-app/src/LocalMusicPlayer/Playback/IAudioOutput.cs`
- Create: `windows-app/src/LocalMusicPlayer/Playback/NAudioOutput.cs`
- Create: `windows-app/src/LocalMusicPlayer/Playback/PlaybackController.cs`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/Playback/PlaybackControllerTests.cs`

**Interfaces:**
- Consumes: `Track`.
- Produces: `PlaybackController.LoadQueue`, `PlayAsync`, `Pause`, `Seek`, `NextAsync`, `PreviousAsync`, `SetMode`, and `SnapshotChanged`.

- [ ] **Step 1: Add playback packages and write state-machine tests**

Run:

```powershell
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package NAudio
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package NAudio.Vorbis
```

Use a fake `IAudioOutput` and fake settings repository. Verify empty queues, sequential wrap, repeat-one completion, deterministic shuffle with an injected `Random`, manual next, seek clamping, unavailable-track skipping, and restoration/persistence of volume, playback mode, and last position.

- [ ] **Step 2: Verify controller tests fail**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter PlaybackControllerTests
```

Expected: FAIL because playback types do not exist.

- [ ] **Step 3: Implement the controller and output adapter**

```csharp
public enum PlaybackMode { RepeatAll, RepeatOne, Shuffle }

public sealed record PlaybackSnapshot(
    IReadOnlyList<Track> Queue, int CurrentIndex, bool IsPlaying,
    TimeSpan Position, TimeSpan Duration, double Volume, PlaybackMode Mode);
```

Use `MediaFoundationReader` for MP3/M4A/AAC/FLAC/WAV and `VorbisWaveReader` for OGG. Wrap readers in a common `WaveStream`; output with `WasapiOut`. Raise completion only after natural end, not after stop/seek.

- [ ] **Step 4: Run playback tests**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter PlaybackControllerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```powershell
git add windows-app
git commit -m "feat: add Windows local playback queue"
```

### Task 6: Add system media controls and application composition

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/Playback/SystemMediaBridge.cs`
- Create: `windows-app/src/LocalMusicPlayer/Composition/AppServices.cs`
- Modify: `windows-app/src/LocalMusicPlayer/App.xaml.cs`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/Playback/SystemMediaBridgeTests.cs`

**Interfaces:**
- Consumes: `PlaybackController` and its `SnapshotChanged` event.
- Produces: lock-screen metadata updates and play/pause/next/previous callbacks.

- [ ] **Step 1: Add the Windows API contract package and write bridge tests**

Run:

```powershell
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package Microsoft.Windows.SDK.Contracts
```

Test bridge behavior through an `ISystemMediaSession` fake: a snapshot updates title/artist/duration, and a media-button callback invokes the matching controller command.

- [ ] **Step 2: Run the bridge tests**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter SystemMediaBridgeTests
```

Expected: FAIL because the bridge does not exist.

- [ ] **Step 3: Implement bridge and dependency composition**

Create the system session once at app startup. Keep Windows Runtime objects inside `SystemMediaBridge`; expose only `ISystemMediaSession` to tests. Construct database, repository, scanner, playback controller, and view models in `AppServices`, then dispose audio and database services during `Application.Exit`.

- [ ] **Step 4: Verify tests and compile without a Windows SDK**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx
dotnet build windows-app/LocalMusicPlayer.slnx -c Release
```

Expected: PASS with zero warnings and no Windows SDK lookup.

- [ ] **Step 5: Commit**

```powershell
git add windows-app
git commit -m "feat: integrate Windows media controls"
```

### Task 7: Implement the library, search, favorites, and playlists UI

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/ViewModels/MainViewModel.cs`
- Create: `windows-app/src/LocalMusicPlayer/ViewModels/LibraryViewModel.cs`
- Create: `windows-app/src/LocalMusicPlayer/ViewModels/PlaylistsViewModel.cs`
- Create: `windows-app/src/LocalMusicPlayer/Views/LibraryView.xaml`
- Create: `windows-app/src/LocalMusicPlayer/Views/PlaylistsView.xaml`
- Create: `windows-app/src/LocalMusicPlayer/Views/AddFolderDialog.xaml`
- Modify: `windows-app/src/LocalMusicPlayer/MainWindow.xaml`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/ViewModels/LibraryViewModelTests.cs`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/ViewModels/PlaylistsViewModelTests.cs`

**Interfaces:**
- Consumes: repository, scanner, and playback controller interfaces.
- Produces: bindable `Tracks`, `FilteredTracks`, `Playlists`, `SearchText`, and async commands.

- [ ] **Step 1: Add MVVM package and write ViewModel tests**

Run:

```powershell
dotnet add windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj package CommunityToolkit.Mvvm
```

Verify accent-insensitive title/artist/album filtering, adding a scan root, toggling likes, creating/renaming/deleting custom playlists, rejecting deletion of “我喜欢”, and starting playback from a filtered row.

- [ ] **Step 2: Run ViewModel tests**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter "LibraryViewModelTests|PlaylistsViewModelTests"
```

Expected: FAIL because the ViewModels do not exist.

- [ ] **Step 3: Implement ViewModels and desktop layout**

Use `[ObservableProperty]` and `[RelayCommand]`. Keep database work behind async commands. Build a three-region `MainWindow`: 196-pixel navigation rail, content presenter, and 84-pixel bottom mini-player. Use `Microsoft.Win32.OpenFolderDialog` for folder selection.

- [ ] **Step 4: Verify behavior and run the app**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx
dotnet run --project windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj
```

Expected: tests PASS; adding a folder populates the list and search/like/playlist actions update immediately.

- [ ] **Step 5: Commit**

```powershell
git add windows-app
git commit -m "feat: add Windows music library UI"
```

### Task 8: Implement the immersive player, lyrics, and no-lyrics animation

**Files:**
- Create: `windows-app/src/LocalMusicPlayer/ViewModels/NowPlayingViewModel.cs`
- Create: `windows-app/src/LocalMusicPlayer/Views/NowPlayingView.xaml`
- Create: `windows-app/src/LocalMusicPlayer/Views/SyncedLyricsView.xaml`
- Create: `windows-app/src/LocalMusicPlayer/Views/RecordVisual.xaml`
- Create: `windows-app/src/LocalMusicPlayer/Themes/Colors.xaml`
- Create: `windows-app/src/LocalMusicPlayer/Themes/Controls.xaml`
- Test: `windows-app/tests/LocalMusicPlayer.Tests/ViewModels/NowPlayingViewModelTests.cs`

**Interfaces:**
- Consumes: `PlaybackSnapshot`, `LrcParser`, and the current `Track`.
- Produces: `CurrentLyricIndex`, `LyricLines`, `HasLyrics`, progress commands, and animation state.

- [ ] **Step 1: Write now-playing ViewModel tests**

Verify lyric index updates when position crosses timestamps, missing/corrupt LRC sets `HasLyrics` false, seek forwards to the controller, and record rotation pauses when playback pauses.

- [ ] **Step 2: Run the tests**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx --filter NowPlayingViewModelTests
```

Expected: FAIL because `NowPlayingViewModel` does not exist.

- [ ] **Step 3: Implement the player presentation**

Use WPF storyboards for continuous record rotation and breathing glow. Bind animation speed to `IsPlaying`; use a virtualized `ItemsControl` for lyrics and call `BringIntoView` only when `CurrentLyricIndex` changes. Use original gradients and geometry-only icons.

- [ ] **Step 4: Run tests and visually inspect both lyric states**

Run:

```powershell
dotnet test windows-app/LocalMusicPlayer.slnx
dotnet run --project windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj
```

Expected: lyrics highlight and scroll with playback; a track without LRC shows the rotating record visual.

- [ ] **Step 5: Commit**

```powershell
git add windows-app
git commit -m "feat: add Windows immersive player"
```

### Task 9: Publish locally and create the per-user installer

**Files:**
- Create: `windows-app/scripts/verify.ps1`
- Create: `windows-app/scripts/package.ps1`
- Create: `windows-app/installer/LocalMusicPlayer.iss`
- Create: `.github/workflows/windows-native.yml`
- Modify: `.gitignore`
- Modify: `README.md`

**Interfaces:**
- Produces: `windows-app/artifacts/publish/LocalMusicPlayer.exe`.
- Produces: `windows-app/artifacts/installer/LocalMusicPlayer-Setup.exe`.

- [ ] **Step 1: Write the verification and packaging scripts**

`verify.ps1` must run restore, formatting verification, Release build, and all tests, stopping on the first non-zero exit.

`package.ps1` must run:

```powershell
dotnet publish windows-app/src/LocalMusicPlayer/LocalMusicPlayer.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=false `
  -o windows-app/artifacts/publish
& $IsccPath windows-app/installer/LocalMusicPlayer.iss
```

- [ ] **Step 2: Define an elevation-free Inno Setup package**

Use:

```ini
[Setup]
AppId={{A0CCBA67-529A-44BE-99FA-7DE2E90EF97E}
AppName=暮色音乐
DefaultDirName={localappdata}\Programs\LocalMusicPlayer
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
OutputDir=..\artifacts\installer
OutputBaseFilename=LocalMusicPlayer-Setup
UninstallDisplayIcon={app}\LocalMusicPlayer.exe
```

Add recursive publish files, a start-menu shortcut, an optional desktop shortcut, and `CloseApplications=yes`.

- [ ] **Step 3: Install Inno Setup to E: and generate the installer**

Install Inno Setup only after explicit system-change approval, selecting an E: destination. Then run:

```powershell
powershell -ExecutionPolicy Bypass -File windows-app/scripts/verify.ps1
powershell -ExecutionPolicy Bypass -File windows-app/scripts/package.ps1
```

Expected: both scripts succeed and `LocalMusicPlayer-Setup.exe` exists.

- [ ] **Step 4: Test install, launch, upgrade, and uninstall**

Install without elevation into a non-default user-selected directory. Verify shortcuts, launch, music database persistence across an upgrade install, and removal through Windows Apps settings. Confirm the music database remains in the user application-data directory after uninstall unless the user explicitly chooses data removal.

- [ ] **Step 5: Add Windows CI**

The workflow runs `verify.ps1`, installs Inno Setup on `windows-latest`, runs `package.ps1`, and uploads only `windows-app/artifacts/installer/LocalMusicPlayer-Setup.exe`.

- [ ] **Step 6: Commit**

```powershell
git add windows-app .github/workflows/windows-native.yml .gitignore README.md
git commit -m "build: publish Windows music player installer"
```

### Task 10: Final Windows verification checkpoint

**Files:**
- Verify only; fix only failures directly caused by this plan.

- [ ] **Step 1: Run the complete automated suite**

Run:

```powershell
powershell -ExecutionPolicy Bypass -File windows-app/scripts/verify.ps1
powershell -ExecutionPolicy Bypass -File windows-app/scripts/package.ps1
```

Expected: formatting, build, tests, self-contained publish, and installer generation all PASS.

- [ ] **Step 2: Perform a clean-user smoke test**

Use a new temporary local Windows user or Windows Sandbox when available. Install without admin rights, import a folder, play MP3 and OGG samples, associate LRC, create a playlist, restart, and confirm state persistence.

- [ ] **Step 3: Record evidence**

Add exact tested versions and artifact paths to `README.md`; do not claim iOS verification here.

- [ ] **Step 4: Commit verification documentation**

```powershell
git add README.md
git commit -m "docs: record Windows release verification"
```
