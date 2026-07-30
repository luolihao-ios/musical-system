using LocalMusicPlayer.Data;
using LocalMusicPlayer.Library;
using LocalMusicPlayer.Playback;
using LocalMusicPlayer.SystemMedia;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Composition;

public sealed class AppServices : IAsyncDisposable
{
    private readonly WindowsSystemMediaSession _systemMediaSession;
    private readonly SystemMediaBridge _systemMediaBridge;

    private AppServices(
        AppPaths paths,
        ILibraryRepository library,
        LibraryScanner scanner,
        PlaybackController playback,
        MainViewModel main,
        WindowsSystemMediaSession systemMediaSession,
        SystemMediaBridge systemMediaBridge)
    {
        Paths = paths;
        Library = library;
        Scanner = scanner;
        Playback = playback;
        Main = main;
        _systemMediaSession = systemMediaSession;
        _systemMediaBridge = systemMediaBridge;
    }

    public AppPaths Paths { get; }

    public ILibraryRepository Library { get; }

    public LibraryScanner Scanner { get; }

    public PlaybackController Playback { get; }

    public MainViewModel Main { get; }

    public static async Task<AppServices> CreateAsync(
        CancellationToken cancellationToken = default)
    {
        var paths = AppPaths.ForCurrentUser();
        var database = new LibraryDatabase(paths.DatabasePath);
        await database.InitializeAsync(cancellationToken);

        var repository = new LibraryRepository(database);
        var scanner = new LibraryScanner(
            new AudioFileDiscovery(),
            new TrackMetadataReader(paths.CoverCacheDirectory),
            repository);
        var playback = new PlaybackController(
            new NAudioOutput(),
            new RepositoryPlaybackPreferences(repository));
        await playback.InitializeAsync(cancellationToken);
        playback.LoadQueue(await repository.GetTracksAsync(cancellationToken));

        var systemMediaSession = new WindowsSystemMediaSession();
        var systemMediaBridge = new SystemMediaBridge(
            playback,
            systemMediaSession);
        var main = new MainViewModel(
            new LibraryViewModel(repository, scanner, playback),
            new PlaylistsViewModel(repository),
            playback);
        await main.InitializeAsync(cancellationToken);
        return new AppServices(
            paths,
            repository,
            scanner,
            playback,
            main,
            systemMediaSession,
            systemMediaBridge);
    }

    public async ValueTask DisposeAsync()
    {
        Main.Dispose();
        _systemMediaBridge.Dispose();
        _systemMediaSession.Dispose();
        await Playback.DisposeAsync();
    }
}
