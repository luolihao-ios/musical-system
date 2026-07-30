using System.Collections.ObjectModel;
using System.Globalization;
using System.Text;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using LocalMusicPlayer.Data;
using LocalMusicPlayer.Domain;
using LocalMusicPlayer.Library;
using LocalMusicPlayer.Playback;

namespace LocalMusicPlayer.ViewModels;

public sealed class LibraryViewModel : ObservableObject
{
    private readonly ILibraryRepository _repository;
    private readonly ILibraryScanner _scanner;
    private readonly IPlaybackCommands _playback;
    private string _searchText = string.Empty;
    private bool _isScanning;
    private string _statusText = "选择一个本地音乐文件夹开始";

    public LibraryViewModel(
        ILibraryRepository repository,
        ILibraryScanner scanner,
        IPlaybackCommands playback)
    {
        _repository = repository;
        _scanner = scanner;
        _playback = playback;
        ToggleLikeCommand = new AsyncRelayCommand<Track>(ToggleLikeAsync);
        PlayCommand = new AsyncRelayCommand<Track>(PlayAsync);
    }

    public ObservableCollection<Track> Tracks { get; } = [];

    public ObservableCollection<Track> FilteredTracks { get; } = [];

    public IAsyncRelayCommand<Track> ToggleLikeCommand { get; }

    public IAsyncRelayCommand<Track> PlayCommand { get; }

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (SetProperty(ref _searchText, value))
            {
                ApplyFilter();
            }
        }
    }

    public bool IsScanning
    {
        get => _isScanning;
        private set => SetProperty(ref _isScanning, value);
    }

    public string StatusText
    {
        get => _statusText;
        private set => SetProperty(ref _statusText, value);
    }

    public async Task InitializeAsync(
        CancellationToken cancellationToken = default) =>
        await RefreshAsync(cancellationToken);

    public async Task AddFolderAsync(
        string path,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(path);
        IsScanning = true;
        StatusText = "正在扫描本地音乐…";
        try
        {
            var result = await _scanner.ScanAsync(path, cancellationToken);
            await RefreshAsync(cancellationToken);
            StatusText = $"扫描完成：收录 {result.Indexed} 首，跳过 {result.Failed} 个文件";
        }
        finally
        {
            IsScanning = false;
        }
    }

    public async Task ToggleLikeAsync(Track? track)
    {
        if (track is null)
        {
            return;
        }

        var updated = track with { IsLiked = !track.IsLiked };
        await _repository.SetLikedAsync(updated.Id, updated.IsLiked);
        ReplaceTrack(updated);
    }

    public async Task PlayAsync(Track? track)
    {
        if (track is null || !track.IsAvailable)
        {
            return;
        }

        var queue = FilteredTracks.Where(item => item.IsAvailable).ToArray();
        var startIndex = Array.FindIndex(queue, item => item.Id == track.Id);
        if (startIndex < 0)
        {
            return;
        }

        _playback.LoadQueue(queue, startIndex);
        await _playback.PlayAsync();
        await _repository.RecordPlayAsync(track.Id, DateTimeOffset.UtcNow);
    }

    private async Task RefreshAsync(CancellationToken cancellationToken)
    {
        var tracks = await _repository.GetTracksAsync(cancellationToken);
        Tracks.Clear();
        foreach (var track in tracks)
        {
            Tracks.Add(track);
        }

        ApplyFilter();
        StatusText = Tracks.Count == 0
            ? "还没有音乐，添加一个本地文件夹吧"
            : $"本地音乐 · {Tracks.Count} 首";
    }

    private void ReplaceTrack(Track updated)
    {
        var index = FindTrackIndex(Tracks, updated.Id);
        if (index >= 0)
        {
            Tracks[index] = updated;
        }

        ApplyFilter();
    }

    private void ApplyFilter()
    {
        var query = Fold(SearchText.Trim());
        FilteredTracks.Clear();
        foreach (var track in Tracks)
        {
            if (query.Length == 0
                || Fold(track.Title).Contains(query, StringComparison.Ordinal)
                || Fold(track.Artist).Contains(query, StringComparison.Ordinal)
                || Fold(track.Album).Contains(query, StringComparison.Ordinal))
            {
                FilteredTracks.Add(track);
            }
        }
    }

    private static int FindTrackIndex(
        IReadOnlyList<Track> tracks,
        string trackId)
    {
        for (var index = 0; index < tracks.Count; index++)
        {
            if (tracks[index].Id == trackId)
            {
                return index;
            }
        }

        return -1;
    }

    private static string Fold(string value)
    {
        var decomposed = value.Normalize(NormalizationForm.FormD);
        var builder = new StringBuilder(decomposed.Length);
        foreach (var character in decomposed)
        {
            if (CharUnicodeInfo.GetUnicodeCategory(character)
                != UnicodeCategory.NonSpacingMark)
            {
                builder.Append(char.ToLowerInvariant(character));
            }
        }

        return builder.ToString().Normalize(NormalizationForm.FormC);
    }
}
