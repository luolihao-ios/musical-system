using FluentAssertions;
using LocalMusicPlayer.Data;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Library;
using LocalMusicPlayer.Playback;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Tests.ViewModels;

public sealed class LibraryViewModelTests
{
    [Fact]
    public async Task Search_IsAccentInsensitiveAcrossTrackMetadata()
    {
        var repository = new FakeLibraryRepository(
            CreateTrack("one", "Lumière", "Beyoncé", "Été"),
            CreateTrack("two", "夜航星", "测试歌手", "城市夜行"));
        var viewModel = new LibraryViewModel(
            repository,
            new FakeLibraryScanner(repository),
            new FakePlaybackCommands());
        await viewModel.InitializeAsync();

        viewModel.SearchText = "beyonce";

        viewModel.FilteredTracks.Should().ContainSingle()
            .Which.Id.Should().Be("one");
    }

    [Fact]
    public async Task AddFolder_ScansAndRefreshesTheLibrary()
    {
        var repository = new FakeLibraryRepository();
        var scanner = new FakeLibraryScanner(repository)
        {
            TrackToAdd = CreateTrack("new", "落日之前", "雾岛乐队", "城市夜行"),
        };
        var viewModel = new LibraryViewModel(
            repository,
            scanner,
            new FakePlaybackCommands());

        await viewModel.AddFolderAsync(@"D:\Music");

        scanner.LastRoot.Should().Be(@"D:\Music");
        viewModel.Tracks.Should().ContainSingle(track => track.Id == "new");
    }

    [Fact]
    public async Task ToggleLike_UpdatesRepositoryAndVisibleTrack()
    {
        var repository = new FakeLibraryRepository(CreateTrack("one", "夜航星", "歌手", "专辑"));
        var viewModel = new LibraryViewModel(
            repository,
            new FakeLibraryScanner(repository),
            new FakePlaybackCommands());
        await viewModel.InitializeAsync();

        await viewModel.ToggleLikeAsync(viewModel.Tracks[0]);

        repository.Tracks[0].IsLiked.Should().BeTrue();
        viewModel.Tracks[0].IsLiked.Should().BeTrue();
    }

    [Fact]
    public async Task Play_UsesFilteredRowsAndSelectedTrack()
    {
        var repository = new FakeLibraryRepository(
            CreateTrack("one", "第一首", "甲", "专辑"),
            CreateTrack("two", "目标歌曲", "乙", "专辑"));
        var playback = new FakePlaybackCommands();
        var viewModel = new LibraryViewModel(
            repository,
            new FakeLibraryScanner(repository),
            playback);
        await viewModel.InitializeAsync();
        viewModel.SearchText = "目标";

        await viewModel.PlayAsync(viewModel.FilteredTracks[0]);

        playback.LoadedQueue.Should().ContainSingle(track => track.Id == "two");
        playback.StartIndex.Should().Be(0);
        playback.PlayCount.Should().Be(1);
    }

    private static Track CreateTrack(
        string id,
        string title,
        string artist,
        string album) =>
        new(
            id,
            $@"D:\Music\{id}.mp3",
            title,
            artist,
            album,
            TimeSpan.FromMinutes(3),
            null,
            null,
            false,
            true,
            null);

    private sealed class FakeLibraryScanner(FakeLibraryRepository repository)
        : ILibraryScanner
    {
        public string? LastRoot { get; private set; }

        public Track? TrackToAdd { get; init; }

        public Task<ScanResult> ScanAsync(
            string root,
            CancellationToken cancellationToken = default)
        {
            LastRoot = root;
            if (TrackToAdd is not null)
            {
                repository.Tracks.Add(TrackToAdd);
            }

            return Task.FromResult(new ScanResult(1, 1, 0, 0));
        }
    }

    private sealed class FakePlaybackCommands : IPlaybackCommands
    {
        public event EventHandler<PlaybackSnapshot>? SnapshotChanged
        {
            add { }
            remove { }
        }

        public PlaybackSnapshot Snapshot { get; private set; } = PlaybackSnapshot.Empty;

        public IReadOnlyList<Track> LoadedQueue { get; private set; } = [];

        public int StartIndex { get; private set; }

        public int PlayCount { get; private set; }

        public void LoadQueue(IReadOnlyList<Track> tracks, int startIndex = 0)
        {
            LoadedQueue = tracks;
            StartIndex = startIndex;
        }

        public Task PlayAsync(CancellationToken cancellationToken = default)
        {
            PlayCount++;
            return Task.CompletedTask;
        }

        public Task PauseAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task NextAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task PreviousAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task SeekAsync(
            TimeSpan position,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;
    }

    private sealed class FakeLibraryRepository(params Track[] tracks)
        : ILibraryRepository
    {
        public List<Track> Tracks { get; } = [.. tracks];

        public Task UpsertTrackAsync(
            Track track,
            CancellationToken cancellationToken = default)
        {
            var index = Tracks.FindIndex(item => item.Id == track.Id);
            if (index >= 0)
            {
                Tracks[index] = track;
            }
            else
            {
                Tracks.Add(track);
            }

            return Task.CompletedTask;
        }

        public Task<IReadOnlyList<Track>> GetTracksAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<Track>>([.. Tracks]);

        public Task SetLikedAsync(
            string trackId,
            bool isLiked,
            CancellationToken cancellationToken = default)
        {
            var index = Tracks.FindIndex(track => track.Id == trackId);
            Tracks[index] = Tracks[index] with { IsLiked = isLiked };
            return Task.CompletedTask;
        }

        public Task<Playlist> CreatePlaylistAsync(
            string name,
            CancellationToken cancellationToken = default) =>
            throw new NotSupportedException();

        public Task<IReadOnlyList<Playlist>> GetPlaylistsAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<Playlist>>([]);

        public Task<bool> RenamePlaylistAsync(
            long playlistId,
            string name,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(false);

        public Task<bool> DeletePlaylistAsync(
            long playlistId,
            CancellationToken cancellationToken = default) =>
            Task.FromResult(false);

        public Task AddTrackToPlaylistAsync(
            long playlistId,
            string trackId,
            int? position = null,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task<IReadOnlyList<Track>> GetPlaylistTracksAsync(
            long playlistId,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<Track>>([]);

        public Task RecordPlayAsync(
            string trackId,
            DateTimeOffset playedAt,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task AddScanRootAsync(
            string path,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task<IReadOnlyList<string>> GetScanRootsAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<string>>([]);

        public Task<string?> GetSettingAsync(
            string key,
            CancellationToken cancellationToken = default) =>
            Task.FromResult<string?>(null);

        public Task SetSettingAsync(
            string key,
            string value,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;
    }
}
