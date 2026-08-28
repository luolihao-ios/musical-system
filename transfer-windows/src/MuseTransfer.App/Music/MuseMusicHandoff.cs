using System.Diagnostics;
using System.Security.Cryptography;
using System.Text.Json;

namespace MuseTransfer.App.Music;

public sealed record MusicHandoffItem(string RelativePath, string Sha256, string Kind);
public sealed record MusicHandoffDocument(int Version, string HandoffId, DateTimeOffset CreatedAt, IReadOnlyList<MusicHandoffItem> Items);

public sealed class MuseMusicHandoff(string handoffRoot)
{
    private static readonly HashSet<string> Supported = new(StringComparer.OrdinalIgnoreCase) { ".mp3", ".m4a", ".aac", ".flac", ".wav", ".aif", ".aiff", ".lrc" };

    public async Task<bool> CreateAndLaunchAsync(string sourceRoot, CancellationToken cancellationToken = default)
    {
        if (!Directory.Exists(sourceRoot)) return false;
        var files = Directory.EnumerateFiles(sourceRoot, "*", SearchOption.AllDirectories).Where(path => Supported.Contains(Path.GetExtension(path))).ToArray();
        if (!files.Any(path => !string.Equals(Path.GetExtension(path), ".lrc", StringComparison.OrdinalIgnoreCase))) return false;
        var id = Guid.NewGuid().ToString("N");
        var root = Path.Combine(handoffRoot, id); Directory.CreateDirectory(root);
        var items = new List<MusicHandoffItem>();
        foreach (var source in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            var relative = Path.GetRelativePath(sourceRoot, source).Replace('\\', '/');
            if (Path.IsPathRooted(relative) || relative.Split('/').Contains("..")) throw new InvalidDataException("Unsafe handoff path.");
            var target = Path.GetFullPath(Path.Combine(root, relative.Replace('/', Path.DirectorySeparatorChar)));
            if (!target.StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("Handoff path escaped its root.");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!); File.Copy(source, target, overwrite: false);
            await using var input = File.OpenRead(target);
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant();
            items.Add(new MusicHandoffItem(relative, hash, string.Equals(Path.GetExtension(source), ".lrc", StringComparison.OrdinalIgnoreCase) ? "lyrics" : "audio"));
        }
        var manifest = Path.Combine(root, "music-handoff-v1.json");
        await File.WriteAllBytesAsync(manifest, JsonSerializer.SerializeToUtf8Bytes(new MusicHandoffDocument(1, id, DateTimeOffset.UtcNow, items), new JsonSerializerOptions(JsonSerializerDefaults.Web)), cancellationToken);
        try { Process.Start(new ProcessStartInfo($"musemusic://import?manifest={Uri.EscapeDataString(manifest)}") { UseShellExecute = true }); return true; }
        catch { return false; }
    }
}
