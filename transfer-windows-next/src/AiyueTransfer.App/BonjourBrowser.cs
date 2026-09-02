using System.Net;
using Makaretu.Dns;

namespace AiyueTransfer.App;

/// <summary>Discovers _aiyue._tcp Bonjour services advertised by iOS and Windows clients.</summary>
public sealed class BonjourBrowser : IDisposable
{
    private readonly MulticastService multicast = new();
    private ServiceDiscovery? discovery;

    public event Action<BonjourDevice>? DeviceDiscovered;

    public void Start()
    {
        if (discovery is not null) return;
        discovery = new ServiceDiscovery(multicast);
        discovery.ServiceInstanceDiscovered += OnServiceInstanceDiscovered;
        multicast.Start();
        Refresh();
    }

    public void Refresh()
    {
        discovery?.QueryServiceInstances(new DomainName("_aiyue._tcp"));
    }

    private void OnServiceInstanceDiscovered(object? sender, ServiceInstanceDiscoveryEventArgs args)
    {
        var records = args.Message.Answers.Concat(args.Message.AdditionalRecords).ToArray();
        var instanceName = args.ServiceInstanceName.ToString();
        var service = records.OfType<SRVRecord>().FirstOrDefault(record => string.Equals(record.Name.ToString(), instanceName, StringComparison.OrdinalIgnoreCase));
        if (service is null || service.Port == 0) return;

        var address = records.OfType<AddressRecord>()
            .FirstOrDefault(record => string.Equals(record.Name.ToString(), service.Target.ToString(), StringComparison.OrdinalIgnoreCase))?.Address
            ?? args.RemoteEndPoint.Address;
        if (IPAddress.Any.Equals(address) || IPAddress.IPv6Any.Equals(address)) return;

        var properties = records.OfType<TXTRecord>()
            .FirstOrDefault(record => string.Equals(record.Name.ToString(), instanceName, StringComparison.OrdinalIgnoreCase))?.Strings
            .Select(value => value.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => parts[0], parts => parts[1], StringComparer.OrdinalIgnoreCase)
            ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var alias = properties.GetValueOrDefault("alias") ?? instanceName.Split('.', 2)[0];
        var deviceType = properties.GetValueOrDefault("deviceType") ?? "附近设备";
        var fingerprint = properties.GetValueOrDefault("fingerprint") ?? $"bonjour:{address}:{service.Port}";
        DeviceDiscovered?.Invoke(new BonjourDevice(alias, deviceType, address, service.Port, fingerprint));
    }

    public void Dispose()
    {
        if (discovery is not null) discovery.ServiceInstanceDiscovered -= OnServiceInstanceDiscovered;
        discovery?.Dispose();
        multicast.Stop();
        multicast.Dispose();
    }
}

public sealed record BonjourDevice(string Alias, string DeviceType, IPAddress Address, int Port, string Fingerprint);
