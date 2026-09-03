using System.Collections.ObjectModel;
using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Input;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public partial class MainWindow : Window
{
    public MainWindow() { InitializeComponent(); DiagnosticLog.Write("Windows client launched."); DataContext = new NearbyDevicesViewModel(); }
    private void Show(FrameworkElement panel) { ReceivePanel.Visibility = Visibility.Collapsed; SendPanel.Visibility = Visibility.Collapsed; SettingsPanel.Visibility = Visibility.Collapsed; panel.Visibility = Visibility.Visible; }
    private void Receive_Click(object sender, RoutedEventArgs e) => Show(ReceivePanel);
    private void Send_Click(object sender, RoutedEventArgs e) => Show(SendPanel);
    private void Settings_Click(object sender, RoutedEventArgs e) => Show(SettingsPanel);
    private void Refresh_Click(object sender, RoutedEventArgs e) { ((System.Windows.Media.Animation.Storyboard)FindResource("RefreshSpin")).Begin(); if (DataContext is NearbyDevicesViewModel model) model.Refresh(); }
    protected override async void OnClosed(EventArgs e) { if (DataContext is NearbyDevicesViewModel model) await model.DisposeAsync(); base.OnClosed(e); }
}

public sealed class NearbyDeviceCard(string alias, string deviceType, Uri endpoint, string fingerprint, Action send)
{
    public string Alias { get; } = alias;
    public string DeviceType { get; } = deviceType;
    public Uri Endpoint { get; } = endpoint;
    public string Fingerprint { get; } = fingerprint;
    public ICommand SendCommand { get; } = new SimpleCommand(send);
}

public sealed class NearbyDevicesViewModel : IAsyncDisposable, INotifyPropertyChanged
{
    public ObservableCollection<NearbyDeviceCard> Devices { get; } = [];
    private readonly List<string> selectedFiles = [];
    private string? selectedFolder;
    public string SavePath { get; private set; }
    public string EmptyText => Devices.Count == 0 ? "暂未发现设备，点击“刷新”重试" : string.Empty;
    public Visibility EmptyDevicesVisibility => Devices.Count == 0 ? Visibility.Visible : Visibility.Collapsed;
    public ICommand RefreshCommand { get; }
    public ICommand ChooseFilesCommand { get; }
    public ICommand ChooseFolderCommand { get; }
    public ICommand ClipboardCommand { get; }
    public ICommand ChooseSavePathCommand { get; }
    public string SelectedSummary => selectedFiles.Count == 0 ? "尚未选择文件" : $"已选择 {selectedFiles.Count} 个文件";
    public event PropertyChangedEventHandler? PropertyChanged;
    private readonly LocalSendDiscovery discovery = new();
    private readonly DeviceInfo local;
    private readonly LocalSendReceiver receiver;
    private readonly BonjourAdvertiser bonjour = new();
    private readonly BonjourBrowser bonjourBrowser = new();
    private readonly Dictionary<string, DateTimeOffset> lastSeen = new(StringComparer.Ordinal);

    public NearbyDevicesViewModel()
    {
        SavePath = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "爱乐互传");
        var port = WindowsTransferPort.Select();
        local = new DeviceInfo("爱乐互传", "2.0", Environment.MachineName, "desktop", Guid.NewGuid().ToString("N"), port, "http");
        DiagnosticLog.Write($"Selected TCP transfer port: {local.Port}.");
        receiver = new LocalSendReceiver(local, SavePath);
        receiver.RequestReceived += OnIncomingRequest;
        RefreshCommand = new SimpleCommand(() => _ = RefreshAsync());
        ChooseFilesCommand = new SimpleCommand(ChooseFiles);
        ChooseFolderCommand = new SimpleCommand(ChooseFolder);
        ClipboardCommand = new SimpleCommand(ChooseClipboard);
        ChooseSavePathCommand = new SimpleCommand(ChooseSavePath);
        discovery.AnnouncementReceived += OnAnnouncement;
        bonjourBrowser.DeviceDiscovered += OnBonjourDevice;
        Devices.CollectionChanged += (_, _) => { Changed(nameof(EmptyText)); Changed(nameof(EmptyDevicesVisibility)); };
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        NetworkDiagnostics.WriteStartupSnapshot(local.Port);
        // Discovery must remain usable when the receiving endpoint cannot bind.
        // Previously one failure stopped the Bonjour browser, which hid iPhones
        // even though browsing itself does not require the HTTP listener.
        try
        {
            bonjourBrowser.Start();
            DiagnosticLog.Write("Bonjour browser started.");
        }
        catch (Exception exception)
        {
            DiagnosticLog.Write($"Bonjour browser start failed: {exception}");
        }

        var receiverStarted = false;
        try
        {
            await receiver.StartAsync();
            receiverStarted = true;
            DiagnosticLog.Write($"HTTP receiver started on TCP {local.Port}.");
        }
        catch (Exception exception)
        {
            DiagnosticLog.Write($"HTTP receiver start failed on TCP {local.Port}: {exception}");
        }

        if (receiverStarted)
        {
            try
            {
                bonjour.Start(local);
                DiagnosticLog.Write("Bonjour advertiser started.");
            }
            catch (Exception exception)
            {
                DiagnosticLog.Write($"Bonjour advertiser start failed: {exception}");
            }
        }

