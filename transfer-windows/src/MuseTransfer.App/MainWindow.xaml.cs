using System.IO;
using System.Windows;
using Microsoft.Win32;
using MuseTransfer.App.Networking;
using MuseTransfer.App.ViewModels;
using MuseTransfer.Core.Music;

namespace MuseTransfer.App;

public partial class MainWindow : Window
{
    private TransferViewModel? model;
    public MainWindow() => InitializeComponent();
    public void Attach(TransferViewModel viewModel) { model = viewModel; DataContext = viewModel; }

    private void OnAddAddress(object sender, RoutedEventArgs e)
    {
        if (model is null || !Uri.TryCreate(AddressBox.Text, UriKind.Absolute, out var uri)) return;
        var device = new NearbyDevice(uri.Host, uri.Host, uri, string.Empty);
        if (!model.NearbyDevices.Any(item => item.BaseAddress == uri)) model.NearbyDevices.Add(device);
        model.SelectedDevice = device;
    }

    private void OnChooseFiles(object sender, RoutedEventArgs e)
    {
        var dialog = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "选择要发送的文件" };
        if (dialog.ShowDialog(this) == true) SetFiles(dialog.FileNames, null);
    }

    private void OnChooseFolder(object sender, RoutedEventArgs e)
    {
        using var dialog = new System.Windows.Forms.FolderBrowserDialog { Description = "选择要发送的文件夹", UseDescriptionForTitle = true };
        if (dialog.ShowDialog() == System.Windows.Forms.DialogResult.OK) SetFiles(Directory.EnumerateFiles(dialog.SelectedPath, "*", SearchOption.AllDirectories), dialog.SelectedPath);
    }

    private void OnDrop(object sender, System.Windows.DragEventArgs e)
    {
        if (!e.Data.GetDataPresent(System.Windows.DataFormats.FileDrop)) return;
        var paths = (string[])e.Data.GetData(System.Windows.DataFormats.FileDrop);
        var files = paths.SelectMany(path => Directory.Exists(path) ? Directory.EnumerateFiles(path, "*", SearchOption.AllDirectories) : [path]);
        SetFiles(files, paths.Length == 1 && Directory.Exists(paths[0]) ? paths[0] : null);
    }

    private void SetFiles(IEnumerable<string> paths, string? root)
    {
        if (model is null) return;
        model.SelectedFiles = paths.Select((path, index) => new SelectedFile($"f{index + 1}", path, root is null ? Path.GetFileName(path) : Path.GetRelativePath(root, path).Replace('\\', '/'), new FileInfo(path).Length)).ToArray();
    }

    private async void OnSend(object sender, RoutedEventArgs e) { if (model is not null) await model.SendAsync(); }
    private async void OnAccept(object sender, RoutedEventArgs e) { if (model is not null) await model.AcceptAsync(); }
    private async void OnReject(object sender, RoutedEventArgs e) { if (model is not null) await model.RejectAsync(); }
    private void OnCancel(object sender, RoutedEventArgs e) => model?.Cancel();
}
