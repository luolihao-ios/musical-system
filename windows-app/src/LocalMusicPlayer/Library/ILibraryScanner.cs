namespace LocalMusicPlayer.Library;

public interface ILibraryScanner
{
    Task<ScanResult> ScanAsync(
        string root,
        CancellationToken cancellationToken = default);
}
