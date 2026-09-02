using System.IO.Compression;
using System.Text.Json;

namespace AiyueTransfer.Core;

public sealed record AiyuePackManifest(string Title, string? Artist, string? Album, string AudioPath, string? LyricsPath, string? CoverPath);

public static class AiyuePack
{
    public static void Create(string audioPath, string outputPath, string? title = null, string? artist = null, string? album = null)
    {
        if (!File.Exists(audioPath)) throw new FileNotFoundException("Audio file was not found.", audioPath);
        var stem = Path.GetFileNameWithoutExtension(audioPath);
        var directory = Path.GetDirectoryName(audioPath) ?? ".";
        var lyrics = FindSibling(directory, stem, ".lrc", ".txt");
        var cover = FindSibling(directory, stem, ".jpg", ".jpeg", ".png") ?? FindSibling(directory, "cover", ".jpg", ".jpeg", ".png");
        var manifest = new AiyuePackManifest(title ?? stem, artist, album, "audio/" + Path.GetFileName(audioPath), lyrics is null ? null : "lyrics/" + Path.GetFileName(lyrics), cover is null ? null : "cover/" + Path.GetFileName(cover));
        using var archive = ZipFile.Open(outputPath, ZipArchiveMode.Create);
        archive.CreateEntryFromFile(audioPath, manifest.AudioPath, CompressionLevel.Fastest);
        if (lyrics is not null) archive.CreateEntryFromFile(lyrics, manifest.LyricsPath!, CompressionLevel.Fastest);
        if (cover is not null) archive.CreateEntryFromFile(cover, manifest.CoverPath!, CompressionLevel.Fastest);
        var entry = archive.CreateEntry("manifest.json");
        using var writer = new StreamWriter(entry.Open());
        writer.Write(JsonSerializer.Serialize(manifest, new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, WriteIndented = true }));
    }

    private static string? FindSibling(string directory, string stem, params string[] extensions) =>
        extensions.Select(extension => Path.Combine(directory, stem + extension)).FirstOrDefault(File.Exists);
}
