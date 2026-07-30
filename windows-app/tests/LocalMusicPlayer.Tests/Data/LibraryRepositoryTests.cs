using FluentAssertions;
using LocalMusicPlayer.Data;
using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Tests.Data;

public sealed class LibraryRepositoryTests : IDisposable
{
    private readonly string _directory =
        Path.Combine(Path.GetTempPath(), "LocalMusicPlayer.Tests", Guid.NewGuid().ToString("N"));

    [Fact]
    public async Task TrackSettingsAndScanRoots_SurviveReopening()
    {
        Directory.CreateDirectory(_directory);
        var databasePath = Path.Combine(_directory, "library.sqlite");
        var first = await CreateRepositoryAsync(databasePath);
        var track = CreateTrack("track-1", "落日之前.mp3");

        await first.UpsertTrackAsync(track);
        await first.SetLikedAsync(track.Id, true);
        await first.AddScanRootAsync(@"D:\Music");
        await first.AddScanRootAsync(@"D:\Music");
        await first.SetSettingAsync("volume", "0.65");

        var reopened = await CreateRepositoryAsync(databasePath);
        var tracks = await reopened.GetTracksAsync();

        tracks.Should().ContainSingle();
        tracks[0].Id.Should().Be("track-1");
        tracks[0].IsLiked.Should().BeTrue();
        (await reopened.GetScanRootsAsync()).Should().Equal(@"D:\Music");
        (await reopened.GetSettingAsync("volume")).Should().Be("0.65");
    }

    [Fact]
    public async Task CustomPlaylist_PreservesOrder_AndBuiltInPlaylistCannotBeDeleted()
    {
        Directory.CreateDirectory(_directory);
        var repository = await CreateRepositoryAsync(Path.Combine(_directory, "library.sqlite"));
        var first = CreateTrack("track-1", "第一首.mp3");
        var second = CreateTrack("track-2", "第二首.mp3");
        await repository.UpsertTrackAsync(first);
        await repository.UpsertTrackAsync(second);

        var playlist = await repository.CreatePlaylistAsync("夜间歌单");
        await repository.AddTrackToPlaylistAsync(playlist.Id, second.Id, 0);
        await repository.AddTrackToPlaylistAsync(playlist.Id, first.Id, 1);

        (await repository.GetPlaylistTracksAsync(playlist.Id))
            .Select(track => track.Id)
            .Should()
            .Equal(second.Id, first.Id);
        (await repository.DeletePlaylistAsync(LibraryRepository.LikedPlaylistId))
            .Should()
            .BeFalse();
        (await repository.DeletePlaylistAsync(playlist.Id)).Should().BeTrue();
    }

    [Fact]
    public async Task RecordPlay_UpdatesLastPlayedTimestamp()
    {
        Directory.CreateDirectory(_directory);
        var repository = await CreateRepositoryAsync(Path.Combine(_directory, "library.sqlite"));
        var track = CreateTrack("track-1", "落日之前.mp3");
        var playedAt = new DateTimeOffset(2026, 7, 30, 12, 30, 0, TimeSpan.Zero);
        await repository.UpsertTrackAsync(track);

        await repository.RecordPlayAsync(track.Id, playedAt);

        (await repository.GetTracksAsync()).Single().LastPlayedAt.Should().Be(playedAt);
    }

    public void Dispose()
    {
        if (Directory.Exists(_directory))
        {
            Directory.Delete(_directory, recursive: true);
        }
    }

    private static async Task<LibraryRepository> CreateRepositoryAsync(string databasePath)
    {
        var database = new LibraryDatabase(databasePath);
        await database.InitializeAsync();
        return new LibraryRepository(database);
    }

    private Track CreateTrack(string id, string fileName) =>
        new(
            id,
            Path.Combine(_directory, fileName),
            Path.GetFileNameWithoutExtension(fileName),
            "测试歌手",
            "测试专辑",
            TimeSpan.FromSeconds(180),
            null,
            null,
            false,
            true,
            null);
}
