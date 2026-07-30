using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Views;

public partial class SyncedLyricsView : UserControl
{
    public SyncedLyricsView()
    {
        InitializeComponent();
        DataContextChanged += HandleDataContextChanged;
        Unloaded += HandleUnloaded;
    }

    private void HandleDataContextChanged(
        object sender,
        DependencyPropertyChangedEventArgs e)
    {
        Subscribe(e.OldValue as NowPlayingViewModel, remove: true);
        Subscribe(e.NewValue as NowPlayingViewModel);
    }

    private void HandleUnloaded(object sender, RoutedEventArgs e) =>
        Subscribe(DataContext as NowPlayingViewModel, remove: true);

    private void HandlePropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(NowPlayingViewModel.CurrentLyricIndex)
            || DataContext is not NowPlayingViewModel viewModel
            || viewModel.CurrentLyricIndex < 0
            || viewModel.CurrentLyricIndex >= viewModel.LyricLines.Count)
        {
            return;
        }

        LyricsList.ScrollIntoView(
            viewModel.LyricLines[viewModel.CurrentLyricIndex]);
    }

    private void Subscribe(
        NowPlayingViewModel? viewModel,
        bool remove = false)
    {
        if (viewModel is null)
        {
            return;
        }

        if (remove)
        {
            viewModel.PropertyChanged -= HandlePropertyChanged;
        }
        else
        {
            viewModel.PropertyChanged -= HandlePropertyChanged;
            viewModel.PropertyChanged += HandlePropertyChanged;
        }
    }
}
