using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using MuseTransfer.Core.Music;
using MuseTransfer.Protocol;

namespace MuseTransfer.App.Networking;

public sealed record NearbyDevice(string Id, string Name, Uri BaseAddress, string CertificateSha256);
public sealed record TransferProgress(long TransferredBytes, long TotalBytes, string CurrentFileName, double BytesPerSecond, TimeSpan? Remaining);
internal sealed record SessionStatusResponse(string Status, string? Token, Dictionary<string, int[]> VerifiedChunks);

public interface ITransferClient
{
    Task SendAsync(NearbyDevice device, IReadOnlyList<SelectedFile> files, IProgress<TransferProgress> progress, CancellationToken cancellationToken);
}

public sealed class TransferClient : ITransferClient
{
    private const int ChunkSize = 1024 * 1024;

    public async Task SendAsync(NearbyDevice device, IReadOnlyList<SelectedFile> files, IProgress<TransferProgress> progress, CancellationToken cancellationToken)
    {
        using var client = CreateClient(device);
        var manifest = await BuildManifestAsync(files, cancellationToken);
        var proposalResponse = await client.PostAsJsonAsync("/v1/sessions", manifest, cancellationToken);
        proposalResponse.EnsureSuccessStatusCode();
        var proposal = await proposalResponse.Content.ReadFromJsonAsync<SessionProposalResponse>(cancellationToken)
            ?? throw new InvalidDataException("Receiver returned an empty proposal.");
        var decision = await WaitForAcceptanceAsync(client, proposal, cancellationToken);
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
            while ((read = await input.ReadAsync(buffer.AsMemory(0, buffer.Length), cancellationToken)) > 0)
            {
                if (decision.VerifiedChunks.TryGetValue(file.Id, out var verified) && verified.Contains(chunkIndex))
                {
                    transferred += read;
                    chunkIndex++;
                    continue;
                }
                using var request = new HttpRequestMessage(HttpMethod.Put, $"/v1/sessions/{proposal.SessionId}/files/{file.Id}/chunks/{chunkIndex}");
                request.Headers.Add("X-Muse-Session-Token", token);
                request.Headers.Add("X-Muse-Manifest-Digest", proposal.ManifestDigest);
                request.Content = new ByteArrayContent(buffer, 0, read);
                request.Content.Headers.ContentRange = new ContentRangeHeaderValue(input.Position - read, input.Position - 1, file.Size);
                using var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                response.EnsureSuccessStatusCode();
                transferred += read;
                chunkIndex++;
                Report(progress, transferred, total, file.RelativePath, stopwatch.Elapsed);
            }
        }

        using var complete = new HttpRequestMessage(HttpMethod.Post, $"/v1/sessions/{proposal.SessionId}/complete");
        complete.Headers.Add("X-Muse-Session-Token", token);
        complete.Headers.Add("X-Muse-Manifest-Digest", proposal.ManifestDigest);
        using var completion = await client.SendAsync(complete, cancellationToken);
        completion.EnsureSuccessStatusCode();
    }

    private static async Task<TransferManifest> BuildManifestAsync(IReadOnlyList<SelectedFile> files, CancellationToken cancellationToken)
    {
        var items = new List<TransferItem>(files.Count);
        foreach (var file in files)
        {
            await using var input = new FileStream(file.FullPath, FileMode.Open, FileAccess.Read, FileShare.Read, 64 * 1024, FileOptions.Asynchronous | FileOptions.SequentialScan);
            var hash = Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant();
            items.Add(new TransferItem(file.Id, file.RelativePath, file.Size, hash));
        }
        var groups = MusicGrouper.Group(files).Select(group => new MusicGroup(group.Id, group.Files.Select(file => file.Id).ToArray())).ToArray();
        return new TransferManifest(1, Environment.MachineName, items, groups);
    }

    private static async Task<SessionStatusResponse> WaitForAcceptanceAsync(HttpClient client, SessionProposalResponse proposal, CancellationToken cancellationToken)
    {
        while (true)
        {
            using var request = new HttpRequestMessage(HttpMethod.Get, $"/v1/sessions/{proposal.SessionId}");
            request.Headers.Add("X-Muse-Proposal-Key", proposal.ProposalKey);
            using var response = await client.SendAsync(request, cancellationToken);
            response.EnsureSuccessStatusCode();
            var status = await response.Content.ReadFromJsonAsync<SessionStatusResponse>(cancellationToken)
                ?? throw new InvalidDataException("Receiver returned an empty session status.");
            if (status.Status == "accepted" || status.Status == "transferring") return status;
            if (status.Status is "rejected" or "cancelled" or "failed") throw new TransferRejectedException(status.Status);
            await Task.Delay(250, cancellationToken);
        }
    }

    private static HttpClient CreateClient(NearbyDevice device)
    {
        var handler = new HttpClientHandler
        {
            ServerCertificateCustomValidationCallback = (_, certificate, _, _) =>
            {
                if (certificate is null) return false;
                var fingerprint = Convert.ToHexString(SHA256.HashData(certificate.GetRawCertData())).ToLowerInvariant();
                return string.IsNullOrWhiteSpace(device.CertificateSha256)
                    || fingerprint.Equals(device.CertificateSha256, StringComparison.OrdinalIgnoreCase);
            }
        };
        return new HttpClient(handler) { BaseAddress = device.BaseAddress };
    }

    private static void Report(IProgress<TransferProgress> progress, long transferred, long total, string file, TimeSpan elapsed)
    {
        var speed = elapsed.TotalSeconds <= 0 ? 0 : transferred / elapsed.TotalSeconds;
        TimeSpan? remaining = speed <= 0 ? null : TimeSpan.FromSeconds((total - transferred) / speed);
        progress.Report(new TransferProgress(transferred, total, file, speed, remaining));
    }
}

public sealed class TransferRejectedException(string status) : InvalidOperationException($"Receiver ended the session with status '{status}'.");
