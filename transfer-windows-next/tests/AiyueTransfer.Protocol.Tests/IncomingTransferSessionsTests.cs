using AiyueTransfer.Core;
using AiyueTransfer.Protocol;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class IncomingTransferSessionsTests
{
    [Fact]
    public void Session_MustBeAcceptedBeforeCompletion()
    {
        var sessions = new IncomingTransferSessions();
        var session = sessions.Propose(new DeviceInfo("iPhone", "2.0", "iPhone", "mobile", "fp", 53317, "http"), new Dictionary<string, FileMetadata> { ["f"] = new("f", "a.txt", 1, "text/plain") });
        Assert.Throws<InvalidOperationException>(() => sessions.Complete(session.Id));
        Assert.Equal(IncomingTransferStatus.Accepted, sessions.Accept(session.Id).Status);
        Assert.Equal(IncomingTransferStatus.Completed, sessions.Complete(session.Id).Status);
    }

    [Fact]
    public void RejectedSession_CannotBeAcceptedAgain()
    {
        var sessions = new IncomingTransferSessions();
        var session = sessions.Propose(new DeviceInfo("Windows", "2.0", "Windows", "desktop", "fp", 53317, "http"), new Dictionary<string, FileMetadata> { ["f"] = new("f", "a.txt", 1, "text/plain") });
        sessions.Reject(session.Id);
        Assert.Throws<InvalidOperationException>(() => sessions.Accept(session.Id));
    }
}
