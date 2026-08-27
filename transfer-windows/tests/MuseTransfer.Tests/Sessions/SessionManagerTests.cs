using MuseTransfer.Core.Sessions;
using MuseTransfer.Protocol;

namespace MuseTransfer.Tests.Sessions;

public sealed class SessionManagerTests
{
    private readonly MutableTimeProvider clock = new(new DateTimeOffset(2026, 8, 28, 0, 0, 0, TimeSpan.Zero));

    [Fact]
    public void Pending_session_rejects_file_chunks()
    {
        var manager = CreateManager();
        var proposal = manager.Propose(Manifest(), "192.168.1.2");

        Assert.Equal(TransferSessionStatus.Pending, proposal.Status);
        Assert.Matches("^[0-9]{6}$", proposal.VerificationCode);
        Assert.Throws<SessionNotAcceptedException>(() =>
            manager.AuthorizeChunk(proposal.Id, "invalid", "f1", 0));
    }

    [Fact]
    public void Rejected_session_cannot_be_accepted_later()
    {
        var manager = CreateManager();
        var proposal = manager.Propose(Manifest(), "192.168.1.2");
        manager.Reject(proposal.Id);

        Assert.Throws<InvalidSessionTransitionException>(() => manager.Accept(proposal.Id));
    }

    [Fact]
    public void Accepted_token_is_bound_to_sender_and_manifest()
    {
        var manager = CreateManager();
        var proposal = manager.Propose(Manifest(), "192.168.1.2");
        var acceptance = manager.Accept(proposal.Id);

        manager.AuthorizeChunk(proposal.Id, acceptance.Token, "f1", 0);
        Assert.Equal(TransferSessionStatus.Transferring, manager.Get(proposal.Id).Status);

        Assert.Throws<InvalidSessionTokenException>(() =>
            manager.AuthorizeChunk(proposal.Id, acceptance.Token + "changed", "f1", 1));
    }

    [Fact]
    public void Token_expires_after_five_minutes()
    {
        var manager = CreateManager();
        var proposal = manager.Propose(Manifest(), "192.168.1.2");
        var acceptance = manager.Accept(proposal.Id);
        clock.Advance(TimeSpan.FromMinutes(5).Add(TimeSpan.FromTicks(1)));

        Assert.Throws<SessionExpiredException>(() =>
            manager.AuthorizeChunk(proposal.Id, acceptance.Token, "f1", 0));
    }

    [Fact]
    public void Token_does_not_survive_a_new_token_service_instance()
    {
        var original = CreateManager();
        var proposal = original.Propose(Manifest(), "192.168.1.2");
        var acceptance = original.Accept(proposal.Id);
        var restarted = new SessionManager(clock, new SessionTokenService());
        restarted.RestoreWithoutAuthorization(proposal);

        Assert.Throws<InvalidSessionTokenException>(() =>
            restarted.AuthorizeChunk(proposal.Id, acceptance.Token, "f1", 0));
    }

    [Fact]
    public void Resume_map_contains_only_chunks_recorded_as_verified()
    {
        var manager = CreateManager();
        var proposal = manager.Propose(Manifest(), "192.168.1.2");
        var acceptance = manager.Accept(proposal.Id);
        manager.AuthorizeChunk(proposal.Id, acceptance.Token, "f1", 0);
        manager.RecordVerifiedChunk(proposal.Id, "f1", 0);
        manager.AuthorizeChunk(proposal.Id, acceptance.Token, "f1", 1);

        var resume = manager.GetResumeMap(proposal.Id);

        Assert.Equal([0], resume["f1"]);
    }

    private SessionManager CreateManager() => new(clock, new SessionTokenService());

    private static TransferManifest Manifest() => new(
        1,
        "sender-a",
        [new TransferItem("f1", "song.mp3", 3, new string('a', 64))],
        []);

    private sealed class MutableTimeProvider(DateTimeOffset now) : TimeProvider
    {
        private DateTimeOffset current = now;
        public override DateTimeOffset GetUtcNow() => current;
        public void Advance(TimeSpan duration) => current += duration;
    }
}
