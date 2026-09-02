using System.Text.Json.Serialization;
using System.Text.Encodings.Web;

namespace AiyueTransfer.Protocol;

public sealed record DeviceInfo(
    string Alias,
    string Version,
    string DeviceModel,
    string DeviceType,
    string Fingerprint,
    int Port,
    string Protocol,
    bool Download = true,
    bool Announce = true);

public sealed record FileMetadata(
    string Id,
    string FileName,
    long Size,
    string FileType,
    string? Sha256 = null,
    string? Preview = null);

public sealed record PrepareUploadRequest(
    DeviceInfo Info,
    IReadOnlyDictionary<string, FileMetadata> Files);

public sealed record PrepareUploadResponse(
    string SessionId,
    IReadOnlyDictionary<string, string> Files);

public static class ProtocolJson
{
    public static readonly System.Text.Json.JsonSerializerOptions Options = new()
    {
        PropertyNamingPolicy = System.Text.Json.JsonNamingPolicy.CamelCase,
        Encoder = JavaScriptEncoder.UnsafeRelaxedJsonEscaping,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull,
        WriteIndented = false
    };
}
