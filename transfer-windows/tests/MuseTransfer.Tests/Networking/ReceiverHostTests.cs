using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using MuseTransfer.App.Discovery;
using MuseTransfer.App.Networking;
using MuseTransfer.Core.Files;
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
    public async Task Proposal_waits_for_local_confirmation_without_writing_files()
    {
        var response = await client!.PostAsJsonAsync("/v1/sessions", Manifest("sender-a"));

        Assert.Equal(HttpStatusCode.Accepted, response.StatusCode);
        Assert.Empty(Directory.Exists(Destination) ? Directory.GetFiles(Destination, "*", SearchOption.AllDirectories) : []);
        Assert.True(advertiser.Started);
        Assert.Equal(host!.BoundPort, advertiser.Port);
    }

    [Fact]
    public async Task Rejected_session_forbids_uploading_file_data()
    {
        var proposal = await ProposeAsync();
        sessions!.Reject(proposal.SessionId);

        var upload = ChunkRequest(proposal, "not-issued", "abc"u8.ToArray());
        var response = await client!.SendAsync(upload);

        Assert.Equal(HttpStatusCode.Forbidden, response.StatusCode);
    }

    [Fact]
    public async Task Accepted_session_rejects_invalid_token_and_changed_manifest()
    {
        var proposal = await ProposeAsync();
        var acceptance = sessions!.Accept(proposal.SessionId);

        var invalidToken = await client!.SendAsync(ChunkRequest(proposal, "invalid", "abc"u8.ToArray()));
        var changedManifest = ChunkRequest(proposal with { ManifestDigest = new string('0', 64) }, acceptance.Token, "abc"u8.ToArray());
        var changed = await client.SendAsync(changedManifest);

        Assert.Equal(HttpStatusCode.Unauthorized, invalidToken.StatusCode);
        Assert.Equal(HttpStatusCode.Conflict, changed.StatusCode);
    }

    [Fact]
    public async Task Valid_chunks_commit_only_after_complete_request()
    {
        var proposal = await ProposeAsync();
        var acceptance = sessions!.Accept(proposal.SessionId);
        var upload = await client!.SendAsync(ChunkRequest(proposal, acceptance.Token, "abc"u8.ToArray()));

        Assert.Equal(HttpStatusCode.NoContent, upload.StatusCode);
        Assert.False(File.Exists(Path.Combine(Destination, "song.mp3")));

        using var completeRequest = new HttpRequestMessage(HttpMethod.Post, $"/v1/sessions/{proposal.SessionId}/complete");
        completeRequest.Headers.Add("X-Muse-Session-Token", acceptance.Token);
        completeRequest.Headers.Add("X-Muse-Manifest-Digest", proposal.ManifestDigest);
        var complete = await client.SendAsync(completeRequest);

        Assert.Equal(HttpStatusCode.OK, complete.StatusCode);
        Assert.Equal("abc", await File.ReadAllTextAsync(Path.Combine(Destination, "song.mp3")));
        Assert.Equal(TransferSessionStatus.Completed, sessions.Get(proposal.SessionId).Status);
    }

    public async Task InitializeAsync()
    {
        sessions = new SessionManager(TimeProvider.System, new SessionTokenService());
        host = new ReceiverHost(
            sessions,
            new IncomingFileStore(Path.Combine(testRoot, "incoming")),
            advertiser,
            new ReceiverOptions(Destination, [IPAddress.Loopback], 0, "device-a", "Test PC", Path.Combine(testRoot, "receiver.pfx")));
        await host.StartAsync(CancellationToken.None);
        client = host.CreateLoopbackClientForTests();
    }

    public async Task DisposeAsync()
    {
        client?.Dispose();
        if (host is not null)
        {
            await host.DisposeAsync();
        }
    }

    public void Dispose()
    {
        if (Directory.Exists(testRoot))
        {
            Directory.Delete(testRoot, recursive: true);
        }
    }

    private string Destination => Path.Combine(testRoot, "destination");

    private async Task<SessionProposalResponse> ProposeAsync()
    {
        var response = await client!.PostAsJsonAsync("/v1/sessions", Manifest("sender-a"));
        response.EnsureSuccessStatusCode();
        return (await response.Content.ReadFromJsonAsync<SessionProposalResponse>())!;
    }

    private static HttpRequestMessage ChunkRequest(SessionProposalResponse proposal, string token, byte[] bytes)
    {
        var request = new HttpRequestMessage(
            HttpMethod.Put,
            $"/v1/sessions/{proposal.SessionId}/files/f1/chunks/0");
        request.Headers.Add("X-Muse-Session-Token", token);
        request.Headers.Add("X-Muse-Manifest-Digest", proposal.ManifestDigest);
        request.Content = new ByteArrayContent(bytes);
        request.Content.Headers.TryAddWithoutValidation("Content-Range", "bytes 0-2/3");
        return request;
    }

    private static TransferManifest Manifest(string senderId) => new(
        1,
        senderId,
        [new TransferItem("f1", "song.mp3", 3, Convert.ToHexString(SHA256.HashData("abc"u8.ToArray())).ToLowerInvariant())],
        []);

    private sealed class FakeMdnsAdvertiser : IMdnsAdvertiser
    {
        public bool Started { get; private set; }
        public int Port { get; private set; }
        public Task StartAsync(MdnsService service, CancellationToken cancellationToken)
        {
            Started = true;
            Port = service.Port;
            return Task.CompletedTask;
        }

        public Task StopAsync(CancellationToken cancellationToken)
        {
            Started = false;
            return Task.CompletedTask;
        }
    }
}
