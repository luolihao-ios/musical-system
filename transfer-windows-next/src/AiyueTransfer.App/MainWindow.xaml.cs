using System.Collections.ObjectModel;
using System.Windows;
using System.Windows.Input;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public partial class MainWindow : Window
{
    public MainWindow() { InitializeComponent(); DataContext = new NearbyDevicesViewModel(); }
    protected override async void OnClosed(EventArgs e) { if (DataContext is NearbyDevicesViewModel model) await model.DisposeAsync(); base.OnClosed(e); }
}

public sealed class NearbyDeviceCard(string alias, string deviceType, Uri endpoint, string fingerprint)
{
    public string Alias { get; } = alias;
    public string DeviceType { get; } = deviceType;
    public Uri Endpoint { get; } = endpoint;
    public string Fingerprint { get; } = fingerprint;
    public ICommand SendCommand { get; } = new SimpleCommand(() => { });
}

public sealed class NearbyDevicesViewModel : IAsyncDisposable
{
    public ObservableCollection<NearbyDeviceCard> Devices { get; } = [];
    public string EmptyText => Devices.Count == 0 ? "暂未发现设备，点击“刷新”重试" : string.Empty;
    public ICommand RefreshCommand { get; }
    private readonly LocalSendDiscovery discovery = new();
    private readonly DeviceInfo local = new("爱乐互传", "2.0", Environment.MachineName, "desktop", Guid.NewGuid().ToString("N"), 53317, "http");
    private readonly Dictionary<string, DateTimeOffset> lastSeen = new(StringComparer.Ordinal);

    public NearbyDevicesViewModel()
    {
        RefreshCommand = new SimpleCommand(() => _ = RefreshAsync());
        discovery.AnnouncementReceived += OnAnnouncement;
        _ = InitializeAsync();
    }

    private async Task InitializeAsync() { try { await discovery.StartAsync(local); } catch (System.Net.Sockets.SocketException) { } }
    private void OnAnnouncement(System.Net.IPEndPoint endpoint, DiscoveryAnnouncement announcement)
    {
        if (announcement.Info.Fingerprint == local.Fingerprint) return;
        Application.Current.Dispatcher.Invoke(() =>
        {
            lastSeen[announcement.Info.Fingerprint] = DateTimeOffset.UtcNow;
            var existing = Devices.FirstOrDefault(device => device.Endpoint.Host == endpoint.Address.ToString());
            if (existing is null) Devices.Add(new NearbyDeviceCard(announcement.Info.Alias, announcement.Info.DeviceType, new Uri($"http://{endpoint.Address}:{announcement.Info.Port}"), announcement.Info.Fingerprint));
        });
    }
    private async Task RefreshAsync()
    {
        await discovery.AnnounceAsync(local);
        var expired = lastSeen.Where(pair => DateTimeOffset.UtcNow - pair.Value > TimeSpan.FromMinutes(2)).Select(pair => pair.Key).ToHashSet(StringComparer.Ordinal);
        foreach (var device in Devices.Where(device => expired.Contains(device.Fingerprint)).ToArray()) Devices.Remove(device);
    }
    public async ValueTask DisposeAsync() => await discovery.DisposeAsync();
}

public sealed class SimpleCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute();
}
