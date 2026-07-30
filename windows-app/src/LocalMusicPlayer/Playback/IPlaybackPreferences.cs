namespace LocalMusicPlayer.Playback;

public interface IPlaybackPreferences
{
    Task<PlaybackPreferences> LoadAsync(CancellationToken cancellationToken = default);

    Task SaveAsync(
        PlaybackPreferences preferences,
        CancellationToken cancellationToken = default);
}
