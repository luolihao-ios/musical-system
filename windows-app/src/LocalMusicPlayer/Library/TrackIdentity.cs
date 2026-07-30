using System.Buffers.Binary;
using System.IO;
using System.Security.Cryptography;

namespace LocalMusicPlayer.Library;

public static class TrackIdentity
{
    private const int SampleSize = 64 * 1024;

    public static async Task<string> CreateAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        await using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read,
            SampleSize,
            FileOptions.Asynchronous | FileOptions.SequentialScan);
        using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        Span<byte> lengthBytes = stackalloc byte[sizeof(long)];
        BinaryPrimitives.WriteInt64LittleEndian(lengthBytes, stream.Length);
        hash.AppendData(lengthBytes);

        var buffer = new byte[SampleSize];
        var firstRead = await stream.ReadAsync(buffer, cancellationToken);
        hash.AppendData(buffer.AsSpan(0, firstRead));

        if (stream.Length > SampleSize)
        {
            stream.Seek(Math.Max(0, stream.Length - SampleSize), SeekOrigin.Begin);
            var lastRead = await stream.ReadAsync(buffer, cancellationToken);
            hash.AppendData(buffer.AsSpan(0, lastRead));
        }

        return Convert.ToHexString(hash.GetHashAndReset()).ToLowerInvariant();
    }
}
