using System.Collections.ObjectModel;
using System.IO;
using System.Net.Http;
using System.Windows;
using System.Windows.Input;
using AiyueTransfer.Protocol;

namespace AiyueTransfer.App;

public partial class MainWindow : Window
{
    public MainWindow() { InitializeComponent(); DataContext = new NearbyDevicesViewModel(); }
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

public sealed class NearbyDevicesViewModel : IAsyncDisposable
{
    public ObservableCollection<NearbyDeviceCard> Devices { get; } = [];
    private readonly List<string> selectedFiles = [];
    public string EmptyText => Devices.Count == 0 ? "暂未发现设备，点击“刷新”重试" : string.Empty;
    public ICommand RefreshCommand { get; }
    public ICommand ChooseFilesCommand { get; }
    public ICommand ChooseFolderCommand { get; }
    public ICommand ClipboardCommand { get; }
    public string SelectedSummary => selectedFiles.Count == 0 ? "尚未选择文件" : $"已选择 {selectedFiles.Count} 个文件";
    private readonly LocalSendDiscovery discovery = new();
    private readonly DeviceInfo local = new("爱乐互传", "2.0", Environment.MachineName, "desktop", Guid.NewGuid().ToString("N"), 53317, "http");
    private readonly LocalSendReceiver receiver;
    private readonly BonjourAdvertiser bonjour = new();
    private readonly Dictionary<string, DateTimeOffset> lastSeen = new(StringComparer.Ordinal);

    public NearbyDevicesViewModel()
    {
        var destination = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Downloads", "爱乐互传");
        receiver = new LocalSendReceiver(local, destination);
        receiver.RequestReceived += OnIncomingRequest;
        RefreshCommand = new SimpleCommand(() => _ = RefreshAsync());
        ChooseFilesCommand = new SimpleCommand(ChooseFiles);
        ChooseFolderCommand = new SimpleCommand(ChooseFolder);
        ClipboardCommand = new SimpleCommand(ChooseClipboard);
        discovery.AnnouncementReceived += OnAnnouncement;
        _ = InitializeAsync();
    }

    private async Task InitializeAsync()
    {
        try { await receiver.StartAsync(); bonjour.Start(local); await discovery.StartAsync(local); }
        catch (System.Net.Sockets.SocketException) { }
    }
    private void OnIncomingRequest(IncomingRequest request) => System.Windows.Application.Current.Dispatcher.Invoke(() =>
    {
        var total = request.Files.Values.Sum(file => file.Size);
        var answer = System.Windows.MessageBox.Show($"{request.Sender.Alias} 要发送 {request.Files.Count} 个文件（{total:N0} 字节）。\n是否接收？", "爱乐互传", System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Question);
        receiver.Decide(request.SessionId, answer == System.Windows.MessageBoxResult.Yes);
    });
    private void OnAnnouncement(System.Net.IPEndPoint endpoint, DiscoveryAnnouncement announcement)
    {
        if (announcement.Info.Fingerprint == local.Fingerprint) return;
        System.Windows.Application.Current.Dispatcher.Invoke(() =>
        {
            lastSeen[announcement.Info.Fingerprint] = DateTimeOffset.UtcNow;
            var existing = Devices.FirstOrDefault(device => device.Endpoint.Host == endpoint.Address.ToString());
            if (existing is null) Devices.Add(new NearbyDeviceCard(announcement.Info.Alias, announcement.Info.DeviceType, new Uri($"http://{endpoint.Address}:{announcement.Info.Port}"), announcement.Info.Fingerprint, () => _ = SendAsync(new Uri($"http://{endpoint.Address}:{announcement.Info.Port}"))));
        });
    }
    private void ChooseFiles()
    {
        var picker = new Microsoft.Win32.OpenFileDialog { Multiselect = true, Title = "选择要发送的文件" };
        if (picker.ShowDialog() == true) { selectedFiles.Clear(); selectedFiles.AddRange(picker.FileNames); }
    }
    private void ChooseFolder()
    {
        using var picker = new System.Windows.Forms.FolderBrowserDialog { Description = "选择要发送的文件夹" };
        if (picker.ShowDialog() == System.Windows.Forms.DialogResult.OK) { selectedFiles.Clear(); selectedFiles.AddRange(Directory.EnumerateFiles(picker.SelectedPath, "*", SearchOption.AllDirectories)); }
    }
    private void ChooseClipboard()
    {
        if (!System.Windows.Clipboard.ContainsText()) { System.Windows.MessageBox.Show("剪贴板中没有文本。", "爱乐互传"); return; }
        var folder = Path.Combine(Path.GetTempPath(), "AiYueTransfer"); Directory.CreateDirectory(folder);
        var path = Path.Combine(folder, $"clipboard-{DateTime.Now:yyyyMMdd-HHmmss}.txt"); File.WriteAllText(path, System.Windows.Clipboard.GetText()); selectedFiles.Clear(); selectedFiles.Add(path);
    }
    private async Task SendAsync(Uri endpoint)
    {
        if (selectedFiles.Count == 0) { System.Windows.MessageBox.Show("请先选择文件。", "爱乐互传"); return; }
        try { await new LocalSendSender(new HttpClient()).SendAsync(endpoint, local, selectedFiles); System.Windows.MessageBox.Show("传输完成。", "爱乐互传"); }
        catch (Exception exception) { System.Windows.MessageBox.Show($"传输失败：{exception.Message}", "爱乐互传", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning); }
    }
    private async Task RefreshAsync()
    {
        await discovery.AnnounceAsync(local);
        var expired = lastSeen.Where(pair => DateTimeOffset.UtcNow - pair.Value > TimeSpan.FromMinutes(2)).Select(pair => pair.Key).ToHashSet(StringComparer.Ordinal);
        foreach (var device in Devices.Where(device => expired.Contains(device.Fingerprint)).ToArray()) Devices.Remove(device);
    }
    public async ValueTask DisposeAsync() { bonjour.Dispose(); await discovery.DisposeAsync(); await receiver.DisposeAsync(); }
}

public sealed class SimpleCommand(Action execute) : ICommand
{
    public event EventHandler? CanExecuteChanged { add { } remove { } }
    public bool CanExecute(object? parameter) => true;
    public void Execute(object? parameter) => execute();
}
