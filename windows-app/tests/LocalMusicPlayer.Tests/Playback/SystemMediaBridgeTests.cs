using FluentAssertions;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Playback;
using LocalMusicPlayer.SystemMedia;

namespace LocalMusicPlayer.Tests.Playback;

public sealed class SystemMediaBridgeTests
{
    [Fact]
    public void Snapshot_UpdatesSystemMediaMetadataAndTimeline()
    {
        var playback = new FakePlaybackCommands
        {
            Snapshot = CreateSnapshot(isPlaying: true),
        };
        var session = new FakeSystemMediaSession();

        using var bridge = new SystemMediaBridge(playback, session);

        session.State.Should().Be(new SystemMediaState(
            "夜航星",
            "测试歌手",
            "测试专辑",
            @"D:\Music\cover.jpg",
            true,
            TimeSpan.FromSeconds(23),
            TimeSpan.FromMinutes(4)));
    }

    [Fact]
    public async Task MediaCommands_AreForwardedToPlaybackController()
    {
        var playback = new FakePlaybackCommands
        {
            Snapshot = CreateSnapshot(isPlaying: false),
        };
        var session = new FakeSystemMediaSession();
        using var bridge = new SystemMediaBridge(playback, session);

        await session.RequestPlayAsync();
        await session.RequestPauseAsync();
        await session.RequestNextAsync();
        await session.RequestPreviousAsync();
        await session.RequestSeekAsync(TimeSpan.FromSeconds(67));

        playback.PlayCount.Should().Be(1);
        playback.PauseCount.Should().Be(1);
        playback.NextCount.Should().Be(1);
        playback.PreviousCount.Should().Be(1);
        playback.LastSeek.Should().Be(TimeSpan.FromSeconds(67));
    }

    private static PlaybackSnapshot CreateSnapshot(bool isPlaying)
    {
        var track = new Track(
            "track-1",
            @"D:\Music\night.mp3",
            "夜航星",
            "测试歌手",
            "测试专辑",
            TimeSpan.FromMinutes(4),
            @"D:\Music\cover.jpg",
            null,
            false,
            true,
            null);
        return new PlaybackSnapshot(
            [track],
            0,
            isPlaying,
            TimeSpan.FromSeconds(23),
            TimeSpan.FromMinutes(4),
            0.8,
            PlaybackMode.RepeatAll);
    }

    private sealed class FakePlaybackCommands : IPlaybackCommands
    {
        public event EventHandler<PlaybackSnapshot>? SnapshotChanged
        {
            add { }
            remove { }
        }

        public required PlaybackSnapshot Snapshot { get; init; }
        public int PlayCount { get; private set; }
        public int PauseCount { get; private set; }
        public int NextCount { get; private set; }
        public int PreviousCount { get; private set; }
        public TimeSpan? LastSeek { get; private set; }

        public Task PlayAsync(CancellationToken cancellationToken = default)
        {
            PlayCount++;
            return Task.CompletedTask;
        }

        public Task PauseAsync(CancellationToken cancellationToken = default)
        {
            PauseCount++;
            return Task.CompletedTask;
        }

        public Task NextAsync(CancellationToken cancellationToken = default)
        {
            NextCount++;
            return Task.CompletedTask;
        }

        public Task PreviousAsync(CancellationToken cancellationToken = default)
        {
            PreviousCount++;
            return Task.CompletedTask;
        }

        public Task SeekAsync(
            TimeSpan position,
            CancellationToken cancellationToken = default)
        {
            LastSeek = position;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeSystemMediaSession : ISystemMediaSession
    {
        public event Func<Task>? PlayRequested;
        public event Func<Task>? PauseRequested;
        public event Func<Task>? NextRequested;
        public event Func<Task>? PreviousRequested;
        public event Func<TimeSpan, Task>? SeekRequested;

        public SystemMediaState State { get; private set; } = SystemMediaState.Empty;

        public void Update(SystemMediaState state) => State = state;

        public Task RequestPlayAsync() => PlayRequested?.Invoke() ?? Task.CompletedTask;

        public Task RequestPauseAsync() => PauseRequested?.Invoke() ?? Task.CompletedTask;

        public Task RequestNextAsync() => NextRequested?.Invoke() ?? Task.CompletedTask;

        public Task RequestPreviousAsync() => PreviousRequested?.Invoke() ?? Task.CompletedTask;

        public Task RequestSeekAsync(TimeSpan position) =>
            SeekRequested?.Invoke(position) ?? Task.CompletedTask;
    }
}
