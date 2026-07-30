using System.Windows;
using System.Windows.Controls;
using LocalMusicPlayer.ViewModels;

namespace LocalMusicPlayer.Views;

public partial class LibraryView : UserControl
{
    public LibraryView()
    {
        InitializeComponent();
    }

    private async void AddFolder_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new AddFolderDialog
        {
            Owner = Window.GetWindow(this),
        };
        if (dialog.ShowDialog() == true
            && DataContext is LibraryViewModel viewModel)
        {
            await viewModel.AddFolderAsync(dialog.SelectedPath);
        }
    }
}
