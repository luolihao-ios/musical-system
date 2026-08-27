namespace MuseTransfer.Core.Files;

public sealed class UnsafePathException(string path)
    : ArgumentException($"The path '{path}' is not a safe relative path.", nameof(path));

public sealed record SafeRelativePath
{
    private static readonly HashSet<string> ReservedNames = new(StringComparer.OrdinalIgnoreCase)
    {
        "CON", "PRN", "AUX", "NUL",
        "COM1", "COM2", "COM3", "COM4", "COM5", "COM6", "COM7", "COM8", "COM9",
        "LPT1", "LPT2", "LPT3", "LPT4", "LPT5", "LPT6", "LPT7", "LPT8", "LPT9"
    };

    private SafeRelativePath(string value) => Value = value;

    public string Value { get; }

    public static SafeRelativePath Parse(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || Path.IsPathRooted(path))
        {
            throw new UnsafePathException(path);
        }

        var normalized = path.Replace('\\', '/');
        var segments = normalized.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (segments.Length == 0 || segments.Any(IsUnsafeSegment))
        {
            throw new UnsafePathException(path);
        }

        return new SafeRelativePath(string.Join(Path.DirectorySeparatorChar, segments));
    }

    public string ResolveBelow(string root)
    {
        var fullRoot = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
        var candidate = Path.GetFullPath(Path.Combine(fullRoot, Value));
        if (!candidate.StartsWith(fullRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new UnsafePathException(Value);
        }

        return candidate;
    }

    private static bool IsUnsafeSegment(string segment)
    {
        if (segment is "." or ".." || segment.EndsWith(' ') || segment.EndsWith('.'))
        {
            return true;
        }

        var stem = Path.GetFileNameWithoutExtension(segment);
        return ReservedNames.Contains(stem) || segment.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0;
    }
}
