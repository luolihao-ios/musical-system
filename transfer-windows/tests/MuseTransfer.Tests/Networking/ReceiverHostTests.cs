using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using MuseTransfer.App.Discovery;
using MuseTransfer.App.Networking;
using MuseTransfer.Core.Files;
using MuseTransfer.Core.Music;
using MuseTransfer.Core.Sessions;
using MuseTransfer.Protocol;

namespace MuseTransfer.Tests.Networking;

public sealed class ReceiverHostTests : IAsyncLifetime, IDisposable
{
    private readonly string testRoot = Path.Combine(Path.GetTempPath(), "MuseTransferReceiverTests", Guid.NewGuid().ToString("N"));
    private readonly FakeMdnsAdvertiser advertiser = new();
    private ReceiverHost? host;
    private SessionManager? sessions;
    private HttpClient? client;

    [Fact]
    public async Task Encrypted_proposal_waits_for_confirmation_without_writing_files()
    {
        var proposal = await ProposeAsync();
        Assert.Equal("pending", proposal.Details.Status);
        Assert.Empty(Directory.Exists(Destination) ? Directory.GetFiles(Destination, "*", SearchOption.AllDirectories) : []);
        Assert.True(advertiser.Started);
        Assert.Equal(host!.BoundPort, advertiser.Port);
        Assert.Equal(Convert.ToBase64String(host.ReceiverPublicKey), advertiser.PublicKey);
    }

    [Fact]
    public async Task Plaintext_manifest_is_rejected()
    {
        var response = await client!.PostAsJsonAsync("/v2/sessions", Manifest("sender-a"));
        Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
    }

