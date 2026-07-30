namespace LocalMusicPlayer.Library;

public sealed record ScanResult(
    int Discovered,
    int Indexed,
    int Failed,
    int MarkedUnavailable);
