using System.Net;
using System.Text;
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
        DiagnosticLog.Write("Bonjour browser starting (_aiyue._tcp.local).");
        discovery = new ServiceDiscovery(multicast);
        discovery.ServiceInstanceDiscovered += OnServiceInstanceDiscovered;
        multicast.Start();
        Refresh();
    }

    public void Refresh()
    {
        // DNS-SD service types are fully qualified on the local mDNS domain.
        // Using the short form only let this client observe its own unsolicited announcement.
        DiagnosticLog.Write("Bonjour browser query sent (_aiyue._tcp.local).");
        discovery?.QueryServiceInstances(new DomainName("_aiyue._tcp.local"));
    }

    private void OnServiceInstanceDiscovered(object? sender, ServiceInstanceDiscoveryEventArgs args)
    {
        var records = args.Message.Answers.Concat(args.Message.AdditionalRecords).ToArray();
        var instanceName = args.ServiceInstanceName.ToString();
        DiagnosticLog.Write($"Bonjour instance received: {instanceName}; records={records.Length}; sender={args.RemoteEndPoint}.");
        var service = records.OfType<SRVRecord>().FirstOrDefault(record => string.Equals(record.Name.ToString(), instanceName, StringComparison.OrdinalIgnoreCase));
        if (service is null || service.Port == 0) { DiagnosticLog.Write($"Bonjour instance ignored: no SRV record for {instanceName}."); return; }

        var addresses = records.OfType<AddressRecord>()
            .Where(record => string.Equals(record.Name.ToString(), service.Target.ToString(), StringComparison.OrdinalIgnoreCase))
            .Select(record => record.Address)
            .ToArray();
        // iOS usually advertises both address families. A link-local IPv6 address
        // needs an interface scope and cannot be used as a plain HTTP URI, while
        // the paired Wi-Fi IPv4 address is directly reachable on this LAN.
        var address = addresses.FirstOrDefault(candidate => candidate.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
            ?? addresses.FirstOrDefault()
            ?? args.RemoteEndPoint.Address;
        if (IPAddress.Any.Equals(address) || IPAddress.IPv6Any.Equals(address)) { DiagnosticLog.Write($"Bonjour instance ignored: unusable address for {instanceName}."); return; }

        var properties = records.OfType<TXTRecord>()
            .FirstOrDefault(record => string.Equals(record.Name.ToString(), instanceName, StringComparison.OrdinalIgnoreCase))?.Strings
            .Select(value => value.Split('=', 2))
            .Where(parts => parts.Length == 2)
            .ToDictionary(parts => parts[0], parts => parts[1], StringComparer.OrdinalIgnoreCase)
            ?? new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var alias = DecodeAlias(properties.GetValueOrDefault("aliasB64")) ?? properties.GetValueOrDefault("alias") ?? instanceName.Split('.', 2)[0];
        var deviceType = properties.GetValueOrDefault("deviceType") ?? "附近设备";
        var fingerprint = properties.GetValueOrDefault("fingerprint") ?? $"bonjour:{address}:{service.Port}";
        DiagnosticLog.Write($"Bonjour device parsed: alias={alias}; endpoint={address}:{service.Port}; allAddresses=[{string.Join(",", addresses)}]; fingerprint={fingerprint}.");
        DeviceDiscovered?.Invoke(new BonjourDevice(alias, deviceType, address, service.Port, fingerprint));
    }

    private static string? DecodeAlias(string? encoded)
    {
        if (string.IsNullOrWhiteSpace(encoded)) return null;
        try { return Encoding.UTF8.GetString(Convert.FromBase64String(encoded)); }
        catch (FormatException) { DiagnosticLog.Write("Bonjour aliasB64 was invalid."); return null; }
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
