using System.Net;
using System.Net.Http.Json;

namespace AiyueTransfer.Protocol;

public sealed class HttpDiscoveryClient(HttpClient http)
{
    public async Task<IReadOnlyList<(Uri Endpoint, DeviceInfo Info)>> RegisterAsync(
        IEnumerable<Uri> endpoints, DeviceInfo local, CancellationToken cancellationToken = default)
    {
        var discovered = new List<(Uri, DeviceInfo)>();
        foreach (var endpoint in endpoints.DistinctBy(uri => uri.ToString(), StringComparer.OrdinalIgnoreCase))
        {
            try
            {
                using var response = await http.PostAsJsonAsync(new Uri(endpoint, TransferRoutes.Register), local, ProtocolJson.Options, cancellationToken);
                if (!response.IsSuccessStatusCode) continue;
                var info = await response.Content.ReadFromJsonAsync<DeviceInfo>(ProtocolJson.Options, cancellationToken);
                if (info is not null && info.Version == "2.0" && info.Port is >= 1 and <= 65535)
                    discovered.Add((endpoint, info));
            }
            catch (HttpRequestException) { }
            catch (TaskCanceledException) when (!cancellationToken.IsCancellationRequested) { }
        }
        return discovered;
    }
}
