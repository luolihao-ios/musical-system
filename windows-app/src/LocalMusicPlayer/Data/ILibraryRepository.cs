using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Data;

public interface ILibraryRepository
{
    Task UpsertTrackAsync(Track track, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<Track>> GetTracksAsync(CancellationToken cancellationToken = default);

    Task SetLikedAsync(
        string trackId,
        bool isLiked,
        CancellationToken cancellationToken = default);

    Task<Playlist> CreatePlaylistAsync(
        string name,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<Playlist>> GetPlaylistsAsync(
        CancellationToken cancellationToken = default);

    Task<bool> RenamePlaylistAsync(
        long playlistId,
        string name,
        CancellationToken cancellationToken = default);

    Task<bool> DeletePlaylistAsync(
        long playlistId,
        CancellationToken cancellationToken = default);

    Task AddTrackToPlaylistAsync(
        long playlistId,
        string trackId,
        int? position = null,
        CancellationToken cancellationToken = default);

    Task<IReadOnlyList<Track>> GetPlaylistTracksAsync(
        long playlistId,
        CancellationToken cancellationToken = default);

    Task RecordPlayAsync(
        string trackId,
        DateTimeOffset playedAt,
        CancellationToken cancellationToken = default);

    Task AddScanRootAsync(string path, CancellationToken cancellationToken = default);

    Task<IReadOnlyList<string>> GetScanRootsAsync(
        CancellationToken cancellationToken = default);

    Task<string?> GetSettingAsync(
        string key,
        CancellationToken cancellationToken = default);

    Task SetSettingAsync(
        string key,
        string value,
        CancellationToken cancellationToken = default);
}
