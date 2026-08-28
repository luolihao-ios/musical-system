namespace MuseTransfer.Core.Music;

public sealed record SelectedFile(string Id, string FullPath, string RelativePath, long Size);
public sealed record MusicFileGroup(string Id, IReadOnlyList<SelectedFile> Files);

public static class MusicGrouper
{
    private static readonly HashSet<string> AudioExtensions = new(StringComparer.OrdinalIgnoreCase)
    { ".mp3", ".m4a", ".aac", ".flac", ".wav", ".ogg", ".aiff" };
    private static readonly HashSet<string> CoverNames = new(StringComparer.OrdinalIgnoreCase)
    { "cover", "folder", "front", "album" };

    public static IReadOnlyList<MusicFileGroup> Group(IReadOnlyList<SelectedFile> files)
    {
        var groups = new List<MusicFileGroup>();
        var claimed = new HashSet<string>(StringComparer.Ordinal);
        foreach (var playlist in files.Where(file => Path.GetExtension(file.RelativePath).Equals(".m3u8", StringComparison.OrdinalIgnoreCase)))
        {
            var directory = Path.GetDirectoryName(playlist.RelativePath)?.Replace('\\', '/') ?? string.Empty;
            var references = File.ReadLines(playlist.FullPath)
                .Select(line => line.Trim())
                .Where(line => line.Length > 0 && !line.StartsWith('#'))
                .Select(line => Normalize(Path.Combine(directory, line)))
                .ToHashSet(StringComparer.OrdinalIgnoreCase);
            var members = files.Where(file => references.Contains(Normalize(file.RelativePath))).Append(playlist).DistinctBy(file => file.Id).ToArray();
            if (members.Length > 1)
            {
                groups.Add(new MusicFileGroup($"music-{groups.Count + 1}", members));
                claimed.UnionWith(members.Select(file => file.Id));
            }
        }

        foreach (var audio in files.Where(file => AudioExtensions.Contains(Path.GetExtension(file.RelativePath)) && !claimed.Contains(file.Id)))
        {
            var directory = Path.GetDirectoryName(audio.RelativePath) ?? string.Empty;
            var stem = Path.GetFileNameWithoutExtension(audio.RelativePath);
            var members = new List<SelectedFile> { audio };
            members.AddRange(files.Where(file =>
                !claimed.Contains(file.Id)
                && string.Equals(Path.GetDirectoryName(file.RelativePath) ?? string.Empty, directory, StringComparison.OrdinalIgnoreCase)
                && (Path.GetExtension(file.RelativePath).Equals(".lrc", StringComparison.OrdinalIgnoreCase)
                    && Path.GetFileNameWithoutExtension(file.RelativePath).Equals(stem, StringComparison.OrdinalIgnoreCase)
                    || IsNamedCover(file.RelativePath))));
            groups.Add(new MusicFileGroup($"music-{groups.Count + 1}", members));
            claimed.UnionWith(members.Select(file => file.Id));
        }
        return groups;
    }

    private static bool IsNamedCover(string path) =>
        Path.GetExtension(path) is ".jpg" or ".jpeg" or ".png" or ".webp"
        && CoverNames.Contains(Path.GetFileNameWithoutExtension(path));

    private static string Normalize(string path) => path.Replace('\\', '/').TrimStart('/');
}
