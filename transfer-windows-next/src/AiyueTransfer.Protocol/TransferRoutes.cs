namespace AiyueTransfer.Protocol;

public static class TransferRoutes
{
    public const string Register = "/api/aiyue/v1/register";
    public const string PrepareUpload = "/api/aiyue/v1/prepare-upload";
    public const string Upload = "/api/aiyue/v1/upload";
    public const string Cancel = "/api/aiyue/v1/cancel";
    public const string PrepareDownload = "/api/aiyue/v1/prepare-download";
    public const string Download = "/api/aiyue/v1/download";
}

public sealed record UploadDecision(string SessionId, bool Accepted, string? Reason = null);

public sealed record UploadProgress(string SessionId, string FileId, long TransferredBytes, long TotalBytes);
