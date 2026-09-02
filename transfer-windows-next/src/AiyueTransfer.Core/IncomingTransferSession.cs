using AiyueTransfer.Protocol;

namespace AiyueTransfer.Core;

public enum IncomingTransferStatus { Pending, Accepted, Rejected, Cancelled, Completed }

public sealed record IncomingTransferSession(string Id, DeviceInfo Sender, IReadOnlyDictionary<string, FileMetadata> Files, IncomingTransferStatus Status);

public sealed class IncomingTransferSessions
{
    private readonly Dictionary<string, IncomingTransferSession> sessions = new(StringComparer.Ordinal);

    public IncomingTransferSession Propose(DeviceInfo sender, IReadOnlyDictionary<string, FileMetadata> files)
    {
        if (files.Count == 0) throw new InvalidDataException("传输请求没有文件。");
        var session = new IncomingTransferSession(Guid.NewGuid().ToString("N"), sender, files, IncomingTransferStatus.Pending);
        sessions.Add(session.Id, session);
        return session;
    }

    public IncomingTransferSession Accept(string id) => SetStatus(id, IncomingTransferStatus.Pending, IncomingTransferStatus.Accepted);
    public IncomingTransferSession Reject(string id) => SetStatus(id, IncomingTransferStatus.Pending, IncomingTransferStatus.Rejected);
    public IncomingTransferSession Cancel(string id) => SetStatus(id, IncomingTransferStatus.Accepted, IncomingTransferStatus.Cancelled);
    public IncomingTransferSession Complete(string id) => SetStatus(id, IncomingTransferStatus.Accepted, IncomingTransferStatus.Completed);

    private IncomingTransferSession SetStatus(string id, IncomingTransferStatus expected, IncomingTransferStatus next)
    {
        if (!sessions.TryGetValue(id, out var current)) throw new KeyNotFoundException("传输会话不存在。");
        if (current.Status != expected) throw new InvalidOperationException($"传输状态 {current.Status} 不能变更为 {next}。");
        var updated = current with { Status = next }; sessions[id] = updated; return updated;
    }
}
