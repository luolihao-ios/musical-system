using FluentAssertions;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Playback;

namespace LocalMusicPlayer.Tests.Playback;

public sealed class PlaybackControllerTests
{
    [Fact]
    public async Task Next_AdvancesAndWrapsInRepeatAllMode()
    {
        var output = new FakeAudioOutput();
        var controller = new PlaybackController(output, new FakePreferences(), new Random(7));
        controller.LoadQueue([CreateTrack("one"), CreateTrack("two")]);

        await controller.PlayAsync();
        await controller.NextAsync();
        controller.Snapshot.CurrentTrack?.Id.Should().Be("two");
        await controller.NextAsync();

        controller.Snapshot.CurrentTrack?.Id.Should().Be("one");
        output.LoadedPaths.Should().HaveCount(3);
    }

    [Fact]
    public async Task NaturalCompletion_ReplaysCurrentTrackInRepeatOneMode()
    {
        var output = new FakeAudioOutput();
        var controller = new PlaybackController(output, new FakePreferences(), new Random(7));
        controller.LoadQueue([CreateTrack("one"), CreateTrack("two")]);
        await controller.SetModeAsync(PlaybackMode.RepeatOne);
        await controller.PlayAsync();

        await output.RaisePlaybackEndedAsync();

        controller.Snapshot.CurrentTrack?.Id.Should().Be("one");
        output.LastSeek.Should().Be(TimeSpan.Zero);
        output.PlayCount.Should().Be(2);
    }

    [Fact]
    public async Task Play_SkipsUnavailableTracks()
    {
        var output = new FakeAudioOutput();
        var controller = new PlaybackController(output, new FakePreferences(), new Random(7));
        controller.LoadQueue([
            CreateTrack("missing") with { IsAvailable = false },
            CreateTrack("available"),
        ]);

        await controller.PlayAsync();

        controller.Snapshot.CurrentTrack?.Id.Should().Be("available");
        output.LoadedPaths.Should().ContainSingle(path => path.EndsWith("available.mp3"));
    }

    [Fact]
    public async Task Preferences_RestoreVolumeModeTrackAndPosition()
    {
        var preferences = new FakePreferences
        {
            Value = new PlaybackPreferences(
                0.4,
                PlaybackMode.Shuffle,
                "two",
                TimeSpan.FromSeconds(42)),
        };
        var output = new FakeAudioOutput { Duration = TimeSpan.FromMinutes(3) };
        var controller = new PlaybackController(output, preferences, new Random(7));
        await controller.InitializeAsync();
        controller.LoadQueue([CreateTrack("one"), CreateTrack("two")]);

        await controller.PlayAsync();

        controller.Snapshot.CurrentTrack?.Id.Should().Be("two");
        controller.Snapshot.Volume.Should().Be(0.4);
        controller.Snapshot.Mode.Should().Be(PlaybackMode.Shuffle);
        output.LastSeek.Should().Be(TimeSpan.FromSeconds(42));
    }

    [Fact]
    public async Task Seek_ClampsToTrackDurationAndPersists()
    {
        var output = new FakeAudioOutput { Duration = TimeSpan.FromSeconds(180) };
        var preferences = new FakePreferences();
        var controller = new PlaybackController(output, preferences, new Random(7));
        controller.LoadQueue([CreateTrack("one")]);
        await controller.PlayAsync();

        await controller.SeekAsync(TimeSpan.FromSeconds(999));

        output.LastSeek.Should().Be(TimeSpan.FromSeconds(180));
        preferences.Saved.LastPosition.Should().Be(TimeSpan.FromSeconds(180));
    }

    private static Track CreateTrack(string id) =>
        new(
            id,
            $@"D:\Music\{id}.mp3",
            id,
            "测试歌手",
            "测试专辑",
            TimeSpan.FromMinutes(3),
            null,
            null,
            false,
            true,
            null);

    private sealed class FakePreferences : IPlaybackPreferences
    {
        public PlaybackPreferences Value { get; init; } = PlaybackPreferences.Default;

        public PlaybackPreferences Saved { get; private set; } = PlaybackPreferences.Default;

        public Task<PlaybackPreferences> LoadAsync(CancellationToken cancellationToken = default) =>
            Task.FromResult(Value);

        public Task SaveAsync(
            PlaybackPreferences preferences,
            CancellationToken cancellationToken = default)
        {
            Saved = preferences;
            return Task.CompletedTask;
        }
    }

    private sealed class FakeAudioOutput : IAudioOutput
    {
        public event Func<Task>? PlaybackEnded;
        public event EventHandler<TimeSpan>? PositionChanged;

        public List<string> LoadedPaths { get; } = [];
        public TimeSpan Position { get; private set; }
        public TimeSpan Duration { get; set; } = TimeSpan.FromMinutes(3);
        public double Volume { get; set; } = 1;
        public bool IsPlaying { get; private set; }
        public TimeSpan? LastSeek { get; private set; }
        public int PlayCount { get; private set; }

        public Task LoadAsync(string path, CancellationToken cancellationToken = default)
        {
            LoadedPaths.Add(path);
            Position = TimeSpan.Zero;
            return Task.CompletedTask;
        }

        public void Play()
        {
            IsPlaying = true;
            PlayCount++;
        }

        public void Pause() => IsPlaying = false;

        public void Seek(TimeSpan position)
        {
            Position = position;
            LastSeek = position;
            PositionChanged?.Invoke(this, position);
        }

        public ValueTask DisposeAsync() => ValueTask.CompletedTask;

        public Task RaisePlaybackEndedAsync() =>
            PlaybackEnded?.Invoke() ?? Task.CompletedTask;
    }
}
