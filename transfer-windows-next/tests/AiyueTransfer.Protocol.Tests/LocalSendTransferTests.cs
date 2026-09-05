using AiyueTransfer.App;
using AiyueTransfer.Protocol;
using System.Net.Http.Json;
using System.Security.Cryptography;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class LocalSendTransferTests
{
    [Fact]
    public async Task Sender_PrepareRequest_HasContentLengthForSimpleHttpReceivers()
    {
        var root = Path.Combine(Path.GetTempPath(), "aiyue-transfer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var source = Path.Combine(root, "hello.txt");
            await File.WriteAllTextAsync(source, "payload");
            var handler = new PrepareRequestCaptureHandler();
            var sender = new LocalSendSender(new HttpClient(handler));

            await Assert.ThrowsAsync<InvalidOperationException>(() => sender.SendAsync(
                new Uri("http://receiver"),
                new DeviceInfo("发送端", "2.0", "Windows", "desktop", "sender", 54218, "http"),
                [source]));

            Assert.Equal(TransferRoutes.PrepareUpload, handler.Path);
            Assert.True(handler.ContentLength is > 0, "准备请求必须发送明确的 Content-Length，供 iOS 接收端读取正文。");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Sender_TransfersFileAfterReceiverAccepts()
    {
        var root = Path.Combine(Path.GetTempPath(), "aiyue-transfer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var receiverInfo = new DeviceInfo("接收端", "2.0", "Windows", "desktop", "receiver", 55317, "http");
            await using var receiver = new LocalSendReceiver(receiverInfo, Path.Combine(root, "received"));
            receiver.RequestReceived += request => receiver.Decide(request.SessionId, true);
            await receiver.StartAsync();
            var source = Path.Combine(root, "hello.txt"); await File.WriteAllTextAsync(source, "爱乐互传");
            await new LocalSendSender(new HttpClient()).SendAsync(new Uri("http://127.0.0.1:55317"), new DeviceInfo("发送端", "2.0", "Windows", "desktop", "sender", 55318, "http"), [source]);
            var received = Directory.EnumerateFiles(Path.Combine(root, "received"), "hello.txt", SearchOption.AllDirectories).Single();
            Assert.Equal("爱乐互传", await File.ReadAllTextAsync(received));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Sender_TransfersNestedFolderWithRelativePaths()
    {
        var root = Path.Combine(Path.GetTempPath(), "aiyue-transfer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var sourceFolder = Path.Combine(root, "Album");
            var source = Path.Combine(sourceFolder, "Disc 1", "song.txt");
            Directory.CreateDirectory(Path.GetDirectoryName(source)!);
            await File.WriteAllTextAsync(source, "nested music");
            var receiverInfo = new DeviceInfo("接收端", "2.0", "Windows", "desktop", "receiver", 55319, "http");
            await using var receiver = new LocalSendReceiver(receiverInfo, Path.Combine(root, "received"));
            receiver.RequestReceived += request => receiver.Decide(request.SessionId, true);
            await receiver.StartAsync();

            await new LocalSendSender(new HttpClient()).SendFolderAsync(
                new Uri("http://127.0.0.1:55319"),
                new DeviceInfo("发送端", "2.0", "Windows", "desktop", "sender", 55320, "http"),
                sourceFolder);

            var received = Directory.EnumerateFiles(Path.Combine(root, "received"), "song.txt", SearchOption.AllDirectories).Single();
            Assert.Equal(Path.Combine("Album", "Disc 1", "song.txt"), Path.GetRelativePath(Path.Combine(root, "received"), received));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Receiver_RejectsTraversalBeforeRequestingUserConfirmation()
    {
        var root = Path.Combine(Path.GetTempPath(), "aiyue-transfer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var receiverInfo = new DeviceInfo("接收端", "2.0", "Windows", "desktop", "receiver", 55321, "http");
            await using var receiver = new LocalSendReceiver(receiverInfo, Path.Combine(root, "received"));
            var requested = false;
            receiver.RequestReceived += _ => requested = true;
            await receiver.StartAsync();
            var request = new PrepareUploadRequest(new DeviceInfo("发送端", "2.0", "Windows", "desktop", "sender", 55322, "http"), new Dictionary<string, FileMetadata>
            {
                ["file"] = new("file", "../outside.txt", 1, "text/plain")
            });

            using var response = await new HttpClient().PostAsJsonAsync(new Uri("http://127.0.0.1:55321" + TransferRoutes.PrepareUpload), request, ProtocolJson.Options);

            Assert.Equal(System.Net.HttpStatusCode.BadRequest, response.StatusCode);
            Assert.False(requested);
            Assert.False(File.Exists(Path.Combine(root, "outside.txt")));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    [Fact]
    public async Task Receiver_RejectsChecksumMismatchWithoutCreatingFinalFile()
    {
        var root = Path.Combine(Path.GetTempPath(), "aiyue-transfer-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var receiverInfo = new DeviceInfo("接收端", "2.0", "Windows", "desktop", "receiver", 55323, "http");
            await using var receiver = new LocalSendReceiver(receiverInfo, Path.Combine(root, "received"));
            receiver.RequestReceived += request => receiver.Decide(request.SessionId, true);
            await receiver.StartAsync();
            var expectedHash = Convert.ToHexString(SHA256.HashData("expected"u8)).ToLowerInvariant();
            var request = new PrepareUploadRequest(new DeviceInfo("发送端", "2.0", "Windows", "desktop", "sender", 55324, "http"), new Dictionary<string, FileMetadata>
            {
                ["file"] = new("file", "music/song.txt", 3, "text/plain", expectedHash)
            });
            using var client = new HttpClient();
            using var prepare = await client.PostAsJsonAsync(new Uri("http://127.0.0.1:55323" + TransferRoutes.PrepareUpload), request, ProtocolJson.Options);
            var accepted = await prepare.Content.ReadFromJsonAsync<PrepareUploadResponse>(ProtocolJson.Options);
            Assert.NotNull(accepted);

            using var response = await client.PostAsync(new Uri($"http://127.0.0.1:55323{TransferRoutes.Upload}?sessionId={accepted!.SessionId}&fileId=file&token={accepted.Files["file"]}"), new StringContent("bad"));

            Assert.Equal(System.Net.HttpStatusCode.UnprocessableEntity, response.StatusCode);
            Assert.Empty(Directory.EnumerateFiles(Path.Combine(root, "received"), "*", SearchOption.AllDirectories));
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private sealed class PrepareRequestCaptureHandler : HttpMessageHandler
    {
        public string? Path { get; private set; }
        public long? ContentLength { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Path = request.RequestUri?.AbsolutePath;
            ContentLength = request.Content?.Headers.ContentLength;
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.Forbidden));
        }
    }
}
