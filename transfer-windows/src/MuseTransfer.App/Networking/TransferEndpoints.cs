using System.Net;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Http;
using MuseTransfer.Core.Files;
using MuseTransfer.Core.Sessions;
using MuseTransfer.Protocol;

namespace MuseTransfer.App.Networking;

public sealed record EncryptedProposalRequest(byte[] SenderPublicKey, EncryptedEnvelope Envelope);
public sealed record SessionProposalEnvelopeResponse(string SessionId, EncryptedEnvelope Envelope);
public sealed record SessionProposalResponse(string SessionId, string VerificationCode, string ManifestDigest, string ProposalKey, string Status);
public sealed record EncryptedStatusResponse(EncryptedEnvelope Envelope);
public sealed record SessionStatusResponse(string Status, string? Token, Dictionary<string, int[]> VerifiedChunks);

public static partial class TransferEndpoints
{
    private const int MaximumEncryptedChunkSize = 1024 * 1024 + 28;
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    public static void Map(WebApplication app)
    {
        app.MapPost("/v2/sessions", ProposeAsync);
        app.MapPut("/v2/sessions/{sessionId}/files/{fileId}/chunks/{chunkIndex:int}", UploadChunkAsync);
        app.MapPost("/v2/sessions/{sessionId}/complete", CompleteAsync);
        app.MapGet("/v2/sessions/{sessionId}", GetStatus);
    }

    private static async Task<IResult> ProposeAsync(HttpContext context, SessionManager sessions, ReceiverCryptoState crypto, CancellationToken cancellationToken)
    {
        try
        {
            var request = await context.Request.ReadFromJsonAsync<EncryptedProposalRequest>(cancellationToken);
            if (request is null || request.SenderPublicKey is null || request.Envelope is null)
                return Error(HttpStatusCode.BadRequest, "invalid_proposal", "An encrypted proposal is required.");
            var key = crypto.DeriveForSender(request.SenderPublicKey);
            var plaintext = TransferCrypto.Decrypt(key, request.Envelope, "proposal|v2"u8.ToArray());
            var manifest = JsonSerializer.Deserialize<TransferManifest>(plaintext, JsonOptions)
                ?? throw new JsonException("Manifest is empty.");
            var digest = ManifestCanonicalizer.ComputeSha256(manifest);
            var code = TransferCrypto.VerificationCode(key, digest);
            var session = sessions.Propose(manifest, context.Connection.RemoteIpAddress?.ToString() ?? "unknown", code);
            crypto.Store(session.Id, key);
            var details = new SessionProposalResponse(session.Id, code, digest, session.ProposalKey, "pending");
            var aad = Encoding.UTF8.GetBytes($"proposal-response|{session.Id}");
            var envelope = TransferCrypto.Encrypt(key, JsonSerializer.SerializeToUtf8Bytes(details, JsonOptions), aad);
            return Results.Accepted($"/v2/sessions/{session.Id}", new SessionProposalEnvelopeResponse(session.Id, envelope));
        }
        catch (Exception exception) when (exception is CryptographicException or JsonException or NotSupportedException or ArgumentException)
        {
            return Error(HttpStatusCode.BadRequest, "invalid_proposal", exception.Message);
        }
    }

    private static async Task<IResult> UploadChunkAsync(HttpContext context, string sessionId, string fileId, int chunkIndex, SessionManager sessions, ReceiverCryptoState crypto, IncomingFileStore files, CancellationToken cancellationToken)
    {
        try
        {
            var session = sessions.Get(sessionId);
            if (!DigestMatches(context, session)) return Error(HttpStatusCode.Conflict, "manifest_changed", "The manifest digest changed.");
            sessions.AuthorizeChunk(sessionId, context.Request.Headers["X-Muse-Session-Token"].ToString(), fileId, chunkIndex);
            var item = session.Manifest.Items.Single(candidate => candidate.Id == fileId);
            if (!TryParseRange(context.Request.Headers.ContentRange, out var offset, out var end, out var total) || total != item.Size || end < offset || end - offset + 1 > 1024 * 1024)
                return Error(HttpStatusCode.BadRequest, "invalid_range", "Content-Range does not match the manifest.");
            if (context.Request.ContentLength is null or > MaximumEncryptedChunkSize)
                return Error(HttpStatusCode.BadRequest, "invalid_chunk", "Encrypted chunk is too large.");
            using var packed = new MemoryStream();
            await context.Request.Body.CopyToAsync(packed, cancellationToken);
            var aad = Encoding.UTF8.GetBytes($"{sessionId}|{fileId}|{chunkIndex}|{offset}|{total}|{session.ManifestDigest}");
            var plaintext = TransferCrypto.Decrypt(crypto.Get(sessionId), TransferCrypto.UnpackEnvelope(packed.ToArray()), aad);
            if (plaintext.LongLength != end - offset + 1) return Error(HttpStatusCode.BadRequest, "invalid_range", "Decrypted chunk length does not match Content-Range.");
            await using var content = new MemoryStream(plaintext, writable: false);
            await files.WriteChunkAsync(sessionId, item, chunkIndex, offset, content, cancellationToken);
            sessions.RecordVerifiedChunk(sessionId, fileId, chunkIndex);
            return Results.NoContent();
        }
        catch (SessionNotAcceptedException exception) { return Error(HttpStatusCode.Forbidden, "session_not_accepted", exception.Message); }
        catch (InvalidSessionTokenException exception) { return Error(HttpStatusCode.Unauthorized, "invalid_token", exception.Message); }
        catch (SessionExpiredException exception) { return Error(HttpStatusCode.Unauthorized, "session_expired", exception.Message); }
        catch (CryptographicException exception) { return Error(HttpStatusCode.BadRequest, "invalid_envelope", exception.Message); }
    }

