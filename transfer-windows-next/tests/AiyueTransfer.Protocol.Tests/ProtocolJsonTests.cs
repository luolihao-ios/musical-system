using System.Text.Json;
using AiyueTransfer.Protocol;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class ProtocolJsonTests
{
    [Fact]
    public void DeviceInfo_UsesLocalSendFieldNames()
    {
        var json = JsonSerializer.Serialize(new DeviceInfo("爱乐互传", "2.0", "Windows", "desktop", "fp", 53317, "http"), ProtocolJson.Options);
        Assert.Contains("\"alias\":\"爱乐互传\"", json);
        Assert.Contains("\"deviceType\":\"desktop\"", json);
        Assert.Contains("\"port\":53317", json);
    }

    [Fact]
    public void PrepareUpload_RoundTrips()
    {
        var request = new PrepareUploadRequest(new DeviceInfo("iPhone", "2.0", "iPhone", "mobile", "fp", 53317, "http"),
            new Dictionary<string, FileMetadata> { ["f1"] = new("f1", "song.mp3", 123, "audio/mpeg", "abc") });
        var restored = JsonSerializer.Deserialize<PrepareUploadRequest>(JsonSerializer.Serialize(request, ProtocolJson.Options), ProtocolJson.Options);
        Assert.Equal("song.mp3", restored!.Files["f1"].FileName);
        Assert.Equal(123, restored.Files["f1"].Size);
    }
}
