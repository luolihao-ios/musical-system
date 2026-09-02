using AiyueTransfer.App;
using AiyueTransfer.Protocol;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class LocalSendTransferTests
{
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
}