    [Fact]
    public async Task Rejected_session_forbids_encrypted_file_data()
    {
        var proposal = await ProposeAsync();
        sessions!.Reject(proposal.Details.SessionId);
        var response = await client!.SendAsync(ChunkRequest(proposal, "not-issued", "abc"u8.ToArray()));
        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Accepted_session_rejects_invalid_token_and_changed_manifest()
    {
        var proposal = await ProposeAsync();
        var acceptance = sessions!.Accept(proposal.Details.SessionId);
        var invalid = await client!.SendAsync(ChunkRequest(proposal, "invalid", "abc"u8.ToArray()));
        var changed = proposal with { Details = proposal.Details with { ManifestDigest = new string('0', 64) } };
        var changedResponse = await client.SendAsync(ChunkRequest(changed, acceptance.Token, "abc"u8.ToArray()));
        Assert.Equal(HttpStatusCode.Unauthorized, invalid.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, changedResponse.StatusCode);
    }

    [Fact]
    public async Task Valid_encrypted_chunks_commit_only_after_complete()
    {
        var proposal = await ProposeAsync();
        var acceptance = sessions!.Accept(proposal.Details.SessionId);
        var upload = await client!.SendAsync(ChunkRequest(proposal, acceptance.Token, "abc"u8.ToArray()));
        Assert.Equal(HttpStatusCode.NoContent, upload.StatusCode);
        Assert.False(File.Exists(Path.Combine(Destination, "song.mp3")));
        using var complete = new HttpRequestMessage(HttpMethod.Post, $"/v2/sessions/{proposal.Details.SessionId}/complete");
        complete.Headers.Add("X-Muse-Session-Token", acceptance.Token);
        complete.Headers.Add("X-Muse-Manifest-Digest", proposal.Details.ManifestDigest);
        var result = await client.SendAsync(complete);
        Assert.Equal(HttpStatusCode.OK, result.StatusCode);
        Assert.Equal("abc", await File.ReadAllTextAsync(Path.Combine(Destination, "song.mp3")));
    }

    [Fact]
    public async Task TransferClient_completes_an_encrypted_round_trip()
    {
        Directory.CreateDirectory(testRoot);
        var source = Path.Combine(testRoot, "source.txt");
        await File.WriteAllTextAsync(source, "round trip");
        var proposed = new TaskCompletionSource<TransferSession>(TaskCreationOptions.RunContinuationsAsynchronously);
        sessions!.SessionProposed += session => proposed.TrySetResult(session);
        var send = new TransferClient().SendAsync(
            new NearbyDevice("receiver", "Receiver", client!.BaseAddress!, host!.ReceiverPublicKey),
            [new SelectedFile("f1", source, "nested/source.txt", new FileInfo(source).Length)],
            new Progress<TransferProgress>(), CancellationToken.None);
        var session = await proposed.Task.WaitAsync(TimeSpan.FromSeconds(5));
        sessions.Accept(session.Id);
        await send.WaitAsync(TimeSpan.FromSeconds(10));
        Assert.Equal("round trip", await File.ReadAllTextAsync(Path.Combine(Destination, "nested", "source.txt")));
    }

    public async Task InitializeAsync()
    {
        sessions = new SessionManager(TimeProvider.System, new SessionTokenService());
        host = new ReceiverHost(sessions, new IncomingFileStore(Path.Combine(testRoot, "incoming")), advertiser,
            new ReceiverOptions(Destination, [IPAddress.Loopback], 0, "device-a", "Test PC"));
        await host.StartAsync(CancellationToken.None);
        client = host.CreateLoopbackClientForTests();
    }

    public async Task DisposeAsync() { client?.Dispose(); if (host is not null) await host.DisposeAsync(); }
    public void Dispose() { if (Directory.Exists(testRoot)) Directory.Delete(testRoot, recursive: true); }
    private string Destination => Path.Combine(testRoot, "destination");

    private async Task<TestProposal> ProposeAsync()
    {
        using var sender = P256KeyPair.Generate();
        var manifest = Manifest("sender-a");
        var key = TransferCrypto.DeriveSessionKey(sender, host!.ReceiverPublicKey, host.ReceiverPublicKey, sender.PublicKeyX963);
        var encrypted = TransferCrypto.Encrypt(key, JsonSerializer.SerializeToUtf8Bytes(manifest, JsonOptions), "proposal|v2"u8.ToArray());
        var response = await client!.PostAsJsonAsync("/v2/sessions", new EncryptedProposalRequest(sender.PublicKeyX963, encrypted));
        response.EnsureSuccessStatusCode();
        var wire = (await response.Content.ReadFromJsonAsync<SessionProposalEnvelopeResponse>())!;
        var details = JsonSerializer.Deserialize<SessionProposalResponse>(TransferCrypto.Decrypt(key, wire.Envelope, Encoding.UTF8.GetBytes($"proposal-response|{wire.SessionId}")), JsonOptions)!;
        return new TestProposal(details, key);
    }

    private static HttpRequestMessage ChunkRequest(TestProposal proposal, string token, byte[] bytes)
    {
        var details = proposal.Details;
        var aad = Encoding.UTF8.GetBytes($"{details.SessionId}|f1|0|0|3|{details.ManifestDigest}");
        var body = TransferCrypto.PackEnvelope(TransferCrypto.Encrypt(proposal.Key, bytes, aad));
        var request = new HttpRequestMessage(HttpMethod.Put, $"/v2/sessions/{details.SessionId}/files/f1/chunks/0");
        request.Headers.Add("X-Muse-Session-Token", token);
        request.Headers.Add("X-Muse-Manifest-Digest", details.ManifestDigest);
        request.Content = new ByteArrayContent(body);
        request.Content.Headers.TryAddWithoutValidation("Content-Range", "bytes 0-2/3");
        return request;
    }

    private static TransferManifest Manifest(string senderId) => new(2, senderId,
        [new TransferItem("f1", "song.mp3", 3, Convert.ToHexString(SHA256.HashData("abc"u8.ToArray())).ToLowerInvariant())], []);
    private sealed record TestProposal(SessionProposalResponse Details, byte[] Key);
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private sealed class FakeMdnsAdvertiser : IMdnsAdvertiser
    {
        public bool Started { get; private set; }
        public int Port { get; private set; }
        public string? PublicKey { get; private set; }
        public Task StartAsync(MdnsService service, CancellationToken cancellationToken) { Started = true; Port = service.Port; PublicKey = service.PublicKey; return Task.CompletedTask; }
        public Task StopAsync(CancellationToken cancellationToken) { Started = false; return Task.CompletedTask; }
    }
}
