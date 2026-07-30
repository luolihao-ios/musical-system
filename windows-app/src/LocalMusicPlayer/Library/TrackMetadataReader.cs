using System.IO;
using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.Library;

public sealed class TrackMetadataReader(string coverCacheDirectory) : ITrackMetadataReader
{
    public async Task<Track> ReadAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        var id = await TrackIdentity.CreateAsync(path, cancellationToken);
        using var file = TagLib.File.Create(path);
        var title = string.IsNullOrWhiteSpace(file.Tag.Title)
            ? Path.GetFileNameWithoutExtension(path)
            : file.Tag.Title.Trim();
        var artist = file.Tag.Performers.FirstOrDefault()?.Trim() ?? string.Empty;
        var album = file.Tag.Album?.Trim() ?? string.Empty;
        var lyricsPath = Path.ChangeExtension(path, ".lrc");
        var coverPath = await CacheCoverAsync(id, file.Tag.Pictures.FirstOrDefault(), cancellationToken);

        return new Track(
            id,
            Path.GetFullPath(path),
            title,
            artist,
            album,
            file.Properties.Duration,
            coverPath,
            File.Exists(lyricsPath) ? lyricsPath : null,
            false,
            true,
            null);
    }

    private async Task<string?> CacheCoverAsync(
        string trackId,
        TagLib.IPicture? picture,
        CancellationToken cancellationToken)
    {
        if (picture is null || picture.Data.Count == 0)
        {
            return null;
        }

        Directory.CreateDirectory(coverCacheDirectory);
        var extension = picture.MimeType.Contains("png", StringComparison.OrdinalIgnoreCase)
            ? ".png"
            : ".jpg";
        var path = Path.Combine(coverCacheDirectory, trackId + extension);
        if (!File.Exists(path))
        {
            await File.WriteAllBytesAsync(path, picture.Data.Data, cancellationToken);
        }

        return path;
    }
}
