namespace MuseTransfer.Protocol;

public sealed record TransferItem(
    string Id,
    string RelativePath,
    long Size,
    string Sha256);

public sealed record MusicGroup(
    string Id,
    IReadOnlyList<string> ItemIds);

public sealed record TransferManifest(
    int ProtocolVersion,
    string SenderId,
    IReadOnlyList<TransferItem> Items,
    IReadOnlyList<MusicGroup> MusicGroups);
