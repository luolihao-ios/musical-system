using LocalMusicPlayer.Playback;

namespace LocalMusicPlayer.SystemMedia;

public sealed class SystemMediaBridge : IDisposable
{
    private readonly IPlaybackCommands _playback;
    private readonly ISystemMediaSession _session;

    public SystemMediaBridge(
        IPlaybackCommands playback,
        ISystemMediaSession session)
    {
        _playback = playback;
        _session = session;

        _playback.SnapshotChanged += HandleSnapshotChanged;
        _session.PlayRequested += HandlePlayRequestedAsync;
        _session.PauseRequested += HandlePauseRequestedAsync;
        _session.NextRequested += HandleNextRequestedAsync;
        _session.PreviousRequested += HandlePreviousRequestedAsync;
        _session.SeekRequested += HandleSeekRequestedAsync;

        UpdateSession(_playback.Snapshot);
    }

    public void Dispose()
    {
        _playback.SnapshotChanged -= HandleSnapshotChanged;
        _session.PlayRequested -= HandlePlayRequestedAsync;
        _session.PauseRequested -= HandlePauseRequestedAsync;
        _session.NextRequested -= HandleNextRequestedAsync;
        _session.PreviousRequested -= HandlePreviousRequestedAsync;
        _session.SeekRequested -= HandleSeekRequestedAsync;
    }

    private Task HandlePlayRequestedAsync() => _playback.PlayAsync();

    private Task HandlePauseRequestedAsync() => _playback.PauseAsync();

    private Task HandleNextRequestedAsync() => _playback.NextAsync();

    private Task HandlePreviousRequestedAsync() => _playback.PreviousAsync();

    private Task HandleSeekRequestedAsync(TimeSpan position) =>
        _playback.SeekAsync(position);

    private void HandleSnapshotChanged(
        object? sender,
        PlaybackSnapshot snapshot) =>
        UpdateSession(snapshot);

    private void UpdateSession(PlaybackSnapshot snapshot)
    {
        var track = snapshot.CurrentTrack;
        _session.Update(track is null
            ? SystemMediaState.Empty
            : new SystemMediaState(
                track.Title,
                track.Artist,
                track.Album,
                track.CoverCachePath,
                snapshot.IsPlaying,
                snapshot.Position,
                snapshot.Duration));
    }
}
