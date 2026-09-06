using AiyueTransfer.Core;
using System.IO.Compression;
using System.Text.Json;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class AiyuePackTests
{
    [Fact]
    public void Mp3OnlyAndExplicitMixedCaseCompanionsAreSupported()
    {
        var root = Path.Combine(Path.GetTempPath(), Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try
        {
            var audio = Path.Combine(root, "Song.MP3"); File.WriteAllText(audio, "audio");
            var solo = Path.Combine(root, "solo.aiyuepack"); AiyuePack.Create(audio, solo);
            var manifest = AiyuePack.Extract(solo, Path.Combine(root, "solo"));
            Assert.Null(manifest.LyricsPath); Assert.Null(manifest.CoverPath);
            var lyrics = Path.Combine(root, "song.LRC"); File.WriteAllText(lyrics, "lyrics");
            var cover = Path.Combine(root, "SONG.PNG"); File.WriteAllText(cover, "cover");
            var full = Path.Combine(root, "full.aiyuepack"); AiyuePack.Create(audio, full, companions: [lyrics, cover]);
            manifest = AiyuePack.Extract(full, Path.Combine(root, "full"));
            Assert.NotNull(manifest.LyricsPath); Assert.NotNull(manifest.CoverPath);
            Assert.Throws<InvalidDataException>(() => AiyuePack.Create(lyrics, Path.Combine(root, "bad.aiyuepack")));
        }
        finally { Directory.Delete(root, true); }
    }
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
