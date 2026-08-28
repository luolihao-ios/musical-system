using System.IO;
using System.Windows;
using MuseTransfer.App.Composition;
using MuseTransfer.App.Networking;
using MuseTransfer.App.ViewModels;

namespace MuseTransfer.App;

public partial class App : System.Windows.Application
{
    private AppServices? services;

    protected override async void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);
        var dataRoot = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "luolihao", "MuseTransfer");
        var destination = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "暮色互传");
        services = new AppServices(dataRoot, destination, LoadDeviceId(dataRoot), Environment.MachineName);
        var model = new TransferViewModel(new TransferClient(), new SessionDecisionService(services.Sessions));
        services.Sessions.SessionProposed += session => Dispatcher.Invoke(() => model.PresentReceiveRequest(new ReceiveRequest(
            session.Id, session.Manifest.SenderId, session.Manifest.Items.Count, session.Manifest.Items.Sum(item => item.Size), session.VerificationCode)));
        services.Browser.DeviceDiscovered += device => Dispatcher.Invoke(() =>
        {
            if (device.Id == LoadDeviceId(dataRoot) || model.NearbyDevices.Any(item => item.Id == device.Id)) return;
            model.NearbyDevices.Add(new NearbyDevice(device.Id, device.Name, new Uri($"http://{device.Address}:{device.Port}"), device.PublicKey));
        });
        var window = new MainWindow();
        window.Attach(model);
        MainWindow = window;
        window.Show();
        try { await services.Receiver.StartAsync(CancellationToken.None); services.Browser.Start(); }
        catch (Exception exception) { System.Windows.MessageBox.Show($"接收服务启动失败：{exception.Message}", "暮色互传", MessageBoxButton.OK, MessageBoxImage.Warning); }
    }

    protected override async void OnExit(ExitEventArgs e)
    {
        if (services is not null) await services.DisposeAsync();
        base.OnExit(e);
    }

    private static string LoadDeviceId(string dataRoot)
    {
        Directory.CreateDirectory(dataRoot);
        var path = Path.Combine(dataRoot, "device-id.txt");
        if (File.Exists(path)) return File.ReadAllText(path).Trim();
        var id = Guid.NewGuid().ToString("N");
        File.WriteAllText(path, id);
        return id;
    }
}
