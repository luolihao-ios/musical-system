using System.Security.Cryptography;
using MuseTransfer.Protocol;

namespace MuseTransfer.Core.Sessions;

public sealed class SessionManager(
    TimeProvider clock,
    SessionTokenService tokenService)
{
    private static readonly TimeSpan AuthorizationLifetime = TimeSpan.FromMinutes(5);
    private readonly Dictionary<string, TransferSession> sessions = new(StringComparer.Ordinal);

    public TransferSession Propose(TransferManifest manifest, string remoteEndpoint)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        if (manifest.Items.Count > 10_000)
        {
            throw new ArgumentOutOfRangeException(nameof(manifest), "A manifest may contain at most 10,000 files.");
        }

        var session = new TransferSession(
            Guid.NewGuid().ToString("N"),
            manifest,
            ManifestCanonicalizer.ComputeSha256(manifest),
            remoteEndpoint,
            RandomNumberGenerator.GetInt32(0, 1_000_000).ToString("D6"),
            clock.GetUtcNow());
        sessions.Add(session.Id, session);
        return session;
    }

    public AcceptedSession Accept(string sessionId)
    {
        var session = Get(sessionId);
        Transition(session, TransferSessionStatus.Accepted);
        session.AuthorizationExpiresAt = clock.GetUtcNow() + AuthorizationLifetime;
        var token = tokenService.Issue(
            session.Id,
            session.Manifest.SenderId,
            session.ManifestDigest,
            session.AuthorizationExpiresAt.Value);
        return new AcceptedSession(session, token);
    }

    public void Reject(string sessionId) => Transition(Get(sessionId), TransferSessionStatus.Rejected);

    public void Cancel(string sessionId) => Transition(Get(sessionId), TransferSessionStatus.Cancelled);

    public void AuthorizeChunk(string sessionId, string token, string fileId, int chunkIndex)
    {
        var session = Get(sessionId);
        if (session.Status is not TransferSessionStatus.Accepted and not TransferSessionStatus.Transferring)
        {
            throw new SessionNotAcceptedException();
        }

        if (session.AuthorizationExpiresAt is null || clock.GetUtcNow() > session.AuthorizationExpiresAt.Value)
        {
            throw new SessionExpiredException();
        }

        if (!tokenService.TryValidate(token, out var claims)
            || claims is null
            || claims.SessionId != session.Id
            || claims.SenderId != session.Manifest.SenderId
            || claims.ManifestDigest != session.ManifestDigest
            || claims.ExpiresAt != session.AuthorizationExpiresAt)
        {
            throw new InvalidSessionTokenException();
        }

        if (chunkIndex < 0 || !session.Manifest.Items.Any(item => item.Id == fileId))
        {
            throw new ArgumentOutOfRangeException(nameof(chunkIndex), "The file or chunk index is not in the manifest.");
        }

        if (session.Status == TransferSessionStatus.Accepted)
        {
            Transition(session, TransferSessionStatus.Transferring);
        }
    }

    public void RecordVerifiedChunk(string sessionId, string fileId, int chunkIndex)
    {
        var session = Get(sessionId);
        if (session.Status != TransferSessionStatus.Transferring)
        {
            throw new SessionNotAcceptedException();
        }

        if (!session.VerifiedChunks.TryGetValue(fileId, out var chunks))
        {
            chunks = [];
            session.VerifiedChunks.Add(fileId, chunks);
        }

        chunks.Add(chunkIndex);
    }

    public IReadOnlyDictionary<string, IReadOnlyList<int>> GetResumeMap(string sessionId) =>
        Get(sessionId).VerifiedChunks.ToDictionary(
            entry => entry.Key,
            entry => (IReadOnlyList<int>)entry.Value.ToArray(),
            StringComparer.Ordinal);

    public TransferSession Get(string sessionId) =>
        sessions.TryGetValue(sessionId, out var session)
            ? session
            : throw new SessionNotFoundException(sessionId);

    public void RestoreWithoutAuthorization(TransferSession persistedSession)
    {
        var restored = new TransferSession(
            persistedSession.Id,
            persistedSession.Manifest,
            persistedSession.ManifestDigest,
            persistedSession.RemoteEndpoint,
            persistedSession.VerificationCode,
            persistedSession.CreatedAt)
        {
            Status = persistedSession.Status,
            AuthorizationExpiresAt = persistedSession.AuthorizationExpiresAt
        };
        sessions.Add(restored.Id, restored);
    }

    private static void Transition(TransferSession session, TransferSessionStatus target)
    {
        var allowed = session.Status switch
        {
            TransferSessionStatus.Pending => target is TransferSessionStatus.Accepted or TransferSessionStatus.Rejected or TransferSessionStatus.Cancelled,
            TransferSessionStatus.Accepted => target is TransferSessionStatus.Transferring or TransferSessionStatus.Cancelled or TransferSessionStatus.Failed,
            TransferSessionStatus.Transferring => target is TransferSessionStatus.Completed or TransferSessionStatus.Cancelled or TransferSessionStatus.Failed,
            _ => false
        };

        if (!allowed)
        {
            throw new InvalidSessionTransitionException();
        }

        session.Status = target;
    }
}
