using System.Windows;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer;

public partial class MainWindow : Window
{
    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        DataContext = viewModel;
    }
}
