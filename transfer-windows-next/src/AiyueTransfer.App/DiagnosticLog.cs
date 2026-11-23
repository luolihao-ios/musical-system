using System.Text;
using System.IO;

namespace AiyueTransfer.App;

public static class DiagnosticLog
{
    private static readonly object Gate = new();
    public static string Path { get; } = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "luolihao", "AiYueTransfer", "diagnostics.log");

    public static void Write(string message)
    {
        lock (Gate)
        {
            Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
            File.AppendAllText(Path, $"{DateTimeOffset.Now:O} {message}{Environment.NewLine}", Encoding.UTF8);
        }
    }
}
