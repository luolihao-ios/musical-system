using System.Collections.Concurrent;
using MuseTransfer.Protocol;

namespace MuseTransfer.App.Networking;

public sealed class ReceiverCryptoState : IDisposable
{
    private readonly P256KeyPair receiverKey = P256KeyPair.Generate();
    private readonly ConcurrentDictionary<string, byte[]> sessionKeys = new(StringComparer.Ordinal);

    public byte[] PublicKey => receiverKey.PublicKeyX963;

    public byte[] DeriveForSender(byte[] senderPublicKey) =>
        TransferCrypto.DeriveSessionKey(receiverKey, senderPublicKey, PublicKey, senderPublicKey);

    public void Store(string sessionId, byte[] key) => sessionKeys[sessionId] = key;
    public byte[] Get(string sessionId) => sessionKeys.TryGetValue(sessionId, out var key) ? key : throw new KeyNotFoundException("Session encryption key was not found.");
    public void Remove(string sessionId) { if (sessionKeys.TryRemove(sessionId, out var key)) System.Security.Cryptography.CryptographicOperations.ZeroMemory(key); }

    public void Dispose()
    {
        foreach (var id in sessionKeys.Keys) Remove(id);
        receiverKey.Dispose();
    }
}
