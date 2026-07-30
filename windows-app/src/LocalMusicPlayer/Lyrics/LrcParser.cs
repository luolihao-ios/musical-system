using System.Globalization;
using System.Text.RegularExpressions;

namespace LocalMusicPlayer.Lyrics;

public static partial class LrcParser
{
    public static IReadOnlyList<LyricLine> Parse(string source)
    {
        if (string.IsNullOrWhiteSpace(source))
        {
            return [];
        }

        var result = new List<LyricLine>();
        foreach (var rawLine in source.Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
        {
            var matches = TimestampRegex().Matches(rawLine);
            if (matches.Count == 0)
            {
                continue;
            }

            var text = TimestampRegex().Replace(rawLine, string.Empty).Trim();
            foreach (Match match in matches)
            {
                var minutes = int.Parse(match.Groups["m"].Value, CultureInfo.InvariantCulture);
                var seconds = int.Parse(match.Groups["s"].Value, CultureInfo.InvariantCulture);
                var fractionText = match.Groups["f"].Value;
                var milliseconds = fractionText.Length switch
                {
                    2 => int.Parse(fractionText, CultureInfo.InvariantCulture) * 10,
                    3 => int.Parse(fractionText, CultureInfo.InvariantCulture),
                    _ => 0,
                };
                result.Add(new LyricLine(
                    TimeSpan.FromMinutes(minutes)
                    + TimeSpan.FromSeconds(seconds)
                    + TimeSpan.FromMilliseconds(milliseconds),
                    text));
            }
        }

        return result.OrderBy(line => line.Timestamp).ToArray();
    }

    public static int FindCurrentLine(
        IReadOnlyList<LyricLine> lines,
        TimeSpan position)
    {
        var low = 0;
        var high = lines.Count - 1;
        var result = -1;
        while (low <= high)
        {
            var middle = low + ((high - low) / 2);
            if (lines[middle].Timestamp <= position)
            {
                result = middle;
                low = middle + 1;
            }
            else
            {
                high = middle - 1;
            }
        }

        return result;
    }

    [GeneratedRegex(
        @"\[(?<m>\d{1,3}):(?<s>\d{2})(?:\.(?<f>\d{2,3}))?\]",
        RegexOptions.CultureInvariant)]
    private static partial Regex TimestampRegex();
}
