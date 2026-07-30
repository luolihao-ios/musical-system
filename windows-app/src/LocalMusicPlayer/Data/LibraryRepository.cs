using System.Globalization;
using System.IO;
using Dapper;
using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Data;

public sealed class LibraryRepository(LibraryDatabase database) : ILibraryRepository
{
    public const long LikedPlaylistId = 1;

    public async Task UpsertTrackAsync(
        Track track,
        CancellationToken cancellationToken = default)
    {
        const string sql = """
            INSERT INTO tracks (
                id, file_path, title, artist, album, duration_ms,
                cover_cache_path, lyrics_path, is_liked, is_available, last_played_at)
            VALUES (
                @Id, @FilePath, @Title, @Artist, @Album, @DurationMs,
                @CoverCachePath, @LyricsPath, @IsLiked, @IsAvailable, @LastPlayedAt)
            ON CONFLICT(id) DO UPDATE SET
                file_path = excluded.file_path,
                title = excluded.title,
                artist = excluded.artist,
                album = excluded.album,
                duration_ms = excluded.duration_ms,
                cover_cache_path = excluded.cover_cache_path,
                lyrics_path = excluded.lyrics_path,
                is_available = excluded.is_available;
            """;
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            sql,
            new
            {
                track.Id,
                track.FilePath,
                track.Title,
                track.Artist,
                track.Album,
                DurationMs = (long)track.Duration.TotalMilliseconds,
                track.CoverCachePath,
                track.LyricsPath,
                track.IsLiked,
                track.IsAvailable,
                LastPlayedAt = FormatTimestamp(track.LastPlayedAt),
            },
            cancellationToken: cancellationToken));
    }

    public async Task<IReadOnlyList<Track>> GetTracksAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<TrackRow>(new CommandDefinition(
            TrackSelect + " ORDER BY title COLLATE NOCASE, id;",
            cancellationToken: cancellationToken));
        return rows.Select(ToTrack).ToArray();
    }

    public async Task SetLikedAsync(
        string trackId,
        bool isLiked,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE tracks SET is_liked = @IsLiked WHERE id = @TrackId;",
            new { TrackId = trackId, IsLiked = isLiked },
            cancellationToken: cancellationToken));
    }

    public async Task<Playlist> CreatePlaylistAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var id = await connection.ExecuteScalarAsync<long>(new CommandDefinition(
            """
            INSERT INTO playlists(name, is_built_in) VALUES (@Name, 0);
            SELECT last_insert_rowid();
            """,
            new { Name = name.Trim() },
            cancellationToken: cancellationToken));
        return new Playlist(id, name.Trim(), false);
    }

    public async Task<IReadOnlyList<Playlist>> GetPlaylistsAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var rows = await connection.QueryAsync<PlaylistRow>(new CommandDefinition(
            """
            SELECT id AS Id, name AS Name, is_built_in AS IsBuiltIn
            FROM playlists
            ORDER BY is_built_in DESC, id;
            """,
            cancellationToken: cancellationToken));
        return rows.Select(row => new Playlist(row.Id, row.Name, row.IsBuiltIn)).ToArray();
    }

    public async Task<bool> RenamePlaylistAsync(
        long playlistId,
        string name,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var affected = await connection.ExecuteAsync(new CommandDefinition(
            """
            UPDATE playlists
            SET name = @Name
            WHERE id = @PlaylistId AND is_built_in = 0;
            """,
            new { PlaylistId = playlistId, Name = name.Trim() },
            cancellationToken: cancellationToken));
        return affected == 1;
    }

    public async Task<bool> DeletePlaylistAsync(
        long playlistId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var affected = await connection.ExecuteAsync(new CommandDefinition(
            "DELETE FROM playlists WHERE id = @PlaylistId AND is_built_in = 0;",
            new { PlaylistId = playlistId },
            cancellationToken: cancellationToken));
        return affected == 1;
    }

    public async Task AddTrackToPlaylistAsync(
        long playlistId,
        string trackId,
        int? position = null,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var resolvedPosition = position
            ?? await connection.ExecuteScalarAsync<int>(new CommandDefinition(
                """
                SELECT COALESCE(MAX(position) + 1, 0)
                FROM playlist_tracks
                WHERE playlist_id = @PlaylistId;
                """,
                new { PlaylistId = playlistId },
                cancellationToken: cancellationToken));
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO playlist_tracks(playlist_id, track_id, position)
            VALUES (@PlaylistId, @TrackId, @Position)
            ON CONFLICT(playlist_id, track_id) DO UPDATE SET position = excluded.position;
            """,
            new { PlaylistId = playlistId, TrackId = trackId, Position = resolvedPosition },
            cancellationToken: cancellationToken));
    }

    public async Task<IReadOnlyList<Track>> GetPlaylistTracksAsync(
        long playlistId,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var sql = playlistId == LikedPlaylistId
            ? TrackSelect + " WHERE is_liked = 1 ORDER BY title COLLATE NOCASE, id;"
            : TrackSelect + "\n" + """
                 INNER JOIN playlist_tracks pt ON pt.track_id = tracks.id
                 WHERE pt.playlist_id = @PlaylistId
                 ORDER BY pt.position, tracks.id;
                 """;
        var rows = await connection.QueryAsync<TrackRow>(new CommandDefinition(
            sql,
            new { PlaylistId = playlistId },
            cancellationToken: cancellationToken));
        return rows.Select(ToTrack).ToArray();
    }

    public async Task RecordPlayAsync(
        string trackId,
        DateTimeOffset playedAt,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            "UPDATE tracks SET last_played_at = @PlayedAt WHERE id = @TrackId;",
            new { TrackId = trackId, PlayedAt = FormatTimestamp(playedAt) },
            cancellationToken: cancellationToken));
    }

    public async Task AddScanRootAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        var normalized = Path.TrimEndingDirectorySeparator(Path.GetFullPath(path));
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            "INSERT OR IGNORE INTO scan_roots(path) VALUES (@Path);",
            new { Path = normalized },
            cancellationToken: cancellationToken));
    }

    public async Task<IReadOnlyList<string>> GetScanRootsAsync(
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        var paths = await connection.QueryAsync<string>(new CommandDefinition(
            "SELECT path FROM scan_roots ORDER BY path COLLATE NOCASE;",
            cancellationToken: cancellationToken));
        return paths.ToArray();
    }

    public async Task<string?> GetSettingAsync(
        string key,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        return await connection.QuerySingleOrDefaultAsync<string>(new CommandDefinition(
            "SELECT value FROM settings WHERE key = @Key;",
            new { Key = key },
            cancellationToken: cancellationToken));
    }

    public async Task SetSettingAsync(
        string key,
        string value,
        CancellationToken cancellationToken = default)
    {
        await using var connection = await database.OpenConnectionAsync(cancellationToken);
        await connection.ExecuteAsync(new CommandDefinition(
            """
            INSERT INTO settings(key, value) VALUES (@Key, @Value)
            ON CONFLICT(key) DO UPDATE SET value = excluded.value;
            """,
            new { Key = key, Value = value },
            cancellationToken: cancellationToken));
    }

    private const string TrackSelect = """
        SELECT
            tracks.id AS Id,
            tracks.file_path AS FilePath,
            tracks.title AS Title,
            tracks.artist AS Artist,
            tracks.album AS Album,
            tracks.duration_ms AS DurationMs,
            tracks.cover_cache_path AS CoverCachePath,
            tracks.lyrics_path AS LyricsPath,
            tracks.is_liked AS IsLiked,
            tracks.is_available AS IsAvailable,
            tracks.last_played_at AS LastPlayedAt
        FROM tracks
        """;

    private static Track ToTrack(TrackRow row) =>
        new(
            row.Id,
            row.FilePath,
            row.Title,
            row.Artist,
            row.Album,
            TimeSpan.FromMilliseconds(row.DurationMs),
            row.CoverCachePath,
            row.LyricsPath,
            row.IsLiked,
            row.IsAvailable,
            ParseTimestamp(row.LastPlayedAt));

    private static string? FormatTimestamp(DateTimeOffset? value) =>
        value?.ToString("O", CultureInfo.InvariantCulture);

    private static DateTimeOffset? ParseTimestamp(string? value) =>
        string.IsNullOrWhiteSpace(value)
            ? null
            : DateTimeOffset.Parse(value, CultureInfo.InvariantCulture, DateTimeStyles.RoundtripKind);

    private sealed class TrackRow
    {
        public required string Id { get; init; }
        public required string FilePath { get; init; }
        public required string Title { get; init; }
        public required string Artist { get; init; }
        public required string Album { get; init; }
        public long DurationMs { get; init; }
        public string? CoverCachePath { get; init; }
        public string? LyricsPath { get; init; }
        public bool IsLiked { get; init; }
        public bool IsAvailable { get; init; }
        public string? LastPlayedAt { get; init; }
    }

    private sealed class PlaylistRow
    {
        public long Id { get; init; }
        public required string Name { get; init; }
        public bool IsBuiltIn { get; init; }
    }
}
