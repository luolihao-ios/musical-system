namespace LocalMusicPlayer.SystemMedia;

public sealed record SystemMediaState(
    string Title,
    string Artist,
    string Album,
    string? CoverPath,
    bool IsPlaying,
    TimeSpan Position,
    TimeSpan Duration)
{
    public static SystemMediaState Empty { get; } =
        new(string.Empty, string.Empty, string.Empty, null, false, TimeSpan.Zero, TimeSpan.Zero);
}
