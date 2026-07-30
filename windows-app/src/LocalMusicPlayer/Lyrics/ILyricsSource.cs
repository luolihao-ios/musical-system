namespace LocalMusicPlayer.Lyrics;

public interface ILyricsSource
{
    string? Read(string path);
}
