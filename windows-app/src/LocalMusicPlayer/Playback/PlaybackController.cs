using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Playback;

public sealed class PlaybackController : IPlaybackCommands, IAsyncDisposable
{
    private readonly IAudioOutput _audioOutput;
    private readonly IPlaybackPreferences _preferences;
    private readonly Random _random;
    private PlaybackPreferences _restoredPreferences = PlaybackPreferences.Default;
    private string? _loadedTrackId;
    private bool _restoredPositionApplied;

    public PlaybackController(
        IAudioOutput audioOutput,
        IPlaybackPreferences preferences,
        Random? random = null)
    {
        _audioOutput = audioOutput;
        _preferences = preferences;
        _random = random ?? Random.Shared;
        _audioOutput.PlaybackEnded += HandlePlaybackEndedAsync;
        _audioOutput.PositionChanged += HandlePositionChanged;
    }

    public event EventHandler<PlaybackSnapshot>? SnapshotChanged;

    public PlaybackSnapshot Snapshot { get; private set; } = PlaybackSnapshot.Empty;

    public async Task InitializeAsync(CancellationToken cancellationToken = default)
    {
        _restoredPreferences = await _preferences.LoadAsync(cancellationToken);
        _audioOutput.Volume = _restoredPreferences.Volume;
        UpdateSnapshot(Snapshot with
        {
            Volume = _restoredPreferences.Volume,
            Mode = _restoredPreferences.Mode,
        });
    }

    public void LoadQueue(IReadOnlyList<Track> tracks, int startIndex = 0)
    {
        var queue = tracks.ToArray();
        int? currentIndex = queue.Length == 0
            ? null
            : Math.Clamp(startIndex, 0, queue.Length - 1);
        if (!string.IsNullOrWhiteSpace(_restoredPreferences.LastTrackId))
        {
            var restoredIndex = Array.FindIndex(
                queue,
                track => track.Id == _restoredPreferences.LastTrackId);
            if (restoredIndex >= 0)
            {
                currentIndex = restoredIndex;
            }
        }

        _loadedTrackId = null;
        _restoredPositionApplied = false;
        UpdateSnapshot(Snapshot with
        {
            Queue = queue,
            CurrentIndex = currentIndex,
            IsPlaying = false,
            Position = TimeSpan.Zero,
            Duration = currentIndex is null ? TimeSpan.Zero : queue[currentIndex.Value].Duration,
        });
    }

    public async Task PlayAsync(CancellationToken cancellationToken = default)
    {
        if (!SelectAvailableTrack())
        {
            return;
        }

        await EnsureCurrentLoadedAsync(cancellationToken);
        if (!_restoredPositionApplied
            && Snapshot.CurrentTrack?.Id == _restoredPreferences.LastTrackId
            && _restoredPreferences.LastPosition > TimeSpan.Zero)
        {
            var restored = ClampPosition(_restoredPreferences.LastPosition);
            _audioOutput.Seek(restored);
            _restoredPositionApplied = true;
        }

        _audioOutput.Play();
        UpdateSnapshot(Snapshot with { IsPlaying = true });
    }

    public async Task PauseAsync(CancellationToken cancellationToken = default)
    {
        _audioOutput.Pause();
        UpdateSnapshot(Snapshot with
        {
            IsPlaying = false,
            Position = _audioOutput.Position,
        });
        await SavePreferencesAsync(cancellationToken);
    }

    public async Task SeekAsync(
        TimeSpan position,
        CancellationToken cancellationToken = default)
    {
        var clamped = ClampPosition(position);
        _audioOutput.Seek(clamped);
        UpdateSnapshot(Snapshot with { Position = clamped });
        await SavePreferencesAsync(cancellationToken);
    }

    public async Task SetVolumeAsync(
        double volume,
        CancellationToken cancellationToken = default)
    {
        var clamped = Math.Clamp(volume, 0, 1);
        _audioOutput.Volume = clamped;
        UpdateSnapshot(Snapshot with { Volume = clamped });
        await SavePreferencesAsync(cancellationToken);
    }

    public async Task SetModeAsync(
        PlaybackMode mode,
        CancellationToken cancellationToken = default)
    {
        UpdateSnapshot(Snapshot with { Mode = mode });
        await SavePreferencesAsync(cancellationToken);
    }

    public async Task NextAsync(CancellationToken cancellationToken = default)
    {
        if (!MoveToNextAvailable())
        {
            return;
        }

        await LoadAndPlayCurrentAsync(cancellationToken);
    }

    public async Task PreviousAsync(CancellationToken cancellationToken = default)
    {
        if (_audioOutput.Position > TimeSpan.FromSeconds(3))
        {
            await SeekAsync(TimeSpan.Zero, cancellationToken);
            return;
        }

        if (!MoveToPreviousAvailable())
        {
            return;
        }

        await LoadAndPlayCurrentAsync(cancellationToken);
    }

