using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MuseTransfer.Core.Music;
using MuseTransfer.Protocol;

namespace MuseTransfer.App.Networking;

public sealed record NearbyDevice(string Id, string Name, Uri BaseAddress, byte[] ReceiverPublicKey);
public sealed record TransferProgress(long TransferredBytes, long TotalBytes, string CurrentFileName, double BytesPerSecond, TimeSpan? Remaining);

public interface ITransferClient
{
    Task SendAsync(NearbyDevice device, IReadOnlyList<SelectedFile> files, IProgress<TransferProgress> progress, CancellationToken cancellationToken);
}

public sealed class TransferClient : ITransferClient
{
    private const int ChunkSize = 1024 * 1024;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public async Task SendAsync(NearbyDevice device, IReadOnlyList<SelectedFile> files, IProgress<TransferProgress> progress, CancellationToken cancellationToken)
    {
        if (device.ReceiverPublicKey.Length != 65) throw new InvalidOperationException("The receiver public key is required.");
        using var client = new HttpClient { BaseAddress = device.BaseAddress };
        using var senderKey = P256KeyPair.Generate();
        var key = TransferCrypto.DeriveSessionKey(senderKey, device.ReceiverPublicKey, device.ReceiverPublicKey, senderKey.PublicKeyX963);
        var manifest = await BuildManifestAsync(files, cancellationToken);
        var manifestEnvelope = TransferCrypto.Encrypt(key, JsonSerializer.SerializeToUtf8Bytes(manifest, JsonOptions), "proposal|v2"u8.ToArray());
        var proposalResponse = await client.PostAsJsonAsync("/v2/sessions", new EncryptedProposalRequest(senderKey.PublicKeyX963, manifestEnvelope), cancellationToken);
        proposalResponse.EnsureSuccessStatusCode();
        var wire = await proposalResponse.Content.ReadFromJsonAsync<SessionProposalEnvelopeResponse>(cancellationToken)
            ?? throw new InvalidDataException("Receiver returned an empty proposal.");
        var proposal = JsonSerializer.Deserialize<SessionProposalResponse>(
            TransferCrypto.Decrypt(key, wire.Envelope, Encoding.UTF8.GetBytes($"proposal-response|{wire.SessionId}")), JsonOptions)
            ?? throw new InvalidDataException("Receiver returned invalid proposal details.");
        var decision = await WaitForAcceptanceAsync(client, proposal, key, cancellationToken);
        var token = decision.Token ?? throw new InvalidDataException("Accepted session did not include an upload token.");

        var total = files.Sum(file => file.Size);
        long transferred = 0;
        var stopwatch = Stopwatch.StartNew();
        foreach (var file in files)
        {
            await using var input = new FileStream(file.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read, ChunkSize, FileOptions.Asynchronous | FileOptions.SequentialScan);
            var buffer = new byte[ChunkSize];
            var chunkIndex = 0;
            int read;
            while ((read = await input.ReadAsync(buffer.AsMemory(), cancellationToken)) > 0)
            {
                if (decision.VerifiedChunks.TryGetValue(file.Id, out var verified) && verified.Contains(chunkIndex)) { transferred += read; chunkIndex++; continue; }
                var offset = input.Position - read;
                var aad = Encoding.UTF8.GetBytes($"{proposal.SessionId}|{file.Id}|{chunkIndex}|{offset}|{file.Size}|{proposal.ManifestDigest}");
                var packed = TransferCrypto.PackEnvelope(TransferCrypto.Encrypt(key, buffer[..read], aad));
                using var request = new HttpRequestMessage(HttpMethod.Put, $"/v2/sessions/{proposal.SessionId}/files/{file.Id}/chunks/{chunkIndex}");
                request.Headers.Add("X-Muse-Session-Token", token);
                request.Headers.Add("X-Muse-Manifest-Digest", proposal.ManifestDigest);
                request.Content = new ByteArrayContent(packed);
                request.Content.Headers.ContentRange = new ContentRangeHeaderValue(offset, input.Position - 1, file.Size);
                using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                response.EnsureSuccessStatusCode();
                transferred += read; chunkIndex++;
                Report(progress, transferred, total, file.RelativePath, stopwatch.Elapsed);
            }
        }
        using var complete = new HttpRequestMessage(HttpMethod.Post, $"/v2/sessions/{proposal.SessionId}/complete");
        complete.Headers.Add("X-Muse-Session-Token", token);
        complete.Headers.Add("X-Muse-Manifest-Digest", proposal.ManifestDigest);
        using var completion = await client.SendAsync(complete, cancellationToken);
        completion.EnsureSuccessStatusCode();
        CryptographicOperations.ZeroMemory(key);
    }

    private static async Task<TransferManifest> BuildManifestAsync(IReadOnlyList<SelectedFile> files, CancellationToken cancellationToken)
    {
        var items = new List<TransferItem>(files.Count);
        foreach (var file in files)
        {
            await using var input = new FileStream(file.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
            items.Add(new TransferItem(file.Id, file.RelativePath, file.Size, Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant()));
        }
        var groups = MusicGrouper.Group(files).Select(group => new MusicGroup(group.Id, group.Files.Select(file => file.Id).ToArray())).ToArray();
        return new TransferManifest(2, Environment.MachineName, items, groups);
    }

    private static async Task<SessionStatusResponse> WaitForAcceptanceAsync(HttpClient client, SessionProposalResponse proposal, byte[] key, CancellationToken cancellationToken)
    {
        while (true)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"/v2/sessions/{proposal.SessionId}");
            request.Headers.Add("X-Muse-Proposal-Key", proposal.ProposalKey);
            using var response = await client.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();
            var wire = await response.Content.ReadFromJsonAsync<EncryptedStatusResponse>(cancellationToken) ?? throw new InvalidDataException("Receiver returned empty status.");
            var status = JsonSerializer.Deserialize<SessionStatusResponse>(TransferCrypto.Decrypt(key, wire.Envelope, Encoding.UTF8.GetBytes($"status|{proposal.SessionId}")), JsonOptions)
                ?? throw new InvalidDataException("Receiver returned invalid status.");
            if (status.Status is "accepted" or "transferring") return status;
            if (status.Status is "rejected" or "cancelled" or "failed") throw new TransferRejectedException(status.Status);
            await Task.Delay(250, cancellationToken);
        }
    }

    private static void Report(IProgress<TransferProgress> progress, long transferred, long total, string file, TimeSpan elapsed)
    {
        var speed = elapsed.TotalSeconds <= 0 ? 0 : transferred / elapsed.TotalSeconds;
        TimeSpan? remaining = speed <= 0 ? null : TimeSpan.FromSeconds((total - transferred) / speed);
        progress.Report(new TransferProgress(transferred, total, file, speed, remaining));
    }
}

public sealed class TransferRejectedException(string status) : InvalidOperationException($"Receiver ended the session with status '{status}'.");
