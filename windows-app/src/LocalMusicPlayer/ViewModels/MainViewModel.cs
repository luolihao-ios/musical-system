using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using LocalMusicPlayer.Playback;

namespace LocalMusicPlayer.ViewModels;

public sealed class MainViewModel : ObservableObject, IDisposable
{
    private readonly IPlaybackCommands _playback;
    private object _currentPage;
    private string _currentTitle = "本地音乐";
    private PlaybackSnapshot _playbackSnapshot;

    public MainViewModel(
        LibraryViewModel library,
        PlaylistsViewModel playlists,
        IPlaybackCommands playback)
    {
        Library = library;
        Playlists = playlists;
        _playback = playback;
        _currentPage = library;
        _playbackSnapshot = playback.Snapshot;
        ShowLibraryCommand = new RelayCommand(ShowLibrary);
        ShowPlaylistsCommand = new RelayCommand(ShowPlaylists);
        TogglePlaybackCommand = new AsyncRelayCommand(TogglePlaybackAsync);
        NextCommand = new AsyncRelayCommand(() => _playback.NextAsync());
        PreviousCommand = new AsyncRelayCommand(() => _playback.PreviousAsync());
        _playback.SnapshotChanged += HandleSnapshotChanged;
    }

    public LibraryViewModel Library { get; }

    public PlaylistsViewModel Playlists { get; }

    public IRelayCommand ShowLibraryCommand { get; }

    public IRelayCommand ShowPlaylistsCommand { get; }

    public IAsyncRelayCommand TogglePlaybackCommand { get; }

    public IAsyncRelayCommand NextCommand { get; }

    public IAsyncRelayCommand PreviousCommand { get; }

    public object CurrentPage
    {
        get => _currentPage;
        private set => SetProperty(ref _currentPage, value);
    }

    public string CurrentTitle
    {
        get => _currentTitle;
        private set => SetProperty(ref _currentTitle, value);
    }

    public PlaybackSnapshot PlaybackSnapshot
    {
        get => _playbackSnapshot;
        private set => SetProperty(ref _playbackSnapshot, value);
    }

    public async Task InitializeAsync(
        CancellationToken cancellationToken = default)
    {
        await Library.InitializeAsync(cancellationToken);
        await Playlists.InitializeAsync(cancellationToken);
    }

    public void Dispose() =>
        _playback.SnapshotChanged -= HandleSnapshotChanged;

    private void ShowLibrary()
    {
        CurrentPage = Library;
        CurrentTitle = "本地音乐";
    }

    private void ShowPlaylists()
    {
        CurrentPage = Playlists;
        CurrentTitle = "我的歌单";
    }

    private Task TogglePlaybackAsync() =>
        PlaybackSnapshot.IsPlaying
            ? _playback.PauseAsync()
            : _playback.PlayAsync();

    private void HandleSnapshotChanged(
        object? sender,
        PlaybackSnapshot snapshot)
    {
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher is not null && !dispatcher.CheckAccess())
        {
            dispatcher.Invoke(() => PlaybackSnapshot = snapshot);
            return;
        }

        PlaybackSnapshot = snapshot;
    }
}
