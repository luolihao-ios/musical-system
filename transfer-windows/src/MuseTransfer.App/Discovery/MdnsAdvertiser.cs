using Makaretu.Dns;
using System.Net;

namespace MuseTransfer.App.Discovery;

public sealed record MdnsService(string DeviceId, string DeviceName, int Port, string CertificateSha256, string Platform = "windows", string ProtocolVersion = "1");

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
        profile.AddProperty("fp", service.CertificateSha256);
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

public sealed record DiscoveredService(string Id, string Name, IPAddress Address, int Port, string CertificateSha256);

public sealed class MdnsDeviceBrowser : IDisposable
{
    private readonly MulticastService multicast = new();
    private readonly ServiceDiscovery discovery;
    public MdnsDeviceBrowser()
    {
        discovery = new ServiceDiscovery(multicast);
        discovery.ServiceInstanceDiscovered += OnServiceInstanceDiscovered;
    }

    public event Action<DiscoveredService>? DeviceDiscovered;
    public void Start() { multicast.Start(); discovery.QueryServiceInstances("_musetransfer._tcp"); }

    private async void OnServiceInstanceDiscovered(object? sender, ServiceInstanceDiscoveryEventArgs e)
    {
        try
        {
            var query = new Makaretu.Dns.Message();
            query.Questions.Add(new Question { Name = e.ServiceInstanceName, Type = DnsType.ANY });
            using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
            var response = await multicast.ResolveAsync(query, timeout.Token);
            var records = response.Answers.Concat(response.AdditionalRecords).ToArray();
            var service = records.OfType<SRVRecord>().FirstOrDefault(record => record.Name == e.ServiceInstanceName);
            var text = records.OfType<TXTRecord>().FirstOrDefault(record => record.Name == e.ServiceInstanceName);
            if (service is null || text is null) return;
            var address = records.OfType<ARecord>().FirstOrDefault(record => record.Name == service.Target)?.Address;
            if (address is null) return;
            var properties = text.Strings.Select(value => value.Split('=', 2)).Where(parts => parts.Length == 2).ToDictionary(parts => parts[0], parts => parts[1], StringComparer.Ordinal);
            if (!properties.TryGetValue("id", out var id) || !properties.TryGetValue("name", out var name)) return;
            properties.TryGetValue("fp", out var fingerprint);
            DeviceDiscovered?.Invoke(new DiscoveredService(id, name, address, service.Port, fingerprint ?? string.Empty));
        }
        catch (OperationCanceledException) { }
    }

    public void Dispose() { discovery.Dispose(); multicast.Dispose(); }
}
