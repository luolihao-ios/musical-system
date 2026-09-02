using Makaretu.Dns;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public sealed class BonjourAdvertiser : IDisposable
{
    private readonly MulticastService multicast = new();
    private ServiceDiscovery? discovery;
    public void Start(DeviceInfo info)
    {
        discovery = new ServiceDiscovery(multicast);
        var profile = new ServiceProfile(info.Alias, "_aiyue._tcp", (ushort)info.Port);
        profile.AddProperty("alias", info.Alias); profile.AddProperty("version", info.Version); profile.AddProperty("deviceType", info.DeviceType);
        profile.AddProperty("fingerprint", info.Fingerprint); profile.AddProperty("protocol", info.Protocol);
        multicast.Start();
        discovery.Advertise(profile);
    }
    public void Dispose() { discovery?.Unadvertise(); multicast.Stop(); discovery?.Dispose(); multicast.Dispose(); }
}
