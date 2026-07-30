using System.IO;
using NAudio.CoreAudioApi;
using NAudio.Vorbis;
using NAudio.Wave;

namespace LocalMusicPlayer.Playback;

public sealed class NAudioOutput : IAudioOutput
{
    private readonly Timer _positionTimer;
    private WaveStream? _reader;
    private WasapiOut? _output;
    private bool _stopping;
    private double _volume = 1;

    public NAudioOutput()
    {
        _positionTimer = new Timer(
            _ => PublishPosition(),
            null,
            TimeSpan.FromMilliseconds(250),
            TimeSpan.FromMilliseconds(250));
    }

    public event Func<Task>? PlaybackEnded;

    public event EventHandler<TimeSpan>? PositionChanged;

    public TimeSpan Position => _reader?.CurrentTime ?? TimeSpan.Zero;

    public TimeSpan Duration => _reader?.TotalTime ?? TimeSpan.Zero;

    public double Volume
    {
        get => _volume;
        set
        {
            _volume = Math.Clamp(value, 0, 1);
            if (_output is not null)
            {
                _output.Volume = (float)_volume;
            }
        }
    }

    public bool IsPlaying => _output?.PlaybackState == NAudio.Wave.PlaybackState.Playing;

    public Task LoadAsync(string path, CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        DisposeCurrent();
        _reader = string.Equals(
            Path.GetExtension(path),
            ".ogg",
            StringComparison.OrdinalIgnoreCase)
            ? new VorbisWaveReader(path)
            : new MediaFoundationReader(path);
        _output = new WasapiOut(AudioClientShareMode.Shared, false, 100)
        {
            Volume = (float)_volume,
        };
        _output.PlaybackStopped += HandlePlaybackStopped;
        _output.Init(_reader);
        return Task.CompletedTask;
    }

    public void Play() => _output?.Play();

    public void Pause() => _output?.Pause();

    public void Seek(TimeSpan position)
    {
        if (_reader is null)
        {
            return;
        }

        _reader.CurrentTime = position < TimeSpan.Zero
            ? TimeSpan.Zero
            : position > _reader.TotalTime
                ? _reader.TotalTime
                : position;
        PositionChanged?.Invoke(this, _reader.CurrentTime);
    }

    public ValueTask DisposeAsync()
    {
        _positionTimer.Dispose();
        DisposeCurrent();
        return ValueTask.CompletedTask;
    }

    private void PublishPosition()
    {
        if (IsPlaying)
        {
            PositionChanged?.Invoke(this, Position);
        }
    }

    private void HandlePlaybackStopped(object? sender, StoppedEventArgs eventArgs)
    {
        if (_stopping || eventArgs.Exception is not null || _reader is null)
        {
            return;
        }

        if (_reader.Position >= _reader.Length)
        {
            var handler = PlaybackEnded;
            if (handler is not null)
            {
                _ = handler.Invoke();
            }
        }
    }

    private void DisposeCurrent()
    {
        _stopping = true;
        if (_output is not null)
        {
            _output.PlaybackStopped -= HandlePlaybackStopped;
            _output.Stop();
            _output.Dispose();
            _output = null;
        }

        _reader?.Dispose();
        _reader = null;
        _stopping = false;
    }
}
