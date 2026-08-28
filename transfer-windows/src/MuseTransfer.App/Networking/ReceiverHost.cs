using System.Net;
using System.Net.Http;
using System.IO;
using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.Extensions.DependencyInjection;
using MuseTransfer.App.Discovery;
using MuseTransfer.Core.Files;
using MuseTransfer.Core.Sessions;

namespace MuseTransfer.App.Networking;

public sealed record ReceiverOptions(string DestinationRoot, IReadOnlyList<IPAddress> ListenAddresses, int Port, string DeviceId, string DeviceName, string? CertificatePath = null);

public interface IReceiverHost
{
    int BoundPort { get; }
    Task StartAsync(CancellationToken cancellationToken);
    Task StopAsync(CancellationToken cancellationToken);
}

public sealed class ReceiverHost(SessionManager sessions, IncomingFileStore files, IMdnsAdvertiser advertiser, ReceiverOptions options)
    : IReceiverHost, IAsyncDisposable
{
    private WebApplication? application;
    private X509Certificate2? certificate;
    private ListenOptions? firstEndpoint;

    public int BoundPort { get; private set; }
    public string CertificateSha256 { get; private set; } = string.Empty;

    public async Task StartAsync(CancellationToken cancellationToken)
    {
        if (application is not null) throw new InvalidOperationException("The receiver is already running.");
        certificate = ReceiverCertificateStore.GetOrCreate(options.CertificatePath ?? Path.Combine(Path.GetTempPath(), "MuseTransfer", "receiver.pfx"));
        CertificateSha256 = Convert.ToHexString(SHA256.HashData(certificate.RawData)).ToLowerInvariant();
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(kestrel =>
        {
            foreach (var address in options.ListenAddresses)
            {
                kestrel.Listen(address, options.Port, endpoint =>
                {
                    endpoint.UseHttps(certificate);
                    firstEndpoint ??= endpoint;
                });
            }
        });
        builder.Services.AddSingleton(sessions);
        builder.Services.AddSingleton(files);
        builder.Services.AddSingleton(options);
        application = builder.Build();
        TransferEndpoints.Map(application);
        await application.StartAsync(cancellationToken);
        var boundEndpoint = firstEndpoint ?? throw new InvalidOperationException("Kestrel did not bind an endpoint.");
        BoundPort = boundEndpoint.IPEndPoint?.Port ?? throw new InvalidOperationException("Kestrel endpoint has no TCP port.");
        await advertiser.StartAsync(new MdnsService(options.DeviceId, options.DeviceName, BoundPort, CertificateSha256), cancellationToken);
    }

    public HttpClient CreateLoopbackClientForTests()
    {
        if (BoundPort == 0) throw new InvalidOperationException("Start the receiver first.");
        var handler = new HttpClientHandler { ServerCertificateCustomValidationCallback = HttpClientHandler.DangerousAcceptAnyServerCertificateValidator };
        return new HttpClient(handler) { BaseAddress = new Uri($"https://127.0.0.1:{BoundPort}") };
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
        certificate?.Dispose();
    }
}

internal static class ReceiverCertificateStore
{
    public static X509Certificate2 GetOrCreate(string path)
    {
        if (File.Exists(path)) return X509CertificateLoader.LoadPkcs12FromFile(path, null);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using var rsa = RSA.Create(2048);
        var request = new CertificateRequest("CN=MuseTransfer Local Receiver", rsa, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1);
        request.CertificateExtensions.Add(new X509BasicConstraintsExtension(false, false, 0, false));
        request.CertificateExtensions.Add(new X509KeyUsageExtension(X509KeyUsageFlags.DigitalSignature, false));
        using var created = request.CreateSelfSigned(DateTimeOffset.UtcNow.AddDays(-1), DateTimeOffset.UtcNow.AddYears(5));
        File.WriteAllBytes(path, created.Export(X509ContentType.Pfx));
        return X509CertificateLoader.LoadPkcs12FromFile(path, null);
    }
}
