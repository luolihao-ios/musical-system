using System.IO;
using System.Runtime.CompilerServices;

namespace LocalMusicPlayer.Library;

public sealed class AudioFileDiscovery : IAudioFileDiscovery
{
    private static readonly HashSet<string> SupportedExtensions =
        new(StringComparer.OrdinalIgnoreCase)
        {
            ".mp3",
            ".m4a",
            ".aac",
            ".flac",
            ".wav",
            ".ogg",
        };

    public async IAsyncEnumerable<string> FindAsync(
        string root,
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(root);
        var pending = new Stack<string>();
        pending.Push(Path.GetFullPath(root));

        while (pending.TryPop(out var directory))
        {
            cancellationToken.ThrowIfCancellationRequested();
            string[] files;
            string[] children;
            try
            {
                files = Directory.GetFiles(directory);
                children = Directory.GetDirectories(directory);
            }
            catch (UnauthorizedAccessException)
            {
                continue;
            }
            catch (IOException)
            {
                continue;
            }

            foreach (var child in children)
            {
                pending.Push(child);
            }

            foreach (var path in files)
            {
                if (SupportedExtensions.Contains(Path.GetExtension(path)))
                {
                    yield return path;
                }
            }

            await Task.Yield();
        }
    }
}
