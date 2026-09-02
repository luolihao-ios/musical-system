using System.Text.Json;
using AiyueTransfer.Protocol;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class DiscoveryAnnouncementTests
{
    [Fact]
    public void Announcement_RoundTrips()
    {
        var source = new DiscoveryAnnouncement(new DeviceInfo("爱乐互传", "2.0", "Windows", "desktop", "fp", 53317, "http"));
        var restored = DiscoveryAnnouncement.Parse(source.ToBytes());
        Assert.Equal("爱乐互传", restored.Info.Alias);
        Assert.Equal(53317, restored.Info.Port);
    }

    [Fact]
    public void Announcement_RejectsUnsupportedVersion()
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(new { alias = "x", version = "1.0", deviceModel = "x", deviceType = "desktop", fingerprint = "x", port = 53317, @protocol = "http" });
        Assert.Throws<JsonException>(() => DiscoveryAnnouncement.Parse(bytes));
    }
}
