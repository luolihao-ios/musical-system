using Windows.Media;
using Windows.Media.Playback;
using Windows.Storage.Streams;
using System.IO;

namespace LocalMusicPlayer.SystemMedia;

public sealed class WindowsSystemMediaSession : ISystemMediaSession, IDisposable
{
    private readonly MediaPlayer _mediaPlayer = new();
    private readonly SystemMediaTransportControls _controls;

    public WindowsSystemMediaSession()
    {
        _mediaPlayer.CommandManager.IsEnabled = false;
        _controls = _mediaPlayer.SystemMediaTransportControls;
        _controls.IsEnabled = true;
        _controls.IsPlayEnabled = true;
        _controls.IsPauseEnabled = true;
        _controls.IsNextEnabled = true;
        _controls.IsPreviousEnabled = true;

        _controls.ButtonPressed += HandleButtonPressed;
        _controls.PlaybackPositionChangeRequested += HandlePositionChangeRequested;
    }

    public event Func<Task>? PlayRequested;
    public event Func<Task>? PauseRequested;
    public event Func<Task>? NextRequested;
    public event Func<Task>? PreviousRequested;
    public event Func<TimeSpan, Task>? SeekRequested;

    public void Update(SystemMediaState state)
    {
        var updater = _controls.DisplayUpdater;
        updater.Type = MediaPlaybackType.Music;
        updater.MusicProperties.Title = state.Title;
        updater.MusicProperties.Artist = state.Artist;
        updater.MusicProperties.AlbumTitle = state.Album;
        updater.Thumbnail = CreateCoverReference(state.CoverPath);
        updater.Update();

        _controls.PlaybackStatus = state.IsPlaying
            ? MediaPlaybackStatus.Playing
            : MediaPlaybackStatus.Paused;

        var duration = state.Duration < TimeSpan.Zero
            ? TimeSpan.Zero
            : state.Duration;
        var position = state.Position < TimeSpan.Zero
            ? TimeSpan.Zero
            : state.Position > duration
                ? duration
                : state.Position;
        _controls.UpdateTimelineProperties(
            new SystemMediaTransportControlsTimelineProperties
            {
                StartTime = TimeSpan.Zero,
                EndTime = duration,
                MinSeekTime = TimeSpan.Zero,
                MaxSeekTime = duration,
                Position = position,
            });
    }

    public void Dispose()
    {
        _controls.ButtonPressed -= HandleButtonPressed;
        _controls.PlaybackPositionChangeRequested -= HandlePositionChangeRequested;
        _controls.IsEnabled = false;
        _mediaPlayer.Dispose();
    }

    private static RandomAccessStreamReference? CreateCoverReference(string? coverPath)
    {
        var path = coverPath;
        if (string.IsNullOrWhiteSpace(path) || !File.Exists(path))
        {
            return null;
        }

        try
        {
            return RandomAccessStreamReference.CreateFromUri(new Uri(path));
        }
        catch (UriFormatException)
        {
            return null;
        }
    }

    private async void HandleButtonPressed(
        SystemMediaTransportControls sender,
        SystemMediaTransportControlsButtonPressedEventArgs args)
    {
        try
        {
            await InvokeButtonAsync(args.Button);
        }
        catch (ObjectDisposedException)
        {
        }
    }

    private Task InvokeButtonAsync(SystemMediaTransportControlsButton button) =>
        button switch
        {
            SystemMediaTransportControlsButton.Play =>
                PlayRequested?.Invoke() ?? Task.CompletedTask,
            SystemMediaTransportControlsButton.Pause =>
                PauseRequested?.Invoke() ?? Task.CompletedTask,
            SystemMediaTransportControlsButton.Next =>
                NextRequested?.Invoke() ?? Task.CompletedTask,
            SystemMediaTransportControlsButton.Previous =>
                PreviousRequested?.Invoke() ?? Task.CompletedTask,
            _ => Task.CompletedTask,
        };

    private async void HandlePositionChangeRequested(
        SystemMediaTransportControls sender,
        PlaybackPositionChangeRequestedEventArgs args)
    {
        try
        {
            await (SeekRequested?.Invoke(args.RequestedPlaybackPosition)
                ?? Task.CompletedTask);
        }
        catch (ObjectDisposedException)
        {
        }
    }
}
