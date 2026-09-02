using System.Net.Http.Json;
using System.Net.Http;
using System.IO;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public sealed class LocalSendSender(HttpClient http)
{
    public async Task SendAsync(Uri endpoint, DeviceInfo local, IReadOnlyList<string> paths, CancellationToken cancellationToken = default)
    {
        var files = paths.Select(path => new FileMetadata(Guid.NewGuid().ToString("N"), Path.GetFileName(path), new FileInfo(path).Length, Mime(path))).ToDictionary(file => file.Id, StringComparer.Ordinal);
        using var prepare = await http.PostAsJsonAsync(new Uri(endpoint, TransferRoutes.PrepareUpload), new PrepareUploadRequest(local, files), ProtocolJson.Options, cancellationToken);
        prepare.EnsureSuccessStatusCode();
        var response = await prepare.Content.ReadFromJsonAsync<PrepareUploadResponse>(ProtocolJson.Options, cancellationToken) ?? throw new InvalidDataException("接收端没有返回传输会话。");
        foreach (var file in files.Values)
        {
            var source = paths.Single(path => Path.GetFileName(path) == file.FileName);
            await using var input = File.OpenRead(source);
            using var content = new StreamContent(input);
            using var upload = await http.PostAsync(new Uri(endpoint, $"{TransferRoutes.Upload}?sessionId={response.SessionId}&fileId={file.Id}&token={response.Files[file.Id]}"), content, cancellationToken);
            upload.EnsureSuccessStatusCode();
        }
    }

    private static string Mime(string path) => Path.GetExtension(path).ToLowerInvariant() switch { ".mp3" => "audio/mpeg", ".flac" => "audio/flac", ".m4a" => "audio/mp4", ".lrc" => "text/plain", _ => "application/octet-stream" };
}
