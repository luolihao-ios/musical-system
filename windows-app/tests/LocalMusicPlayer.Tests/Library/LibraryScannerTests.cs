using FluentAssertions;
using LocalMusicPlayer.Data;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Library;

namespace LocalMusicPlayer.Tests.Library;

public sealed class LibraryScannerTests : IDisposable
{
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), "LocalMusicPlayer.ScannerTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task Discovery_FindsSupportedAudioRecursively()
    {
        var nested = Directory.CreateDirectory(Path.Combine(_directory, "nested")).FullName;
        await File.WriteAllBytesAsync(Path.Combine(_directory, "first.MP3"), [1, 2, 3]);
        await File.WriteAllBytesAsync(Path.Combine(nested, "second.flac"), [4, 5, 6]);
        await File.WriteAllTextAsync(Path.Combine(nested, "notes.txt"), "ignore");
        var discovery = new AudioFileDiscovery();

        var discovered = new List<string>();
        await foreach (var path in discovery.FindAsync(_directory))
        {
            discovered.Add(Path.GetFileName(path));
        }

        discovered.Should().BeEquivalentTo("first.MP3", "second.flac");
    }

    [Fact]
    public async Task TrackIdentity_RemainsStableWhenAFileMoves()
    {
        Directory.CreateDirectory(_directory);
        var original = Path.Combine(_directory, "before.mp3");
        var moved = Path.Combine(_directory, "after.mp3");
        await File.WriteAllBytesAsync(original, Enumerable.Range(0, 200_000)
            .Select(index => (byte)(index % 251))
            .ToArray());
        var originalId = await TrackIdentity.CreateAsync(original);

        File.Move(original, moved);

        (await TrackIdentity.CreateAsync(moved)).Should().Be(originalId);
    }

    [Fact]
    public async Task Scan_ContinuesAfterMetadataFailure_AndMarksMissingTrackUnavailable()
    {
        Directory.CreateDirectory(_directory);
        var goodPath = Path.Combine(_directory, "good.mp3");
        var brokenPath = Path.Combine(_directory, "broken.flac");
        await File.WriteAllBytesAsync(goodPath, [1, 2, 3, 4]);
        await File.WriteAllTextAsync(Path.ChangeExtension(goodPath, ".lrc"), "[00:01.00]第一句");
        await File.WriteAllBytesAsync(brokenPath, [9, 9, 9]);
        var repository = await CreateRepositoryAsync();
        var scanner = new LibraryScanner(
            new AudioFileDiscovery(),
            new StubMetadataReader(),
            repository);

        var first = await scanner.ScanAsync(_directory);

        first.Indexed.Should().Be(1);
        first.Failed.Should().Be(1);
        var indexed = (await repository.GetTracksAsync()).Single();
        indexed.LyricsPath.Should().Be(Path.ChangeExtension(goodPath, ".lrc"));
        indexed.IsAvailable.Should().BeTrue();

        File.Delete(goodPath);
        var second = await scanner.ScanAsync(_directory);

        second.MarkedUnavailable.Should().Be(1);
        (await repository.GetTracksAsync()).Single().IsAvailable.Should().BeFalse();
    }

    [Fact]
    public async Task Scan_UpdatesPathWithoutDuplicatingMovedTrack()
    {
        Directory.CreateDirectory(_directory);
        var originalPath = Path.Combine(_directory, "original.mp3");
        var movedPath = Path.Combine(_directory, "moved.mp3");
        await File.WriteAllBytesAsync(originalPath, [8, 6, 7, 5, 3, 0, 9]);
        var repository = await CreateRepositoryAsync();
        var scanner = new LibraryScanner(
            new AudioFileDiscovery(),
            new StubMetadataReader(),
            repository);
        await scanner.ScanAsync(_directory);

        File.Move(originalPath, movedPath);
        await scanner.ScanAsync(_directory);

        var tracks = await repository.GetTracksAsync();
        tracks.Should().ContainSingle();
        tracks[0].FilePath.Should().Be(movedPath);
        tracks[0].IsAvailable.Should().BeTrue();
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private async Task<LibraryRepository> CreateRepositoryAsync()
    {
        var database = new LibraryDatabase(Path.Combine(_directory, "library.sqlite"));
        await database.InitializeAsync();
        return new LibraryRepository(database);
    }

    private sealed class StubMetadataReader : ITrackMetadataReader
    {
        public async Task<Track> ReadAsync(
            string path,
            CancellationToken cancellationToken = default)
        {
            if (Path.GetFileName(path).StartsWith("broken", StringComparison.OrdinalIgnoreCase))
            {
                throw new InvalidDataException("Synthetic broken metadata.");
            }

            return new Track(
                await TrackIdentity.CreateAsync(path, cancellationToken),
                path,
                Path.GetFileNameWithoutExtension(path),
                "测试歌手",
                "测试专辑",
                TimeSpan.FromMinutes(3),
                null,
                File.Exists(Path.ChangeExtension(path, ".lrc"))
                    ? Path.ChangeExtension(path, ".lrc")
                    : null,
                false,
                true,
                null);
        }
    }
}
