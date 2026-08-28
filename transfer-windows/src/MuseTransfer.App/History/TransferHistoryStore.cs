using System.IO;
using System.Text.Json;

namespace MuseTransfer.App.History;

public sealed record TransferHistoryEntry(Guid Id, DateTimeOffset Timestamp, string DeviceName, string Direction, string Result, IReadOnlyList<string> Files, long TotalBytes);
public interface ITransferHistoryStore { Task<IReadOnlyList<TransferHistoryEntry>> LoadAsync(); Task AppendAsync(TransferHistoryEntry entry); Task ClearAsync(); }

public sealed class TransferHistoryStore(string path) : ITransferHistoryStore
{
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web) { WriteIndented = true };
    private readonly SemaphoreSlim gate = new(1, 1);
    public async Task<IReadOnlyList<TransferHistoryEntry>> LoadAsync()
    {
        await gate.WaitAsync(); try { return File.Exists(path) ? JsonSerializer.Deserialize<List<TransferHistoryEntry>>(await File.ReadAllBytesAsync(path), Options) ?? [] : []; } finally { gate.Release(); }
    }
    public async Task AppendAsync(TransferHistoryEntry entry)
    {
        await gate.WaitAsync(); try { var list = File.Exists(path) ? JsonSerializer.Deserialize<List<TransferHistoryEntry>>(await File.ReadAllBytesAsync(path), Options) ?? [] : []; list.Insert(0, entry); if (list.Count > 500) list.RemoveRange(500, list.Count - 500); Directory.CreateDirectory(Path.GetDirectoryName(path)!); await File.WriteAllBytesAsync(path, JsonSerializer.SerializeToUtf8Bytes(list, Options)); } finally { gate.Release(); }
    }
    public async Task ClearAsync() { await gate.WaitAsync(); try { if (File.Exists(path)) File.Delete(path); } finally { gate.Release(); } }
}
