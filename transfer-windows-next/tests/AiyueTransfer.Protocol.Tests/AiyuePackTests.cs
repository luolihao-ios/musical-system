using AiyueTransfer.Core;
using System.IO.Compression;
using System.Text.Json;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class AiyuePackTests
{
    [Fact]
    public void Create_IncludesAudioLyricsAndCover()
    {
        var root = Path.Combine(Path.GetTempPath(), "aiyue-pack-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "song.mp3"), "audio"); File.WriteAllText(Path.Combine(root, "song.lrc"), "lyrics"); File.WriteAllBytes(Path.Combine(root, "song.jpg"), [1, 2, 3]);
            var output = Path.Combine(root, "song.aiyuepack"); AiyuePack.Create(Path.Combine(root, "song.mp3"), output);
            using var zip = ZipFile.OpenRead(output);
            Assert.NotNull(zip.GetEntry("audio/song.mp3")); Assert.NotNull(zip.GetEntry("lyrics/song.lrc")); Assert.NotNull(zip.GetEntry("cover/song.jpg"));
            using var reader = new StreamReader(zip.GetEntry("manifest.json")!.Open());
            var manifest = JsonSerializer.Deserialize<AiyuePackManifest>(reader.ReadToEnd(), new JsonSerializerOptions { PropertyNamingPolicy = JsonNamingPolicy.CamelCase });
            Assert.Equal("song", manifest!.Title);
            var extract = Path.Combine(root, "extract");
            var unpacked = AiyuePack.Extract(output, extract);
            Assert.Equal("audio/song.mp3", unpacked.AudioPath);
            Assert.True(File.Exists(Path.Combine(extract, "audio", "song.mp3")));
        }
        finally { Directory.Delete(root, true); }
    }
}
