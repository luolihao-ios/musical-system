using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;

namespace MuseTransfer.Protocol;

public sealed class P256KeyPair : IDisposable
{
    private readonly ECDiffieHellman key;

    private P256KeyPair(ECDiffieHellman key) => this.key = key;

    public byte[] PublicKeyX963
    {
        get
        {
            var parameters = key.ExportParameters(false);
            return [0x04, .. parameters.Q.X!, .. parameters.Q.Y!];
        }
    }

    public static P256KeyPair Generate() => new(ECDiffieHellman.Create(ECCurve.NamedCurves.nistP256));

    public static P256KeyPair FromPrivateScalar(byte[] privateScalar) =>
        new(ECDiffieHellman.Create(new ECParameters { Curve = ECCurve.NamedCurves.nistP256, D = privateScalar }));

    internal byte[] DeriveRawSecret(byte[] remotePublicKey)
    {
        using var remote = ECDiffieHellman.Create(TransferCrypto.ImportPublicParameters(remotePublicKey));
        return key.DeriveRawSecretAgreement(remote.PublicKey);
    }

    public void Dispose() => key.Dispose();
}

public sealed record EncryptedEnvelope(byte[] Nonce, byte[] Ciphertext, byte[] Tag);

public static class TransferCrypto
{
    private static readonly byte[] HkdfInfo = "muse-transfer-v2"u8.ToArray();

    public static byte[] DeriveSessionKey(P256KeyPair localKey, byte[] remotePublicKey, byte[] receiverPublicKey, byte[] senderPublicKey)
    {
        var secret = localKey.DeriveRawSecret(remotePublicKey);
        var salt = SHA256.HashData([.. receiverPublicKey, .. senderPublicKey]);
        try
        {
            return HKDF.DeriveKey(HashAlgorithmName.SHA256, secret, 32, salt, HkdfInfo);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(secret);
        }
    }

    public static EncryptedEnvelope Encrypt(byte[] key, byte[] plaintext, byte[] associatedData, byte[]? nonce = null)
    {
        nonce ??= RandomNumberGenerator.GetBytes(12);
        if (nonce.Length != 12) throw new ArgumentException("AES-GCM nonce must be 12 bytes.", nameof(nonce));
        var ciphertext = new byte[plaintext.Length];
        var tag = new byte[16];
        using var aes = new AesGcm(key, 16);
        aes.Encrypt(nonce, plaintext, ciphertext, tag, associatedData);
        return new EncryptedEnvelope(nonce, ciphertext, tag);
    }

    public static byte[] Decrypt(byte[] key, EncryptedEnvelope envelope, byte[] associatedData)
    {
        var plaintext = new byte[envelope.Ciphertext.Length];
        using var aes = new AesGcm(key, 16);
        aes.Decrypt(envelope.Nonce, envelope.Ciphertext, envelope.Tag, plaintext, associatedData);
        return plaintext;
    }

    public static byte[] PackEnvelope(EncryptedEnvelope envelope)
    {
        if (envelope.Nonce.Length != 12 || envelope.Tag.Length != 16) throw new CryptographicException("Invalid AES-GCM envelope sizes.");
        return [.. envelope.Nonce, .. envelope.Tag, .. envelope.Ciphertext];
    }

    public static EncryptedEnvelope UnpackEnvelope(byte[] packed)
    {
        if (packed.Length < 28) throw new CryptographicException("Encrypted envelope is truncated.");
        return new EncryptedEnvelope(packed[..12], packed[28..], packed[12..28]);
    }

    public static string VerificationCode(byte[] sessionKey, string manifestDigest)
    {
        var digest = HMACSHA256.HashData(sessionKey, Encoding.UTF8.GetBytes(manifestDigest));
        return (BinaryPrimitives.ReadUInt32LittleEndian(digest) % 1_000_000).ToString("D6");
    }

    internal static ECParameters ImportPublicParameters(byte[] publicKey)
    {
        if (publicKey.Length != 65 || publicKey[0] != 0x04) throw new CryptographicException("P-256 public key must use 65-byte X9.63 uncompressed form.");
        return new ECParameters
        {
            Curve = ECCurve.NamedCurves.nistP256,
            Q = new ECPoint { X = publicKey[1..33], Y = publicKey[33..65] }
        };
    }
}