    public async ValueTask DisposeAsync()
    {
        _audioOutput.PlaybackEnded -= HandlePlaybackEndedAsync;
        _audioOutput.PositionChanged -= HandlePositionChanged;
        await _audioOutput.DisposeAsync();
    }

    private async Task HandlePlaybackEndedAsync()
    {
        if (Snapshot.Mode == PlaybackMode.RepeatOne)
        {
            _audioOutput.Seek(TimeSpan.Zero);
            _audioOutput.Play();
            UpdateSnapshot(Snapshot with
            {
                IsPlaying = true,
                Position = TimeSpan.Zero,
            });
            return;
        }

        await NextAsync();
    }

    private async Task LoadAndPlayCurrentAsync(CancellationToken cancellationToken)
    {
        _loadedTrackId = null;
        _restoredPositionApplied = true;
        await EnsureCurrentLoadedAsync(cancellationToken);
        _audioOutput.Seek(TimeSpan.Zero);
        _audioOutput.Play();
        UpdateSnapshot(Snapshot with
        {
            IsPlaying = true,
            Position = TimeSpan.Zero,
        });
        await SavePreferencesAsync(cancellationToken);
    }

    private async Task EnsureCurrentLoadedAsync(CancellationToken cancellationToken)
    {
        var track = Snapshot.CurrentTrack;
        if (track is null || _loadedTrackId == track.Id)
        {
            return;
        }

        await _audioOutput.LoadAsync(track.FilePath, cancellationToken);
        _audioOutput.Volume = Snapshot.Volume;
        _loadedTrackId = track.Id;
        UpdateSnapshot(Snapshot with
        {
            Position = TimeSpan.Zero,
            Duration = _audioOutput.Duration > TimeSpan.Zero
                ? _audioOutput.Duration
                : track.Duration,
        });
    }

    private bool SelectAvailableTrack()
    {
        if (Snapshot.CurrentTrack?.IsAvailable == true)
        {
            return true;
        }

        var current = Snapshot.CurrentIndex ?? -1;
        for (var offset = 1; offset <= Snapshot.Queue.Count; offset++)
        {
            var candidate = (current + offset) % Snapshot.Queue.Count;
            if (Snapshot.Queue[candidate].IsAvailable)
            {
                UpdateSnapshot(Snapshot with { CurrentIndex = candidate });
                return true;
            }
        }

        return false;
    }

    private bool MoveToNextAvailable()
    {
        if (Snapshot.Queue.Count == 0)
        {
            return false;
        }

        if (Snapshot.Mode == PlaybackMode.Shuffle)
        {
            var available = Snapshot.Queue
                .Select((track, index) => (track, index))
                .Where(item => item.track.IsAvailable && item.index != Snapshot.CurrentIndex)
                .Select(item => item.index)
                .ToArray();
            if (available.Length == 0)
            {
                return Snapshot.CurrentTrack?.IsAvailable == true;
            }

            UpdateSnapshot(Snapshot with
            {
                CurrentIndex = available[_random.Next(available.Length)],
            });
            return true;
        }

        var current = Snapshot.CurrentIndex ?? -1;
        for (var offset = 1; offset <= Snapshot.Queue.Count; offset++)
        {
            var candidate = (current + offset) % Snapshot.Queue.Count;
            if (Snapshot.Queue[candidate].IsAvailable)
            {
                UpdateSnapshot(Snapshot with { CurrentIndex = candidate });
                return true;
            }
        }

        return false;
    }

    private bool MoveToPreviousAvailable()
    {
        if (Snapshot.Queue.Count == 0)
        {
            return false;
        }

        var current = Snapshot.CurrentIndex ?? 0;
        for (var offset = 1; offset <= Snapshot.Queue.Count; offset++)
        {
            var candidate = (current - offset + Snapshot.Queue.Count) % Snapshot.Queue.Count;
            if (Snapshot.Queue[candidate].IsAvailable)
            {
                UpdateSnapshot(Snapshot with { CurrentIndex = candidate });
                return true;
            }
        }

        return false;
    }

    private TimeSpan ClampPosition(TimeSpan position)
    {
        var duration = _audioOutput.Duration > TimeSpan.Zero
            ? _audioOutput.Duration
            : Snapshot.Duration;
        return position < TimeSpan.Zero
            ? TimeSpan.Zero
            : position > duration
                ? duration
                : position;
    }

    private async Task SavePreferencesAsync(CancellationToken cancellationToken)
    {
        await _preferences.SaveAsync(
            new PlaybackPreferences(
                Snapshot.Volume,
                Snapshot.Mode,
                Snapshot.CurrentTrack?.Id,
                Snapshot.Position),
            cancellationToken);
    }

    private void HandlePositionChanged(object? sender, TimeSpan position) =>
        UpdateSnapshot(Snapshot with { Position = position });

    private void UpdateSnapshot(PlaybackSnapshot snapshot)
    {
        Snapshot = snapshot;
        SnapshotChanged?.Invoke(this, snapshot);
    }
}
