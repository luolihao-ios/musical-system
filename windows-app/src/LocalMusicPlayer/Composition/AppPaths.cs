using System.IO;

namespace LocalMusicPlayer.Composition;

public sealed record AppPaths(
    string DataDirectory,
    string DatabasePath,
    string CoverCacheDirectory)
{
    public static AppPaths ForCurrentUser()
    {
        var localAppData = Environment.GetFolderPath(
            Environment.SpecialFolder.LocalApplicationData);
        var dataDirectory = Path.Combine(
            localAppData,
            "luolihao",
            "LocalMusicPlayer");
        return new AppPaths(
            dataDirectory,
            Path.Combine(dataDirectory, "library.db"),
            Path.Combine(dataDirectory, "covers"));
    }
}
