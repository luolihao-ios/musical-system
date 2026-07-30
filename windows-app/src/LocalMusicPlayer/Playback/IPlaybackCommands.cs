namespace LocalMusicPlayer.Playback;

public interface IPlaybackCommands
{
    event EventHandler<PlaybackSnapshot>? SnapshotChanged;

    PlaybackSnapshot Snapshot { get; }

    void LoadQueue(IReadOnlyList<Domain.Track> tracks, int startIndex = 0);

    Task PlayAsync(CancellationToken cancellationToken = default);

    Task PauseAsync(CancellationToken cancellationToken = default);

    Task NextAsync(CancellationToken cancellationToken = default);

    Task PreviousAsync(CancellationToken cancellationToken = default);

    Task SeekAsync(
        TimeSpan position,
        CancellationToken cancellationToken = default);
}
