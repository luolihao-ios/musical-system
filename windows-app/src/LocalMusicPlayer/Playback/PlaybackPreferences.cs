namespace LocalMusicPlayer.Playback;

public sealed record PlaybackPreferences(
    double Volume,
    PlaybackMode Mode,
    string? LastTrackId,
    TimeSpan LastPosition)
{
    public static PlaybackPreferences Default { get; } =
        new(1, PlaybackMode.RepeatAll, null, TimeSpan.Zero);
}
