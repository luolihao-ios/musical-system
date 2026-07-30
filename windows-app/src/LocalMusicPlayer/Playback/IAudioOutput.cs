namespace LocalMusicPlayer.Playback;

public interface IAudioOutput : IAsyncDisposable
{
    event Func<Task>? PlaybackEnded;

    event EventHandler<TimeSpan>? PositionChanged;

    TimeSpan Position { get; }

    TimeSpan Duration { get; }

    double Volume { get; set; }

    bool IsPlaying { get; }

    Task LoadAsync(string path, CancellationToken cancellationToken = default);

    void Play();

    void Pause();

    void Seek(TimeSpan position);
}
