using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Runtime.CompilerServices;
using MuseTransfer.App.Networking;
using MuseTransfer.App.History;
using MuseTransfer.Core.Music;
using MuseTransfer.Core.Sessions;

namespace MuseTransfer.App.ViewModels;

public sealed record ReceiveRequest(string SessionId, string SenderName, int FileCount, long TotalBytes, string VerificationCode);

public interface IReceiveDecisionService
{
    Task AcceptAsync(string sessionId);
    Task RejectAsync(string sessionId);
}

public sealed class SessionDecisionService(SessionManager sessions) : IReceiveDecisionService
{
    public Task AcceptAsync(string sessionId) { sessions.Accept(sessionId); return Task.CompletedTask; }
    public Task RejectAsync(string sessionId) { sessions.Reject(sessionId); return Task.CompletedTask; }
}

public sealed class TransferViewModel(ITransferClient transferClient, IReceiveDecisionService decisions, ITransferHistoryStore? historyStore = null) : INotifyPropertyChanged
{
    private NearbyDevice? selectedDevice;
    private IReadOnlyList<SelectedFile> selectedFiles = [];
    private ReceiveRequest? pendingReceiveRequest;
    private string statusText = "选择附近设备开始传输";
    private string currentFileName = string.Empty;
    private double progress;
    private CancellationTokenSource? sendCancellation;
    private string localPublicKey = string.Empty;
    private string localAddress = "正在启动接收服务";

    public ObservableCollection<NearbyDevice> NearbyDevices { get; } = [];
    public ObservableCollection<TransferHistoryEntry> History { get; } = [];
    public string LocalPublicKey { get => localPublicKey; private set => Set(ref localPublicKey, value); }
    public string LocalAddress { get => localAddress; private set => Set(ref localAddress, value); }

    public NearbyDevice? SelectedDevice
    {
        get => selectedDevice;
        set { if (Set(ref selectedDevice, value)) OnPropertyChanged(nameof(CanSend)); }
    }

    public IReadOnlyList<SelectedFile> SelectedFiles
    {
        get => selectedFiles;
        set { if (Set(ref selectedFiles, value)) OnPropertyChanged(nameof(CanSend)); }
    }

    public ReceiveRequest? PendingReceiveRequest { get => pendingReceiveRequest; private set => Set(ref pendingReceiveRequest, value); }
    public string StatusText { get => statusText; private set => Set(ref statusText, value); }
    public string CurrentFileName { get => currentFileName; private set => Set(ref currentFileName, value); }
    public double Progress { get => progress; private set => Set(ref progress, value); }
    public bool CanSend => SelectedDevice is not null && SelectedFiles.Count > 0 && sendCancellation is null;

    public void PresentReceiveRequest(ReceiveRequest request) => PendingReceiveRequest = request;

    public async Task AcceptAsync()
    {
        var request = PendingReceiveRequest ?? throw new InvalidOperationException("There is no receive request to accept.");
        await decisions.AcceptAsync(request.SessionId);
        PendingReceiveRequest = null;
        StatusText = "等待发送方上传";
    }

    public async Task RejectAsync()
    {
        var request = PendingReceiveRequest ?? throw new InvalidOperationException("There is no receive request to reject.");
        await decisions.RejectAsync(request.SessionId);
        PendingReceiveRequest = null;
        StatusText = "已拒绝传输";
    }

    public async Task SendAsync()
    {
        if (!CanSend) return;
        sendCancellation = new CancellationTokenSource();
        OnPropertyChanged(nameof(CanSend));
        StatusText = "等待接收方确认";
        try
        {
            var reporter = new Progress<TransferProgress>(ReportProgress);
            await transferClient.SendAsync(SelectedDevice!, SelectedFiles, reporter, sendCancellation.Token);
            Progress = 1;
            StatusText = "传输完成";
            if (historyStore is not null) await historyStore.AppendAsync(new TransferHistoryEntry(Guid.NewGuid(), DateTimeOffset.Now, SelectedDevice!.Name, "sent", "completed", SelectedFiles.Select(file => file.RelativePath).ToArray(), SelectedFiles.Sum(file => file.Size)));
        }
        catch (OperationCanceledException)
        {
            StatusText = "传输已取消";
        }
        finally
        {
            sendCancellation.Dispose();
            sendCancellation = null;
            OnPropertyChanged(nameof(CanSend));
        }
    }

    public void Cancel() => sendCancellation?.Cancel();
    public void SetReceiverInfo(int port, byte[] publicKey) { LocalAddress = $"本机端口 {port}"; LocalPublicKey = Convert.ToBase64String(publicKey); }
    public async Task LoadHistoryAsync() { if (historyStore is null) return; History.Clear(); foreach (var item in await historyStore.LoadAsync()) History.Add(item); }

    public void ReportProgress(TransferProgress update)
    {
        Progress = update.TotalBytes <= 0 ? 0 : (double)update.TransferredBytes / update.TotalBytes;
        CurrentFileName = update.CurrentFileName;
        StatusText = update.Remaining is null ? "正在传输" : $"剩余约 {Math.Ceiling(update.Remaining.Value.TotalSeconds)} 秒";
    }

    public event PropertyChangedEventHandler? PropertyChanged;
    private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    private bool Set<T>(ref T field, T value, [CallerMemberName] string? name = null)
    {
        if (EqualityComparer<T>.Default.Equals(field, value)) return false;
        field = value;
        OnPropertyChanged(name);
        return true;
    }
}
