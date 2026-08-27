using System.Security.Cryptography;
using System.Text.Json;

namespace MuseTransfer.Protocol;

public static class ManifestCanonicalizer
{
    public static byte[] Canonicalize(TransferManifest manifest)
    {
        ArgumentNullException.ThrowIfNull(manifest);
        if (manifest.ProtocolVersion != 1)
        {
            throw new NotSupportedException($"Protocol version {manifest.ProtocolVersion} is not supported.");
        }

        using var buffer = new MemoryStream();
        using (var writer = new Utf8JsonWriter(buffer, new JsonWriterOptions { Indented = false }))
        {
            writer.WriteStartObject();
            writer.WriteNumber("protocolVersion", manifest.ProtocolVersion);
            writer.WriteString("senderId", manifest.SenderId);
            writer.WriteStartArray("items");
            foreach (var item in manifest.Items)
            {
                writer.WriteStartObject();
                writer.WriteString("id", item.Id);
                writer.WriteString("relativePath", item.RelativePath);
                writer.WriteNumber("size", item.Size);
                writer.WriteString("sha256", item.Sha256);
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
            writer.WriteStartArray("musicGroups");
            foreach (var group in manifest.MusicGroups)
            {
                writer.WriteStartObject();
                writer.WriteString("id", group.Id);
                writer.WriteStartArray("itemIds");
                foreach (var itemId in group.ItemIds)
                {
                    writer.WriteStringValue(itemId);
                }
                writer.WriteEndArray();
                writer.WriteEndObject();
            }
            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        return buffer.ToArray();
    }

    public static string ComputeSha256(TransferManifest manifest) =>
        Convert.ToHexString(SHA256.HashData(Canonicalize(manifest))).ToLowerInvariant();
}
