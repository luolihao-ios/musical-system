using AiyueTransfer.Protocol;
using Xunit;

namespace AiyueTransfer.Protocol.Tests;

public sealed class TransferRoutesTests
{
    [Fact]
    public void Routes_UsePrivateAiYueV1Prefix()
    {
        Assert.Equal("/api/aiyue/v1/register", TransferRoutes.Register);
        Assert.Equal("/api/aiyue/v1/prepare-upload", TransferRoutes.PrepareUpload);
        Assert.Equal("/api/aiyue/v1/upload", TransferRoutes.Upload);
        Assert.Equal("/api/aiyue/v1/cancel", TransferRoutes.Cancel);
    }

    [Fact]
    public void Decision_RequiresExplicitBoolean()
    {
        var decision = new UploadDecision("session-1", false, "user_rejected");
        Assert.False(decision.Accepted);
        Assert.Equal("user_rejected", decision.Reason);
    }
}
