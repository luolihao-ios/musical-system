using System.Collections.ObjectModel;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Lyrics;
using LocalMusicPlayer.Playback;

namespace LocalMusicPlayer.ViewModels;

public sealed class NowPlayingViewModel : ObservableObject, IDisposable
{
    private readonly IPlaybackCommands _playback;
    private readonly ILyricsSource _lyricsSource;
    private string? _loadedTrackId;
    private Track? _currentTrack;
    private int _currentLyricIndex = -1;
    private string _currentLyricText = string.Empty;
    private bool _hasLyrics;
    private bool _isRecordRotating;
    private TimeSpan _position;
    private TimeSpan _duration;

    public NowPlayingViewModel(
        IPlaybackCommands playback,
        ILyricsSource lyricsSource)
    {
        _playback = playback;
        _lyricsSource = lyricsSource;
        TogglePlaybackCommand = new AsyncRelayCommand(TogglePlaybackAsync);
        NextCommand = new AsyncRelayCommand(() => _playback.NextAsync());
        PreviousCommand = new AsyncRelayCommand(() => _playback.PreviousAsync());
        _playback.SnapshotChanged += HandleSnapshotChanged;
        ApplySnapshot(_playback.Snapshot);
    }

    public ObservableCollection<LyricLine> LyricLines { get; } = [];

    public IAsyncRelayCommand TogglePlaybackCommand { get; }

    public IAsyncRelayCommand NextCommand { get; }

    public IAsyncRelayCommand PreviousCommand { get; }

    public Track? CurrentTrack
    {
        get => _currentTrack;
        private set => SetProperty(ref _currentTrack, value);
    }

    public int CurrentLyricIndex
    {
        get => _currentLyricIndex;
        private set => SetProperty(ref _currentLyricIndex, value);
    }

    public string CurrentLyricText
    {
        get => _currentLyricText;
        private set => SetProperty(ref _currentLyricText, value);
    }

    public bool HasLyrics
    {
        get => _hasLyrics;
        private set => SetProperty(ref _hasLyrics, value);
    }

    public bool IsRecordRotating
    {
        get => _isRecordRotating;
        private set => SetProperty(ref _isRecordRotating, value);
    }

    public TimeSpan Position
    {
        get => _position;
        private set
        {
            if (SetProperty(ref _position, value))
            {
                OnPropertyChanged(nameof(PositionText));
                OnPropertyChanged(nameof(Progress));
            }
        }
    }

    public TimeSpan Duration
    {
        get => _duration;
        private set
        {
            if (SetProperty(ref _duration, value))
            {
                OnPropertyChanged(nameof(DurationText));
                OnPropertyChanged(nameof(Progress));
            }
        }
    }

    public string PositionText => FormatTime(Position);

    public string DurationText => FormatTime(Duration);

    public double Progress =>
        Duration <= TimeSpan.Zero
            ? 0
            : Math.Clamp(Position.TotalMilliseconds / Duration.TotalMilliseconds, 0, 1);

    public Task SeekAsync(
        TimeSpan position,
        CancellationToken cancellationToken = default) =>
        _playback.SeekAsync(position, cancellationToken);

    public Task SeekFractionAsync(
        double fraction,
        CancellationToken cancellationToken = default) =>
        SeekAsync(
            TimeSpan.FromMilliseconds(
                Duration.TotalMilliseconds * Math.Clamp(fraction, 0, 1)),
            cancellationToken);

    public void Dispose() =>
        _playback.SnapshotChanged -= HandleSnapshotChanged;

    private Task TogglePlaybackAsync() =>
        IsRecordRotating
            ? _playback.PauseAsync()
            : _playback.PlayAsync();

    private void HandleSnapshotChanged(
        object? sender,
        PlaybackSnapshot snapshot)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(() => ApplySnapshot(snapshot));
            return;
        }

        ApplySnapshot(snapshot);
    }

    private void ApplySnapshot(PlaybackSnapshot snapshot)
    {
        CurrentTrack = snapshot.CurrentTrack;
        Position = snapshot.Position;
        Duration = snapshot.Duration;
        IsRecordRotating = snapshot.IsPlaying;

        if (_loadedTrackId != snapshot.CurrentTrack?.Id)
        {
            _loadedTrackId = snapshot.CurrentTrack?.Id;
            LoadLyrics(snapshot.CurrentTrack);
        }

        CurrentLyricIndex = LrcParser.FindCurrentLine(
            LyricLines,
            snapshot.Position);
        CurrentLyricText = CurrentLyricIndex >= 0
            ? LyricLines[CurrentLyricIndex].Text
            : string.Empty;
    }

    private void LoadLyrics(Track? track)
    {
        LyricLines.Clear();
        if (string.IsNullOrWhiteSpace(track?.LyricsPath))
        {
            HasLyrics = false;
            return;
        }

        try
        {
            var source = _lyricsSource.Read(track.LyricsPath);
            foreach (var line in LrcParser.Parse(source ?? string.Empty))
            {
                LyricLines.Add(line);
            }
        }
        catch (Exception exception) when (
            exception is IOException
            or UnauthorizedAccessException)
        {
            LyricLines.Clear();
        }

        HasLyrics = LyricLines.Count > 0;
    }

    private static string FormatTime(TimeSpan value) =>
        $"{Math.Max(0, (int)value.TotalMinutes):00}:{Math.Max(0, value.Seconds):00}";
}
