using LocalMusicPlayer.Data;
using LocalMusicPlayer.Library;
using LocalMusicPlayer.Playback;
using LocalMusicPlayer.SystemMedia;

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
        WindowsSystemMediaSession systemMediaSession,
        SystemMediaBridge systemMediaBridge)
    {
        Paths = paths;
        Library = library;
        Scanner = scanner;
        Playback = playback;
        _systemMediaSession = systemMediaSession;
        _systemMediaBridge = systemMediaBridge;
    }

    public AppPaths Paths { get; }

    public ILibraryRepository Library { get; }

    public LibraryScanner Scanner { get; }

    public PlaybackController Playback { get; }

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
        return new AppServices(
            paths,
            repository,
            scanner,
            playback,
            systemMediaSession,
            systemMediaBridge);
    }

    public async ValueTask DisposeAsync()
    {
        _systemMediaBridge.Dispose();
        _systemMediaSession.Dispose();
        await Playback.DisposeAsync();
    }
}
