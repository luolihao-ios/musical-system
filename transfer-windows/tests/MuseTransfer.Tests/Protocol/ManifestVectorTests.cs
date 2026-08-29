using System.Text;
using System.Text.Json;
using MuseTransfer.Protocol;

namespace MuseTransfer.Tests.Protocol;

public sealed class ManifestVectorTests
{
    [Fact]
    public void Canonicalize_matches_shared_protocol_vector()
    {
        var vector = LoadVector();

        var canonical = ManifestCanonicalizer.Canonicalize(vector.Manifest);

        Assert.Equal(vector.CanonicalUtf8, Encoding.UTF8.GetString(canonical));
        Assert.Equal(vector.CanonicalSha256, ManifestCanonicalizer.ComputeSha256(vector.Manifest));
    }

    private static ManifestVector LoadVector()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var candidate = Path.Combine(directory.FullName, "docs", "transfer-protocol", "vectors", "manifest-v2.json");
            if (File.Exists(candidate))
            {
                return JsonSerializer.Deserialize<ManifestVector>(File.ReadAllText(candidate), JsonOptions)
                    ?? throw new InvalidDataException("Manifest vector is empty.");
            }

            directory = directory.Parent;
        }

        throw new FileNotFoundException("Could not locate manifest-v2.json from the test output directory.");
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private sealed record ManifestVector(
        TransferManifest Manifest,
        string CanonicalUtf8,
        string CanonicalSha256);
}
