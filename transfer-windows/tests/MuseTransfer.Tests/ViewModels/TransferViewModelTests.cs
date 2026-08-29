using MuseTransfer.App.Networking;
using MuseTransfer.App.ViewModels;
using MuseTransfer.Core.Music;

namespace MuseTransfer.Tests.ViewModels;

public sealed class TransferViewModelTests
{
    [Fact]
    public void Send_is_disabled_until_a_device_and_files_are_selected()
    {
        var model = CreateModel(out _, out _);
        Assert.False(model.CanSend);

        model.SelectedDevice = new NearbyDevice("phone", "iPhone", new Uri("http://127.0.0.1:5000"), new byte[65]);
        Assert.False(model.CanSend);

        model.SelectedFiles = [new SelectedFile("f1", "C:\\song.mp3", "song.mp3", 3)];
        Assert.True(model.CanSend);
    }

    [Fact]
    public async Task Reject_calls_receiver_before_dismissing_the_request()
    {
        var model = CreateModel(out _, out var decisions);
        model.PresentReceiveRequest(new ReceiveRequest("session-a", "Laptop", 2, 10, "123456"));

        await model.RejectAsync();

        Assert.Equal("session-a", decisions.RejectedSessionId);
        Assert.Null(model.PendingReceiveRequest);
    }

    [Fact]
    public async Task Accept_calls_receiver_and_keeps_progress_visible()
    {
        var model = CreateModel(out _, out var decisions);
        model.PresentReceiveRequest(new ReceiveRequest("session-a", "Laptop", 2, 10, "123456"));

        await model.AcceptAsync();

        Assert.Equal("session-a", decisions.AcceptedSessionId);
        Assert.Null(model.PendingReceiveRequest);
        Assert.Equal("等待发送方上传", model.StatusText);
    }

    [Fact]
    public void Progress_is_derived_from_transferred_and_total_bytes()
    {
        var model = CreateModel(out _, out _);

        model.ReportProgress(new TransferProgress(25, 100, "song.mp3", 10, TimeSpan.FromSeconds(8)));

        Assert.Equal(0.25, model.Progress);
        Assert.Equal("song.mp3", model.CurrentFileName);
    }

    private static TransferViewModel CreateModel(out FakeTransferClient client, out FakeDecisionService decisions)
    {
        client = new FakeTransferClient();
        decisions = new FakeDecisionService();
        return new TransferViewModel(client, decisions);
    }

    private sealed class FakeTransferClient : ITransferClient
    {
        public Task SendAsync(NearbyDevice device, IReadOnlyList<SelectedFile> files, IProgress<TransferProgress> progress, CancellationToken cancellationToken) => Task.CompletedTask;
    }

    private sealed class FakeDecisionService : IReceiveDecisionService
    {
        public string? AcceptedSessionId { get; private set; }
        public string? RejectedSessionId { get; private set; }
        public Task AcceptAsync(string sessionId) { AcceptedSessionId = sessionId; return Task.CompletedTask; }
        public Task RejectAsync(string sessionId) { RejectedSessionId = sessionId; return Task.CompletedTask; }
    }
}
