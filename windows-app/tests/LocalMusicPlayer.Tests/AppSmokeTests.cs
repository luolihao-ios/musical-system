using FluentAssertions;

namespace LocalMusicPlayer.Tests;

public sealed class AppSmokeTests
{
    [Fact]
    public void DisplayName_UsesProductName()
    {
        AppInfo.DisplayName.Should().Be("暮色音乐");
    }
}
