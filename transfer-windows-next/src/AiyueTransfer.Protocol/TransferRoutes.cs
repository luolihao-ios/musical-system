namespace AiyueTransfer.Protocol;

public static class TransferRoutes
{
    public const string Register = "/api/localsend/v2/register";
    public const string PrepareUpload = "/api/localsend/v2/prepare-upload";
    public const string Upload = "/api/localsend/v2/upload";
    public const string Cancel = "/api/localsend/v2/cancel";
    public const string PrepareDownload = "/api/localsend/v2/prepare-download";
    public const string Download = "/api/localsend/v2/download";
}

public sealed record UploadDecision(string SessionId, bool Accepted, string? Reason = null);

public sealed record UploadProgress(string SessionId, string FileId, long TransferredBytes, long TotalBytes);
