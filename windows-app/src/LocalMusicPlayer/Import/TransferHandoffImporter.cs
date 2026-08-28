using System.Security.Cryptography;
using System.Text.Json;
using LocalMusicPlayer.Library;

namespace LocalMusicPlayer.Import;

public sealed record TransferHandoffItem(string RelativePath, string Sha256, string Kind);
public sealed record TransferHandoffDocument(int Version, string HandoffId, DateTimeOffset CreatedAt, IReadOnlyList<TransferHandoffItem> Items);

public sealed class TransferHandoffImporter(LibraryScanner scanner, string allowedRoot, string processedRoot)
{
    public async Task<bool> ImportAsync(string argument, CancellationToken cancellationToken = default)
    {
        if (!Uri.TryCreate(argument, UriKind.Absolute, out var uri) || !string.Equals(uri.Scheme, "musemusic", StringComparison.OrdinalIgnoreCase)) return false;
        var manifestPath = uri.Query.TrimStart('?').Split('&', StringSplitOptions.RemoveEmptyEntries)
            .Select(value => value.Split('=', 2)).Where(parts => parts.Length == 2 && parts[0] == "manifest")
            .Select(parts => Uri.UnescapeDataString(parts[1])).FirstOrDefault();
        if (string.IsNullOrWhiteSpace(manifestPath)) return false;
        var manifest = Path.GetFullPath(manifestPath); var normalizedRoot = Path.GetFullPath(allowedRoot) + Path.DirectorySeparatorChar;
        if (!manifest.StartsWith(normalizedRoot, StringComparison.OrdinalIgnoreCase) || !File.Exists(manifest)) return false;
        var document = JsonSerializer.Deserialize<TransferHandoffDocument>(await File.ReadAllBytesAsync(manifest, cancellationToken), new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (document is null || document.Version != 1 || document.Items.Count == 0) return false;
        Directory.CreateDirectory(processedRoot); var marker = Path.Combine(processedRoot, document.HandoffId + ".done"); if (File.Exists(marker)) return true;
        var handoffDirectory = Path.GetDirectoryName(manifest)!; var prefix = Path.GetFullPath(handoffDirectory) + Path.DirectorySeparatorChar;
        foreach (var item in document.Items)
        {
            if (Path.IsPathRooted(item.RelativePath) || item.RelativePath.Split('/', '\\').Contains("..")) return false;
            var file = Path.GetFullPath(Path.Combine(handoffDirectory, item.RelativePath.Replace('/', Path.DirectorySeparatorChar)));
            if (!file.StartsWith(prefix, StringComparison.OrdinalIgnoreCase) || !File.Exists(file)) return false;
            await using var input = File.OpenRead(file); var hash = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant();
            if (!CryptographicOperations.FixedTimeEquals(Convert.FromHexString(hash), Convert.FromHexString(item.Sha256))) return false;
        }
        await scanner.ScanAsync(handoffDirectory, cancellationToken); await File.WriteAllTextAsync(marker, DateTimeOffset.UtcNow.ToString("O"), cancellationToken); return true;
    }
}
