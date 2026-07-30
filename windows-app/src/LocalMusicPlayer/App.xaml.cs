using System.Windows;
using LocalMusicPlayer.Composition;

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
            var window = new MainWindow();
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
