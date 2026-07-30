using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Library;

public interface ITrackMetadataReader
{
    Task<Track> ReadAsync(string path, CancellationToken cancellationToken = default);
}
