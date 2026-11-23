using System.Security.Cryptography;
using System.Text.Json;

namespace AiyueTransfer.Core;

public sealed record MusicHandoffItem(string RelativePath, string Sha256, string Kind);
public sealed record MusicHandoffDocument(int Version, string HandoffId, DateTimeOffset CreatedAt, IReadOnlyList<MusicHandoffItem> Items);

public static class MusicHandoff
{
    private static readonly HashSet<string> AudioExtensions = new(StringComparer.OrdinalIgnoreCase) { ".mp3", ".m4a", ".aac", ".flac", ".wav", ".aif", ".aiff" };
    public static async Task<string?> CreateAsync(string sourceRoot, string handoffRoot, CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(sourceRoot)) return null;
        var files = Directory.EnumerateFiles(sourceRoot, "*", SearchOption.AllDirectories).Where(path => AudioExtensions.Contains(Path.GetExtension(path)) || string.Equals(Path.GetExtension(path), ".lrc", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (!files.Any(path => AudioExtensions.Contains(Path.GetExtension(path)))) return null;
        var id = Guid.NewGuid().ToString("N"); var root = Path.Combine(handoffRoot, id); Directory.CreateDirectory(root); var items = new List<MusicHandoffItem>();
        foreach (var source in files)
        {
            var relative = Path.GetRelativePath(sourceRoot, source).Replace('\\', '/'); if (relative.Contains("..", StringComparison.Ordinal) || Path.IsPathRooted(relative)) throw new InvalidDataException("音乐导入路径无效。");
            var target = Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)); Directory.CreateDirectory(Path.GetDirectoryName(target)!); File.Copy(source, target);
            await using var input = File.OpenRead(target); var hash = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant();
            items.Add(new MusicHandoffItem(relative, hash, string.Equals(Path.GetExtension(source), ".lrc", StringComparison.OrdinalIgnoreCase) ? "lyrics" : "audio"));
        }
        await File.WriteAllBytesAsync(Path.Combine(root, "music-handoff-v1.json"), JsonSerializer.SerializeToUtf8Bytes(new MusicHandoffDocument(1, id, DateTimeOffset.UtcNow, items), new JsonSerializerOptions(JsonSerializerDefaults.Web)), cancellationToken);
        return id;
    }
}
