using Makaretu.Dns;

namespace MuseTransfer.App.Discovery;

public sealed record MdnsService(string DeviceId, string DeviceName, int Port, string Platform = "windows", string ProtocolVersion = "1");

public interface IMdnsAdvertiser
{
    Task StartAsync(MdnsService service, CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public sealed class MdnsAdvertiser : IMdnsAdvertiser, IDisposable
{
    private readonly MulticastService multicast = new();
    private ServiceDiscovery? discovery;

    public Task StartAsync(MdnsService service, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        discovery = new ServiceDiscovery(multicast);
        var profile = new ServiceProfile(service.DeviceName, "_musetransfer._tcp", (ushort)service.Port);
        profile.AddProperty("id", service.DeviceId);
        profile.AddProperty("name", service.DeviceName);
        profile.AddProperty("platform", service.Platform);
        profile.AddProperty("v", service.ProtocolVersion);
        discovery.Advertise(profile);
        multicast.Start();
        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        discovery?.Unadvertise();
        multicast.Stop();
        return Task.CompletedTask;
    }

    public void Dispose()
    {
        discovery?.Dispose();
        multicast.Dispose();
    }
}
