using System.IO;

namespace LocalMusicPlayer.Lyrics;

public sealed class FileLyricsSource : ILyricsSource
{
    public string? Read(string path) =>
        File.Exists(path) ? File.ReadAllText(path) : null;
}
