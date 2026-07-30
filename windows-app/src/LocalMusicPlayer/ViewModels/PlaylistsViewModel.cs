using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using LocalMusicPlayer.Data;
using LocalMusicPlayer.Domain;

namespace LocalMusicPlayer.ViewModels;

public sealed class PlaylistsViewModel : ObservableObject
{
    private readonly ILibraryRepository _repository;
    private string _newPlaylistName = string.Empty;
    private string _renameText = string.Empty;
    private Playlist? _selectedPlaylist;

    public PlaylistsViewModel(ILibraryRepository repository)
    {
        _repository = repository;
        CreateCommand = new AsyncRelayCommand(CreateFromInputAsync);
        DeleteCommand = new AsyncRelayCommand<Playlist>(DeleteFromCommandAsync);
        RenameCommand = new AsyncRelayCommand(RenameSelectedAsync);
    }

    public ObservableCollection<Playlist> Playlists { get; } = [];

    public IAsyncRelayCommand CreateCommand { get; }

    public IAsyncRelayCommand<Playlist> DeleteCommand { get; }

    public IAsyncRelayCommand RenameCommand { get; }

    public string NewPlaylistName
    {
        get => _newPlaylistName;
        set => SetProperty(ref _newPlaylistName, value);
    }

    public Playlist? SelectedPlaylist
    {
        get => _selectedPlaylist;
        set
        {
            if (SetProperty(ref _selectedPlaylist, value))
            {
                RenameText = value?.Name ?? string.Empty;
            }
        }
    }

    public string RenameText
    {
        get => _renameText;
        set => SetProperty(ref _renameText, value);
    }

    public async Task InitializeAsync(
        CancellationToken cancellationToken = default)
    {
        var playlists = await _repository.GetPlaylistsAsync(cancellationToken);
        Playlists.Clear();
        foreach (var playlist in playlists)
        {
            Playlists.Add(playlist);
        }

        SelectedPlaylist ??= Playlists.FirstOrDefault();
    }

    public async Task<Playlist> CreateAsync(
        string name,
        CancellationToken cancellationToken = default)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(name);
        var playlist = await _repository.CreatePlaylistAsync(
            name.Trim(),
            cancellationToken);
        Playlists.Add(playlist);
        SelectedPlaylist = playlist;
        return playlist;
    }

    public async Task<bool> RenameAsync(
        Playlist playlist,
        string name,
        CancellationToken cancellationToken = default)
    {
        if (playlist.IsBuiltIn || string.IsNullOrWhiteSpace(name))
        {
            return false;
        }

        var trimmed = name.Trim();
        if (!await _repository.RenamePlaylistAsync(
            playlist.Id,
            trimmed,
            cancellationToken))
        {
            return false;
        }

        var updated = playlist with { Name = trimmed };
        ReplacePlaylist(updated);
        return true;
    }

    public async Task<bool> DeleteAsync(
        Playlist playlist,
        CancellationToken cancellationToken = default)
    {
        if (playlist.IsBuiltIn
            || !await _repository.DeletePlaylistAsync(
                playlist.Id,
                cancellationToken))
        {
            return false;
        }

        Playlists.Remove(playlist);
        SelectedPlaylist = Playlists.FirstOrDefault();
        return true;
    }

    private async Task CreateFromInputAsync()
    {
        if (string.IsNullOrWhiteSpace(NewPlaylistName))
        {
            return;
        }

        await CreateAsync(NewPlaylistName);
        NewPlaylistName = string.Empty;
    }

    private async Task DeleteFromCommandAsync(Playlist? playlist)
    {
        if (playlist is not null)
        {
            await DeleteAsync(playlist);
        }
    }

    private async Task RenameSelectedAsync()
    {
        if (SelectedPlaylist is not null)
        {
            await RenameAsync(SelectedPlaylist, RenameText);
        }
    }

    private void ReplacePlaylist(Playlist playlist)
    {
        for (var index = 0; index < Playlists.Count; index++)
        {
            if (Playlists[index].Id != playlist.Id)
            {
                continue;
            }

            Playlists[index] = playlist;
            if (SelectedPlaylist?.Id == playlist.Id)
            {
                SelectedPlaylist = playlist;
            }

            return;
        }
    }
}
