using System.Net;
using System.Net.Sockets;

namespace AiyueTransfer.App;

/// <summary>Selects a TCP port that this Windows installation is allowed to bind.</summary>
internal static class WindowsTransferPort
{
    // Deliberately separate from LocalSend's default 53317 TCP/UDP port.
    public const int Preferred = 54218;
    public const int LastCandidate = 54318;

    public static int Select()
    {
        for (var candidate = Preferred; candidate <= LastCandidate; candidate++)
        {
            TcpListener? listener = null;
            try
            {
                listener = new TcpListener(IPAddress.Any, candidate);
                listener.Start();
                DiagnosticLog.Write($"TCP port probe succeeded: {candidate}.");
                return candidate;
            }
            catch (SocketException exception)
            {
                DiagnosticLog.Write($"TCP port probe failed: {candidate}; socketError={exception.SocketErrorCode}; native={exception.ErrorCode}.");
            }
            finally
            {
                listener?.Stop();
            }
        }

        throw new InvalidOperationException($"No usable TCP port was found in {Preferred}-{LastCandidate}.");
    }
}
