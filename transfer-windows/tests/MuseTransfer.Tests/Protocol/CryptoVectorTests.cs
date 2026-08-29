using System.Text.Json;
using MuseTransfer.Protocol;

namespace MuseTransfer.Tests.Protocol;

public sealed class CryptoVectorTests
{
    [Fact]
    public void P256_HKDF_AESGCM_and_verification_code_match_shared_vector()
    {
        var vector = LoadVector();
        using var receiver = P256KeyPair.FromPrivateScalar(Convert.FromBase64String(vector.ReceiverPrivate));
        using var sender = P256KeyPair.FromPrivateScalar(Convert.FromBase64String(vector.SenderPrivate));

        Assert.Equal(vector.ReceiverPublic, Convert.ToBase64String(receiver.PublicKeyX963));
        Assert.Equal(vector.SenderPublic, Convert.ToBase64String(sender.PublicKeyX963));

        var key = TransferCrypto.DeriveSessionKey(sender, receiver.PublicKeyX963, receiver.PublicKeyX963, sender.PublicKeyX963);
        Assert.Equal(vector.DerivedKey, Convert.ToBase64String(key));
        var envelope = TransferCrypto.Encrypt(
            key,
            Convert.FromBase64String(vector.Plaintext),
            Convert.FromBase64String(vector.AssociatedData),
            Convert.FromBase64String(vector.Nonce));

        Assert.Equal(vector.Ciphertext, Convert.ToBase64String(envelope.Ciphertext));
        Assert.Equal(vector.Tag, Convert.ToBase64String(envelope.Tag));
        Assert.Equal(Convert.FromBase64String(vector.Plaintext), TransferCrypto.Decrypt(key, envelope, Convert.FromBase64String(vector.AssociatedData)));
        Assert.Equal(vector.VerificationCode, TransferCrypto.VerificationCode(key, "manifest-digest"));
    }

    private static CryptoVector LoadVector()
    {
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            var path = Path.Combine(directory.FullName, "docs", "transfer-protocol", "vectors", "crypto-v2.json");
            if (File.Exists(path)) return JsonSerializer.Deserialize<CryptoVector>(File.ReadAllText(path), new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
            directory = directory.Parent;
        }
        throw new FileNotFoundException("Could not locate crypto-v2.json.");
    }

    private sealed record CryptoVector(
        string ReceiverPrivate, string ReceiverPublic, string SenderPrivate, string SenderPublic,
        string Salt, string DerivedKey, string Nonce, string Plaintext, string AssociatedData,
        string Ciphertext, string Tag, string VerificationCode);
}
