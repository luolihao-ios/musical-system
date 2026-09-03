using System.Net.NetworkInformation;

namespace AiyueTransfer.App;

/// <summary>Writes the network facts needed to diagnose LAN discovery failures.</summary>
internal static class NetworkDiagnostics
{
    public static void WriteStartupSnapshot(int transferPort)
    {
        try
        {
            var adapters = NetworkInterface.GetAllNetworkInterfaces()
                .Where(adapter => adapter.OperationalStatus == OperationalStatus.Up)
                .Select(adapter =>
                {
                    var properties = adapter.GetIPProperties();
                    var addresses = string.Join(",", properties.UnicastAddresses.Select(address => address.Address.ToString()));
                    var gateways = string.Join(",", properties.GatewayAddresses.Select(gateway => gateway.Address.ToString()));
                    return $"{adapter.Name} [{adapter.NetworkInterfaceType}] addresses={addresses} gateways={gateways}";
                });
            DiagnosticLog.Write($"Network snapshot: port={transferPort}; activeAdapters={string.Join(" | ", adapters)}.");

            var properties = IPGlobalProperties.GetIPGlobalProperties();
            var tcpListeners = properties.GetActiveTcpListeners()
                .Where(endpoint => endpoint.Port == transferPort)
                .Select(endpoint => endpoint.ToString());
            var udpListeners = properties.GetActiveUdpListeners()
                .Where(endpoint => endpoint.Port is 5353 or 53317)
                .Select(endpoint => endpoint.ToString());
            DiagnosticLog.Write($"Network listeners before startup: tcp{transferPort}=[{string.Join(",", tcpListeners)}]; udp5353-or-53317=[{string.Join(",", udpListeners)}].");
        }
        catch (Exception exception)
        {
            DiagnosticLog.Write($"Network snapshot failed: {exception}");
        }
    }
}
