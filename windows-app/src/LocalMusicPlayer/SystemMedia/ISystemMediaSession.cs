namespace LocalMusicPlayer.SystemMedia;

public interface ISystemMediaSession
{
    event Func<Task>? PlayRequested;

    event Func<Task>? PauseRequested;

    event Func<Task>? NextRequested;

    event Func<Task>? PreviousRequested;

    event Func<TimeSpan, Task>? SeekRequested;

    void Update(SystemMediaState state);
}