        try
        {
            await discovery.StartAsync(local);
            DiagnosticLog.Write("UDP discovery started and announcement sent.");
        }
        catch (Exception exception)
        {
            DiagnosticLog.Write($"UDP discovery start failed: {exception}");
        }
    }
    private void OnIncomingRequest(IncomingRequest request) => System.Windows.Application.Current.Dispatcher.Invoke(() =>
    {
        var total = request.Files.Values.Sum(file => file.Size);
        var answer = System.Windows.MessageBox.Show($"{request.Sender.Alias} 要发送 {request.Files.Count} 个文件（{total:N0} 字节）。\n是否接收？", "爱乐互传", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Question);
        receiver.Decide(request.SessionId, answer == System.Windows.MessageBoxResult.Yes);
    });
    private void OnAnnouncement(System.Net.IPEndPoint endpoint, DiscoveryAnnouncement announcement)
    {
        DiagnosticLog.Write($"UDP announcement received from {endpoint}; alias={announcement.Info.Alias}; port={announcement.Info.Port}.");
        if (announcement.Info.Fingerprint == local.Fingerprint) return;
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            lastSeen[announcement.Info.Fingerprint] = DateTimeOffset.UtcNow;
            var existing = Devices.FirstOrDefault(device => device.Endpoint.Host == endpoint.Address.ToString());
            if (existing is null) Devices.Add(new NearbyDeviceCard(announcement.Info.Alias, announcement.Info.DeviceType, new Uri($"http://{endpoint.Address}:{announcement.Info.Port}"), announcement.Info.Fingerprint, () => _ = SendAsync(new Uri($"http://{endpoint.Address}:{announcement.Info.Port}"))));
        });
    }
    private void OnBonjourDevice(BonjourDevice device)
    {
        DiagnosticLog.Write($"Bonjour device delivered to UI: {device.Alias}; {device.Address}:{device.Port}.");
        if (device.Fingerprint == local.Fingerprint) return;
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            lastSeen[device.Fingerprint] = DateTimeOffset.UtcNow;
            var endpoint = new Uri($"http://{device.Address}:{device.Port}");
            if (Devices.All(existing => existing.Endpoint != endpoint))
                Devices.Add(new NearbyDeviceCard(device.Alias, device.DeviceType, endpoint, device.Fingerprint, () => _ = SendAsync(endpoint)));
        });
    }
    private void ChooseFiles()
    {
        var picker = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "选择要发送的文件" };
        if (picker.ShowDialog() == true) { selectedFolder = null; selectedFiles.Clear(); selectedFiles.AddRange(picker.FileNames); Changed(nameof(SelectedSummary)); }
    }
    private void ChooseFolder()
    {
        using var picker = new System.Windows.Forms.FolderBrowserDialog { Description = "选择要发送的文件夹" };
        if (picker.ShowDialog() == System.Windows.Forms.DialogResult.OK) { selectedFolder = picker.SelectedPath; selectedFiles.Clear(); selectedFiles.AddRange(Directory.EnumerateFiles(picker.SelectedPath, "*", SearchOption.AllDirectories)); Changed(nameof(SelectedSummary)); }
    }
    private void ChooseClipboard()
    {
        if (!System.Windows.Clipboard.ContainsText()) { System.Windows.MessageBox.Show("剪贴板中没有文本。", "爱乐互传"); return; }
        var folder = Path.Combine(Path.GetTempPath(), "AiYueTransfer"); Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, $"clipboard-{DateTime.Now:yyyyMMdd-HHmmss}.txt"); File.WriteAllText(path, System.Windows.Clipboard.GetText()); selectedFolder = null; selectedFiles.Clear(); selectedFiles.Add(path); Changed(nameof(SelectedSummary));
    }
    private void ChooseSavePath()
    {
        using var picker = new System.Windows.Forms.FolderBrowserDialog { Description = "选择接收文件的保存位置" };
        if (picker.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;
        SavePath = picker.SelectedPath; receiver.SetDestination(SavePath); Changed(nameof(SavePath));
    }
    private async Task SendAsync(Uri endpoint)
    {
        if (selectedFiles.Count == 0) { System.Windows.MessageBox.Show("请先选择文件。", "爱乐互传"); return; }
        try { var sender = new LocalSendSender(new HttpClient()); if (selectedFolder is not null) await sender.SendFolderAsync(endpoint, local, selectedFolder); else await sender.SendAsync(endpoint, local, selectedFiles); System.Windows.MessageBox.Show("传输完成。", "爱乐互传"); }
        catch (Exception exception) { System.Windows.MessageBox.Show($"传输失败：{exception.Message}", "爱乐互传", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning); }
    }
    private async Task RefreshAsync()
    {
        DiagnosticLog.Write("User requested discovery refresh.");
        bonjour.Announce();
        bonjourBrowser.Refresh();
        await discovery.AnnounceAsync(local);
        var expired = lastSeen.Where(pair => DateTimeOffset.UtcNow - pair.Value > TimeSpan.FromMinutes(2)).Select(pair => pair.Key).ToHashSet(StringComparer.Ordinal);
        foreach (var device in Devices.Where(device => expired.Contains(device.Fingerprint)).ToArray()) Devices.Remove(device);
    }
    public void Refresh() => _ = RefreshAsync();
    public async ValueTask DisposeAsync() { bonjourBrowser.Dispose(); bonjour.Dispose(); await discovery.DisposeAsync(); await receiver.DisposeAsync(); }
    private void Changed([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
}

public sealed class SimpleCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute();
}
