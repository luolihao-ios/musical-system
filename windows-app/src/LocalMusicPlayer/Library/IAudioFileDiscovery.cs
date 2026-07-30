using System.Runtime.CompilerServices;

namespace LocalMusicPlayer.Library;

public interface IAudioFileDiscovery
{
    IAsyncEnumerable<string> FindAsync(
        string root,
        CancellationToken cancellationToken = default);
}
