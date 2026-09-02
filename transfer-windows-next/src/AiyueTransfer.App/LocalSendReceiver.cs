using System.Collections.Concurrent;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Hosting;
using Microsoft.AspNetCore.Http;
using AiyueTransfer.Protocol;
using AiyueTransfer.Core;

namespace AiyueTransfer.App;

public sealed record IncomingRequest(string SessionId, DeviceInfo Sender, IReadOnlyDictionary<string, FileMetadata> Files);

public sealed class LocalSendReceiver : IAsyncDisposable
{
    private readonly DeviceInfo local;
    private readonly string destination;
    private readonly ConcurrentDictionary<string, PendingUpload> sessions = new(StringComparer.Ordinal);
    private WebApplication? application;
    public event Action<IncomingRequest>? RequestReceived;

    public LocalSendReceiver(DeviceInfo local, string destination) { this.local = local; this.destination = destination; }

    public async Task StartAsync(CancellationToken cancellationToken = default)
    {
        if (application is not null) return;
        Directory.CreateDirectory(destination);
        var builder = WebApplication.CreateSlimBuilder();
        builder.WebHost.ConfigureKestrel(options => options.ListenAnyIP(local.Port));
        application = builder.Build();
        application.MapPost(TransferRoutes.Register, () => Results.Json(local, ProtocolJson.Options));
        application.MapPost(TransferRoutes.PrepareUpload, async (HttpContext context) =>
        {
            var request = await context.Request.ReadFromJsonAsync<PrepareUploadRequest>(ProtocolJson.Options, context.RequestAborted);
            if (request is null || request.Files.Count == 0) return Results.BadRequest(new { message = "需要至少一个文件。" });
            if (request.Files.Values.Any(file => !IsSafeRelativeName(file.FileName) || file.Size < 0)) return Results.BadRequest(new { message = "文件名或大小无效。" });
            var session = new PendingUpload(Guid.NewGuid().ToString("N"), request);
            sessions[session.Id] = session;
            RequestReceived?.Invoke(new IncomingRequest(session.Id, request.Info, request.Files));
            var accepted = await session.Decision.Task.WaitAsync(TimeSpan.FromMinutes(2), context.RequestAborted);
            if (!accepted) return Results.StatusCode(StatusCodes.Status403Forbidden);
            return Results.Json(new PrepareUploadResponse(session.Id, session.Tokens), ProtocolJson.Options, statusCode: StatusCodes.Status200OK);
        });
        application.MapPost(TransferRoutes.Upload, async (HttpContext context) =>
        {
            var sessionId = context.Request.Query["sessionId"].ToString(); var fileId = context.Request.Query["fileId"].ToString(); var token = context.Request.Query["token"].ToString();
            if (!sessions.TryGetValue(sessionId, out var session) || !session.Tokens.TryGetValue(fileId, out var expected) || !CryptographicOperations.FixedTimeEquals(Encoding.UTF8.GetBytes(token), Encoding.UTF8.GetBytes(expected))) return Results.Unauthorized();
            if (!session.Request.Files.TryGetValue(fileId, out var file)) return Results.BadRequest();
            var folder = destination; Directory.CreateDirectory(folder);
            var path = Path.GetFullPath(Path.Combine(folder, file.FileName.Replace('/', Path.DirectorySeparatorChar)));
            if (!path.StartsWith(Path.GetFullPath(folder) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) return Results.BadRequest();
            Directory.CreateDirectory(Path.GetDirectoryName(path)!);
            var temporary = path + ".partial";
            long length;
            await using (var output = File.Create(temporary))
            {
                await context.Request.Body.CopyToAsync(output, context.RequestAborted);
                length = output.Length;
            }
            if (length != file.Size || (file.Sha256 is not null && !string.Equals(await HashAsync(temporary, context.RequestAborted), file.Sha256, StringComparison.OrdinalIgnoreCase))) { File.Delete(temporary); return Results.StatusCode(StatusCodes.Status422UnprocessableEntity); }
            File.Move(temporary, path, true);
            if (string.Equals(Path.GetExtension(path), ".aiyuepack", StringComparison.OrdinalIgnoreCase))
            {
                var musicRoot = Path.Combine(destination, "MusicPackages", sessionId);
                try { AiyuePack.Extract(path, musicRoot); await MusicHandoff.CreateAsync(musicRoot, Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "luolihao", "AiYueTransfer", "MusicHandoff"), context.RequestAborted); }
                catch (InvalidDataException) { return Results.UnprocessableEntity(new { message = "音乐包无效，文件已保留。" }); }
            }
            return Results.NoContent();
        });
        application.MapPost(TransferRoutes.Cancel, (string sessionId) => { sessions.TryRemove(sessionId, out _); return Results.NoContent(); });
        await application.StartAsync(cancellationToken);
    }

    public bool Decide(string sessionId, bool accepted) => sessions.TryGetValue(sessionId, out var session) && session.Decision.TrySetResult(accepted);
    public async ValueTask DisposeAsync() { if (application is not null) { await application.StopAsync(); await application.DisposeAsync(); } }

    private static bool IsSafeRelativeName(string fileName)
    {
        if (string.IsNullOrWhiteSpace(fileName) || Path.IsPathRooted(fileName)) return false;
        var normalized = fileName.Replace('\\', '/');
        return normalized.Split('/', StringSplitOptions.RemoveEmptyEntries).All(part => part is not "." and not "..");
    }
    private static async Task<string> HashAsync(string path, CancellationToken cancellationToken)
    {
        await using var input = File.OpenRead(path);
        return Convert.ToHexString(await SHA256.HashDataAsync(input, cancellationToken)).ToLowerInvariant();
    }

    private sealed class PendingUpload
    {
        public string Id { get; } public PrepareUploadRequest Request { get; } public TaskCompletionSource<bool> Decision { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Dictionary<string, string> Tokens { get; }
        public PendingUpload(string id, PrepareUploadRequest request) { Id = id; Request = request; Tokens = request.Files.Keys.ToDictionary(key => key, _ => Convert.ToHexString(RandomNumberGenerator.GetBytes(24)).ToLowerInvariant(), StringComparer.Ordinal); }
    }
}
