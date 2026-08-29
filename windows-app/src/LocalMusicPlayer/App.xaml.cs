using System.IO;
using System.Windows;
using LocalMusicPlayer.Composition;
using LocalMusicPlayer.Import;

namespace LocalMusicPlayer;

public partial class App : Application
{
    private AppServices? _services;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        try
        {
            _services = await AppServices.CreateAsync();
            var handoffRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "luolihao", "MuseTransfer", "MusicHandoff");
            var importer = new TransferHandoffImporter(_services.Scanner, handoffRoot, Path.Combine(_services.Paths.DataDirectory, "ProcessedHandoffs"));
            foreach (var argument in e.Args.Where(value => value.StartsWith("musemusic:", StringComparison.OrdinalIgnoreCase))) await importer.ImportAsync(argument);
            var window = new MainWindow(_services.Main);
            MainWindow = window;
            window.Show();
        }
        catch (Exception exception)
        {
            MessageBox.Show(
                $"暮色音乐启动失败：{exception.Message}",
                AppInfo.DisplayName,
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            Shutdown(1);
        }
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (_services is not null)
        {
            await _services.DisposeAsync();
        }

        base.OnExit(e);
    }
}
