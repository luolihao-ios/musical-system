using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using AiyueTransfer.Protocol;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class HttpDiscoveryTests
{
    [Fact]
    public async Task Register_ParsesDeviceAndSkipsFailures()
    {
        var handler = new StubHandler(request => request.RequestUri!.Host == "192.168.1.2"
            ? new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new DeviceInfo("iPhone", "2.0", "iPhone", "mobile", "fp", 53317, "http"), options: ProtocolJson.Options) }
            : new HttpResponseMessage(HttpStatusCode.NotFound));
        var client = new HttpDiscoveryClient(new HttpClient(handler));
        var result = await client.RegisterAsync([new Uri("http://192.168.1.2:53317"), new Uri("http://192.168.1.3:53317")], new DeviceInfo("Windows", "2.0", "Windows", "desktop", "local", 53317, "http"));
        Assert.Single(result);
        Assert.Equal("iPhone", result[0].Info.Alias);
    }

    private sealed class StubHandler(Func<HttpRequestMessage, HttpResponseMessage> responder) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(responder(request));
    }
}
