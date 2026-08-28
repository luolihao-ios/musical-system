using MuseTransfer.Protocol;

namespace MuseTransfer.Core.Sessions;

public enum TransferSessionStatus
{
    Pending,
    Accepted,
    Rejected,
    Transferring,
    Completed,
    Failed,
    Cancelled
}

public sealed class TransferSession
{
    internal TransferSession(
        string id,
        TransferManifest manifest,
        string manifestDigest,
        string remoteEndpoint,
        string verificationCode,
        string proposalKey,
        DateTimeOffset createdAt)
    {
        Id = id;
        Manifest = manifest;
        ManifestDigest = manifestDigest;
        RemoteEndpoint = remoteEndpoint;
        VerificationCode = verificationCode;
        ProposalKey = proposalKey;
        CreatedAt = createdAt;
    }

    public string Id { get; }
    public TransferManifest Manifest { get; }
    public string ManifestDigest { get; }
    public string RemoteEndpoint { get; }
    public string VerificationCode { get; }
    public string ProposalKey { get; }
    public DateTimeOffset CreatedAt { get; }
    public DateTimeOffset? AuthorizationExpiresAt { get; internal set; }
    public TransferSessionStatus Status { get; internal set; } = TransferSessionStatus.Pending;
    internal string? AcceptedToken { get; set; }

    internal Dictionary<string, SortedSet<int>> VerifiedChunks { get; } = new(StringComparer.Ordinal);
}

public sealed record AcceptedSession(TransferSession Session, string Token);
public sealed record SessionDecision(TransferSessionStatus Status, string? Token, IReadOnlyDictionary<string, IReadOnlyList<int>> VerifiedChunks);

public sealed class SessionNotFoundException(string id) : KeyNotFoundException($"Transfer session '{id}' was not found.");
public sealed class SessionNotAcceptedException() : InvalidOperationException("The receiver has not accepted this session.");
public sealed class InvalidSessionTransitionException() : InvalidOperationException("The requested session state transition is not allowed.");
public sealed class InvalidSessionTokenException() : UnauthorizedAccessException("The session token is invalid.");
public sealed class SessionExpiredException() : UnauthorizedAccessException("The session authorization has expired.");