    private static async Task<IResult> CompleteAsync(HttpContext context, string sessionId, SessionManager sessions, ReceiverCryptoState crypto, IncomingFileStore files, ReceiverOptions options, CancellationToken cancellationToken)
    {
        try
        {
            var session = sessions.Get(sessionId);
            if (!DigestMatches(context, session)) return Error(HttpStatusCode.Conflict, "manifest_changed", "The manifest digest changed.");
            sessions.AuthorizeCompletion(sessionId, context.Request.Headers["X-Muse-Session-Token"].ToString());
            foreach (var item in session.Manifest.Items) await files.CommitAsync(sessionId, item, options.DestinationRoot, cancellationToken);
            sessions.Complete(sessionId);
            crypto.Remove(sessionId);
            return Results.Ok(new { status = "completed" });
        }
        catch (FileIntegrityException exception) { return Error(HttpStatusCode.Conflict, "hash_mismatch", exception.Message); }
        catch (SessionNotAcceptedException exception) { return Error(HttpStatusCode.Forbidden, "session_not_accepted", exception.Message); }
        catch (InvalidSessionTokenException exception) { return Error(HttpStatusCode.Unauthorized, "invalid_token", exception.Message); }
    }

    private static IResult GetStatus(HttpContext context, string sessionId, SessionManager sessions, ReceiverCryptoState crypto)
    {
        try
        {
            var decision = sessions.ReadDecision(sessionId, context.Request.Headers["X-Muse-Proposal-Key"].ToString());
            var status = new SessionStatusResponse(decision.Status.ToString().ToLowerInvariant(), decision.Token,
                decision.VerifiedChunks.ToDictionary(entry => entry.Key, entry => entry.Value.ToArray(), StringComparer.Ordinal));
            var envelope = TransferCrypto.Encrypt(crypto.Get(sessionId), JsonSerializer.SerializeToUtf8Bytes(status, JsonOptions), Encoding.UTF8.GetBytes($"status|{sessionId}"));
            return Results.Ok(new EncryptedStatusResponse(envelope));
        }
        catch (SessionNotFoundException exception) { return Error(HttpStatusCode.NotFound, "session_not_found", exception.Message); }
        catch (InvalidSessionTokenException exception) { return Error(HttpStatusCode.Unauthorized, "invalid_proposal_key", exception.Message); }
    }

    private static bool DigestMatches(HttpContext context, TransferSession session) => string.Equals(context.Request.Headers["X-Muse-Manifest-Digest"].ToString(), session.ManifestDigest, StringComparison.Ordinal);
    private static bool TryParseRange(string? value, out long start, out long end, out long total)
    {
        start = end = total = 0;
        if (value is null) return false;
        var match = ContentRangePattern().Match(value);
        return long.TryParse(match.Groups[1].Value, out start) && long.TryParse(match.Groups[2].Value, out end) && long.TryParse(match.Groups[3].Value, out total);
    }
    private static IResult Error(HttpStatusCode status, string code, string message) => Results.Json(new { code, message }, statusCode: (int)status);
    [GeneratedRegex("^bytes ([0-9]+)-([0-9]+)/([0-9]+)$", RegexOptions.CultureInvariant)] private static partial Regex ContentRangePattern();
}
