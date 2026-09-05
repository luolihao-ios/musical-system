using System.Net.Http.Json;
using System.Net.Http;
using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public sealed class LocalSendSender(HttpClient http)
{
    public async Task SendAsync(Uri endpoint, DeviceInfo local, IReadOnlyList<string> paths, CancellationToken cancellationToken = default)
    {
        await SendEntriesAsync(endpoint, local, paths.Select(path => new TransferFile(path, Path.GetFileName(path))), cancellationToken);
    }

    public async Task SendFolderAsync(Uri endpoint, DeviceInfo local, string folder, CancellationToken cancellationToken = default)
    {
        var parent = Directory.GetParent(Path.GetFullPath(folder))?.FullName ?? throw new InvalidDataException("文件夹没有父级目录。");
        var files = Directory.EnumerateFiles(folder, "*", SearchOption.AllDirectories)
            .Select(path => new TransferFile(path, Path.GetRelativePath(parent, path)));
        await SendEntriesAsync(endpoint, local, files, cancellationToken);
    }

    public async Task SendEntriesAsync(Uri endpoint, DeviceInfo local, IEnumerable<TransferFile> entries, CancellationToken cancellationToken = default)
    {
        var sources = entries.ToArray();
        if (sources.Length == 0) throw new InvalidDataException("没有可发送的文件。");
        var files = sources.Select(source => new FileMetadata(Guid.NewGuid().ToString("N"), source.TransferName.Replace('\\', '/'), new FileInfo(source.Path).Length, Mime(source.Path), Hash(source.Path))).ToDictionary(file => file.Id, StringComparer.Ordinal);
        var preparePayload = JsonSerializer.SerializeToUtf8Bytes(new PrepareUploadRequest(local, files), ProtocolJson.Options);
        using var prepareContent = new ByteArrayContent(preparePayload);
        prepareContent.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("application/json");
        // JsonContent is streamed as chunked HTTP on this runtime. The iOS receiver
        // intentionally uses a small LAN-only parser and requires a known length.
        using var prepare = await http.PostAsync(new Uri(endpoint, TransferRoutes.PrepareUpload), prepareContent, cancellationToken);
        if (!prepare.IsSuccessStatusCode)
        {
            var details = await prepare.Content.ReadAsStringAsync(cancellationToken);
            throw new InvalidOperationException(prepare.StatusCode == System.Net.HttpStatusCode.Forbidden
                ? "对方拒绝了本次传输。"
                : $"对方未能接受传输请求（{(int)prepare.StatusCode}）：{details}");
        }
        var response = await prepare.Content.ReadFromJsonAsync<PrepareUploadResponse>(ProtocolJson.Options, cancellationToken) ?? throw new InvalidDataException("接收端没有返回传输会话。");
        foreach (var file in files.Values)
        {
            var source = sources.Single(path => string.Equals(path.TransferName.Replace('\\', '/'), file.FileName, StringComparison.Ordinal)).Path;
            await using var input = File.OpenRead(source);
            using var content = new StreamContent(input);
            using var upload = await http.PostAsync(new Uri(endpoint, $"{TransferRoutes.Upload}?sessionId={response.SessionId}&fileId={file.Id}&token={response.Files[file.Id]}"), content, cancellationToken);
            upload.EnsureSuccessStatusCode();
        }
    }

    private static string Hash(string path) { using var input = File.OpenRead(path); return Convert.ToHexString(SHA256.HashData(input)).ToLowerInvariant(); }

    private static string Mime(string path) => Path.GetExtension(path).ToLowerInvariant() switch { ".mp3" => "audio/mpeg", ".flac" => "audio/flac", ".m4a" => "audio/mp4", ".lrc" => "text/plain", _ => "application/octet-stream" };
}

public sealed record TransferFile(string Path, string TransferName);
