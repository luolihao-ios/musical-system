using System.Net;
using System.Net.Http;
using System.Security.Cryptography;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using MuseTransfer.App.Discovery;
using MuseTransfer.Core.Files;
using MuseTransfer.Core.Sessions;

namespace MuseTransfer.App.Networking;

public sealed record ReceiverOptions(string DestinationRoot, IReadOnlyList<IPAddress> ListenAddresses, int Port, string DeviceId, string DeviceName);

public interface IReceiverHost
{
    int BoundPort { get; }
    Task StartAsync(CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public sealed class ReceiverHost(SessionManager sessions, IncomingFileStore files, IMdnsAdvertiser advertiser, ReceiverOptions options)
    : IReceiverHost, IAsyncDisposable
{
    private readonly ReceiverCryptoState crypto = new();
    private WebApplication? application;
    private ListenOptions? firstEndpoint;

    public int BoundPort { get; private set; }
    public byte[] ReceiverPublicKey => crypto.PublicKey;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (application is not null) throw new InvalidOperationException("The receiver is already running.");
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(kestrel =>
        {
            foreach (var address in options.ListenAddresses)
            {
                kestrel.Listen(address, options.Port, endpoint => firstEndpoint ??= endpoint);
            }
        });
        builder.Services.AddSingleton(sessions);
        builder.Services.AddSingleton(files);
        builder.Services.AddSingleton(options);
        builder.Services.AddSingleton(crypto);
        application = builder.Build();
        TransferEndpoints.Map(application);
        await application.StartAsync(cancellationToken);
        var boundEndpoint = firstEndpoint ?? throw new InvalidOperationException("Kestrel did not bind an endpoint.");
        BoundPort = boundEndpoint.IPEndPoint?.Port ?? throw new InvalidOperationException("Kestrel endpoint has no TCP port.");
        var keyId = Convert.ToHexString(SHA256.HashData(ReceiverPublicKey)).ToLowerInvariant();
        await advertiser.StartAsync(new MdnsService(options.DeviceId, options.DeviceName, BoundPort, Convert.ToBase64String(ReceiverPublicKey), keyId), cancellationToken);
    }

    public HttpClient CreateLoopbackClientForTests()
    {
        if (BoundPort == 0) throw new InvalidOperationException("Start the receiver first.");
        return new HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{BoundPort}") };
    }

    public async Task StopAsync(CancellationToken cancellationToken)
    {
        await advertiser.StopAsync(cancellationToken);
        if (application is null) return;
        await application.StopAsync(cancellationToken);
        await application.DisposeAsync();
        application = null;
    }

    public async ValueTask DisposeAsync()
    {
        if (application is not null) await StopAsync(CancellationToken.None);
        crypto.Dispose();
    }
}
