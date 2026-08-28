using System.Net;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using MuseTransfer.Core.Files;
using MuseTransfer.Core.Sessions;
using MuseTransfer.Protocol;

namespace MuseTransfer.App.Networking;

public sealed record SessionProposalResponse(string SessionId, string VerificationCode, string ManifestDigest, string ProposalKey, string Status);

public static partial class TransferEndpoints
{
    public static void Map(WebApplication app)
    {
        app.MapPost("/v1/sessions", ProposeAsync);
        app.MapPut("/v1/sessions/{sessionId}/files/{fileId}/chunks/{chunkIndex:int}", UploadChunkAsync);
        app.MapPost("/v1/sessions/{sessionId}/complete", CompleteAsync);
        app.MapGet("/v1/sessions/{sessionId}", GetStatus);
    }

    private static async Task<IResult> ProposeAsync(HttpContext context, SessionManager sessions, CancellationToken cancellationToken)
    {
        var sizeFeature = context.Features.Get<Microsoft.AspNetCore.Http.Features.IHttpMaxRequestBodySizeFeature>();
        if (sizeFeature is not null && !sizeFeature.IsReadOnly) sizeFeature.MaxRequestBodySize = 8 * 1024 * 1024;
        var manifest = await context.Request.ReadFromJsonAsync<TransferManifest>(cancellationToken);
        if (manifest is null) return Error(HttpStatusCode.BadRequest, "invalid_manifest", "The transfer manifest is required.");
        try
        {
            var session = sessions.Propose(manifest, context.Connection.RemoteIpAddress?.ToString() ?? "unknown");
            return Results.Accepted($"/v1/sessions/{session.Id}", new SessionProposalResponse(session.Id, session.VerificationCode, session.ManifestDigest, session.ProposalKey, "pending"));
        }
        catch (Exception exception) when (exception is NotSupportedException or ArgumentException)
        {
            return Error(HttpStatusCode.BadRequest, "invalid_manifest", exception.Message);
        }
    }

    private static async Task<IResult> UploadChunkAsync(HttpContext context, string sessionId, string fileId, int chunkIndex, SessionManager sessions, IncomingFileStore files, CancellationToken cancellationToken)
    {
        try
        {
            var session = sessions.Get(sessionId);
            if (!DigestMatches(context, session)) return Error(HttpStatusCode.Conflict, "manifest_changed", "The manifest digest changed.");
            sessions.AuthorizeChunk(sessionId, context.Request.Headers["X-Muse-Session-Token"].ToString(), fileId, chunkIndex);
            var item = session.Manifest.Items.Single(candidate => candidate.Id == fileId);
            if (!TryParseRange(context.Request.Headers.ContentRange, out var offset, out var end, out var total) || total != item.Size || end < offset)
                return Error(HttpStatusCode.BadRequest, "invalid_range", "Content-Range does not match the manifest.");
            var result = await files.WriteChunkAsync(sessionId, item, chunkIndex, offset, context.Request.Body, cancellationToken);
            if (result.BytesWritten != end - offset + 1) return Error(HttpStatusCode.BadRequest, "invalid_range", "Body length does not match Content-Range.");
            sessions.RecordVerifiedChunk(sessionId, fileId, chunkIndex);
            return Results.NoContent();
        }
        catch (SessionNotAcceptedException exception) { return Error(HttpStatusCode.Forbidden, "session_not_accepted", exception.Message); }
        catch (InvalidSessionTokenException exception) { return Error(HttpStatusCode.Unauthorized, "invalid_token", exception.Message); }
        catch (SessionExpiredException exception) { return Error(HttpStatusCode.Unauthorized, "session_expired", exception.Message); }
    }

    private static async Task<IResult> CompleteAsync(HttpContext context, string sessionId, SessionManager sessions, IncomingFileStore files, ReceiverOptions options, CancellationToken cancellationToken)
    {
        try
        {
            var session = sessions.Get(sessionId);
            if (!DigestMatches(context, session)) return Error(HttpStatusCode.Conflict, "manifest_changed", "The manifest digest changed.");
            sessions.AuthorizeCompletion(sessionId, context.Request.Headers["X-Muse-Session-Token"].ToString());
            foreach (var item in session.Manifest.Items) await files.CommitAsync(sessionId, item, options.DestinationRoot, cancellationToken);
            sessions.Complete(sessionId);
            return Results.Ok(new { status = "completed" });
        }
        catch (FileIntegrityException exception) { return Error(HttpStatusCode.Conflict, "hash_mismatch", exception.Message); }
        catch (SessionNotAcceptedException exception) { return Error(HttpStatusCode.Forbidden, "session_not_accepted", exception.Message); }
        catch (InvalidSessionTokenException exception) { return Error(HttpStatusCode.Unauthorized, "invalid_token", exception.Message); }
    }

    private static IResult GetStatus(HttpContext context, string sessionId, SessionManager sessions)
    {
        try
        {
            var decision = sessions.ReadDecision(sessionId, context.Request.Headers["X-Muse-Proposal-Key"].ToString());
            return Results.Ok(new { status = decision.Status.ToString().ToLowerInvariant(), token = decision.Token, verifiedChunks = decision.VerifiedChunks });
        }
        catch (SessionNotFoundException exception) { return Error(HttpStatusCode.NotFound, "session_not_found", exception.Message); }
        catch (InvalidSessionTokenException exception) { return Error(HttpStatusCode.Unauthorized, "invalid_proposal_key", exception.Message); }
    }

    private static bool DigestMatches(HttpContext context, TransferSession session) =>
        string.Equals(context.Request.Headers["X-Muse-Manifest-Digest"].ToString(), session.ManifestDigest, StringComparison.Ordinal);

    private static bool TryParseRange(string? value, out long start, out long end, out long total)
    {
        start = end = total = 0;
        if (value is null) return false;
        var match = ContentRangePattern().Match(value);
        return long.TryParse(match.Groups[1].Value, out start) && long.TryParse(match.Groups[2].Value, out end) && long.TryParse(match.Groups[3].Value, out total);
    }

    private static IResult Error(HttpStatusCode status, string code, string message) => Results.Json(new { code, message }, statusCode: (int)status);

    [GeneratedRegex("^bytes ([0-9]+)-([0-9]+)/([0-9]+)$", RegexOptions.CultureInvariant)]
    private static partial Regex ContentRangePattern();
}
