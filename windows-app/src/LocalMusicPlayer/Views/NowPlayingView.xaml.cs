using System.Windows.Controls;
using System.Windows.Input;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Views;

public partial class NowPlayingView : UserControl
{
    public NowPlayingView()
    {
        InitializeComponent();
    }

    private async void ProgressSlider_MouseLeftButtonUp(
        object sender,
        MouseButtonEventArgs e)
    {
        if (DataContext is NowPlayingViewModel viewModel)
        {
            await viewModel.SeekFractionAsync(ProgressSlider.Value);
        }
    }
}
