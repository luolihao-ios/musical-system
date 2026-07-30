using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Playback;

public sealed record PlaybackSnapshot(
    IReadOnlyList<Track> Queue,
    int? CurrentIndex,
    bool IsPlaying,
    TimeSpan Position,
    TimeSpan Duration,
    double Volume,
    PlaybackMode Mode)
{
    public Track? CurrentTrack =>
        CurrentIndex is { } index && index >= 0 && index < Queue.Count
            ? Queue[index]
            : null;

    public static PlaybackSnapshot Empty { get; } =
        new([], null, false, TimeSpan.Zero, TimeSpan.Zero, 1, PlaybackMode.RepeatAll);
}
