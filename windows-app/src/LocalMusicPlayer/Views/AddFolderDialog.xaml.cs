using System.IO;
using System.Windows;
using Microsoft.Win32;

namespace LocalMusicPlayer.Views;

public partial class AddFolderDialog : Window
{
    public AddFolderDialog()
    {
        InitializeComponent();
    }

    public string SelectedPath => PathTextBox.Text.Trim();

    private void Browse_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "选择本地音乐文件夹",
            Multiselect = false,
        };
        if (dialog.ShowDialog(this) == true)
        {
            PathTextBox.Text = dialog.FolderName;
        }
    }

    private void Confirm_Click(object sender, RoutedEventArgs e)
    {
        if (!Directory.Exists(SelectedPath))
        {
            MessageBox.Show(
                this,
                "请选择一个存在的文件夹。",
                AppInfo.DisplayName,
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        DialogResult = true;
    }
}
