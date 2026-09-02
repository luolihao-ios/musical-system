using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;

namespace AiyueTransfer.Protocol;

public sealed record DiscoveryAnnouncement(DeviceInfo Info)
{
    public static DiscoveryAnnouncement Parse(ReadOnlySpan<byte> payload)
    {
        var value = JsonSerializer.Deserialize<DeviceInfo>(payload, ProtocolJson.Options)
            ?? throw new JsonException("Discovery announcement is empty.");
        if (value.Port is < 1 or > 65535 || value.Version != "2.0") throw new JsonException("Unsupported discovery announcement.");
        return new DiscoveryAnnouncement(value);
    }

    public byte[] ToBytes() => JsonSerializer.SerializeToUtf8Bytes(Info, ProtocolJson.Options);
}

public sealed class LocalSendDiscovery : IAsyncDisposable
{
    public const int DefaultPort = 53317;
    public static readonly IPAddress MulticastAddress = IPAddress.Parse("224.0.0.167");
    private readonly UdpClient client;
    private readonly CancellationTokenSource stop = new();
    private Task? receiveLoop;

    public LocalSendDiscovery(int port = DefaultPort)
    {
        client = new UdpClient(AddressFamily.InterNetwork) { EnableBroadcast = true };
        client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
        client.Client.Bind(new IPEndPoint(IPAddress.Any, port));
        client.JoinMulticastGroup(MulticastAddress);
    }

    public event Action<IPEndPoint, DiscoveryAnnouncement>? AnnouncementReceived;

    public Task StartAsync(DeviceInfo local, CancellationToken cancellationToken = default)
    {
        cancellationToken.Register(() => stop.Cancel());
        receiveLoop = ReceiveAsync(stop.Token);
        return AnnounceAsync(local, cancellationToken);
    }

    public Task AnnounceAsync(DeviceInfo local, CancellationToken cancellationToken = default) =>
        client.SendAsync(new DiscoveryAnnouncement(local).ToBytes(), new IPEndPoint(MulticastAddress, local.Port), cancellationToken).AsTask();

    private async Task ReceiveAsync(CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            try
            {
                var result = await client.ReceiveAsync(cancellationToken);
                AnnouncementReceived?.Invoke(result.RemoteEndPoint, DiscoveryAnnouncement.Parse(result.Buffer));
            }
            catch (OperationCanceledException) { break; }
            catch (JsonException) { }
            catch (SocketException) when (cancellationToken.IsCancellationRequested) { break; }
        }
    }

    public async ValueTask DisposeAsync()
    {
        stop.Cancel();
        client.Dispose();
        if (receiveLoop is not null) { try { await receiveLoop; } catch (OperationCanceledException) { } }
        stop.Dispose();
    }
}
