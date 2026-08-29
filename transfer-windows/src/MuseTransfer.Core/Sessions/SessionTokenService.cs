using System.Security.Cryptography;
using System.Text.Json;

namespace MuseTransfer.Core.Sessions;

public sealed record SessionTokenClaims(
    string SessionId,
    string SenderId,
    string ManifestDigest,
    DateTimeOffset ExpiresAt,
    string Nonce);

public sealed class SessionTokenService
{
    private readonly byte[] key = RandomNumberGenerator.GetBytes(32);

    public string Issue(
        string sessionId,
        string senderId,
        string manifestDigest,
        DateTimeOffset expiresAt)
    {
        var claims = new SessionTokenClaims(
            sessionId,
            senderId,
            manifestDigest,
            expiresAt,
            Convert.ToHexString(RandomNumberGenerator.GetBytes(16)).ToLowerInvariant());
        var payload = JsonSerializer.SerializeToUtf8Bytes(claims, JsonOptions);
        var signature = HMACSHA256.HashData(key, payload);
        return $"{Base64UrlEncode(payload)}.{Base64UrlEncode(signature)}";
    }

    public bool TryValidate(string token, out SessionTokenClaims? claims)
    {
        claims = null;
        try
        {
            var parts = token.Split('.');
            if (parts.Length != 2)
            {
                return false;
            }

            var payload = Base64UrlDecode(parts[0]);
            var suppliedSignature = Base64UrlDecode(parts[1]);
            var expectedSignature = HMACSHA256.HashData(key, payload);
            if (!CryptographicOperations.FixedTimeEquals(expectedSignature, suppliedSignature))
            {
                return false;
            }

            claims = JsonSerializer.Deserialize<SessionTokenClaims>(payload, JsonOptions);
            return claims is not null;
        }
        catch (Exception exception) when (exception is FormatException or JsonException)
        {
            return false;
        }
    }

    private static string Base64UrlEncode(byte[] value) =>
        Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_');

    private static byte[] Base64UrlDecode(string value)
    {
        var padded = value.Replace('-', '+').Replace('_', '/');
        padded += new string('=', (4 - padded.Length % 4) % 4);
        return Convert.FromBase64String(padded);
    }

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);
}
