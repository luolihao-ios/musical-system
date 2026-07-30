using System.Globalization;
using LocalMusicPlayer.Data;

namespace LocalMusicPlayer.Playback;

public sealed class RepositoryPlaybackPreferences(ILibraryRepository repository)
    : IPlaybackPreferences
{
    private const string VolumeKey = "playback.volume";
    private const string ModeKey = "playback.mode";
    private const string LastTrackKey = "playback.lastTrackId";
    private const string LastPositionKey = "playback.lastPositionMs";

    public async Task<PlaybackPreferences> LoadAsync(
        CancellationToken cancellationToken = default)
    {
        var volumeText = await repository.GetSettingAsync(VolumeKey, cancellationToken);
        var modeText = await repository.GetSettingAsync(ModeKey, cancellationToken);
        var lastTrackId = await repository.GetSettingAsync(LastTrackKey, cancellationToken);
        var positionText = await repository.GetSettingAsync(LastPositionKey, cancellationToken);
        var volume = double.TryParse(
            volumeText,
            NumberStyles.Float,
            CultureInfo.InvariantCulture,
            out var parsedVolume)
            ? Math.Clamp(parsedVolume, 0, 1)
            : 1;
        var mode = Enum.TryParse<PlaybackMode>(modeText, out var parsedMode)
            ? parsedMode
            : PlaybackMode.RepeatAll;
        var position = long.TryParse(
            positionText,
            NumberStyles.Integer,
            CultureInfo.InvariantCulture,
            out var milliseconds)
            ? TimeSpan.FromMilliseconds(Math.Max(0, milliseconds))
            : TimeSpan.Zero;
        return new PlaybackPreferences(volume, mode, lastTrackId, position);
    }

    public async Task SaveAsync(
        PlaybackPreferences preferences,
        CancellationToken cancellationToken = default)
    {
        await repository.SetSettingAsync(
            VolumeKey,
            preferences.Volume.ToString(CultureInfo.InvariantCulture),
            cancellationToken);
        await repository.SetSettingAsync(
            ModeKey,
            preferences.Mode.ToString(),
            cancellationToken);
        await repository.SetSettingAsync(
            LastTrackKey,
            preferences.LastTrackId ?? string.Empty,
            cancellationToken);
        await repository.SetSettingAsync(
            LastPositionKey,
            ((long)preferences.LastPosition.TotalMilliseconds)
                .ToString(CultureInfo.InvariantCulture),
            cancellationToken);
    }
}
