using System.IO.Compression;
using System.Text.Json;

namespace AiyueTransfer.Core;

public sealed record AiyuePackManifest(string Title, string? Artist, string? Album, string AudioPath, string? LyricsPath, string? CoverPath);

public static class AiyuePack
{
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true };
    public static void Create(string audioPath, string outputPath, string? title = null, string? artist = null, string? album = null, IEnumerable<string>? companions = null)
    {
        if (!File.Exists(audioPath)) throw new FileNotFoundException("Audio file was not found.", audioPath);
        if (!string.Equals(Path.GetExtension(audioPath), ".mp3", StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("音乐包需要 MP3 文件。");
        var stem = Path.GetFileNameWithoutExtension(audioPath);
        var directory = Path.GetDirectoryName(audioPath) ?? ".";
        var candidates = (companions ?? Directory.EnumerateFiles(directory)).Where(File.Exists).ToArray();
        string? Match(string name, params string[] extensions) => candidates.FirstOrDefault(path => string.Equals(Path.GetFileNameWithoutExtension(path), name, StringComparison.OrdinalIgnoreCase) && extensions.Contains(Path.GetExtension(path), StringComparer.OrdinalIgnoreCase));
        var lyrics = Match(stem, ".lrc");
        var cover = Match(stem, ".jpg", ".jpeg", ".png", ".webp") ?? Match("cover", ".jpg", ".jpeg", ".png", ".webp");
        var manifest = new AiyuePackManifest(title ?? stem, artist, album, "audio/" + Path.GetFileName(audioPath), lyrics is null ? null : "lyrics/" + Path.GetFileName(lyrics), cover is null ? null : "cover/" + Path.GetFileName(cover));
        using var archive = ZipFile.Open(outputPath, ZipArchiveMode.Create);
        archive.CreateEntryFromFile(audioPath, manifest.AudioPath, CompressionLevel.Fastest);
        if (lyrics is not null) archive.CreateEntryFromFile(lyrics, manifest.LyricsPath!, CompressionLevel.Fastest);
        if (cover is not null) archive.CreateEntryFromFile(cover, manifest.CoverPath!, CompressionLevel.Fastest);
        var entry = archive.CreateEntry("manifest.json");
        using var writer = new StreamWriter(entry.Open());
        writer.Write(JsonSerializer.Serialize(manifest, JsonOptions));
    }

    public static AiyuePackManifest Extract(string packagePath, string destinationRoot)
    {
        Directory.CreateDirectory(destinationRoot);
        using var archive = ZipFile.OpenRead(packagePath);
        var manifestEntry = archive.GetEntry("manifest.json") ?? throw new InvalidDataException("音乐包缺少 manifest.json。");
        using var reader = new StreamReader(manifestEntry.Open());
        var manifest = JsonSerializer.Deserialize<AiyuePackManifest>(reader.ReadToEnd(), JsonOptions) ?? throw new InvalidDataException("音乐包 manifest 无效。");
        var allowed = new[] { manifest.AudioPath, manifest.LyricsPath, manifest.CoverPath }.Where(path => !string.IsNullOrWhiteSpace(path)).Cast<string>().ToHashSet(StringComparer.Ordinal);
        if (!allowed.Contains(manifest.AudioPath) || !manifest.AudioPath.StartsWith("audio/", StringComparison.Ordinal)) throw new InvalidDataException("音乐包音频路径无效。");
        foreach (var path in allowed)
        {
            if (path.Contains("..", StringComparison.Ordinal) || Path.IsPathRooted(path)) throw new InvalidDataException("音乐包包含不安全路径。");
            var entry = archive.GetEntry(path) ?? throw new InvalidDataException($"音乐包缺少 {path}。");
            var target = Path.GetFullPath(Path.Combine(destinationRoot, path));
            var root = Path.GetFullPath(destinationRoot) + Path.DirectorySeparatorChar;
            if (!target.StartsWith(root, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("音乐包路径越界。");
            Directory.CreateDirectory(Path.GetDirectoryName(target)!);
            using var input = entry.Open(); using var output = File.Create(target); input.CopyTo(output);
        }
        return manifest;
    }

    private static string? FindSibling(string directory, string stem, params string[] extensions) =>
        extensions.Select(extension => Path.Combine(directory, stem + extension)).FirstOrDefault(File.Exists);
}
