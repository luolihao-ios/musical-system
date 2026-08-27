using System.Security.Cryptography;
using MuseTransfer.Protocol;

namespace MuseTransfer.Core.Files;

public sealed class FileIntegrityException(string message) : IOException(message);

public sealed record ChunkWriteResult(int ChunkIndex, long BytesWritten);

public sealed record CommittedFile(string FullPath, long Size, string Sha256);

public sealed class IncomingFileStore(string temporaryRoot)
{
    public async Task<ChunkWriteResult> WriteChunkAsync(
        string sessionId,
        TransferItem item,
        int chunkIndex,
        long offset,
        Stream content,
        CancellationToken cancellationToken)
    {
        ArgumentOutOfRangeException.ThrowIfNegative(chunkIndex);
        ArgumentOutOfRangeException.ThrowIfNegative(offset);
        SafeRelativePath.Parse(item.RelativePath);

        var temporaryPath = GetTemporaryPath(sessionId, item.Id);
        Directory.CreateDirectory(Path.GetDirectoryName(temporaryPath)!);
        await using var target = new FileStream(
            temporaryPath,
            FileMode.OpenOrCreate,
            FileAccess.Write,
            FileShare.None,
            64 * 1024,
            FileOptions.Asynchronous | FileOptions.RandomAccess);
        target.Position = offset;
        var before = target.Position;
        await content.CopyToAsync(target, 64 * 1024, cancellationToken);
        await target.FlushAsync(cancellationToken);
        return new ChunkWriteResult(chunkIndex, target.Position - before);
    }

    public async Task<CommittedFile> CommitAsync(
        string sessionId,
        TransferItem item,
        string destinationRoot,
        CancellationToken cancellationToken)
    {
        var temporaryPath = GetTemporaryPath(sessionId, item.Id);
        var info = new FileInfo(temporaryPath);
        if (!info.Exists || info.Length != item.Size)
        {
            throw new FileIntegrityException("The received file size does not match its manifest.");
        }

        string actualHash;
        await using (var input = new FileStream(
            temporaryPath, FileMode.Open, FileAccess.Read, FileShare.Read,
            64 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan))
        {
            actualHash = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant();
        }

        if (!CryptographicOperations.FixedTimeEquals(
            Convert.FromHexString(actualHash), Convert.FromHexString(item.Sha256)))
        {
            throw new FileIntegrityException("The received file hash does not match its manifest.");
        }

        Directory.CreateDirectory(destinationRoot);
        var relativePath = new DuplicateNameResolver(destinationRoot).Resolve(item.RelativePath);
        var finalPath = SafeRelativePath.Parse(relativePath).ResolveBelow(destinationRoot);
        Directory.CreateDirectory(Path.GetDirectoryName(finalPath)!);
        File.Move(temporaryPath, finalPath, overwrite: false);
        return new CommittedFile(finalPath, item.Size, actualHash);
    }

    private string GetTemporaryPath(string sessionId, string itemId)
    {
        var safeSession = SafeIdentifier(sessionId);
        var safeItem = SafeIdentifier(itemId);
        return Path.Combine(temporaryRoot, safeSession, $"{safeItem}.part");
    }

    private static string SafeIdentifier(string value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Any(character => !char.IsAsciiLetterOrDigit(character) && character is not '-' and not '_'))
        {
            throw new ArgumentException("Identifiers may contain only ASCII letters, digits, '-' and '_'.", nameof(value));
        }

        return value;
    }
}
