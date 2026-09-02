using Makaretu.Dns;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public sealed class BonjourAdvertiser : IDisposable
{
    private readonly MulticastService multicast = new();
    private ServiceDiscovery? discovery;
    private ServiceProfile? profile;
    public void Start(DeviceInfo info)
    {
        discovery = new ServiceDiscovery(multicast);
        profile = new ServiceProfile($"aiyue-{info.Fingerprint[..12]}", "_aiyue._tcp", (ushort)info.Port);
        profile.AddProperty("alias", info.Alias); profile.AddProperty("version", info.Version); profile.AddProperty("deviceType", info.DeviceType);
        profile.AddProperty("fingerprint", info.Fingerprint); profile.AddProperty("protocol", info.Protocol);
        multicast.Start();
        discovery.Advertise(profile);
        discovery.Announce(profile);
        DiagnosticLog.Write($"Bonjour service announced: {profile.FullyQualifiedName}.");
    }
    public void Announce() { if (discovery is not null && profile is not null) { discovery.Announce(profile); DiagnosticLog.Write("Bonjour service re-announced."); } }
    public void Dispose() { discovery?.Unadvertise(); multicast.Stop(); discovery?.Dispose(); multicast.Dispose(); }
}
