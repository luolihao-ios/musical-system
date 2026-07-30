using FluentAssertions;
using LocalMusicPlayer.Data;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Tests.ViewModels;

public sealed class PlaylistsViewModelTests
{
    [Fact]
    public async Task CustomPlaylists_CanBeCreatedRenamedAndDeleted()
    {
        var repository = new FakePlaylistRepository();
        var viewModel = new PlaylistsViewModel(repository);
        await viewModel.InitializeAsync();

        var playlist = await viewModel.CreateAsync("  夜行歌单  ");
        await viewModel.RenameAsync(playlist, " 深夜收藏 ");
        var deleted = await viewModel.DeleteAsync(
            viewModel.Playlists.Single(item => item.Id == playlist.Id));

        deleted.Should().BeTrue();
        repository.Playlists.Should().NotContain(item => item.Id == playlist.Id);
    }

    [Fact]
    public async Task BuiltInLikedPlaylist_CannotBeDeletedOrRenamed()
    {
        var repository = new FakePlaylistRepository();
        var viewModel = new PlaylistsViewModel(repository);
        await viewModel.InitializeAsync();
        var liked = viewModel.Playlists.Single(item => item.IsBuiltIn);

        var renamed = await viewModel.RenameAsync(liked, "不能改名");
        var deleted = await viewModel.DeleteAsync(liked);

        renamed.Should().BeFalse();
        deleted.Should().BeFalse();
        repository.Playlists.Should().ContainSingle(item => item.Name == "我喜欢");
    }

    private sealed class FakePlaylistRepository : ILibraryRepository
    {
        private long _nextId = 2;

        public List<Playlist> Playlists { get; } =
            [new Playlist(1, "我喜欢", true)];

        public Task<Playlist> CreatePlaylistAsync(
            string name,
            CancellationToken cancellationToken = default)
        {
            var playlist = new Playlist(_nextId++, name, false);
            Playlists.Add(playlist);
            return Task.FromResult(playlist);
        }

        public Task<IReadOnlyList<Playlist>> GetPlaylistsAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<Playlist>>([.. Playlists]);

        public Task<bool> RenamePlaylistAsync(
            long playlistId,
            string name,
            CancellationToken cancellationToken = default)
        {
            var index = Playlists.FindIndex(item => item.Id == playlistId);
            if (index < 0 || Playlists[index].IsBuiltIn)
            {
                return Task.FromResult(false);
            }

            Playlists[index] = Playlists[index] with { Name = name };
            return Task.FromResult(true);
        }

        public Task<bool> DeletePlaylistAsync(
            long playlistId,
            CancellationToken cancellationToken = default)
        {
            var playlist = Playlists.FirstOrDefault(item => item.Id == playlistId);
            if (playlist is null || playlist.IsBuiltIn)
            {
                return Task.FromResult(false);
            }

            Playlists.Remove(playlist);
            return Task.FromResult(true);
        }

        public Task UpsertTrackAsync(
            Track track,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task<IReadOnlyList<Track>> GetTracksAsync(
            CancellationToken cancellationToken = default) =>
            Task.FromResult<IReadOnlyList<Track>>([]);

        public Task SetLikedAsync(
            string trackId,
            bool isLiked,
            CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

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
