using System.Security.Cryptography;
using MuseTransfer.Core.Files;
using MuseTransfer.Protocol;

namespace MuseTransfer.Tests.Files;

public sealed class IncomingFileStoreTests : IDisposable
{
    private readonly string testRoot = Path.Combine(Path.GetTempPath(), "MuseTransferTests", Guid.NewGuid().ToString("N"));
    private string DestinationRoot => Path.Combine(testRoot, "destination");

    [Theory]
    [InlineData("../escape.mp3")]
    [InlineData("/root/song.mp3")]
    [InlineData("C:\\song.mp3")]
    [InlineData("album/CON/song.mp3")]
    public void SafeRelativePath_rejects_paths_that_can_escape_or_target_devices(string path)
    {
        Assert.Throws<UnsafePathException>(() => SafeRelativePath.Parse(path));
    }

    [Fact]
    public void DuplicateNameResolver_creates_a_numbered_copy_without_overwriting()
    {
        Directory.CreateDirectory(DestinationRoot);
        File.WriteAllText(Path.Combine(DestinationRoot, "song.mp3"), "existing");
        var resolver = new DuplicateNameResolver(DestinationRoot);

        var resolved = resolver.Resolve("song.mp3");

        Assert.Equal("song (2).mp3", resolved);
    }

    [Fact]
    public async Task CommitAsync_streams_chunks_then_atomically_publishes_a_verified_file()
    {
        var bytes = RandomNumberGenerator.GetBytes(2 * 1024 * 1024);
        var item = ItemFor("Album/song.mp3", bytes);
        var store = CreateStore();

        for (var index = 0; index < 8; index++)
        {
            await using var chunk = new MemoryStream(bytes, index * 256 * 1024, 256 * 1024, writable: false);
            await store.WriteChunkAsync("session-a", item, index, index * 256L * 1024, chunk, CancellationToken.None);
        }

        Assert.Empty(Directory.Exists(DestinationRoot) ? Directory.GetFiles(DestinationRoot, "*", SearchOption.AllDirectories) : []);
        var committed = await store.CommitAsync("session-a", item, DestinationRoot, CancellationToken.None);

        Assert.Equal(Path.Combine(DestinationRoot, "Album", "song.mp3"), committed.FullPath);
        Assert.Equal(bytes, await File.ReadAllBytesAsync(committed.FullPath));
    }

    [Fact]
    public async Task CommitAsync_does_not_publish_a_file_when_the_hash_is_wrong()
    {
        var bytes = "damaged"u8.ToArray();
        var item = new TransferItem("f1", "song.mp3", bytes.Length, new string('0', 64));
        var store = CreateStore();
        await using var chunk = new MemoryStream(bytes);
        await store.WriteChunkAsync("session-b", item, 0, 0, chunk, CancellationToken.None);

        await Assert.ThrowsAsync<FileIntegrityException>(() =>
            store.CommitAsync("session-b", item, DestinationRoot, CancellationToken.None));

        Assert.False(File.Exists(Path.Combine(DestinationRoot, "song.mp3")));
    }

    private IncomingFileStore CreateStore() =>
        new(Path.Combine(testRoot, "incoming"));

    private static TransferItem ItemFor(string path, byte[] bytes) =>
        new("f1", path, bytes.Length, Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant());

    public void Dispose()
    {
        if (Directory.Exists(testRoot))
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }
}
