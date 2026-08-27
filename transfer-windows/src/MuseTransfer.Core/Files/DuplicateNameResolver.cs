namespace MuseTransfer.Core.Files;

public sealed class DuplicateNameResolver(string destinationRoot)
{
    public string Resolve(string relativePath)
    {
        var safePath = SafeRelativePath.Parse(relativePath);
        if (!File.Exists(safePath.ResolveBelow(destinationRoot)))
        {
            return safePath.Value;
        }

        var directory = Path.GetDirectoryName(safePath.Value) ?? string.Empty;
        var name = Path.GetFileNameWithoutExtension(safePath.Value);
        var extension = Path.GetExtension(safePath.Value);
        for (var copy = 2; ; copy++)
        {
            var candidate = Path.Combine(directory, $"{name} ({copy}){extension}");
            if (!File.Exists(SafeRelativePath.Parse(candidate).ResolveBelow(destinationRoot)))
            {
                return candidate;
            }
        }
    }
}
