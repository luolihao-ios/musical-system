using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Views;

public partial class RecordVisual : UserControl
{
    private Storyboard? _spin;

    public RecordVisual()
    {
        InitializeComponent();
        Loaded += HandleLoaded;
        Unloaded += HandleUnloaded;
        DataContextChanged += HandleDataContextChanged;
    }

    private void HandleLoaded(object sender, RoutedEventArgs e)
    {
        _spin = (Storyboard)FindResource("SpinStoryboard");
        _spin.Begin(this, true);
        ((Storyboard)FindResource("PulseStoryboard")).Begin(this, true);
        ApplyPlaybackState();
        Subscribe(DataContext as NowPlayingViewModel);
    }

    private void HandleUnloaded(object sender, RoutedEventArgs e)
    {
        Subscribe(DataContext as NowPlayingViewModel, remove: true);
        _spin?.Remove(this);
        ((Storyboard)FindResource("PulseStoryboard")).Remove(this);
    }

    private void HandleDataContextChanged(
        object sender,
        DependencyPropertyChangedEventArgs e)
    {
        Subscribe(e.OldValue as NowPlayingViewModel, remove: true);
        Subscribe(e.NewValue as NowPlayingViewModel);
        ApplyPlaybackState();
    }

    private void HandleViewModelPropertyChanged(
        object? sender,
        PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(NowPlayingViewModel.IsRecordRotating))
        {
            ApplyPlaybackState();
        }
    }

    private void ApplyPlaybackState()
    {
        if (_spin is null || DataContext is not NowPlayingViewModel viewModel)
        {
            return;
        }

        if (viewModel.IsRecordRotating)
        {
            _spin.Resume(this);
        }
        else
        {
            _spin.Pause(this);
        }
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
            viewModel.PropertyChanged -= HandleViewModelPropertyChanged;
        }
        else
        {
            viewModel.PropertyChanged -= HandleViewModelPropertyChanged;
            viewModel.PropertyChanged += HandleViewModelPropertyChanged;
        }
    }
}
