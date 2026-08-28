using System.Net;
using System.IO;
using MuseTransfer.App.Discovery;
using MuseTransfer.App.Networking;
using MuseTransfer.Core.Files;
using MuseTransfer.Core.Sessions;

namespace MuseTransfer.App.Composition;

public sealed class AppServices : IAsyncDisposable
{
    public AppServices(string applicationDataRoot, string destinationRoot, string deviceId, string deviceName)
    {
        Sessions = new SessionManager(TimeProvider.System, new SessionTokenService());
        Receiver = new ReceiverHost(Sessions, new IncomingFileStore(Path.Combine(applicationDataRoot, "Incoming")), new MdnsAdvertiser(),
            new ReceiverOptions(destinationRoot, GetPrivateAddresses(), 53317, deviceId, deviceName, Path.Combine(applicationDataRoot, "receiver.pfx")));
    }

    public SessionManager Sessions { get; }
    public ReceiverHost Receiver { get; }
    public ValueTask DisposeAsync() => Receiver.DisposeAsync();

    private static IReadOnlyList<IPAddress> GetPrivateAddresses() =>
        Dns.GetHostAddresses(Dns.GetHostName())
            .Where(address => address.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork && IsPrivate(address))
            .Prepend(IPAddress.Loopback).Distinct().ToArray();

    private static bool IsPrivate(IPAddress address)
    {
        var bytes = address.GetAddressBytes();
        return bytes[0] == 10 || bytes[0] == 172 && bytes[1] is >= 16 and <= 31 || bytes[0] == 192 && bytes[1] == 168;
    }
}
