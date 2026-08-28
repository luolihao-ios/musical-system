using MuseTransfer.Core.Music;

namespace MuseTransfer.Tests.Music;

public sealed class MusicGrouperTests : IDisposable
{
    private readonly string root = Path.Combine(Path.GetTempPath(), "MuseTransferMusicTests", Guid.NewGuid().ToString("N"));

    [Fact]
    public void Group_links_audio_lyrics_and_named_cover_without_claiming_unrelated_images()
    {
        var files = CreateFiles(
            ("Album/song.mp3", "audio"),
            ("Album/song.lrc", "lyrics"),
            ("Album/cover.jpg", "cover"),
            ("Album/photo.png", "photo"));

        var result = MusicGrouper.Group(files);

        var group = Assert.Single(result);
        Assert.Equal(["Album/song.mp3", "Album/song.lrc", "Album/cover.jpg"], group.Files.Select(file => file.RelativePath));
        Assert.DoesNotContain(group.Files, file => file.RelativePath.EndsWith("photo.png"));
    }

    [Fact]
    public void Group_uses_m3u8_references_without_changing_relative_paths()
    {
        var files = CreateFiles(
            ("Mix/first.mp3", "one"),
            ("Mix/second.flac", "two"),
            ("Mix/list.m3u8", "#EXTM3U\nfirst.mp3\nsecond.flac\n"));

        var group = Assert.Single(MusicGrouper.Group(files));

        Assert.Equal(["Mix/first.mp3", "Mix/second.flac", "Mix/list.m3u8"], group.Files.Select(file => file.RelativePath));
    }

    private IReadOnlyList<SelectedFile> CreateFiles(params (string RelativePath, string Content)[] values)
    {
        return values.Select((value, index) =>
        {
            var fullPath = Path.Combine(root, value.RelativePath.Replace('/', Path.DirectorySeparatorChar));
            Directory.CreateDirectory(Path.GetDirectoryName(fullPath)!);
            File.WriteAllText(fullPath, value.Content);
            return new SelectedFile($"f{index + 1}", fullPath, value.RelativePath, new FileInfo(fullPath).Length);
        }).ToArray();
    }

    public void Dispose()
    {
        if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
    }
}
