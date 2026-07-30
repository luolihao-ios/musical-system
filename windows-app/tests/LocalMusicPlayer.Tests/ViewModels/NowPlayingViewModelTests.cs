using FluentAssertions;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Lyrics;
using LocalMusicPlayer.Playback;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Tests.ViewModels;

public sealed class NowPlayingViewModelTests
{
    [Fact]
    public void Snapshot_CrossingTimestampUpdatesCurrentLyric()
    {
        var playback = new FakePlaybackCommands(CreateSnapshot(
            TimeSpan.FromSeconds(5),
            isPlaying: true,
            lyricsPath: @"D:\Music\night.lrc"));
        var lyrics = new FakeLyricsSource(
            "[00:01.00]第一句\n[00:10.00]第二句");
        var viewModel = new NowPlayingViewModel(playback, lyrics);

        playback.Publish(CreateSnapshot(
            TimeSpan.FromSeconds(12),
            isPlaying: true,
            lyricsPath: @"D:\Music\night.lrc"));

        viewModel.CurrentLyricIndex.Should().Be(1);
        viewModel.CurrentLyricText.Should().Be("第二句");
    }

    [Theory]
    [InlineData(null)]
    [InlineData("not an lrc file")]
    public void MissingOrMalformedLyrics_ShowsRecordFallback(string? source)
    {
        var playback = new FakePlaybackCommands(CreateSnapshot(
            TimeSpan.Zero,
            isPlaying: false,
            lyricsPath: source is null ? null : @"D:\Music\bad.lrc"));
        var viewModel = new NowPlayingViewModel(
            playback,
            new FakeLyricsSource(source));

        viewModel.HasLyrics.Should().BeFalse();
        viewModel.LyricLines.Should().BeEmpty();
    }

    [Fact]
    public async Task Seek_ForwardsToPlaybackController()
    {
        var playback = new FakePlaybackCommands(CreateSnapshot(
            TimeSpan.Zero,
            isPlaying: false,
            lyricsPath: null));
        var viewModel = new NowPlayingViewModel(
            playback,
            new FakeLyricsSource(null));

        await viewModel.SeekAsync(TimeSpan.FromSeconds(74));

        playback.LastSeek.Should().Be(TimeSpan.FromSeconds(74));
    }

    [Fact]
    public void RecordRotation_FollowsPlayingState()
    {
        var playback = new FakePlaybackCommands(CreateSnapshot(
            TimeSpan.Zero,
            isPlaying: true,
            lyricsPath: null));
        var viewModel = new NowPlayingViewModel(
            playback,
            new FakeLyricsSource(null));
        viewModel.IsRecordRotating.Should().BeTrue();

        playback.Publish(CreateSnapshot(
            TimeSpan.FromSeconds(3),
            isPlaying: false,
            lyricsPath: null));

        viewModel.IsRecordRotating.Should().BeFalse();
    }

    private static PlaybackSnapshot CreateSnapshot(
        TimeSpan position,
        bool isPlaying,
        string? lyricsPath)
    {
        var track = new Track(
            "night",
            @"D:\Music\night.mp3",
            "夜航星",
            "测试歌手",
            "测试专辑",
            TimeSpan.FromMinutes(4),
            null,
            lyricsPath,
            false,
            true,
            null);
        return new PlaybackSnapshot(
            [track],
            0,
            isPlaying,
            position,
            TimeSpan.FromMinutes(4),
            0.8,
            PlaybackMode.RepeatAll);
    }

    private sealed class FakeLyricsSource(string? source) : ILyricsSource
    {
        public string? Read(string path) => source;
    }

    private sealed class FakePlaybackCommands(PlaybackSnapshot snapshot)
        : IPlaybackCommands
    {
        public event EventHandler<PlaybackSnapshot>? SnapshotChanged;

        public PlaybackSnapshot Snapshot { get; private set; } = snapshot;

        public TimeSpan? LastSeek { get; private set; }

        public void LoadQueue(IReadOnlyList<Track> tracks, int startIndex = 0)
        {
        }

        public Task PlayAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task PauseAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task NextAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task PreviousAsync(CancellationToken cancellationToken = default) =>
            Task.CompletedTask;

        public Task SeekAsync(
            TimeSpan position,
            CancellationToken cancellationToken = default)
        {
            LastSeek = position;
            return Task.CompletedTask;
        }

        public void Publish(PlaybackSnapshot value)
        {
            Snapshot = value;
            SnapshotChanged?.Invoke(this, value);
        }
    }
}
