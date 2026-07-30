using System.IO;
using LocalMusicPlayer.Data;

namespace LocalMusicPlayer.Library;

public sealed class LibraryScanner(
    IAudioFileDiscovery discovery,
    ITrackMetadataReader metadataReader,
    ILibraryRepository repository)
{
    public async Task<ScanResult> ScanAsync(
        string root,
        CancellationToken cancellationToken = default)
    {
        var normalizedRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
        await repository.AddScanRootAsync(normalizedRoot, cancellationToken);
        var existing = await repository.GetTracksAsync(cancellationToken);
        var discoveredIds = new HashSet<string>(StringComparer.Ordinal);
        var discoveredCount = 0;
        var indexedCount = 0;
        var failedCount = 0;

        await foreach (var path in discovery.FindAsync(normalizedRoot, cancellationToken))
        {
            discoveredCount++;
            try
            {
                var track = await metadataReader.ReadAsync(path, cancellationToken);
                discoveredIds.Add(track.Id);
                await repository.UpsertTrackAsync(track, cancellationToken);
                indexedCount++;
            }
            catch (Exception exception) when (
                exception is IOException
                or InvalidDataException
                or UnauthorizedAccessException
                or TagLib.CorruptFileException
                or TagLib.UnsupportedFormatException)
            {
                failedCount++;
            }
        }

        var unavailableCount = 0;
        foreach (var track in existing.Where(track => IsInside(normalizedRoot, track.FilePath)))
        {
            if (discoveredIds.Contains(track.Id) || File.Exists(track.FilePath))
            {
                continue;
            }

            await repository.UpsertTrackAsync(
                track with { IsAvailable = false },
                cancellationToken);
            unavailableCount++;
        }

        return new ScanResult(
            discoveredCount,
            indexedCount,
            failedCount,
            unavailableCount);
    }

    private static bool IsInside(string root, string candidate)
    {
        var relative = Path.GetRelativePath(root, candidate);
        return !Path.IsPathRooted(relative)
            && !string.Equals(relative, "..", StringComparison.Ordinal)
            && !relative.StartsWith($"..{Path.DirectorySeparatorChar}", StringComparison.Ordinal);
    }
}
