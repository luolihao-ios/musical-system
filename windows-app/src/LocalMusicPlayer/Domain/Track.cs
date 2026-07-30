namespace LocalMusicPlayer.Domain;

public sealed record Track(
    string Id,
    string FilePath,
    string Title,
    string Artist,
    string Album,
    TimeSpan Duration,
    string? CoverCachePath,
    string? LyricsPath,
    bool IsLiked,
    bool IsAvailable,
    DateTimeOffset? LastPlayedAt);
