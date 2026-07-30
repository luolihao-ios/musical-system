using FluentAssertions;
using LocalMusicPlayer.Lyrics;

namespace LocalMusicPlayer.Tests.Lyrics;

public sealed class LrcParserTests
{
    [Fact]
    public void Parse_SupportsMultipleTimestampsAndFractionPrecisions()
    {
        const string source = """
            [ar:雾岛乐队]
            [01:02.34][02:03.456]风从城市尽头吹来
            [00:05]序章
            """;

        var lines = LrcParser.Parse(source);

        lines.Should().Equal(
            new LyricLine(TimeSpan.FromSeconds(5), "序章"),
            new LyricLine(TimeSpan.FromMinutes(1) + TimeSpan.FromSeconds(2.34), "风从城市尽头吹来"),
            new LyricLine(TimeSpan.FromMinutes(2) + TimeSpan.FromSeconds(3.456), "风从城市尽头吹来"));
    }

    [Fact]
    public void Parse_IgnoresMalformedAndMetadataLines()
    {
        const string source = """
            [ti:城市夜行]
            ordinary text
            [00:not-a-time]broken
            """;

        LrcParser.Parse(source).Should().BeEmpty();
    }

    [Theory]
    [InlineData(0.0, -1)]
    [InlineData(1.0, 0)]
    [InlineData(2.99, 0)]
    [InlineData(3.0, 1)]
    [InlineData(99.0, 1)]
    public void FindCurrentLine_ReturnsLatestElapsedTimestamp(double seconds, int expected)
    {
        var lines = new[]
        {
            new LyricLine(TimeSpan.FromSeconds(1), "第一句"),
            new LyricLine(TimeSpan.FromSeconds(3), "第二句"),
        };

        LrcParser.FindCurrentLine(lines, TimeSpan.FromSeconds(seconds)).Should().Be(expected);
    }
}
