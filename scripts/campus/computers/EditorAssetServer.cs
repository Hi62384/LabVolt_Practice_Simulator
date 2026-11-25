#nullable enable
using Godot;
using System;
using System.Globalization;
using System.IO;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

public partial class EditorAssetServer : RefCounted
{
    private TcpListener? _listener;
    private CancellationTokenSource? _stop;

    public string Start(byte[] assets, byte[] document)
    {
        Stop();
        var listener = new TcpListener(IPAddress.Loopback, 0);
        try { listener.Start(32); }
        catch (SocketException) { return ""; }
        _listener = listener;
        _stop = new CancellationTokenSource();
        string authority = "127.0.0.1:" + ((IPEndPoint)listener.LocalEndpoint).Port;
        string prefix = "/" + Guid.NewGuid().ToString("N", CultureInfo.InvariantCulture) + "/";
        _ = Serve(listener, assets, document, authority, prefix, _stop.Token);
        return "http://" + authority + prefix;
    }

    public void Stop()
    {
        _stop?.Cancel();
        _listener?.Stop();
        _stop?.Dispose();
        _stop = null;
        _listener = null;
    }

    private static async Task Serve(TcpListener listener, byte[] assets, byte[] document, string authority,
        string prefix, CancellationToken stop)
    {
        var slots = new SemaphoreSlim(32);
        try
        {
            while (!stop.IsCancellationRequested)
            {
                TcpClient client = await listener.AcceptTcpClientAsync(stop).ConfigureAwait(false);
                if (slots.Wait(0)) _ = Handle(client, assets, document, authority, prefix, slots, stop);
                else client.Dispose();
            }
        }
        catch (Exception failure) when (failure is SocketException or OperationCanceledException or ObjectDisposedException) { }
    }

    private static async Task Handle(TcpClient client, byte[] assets, byte[] document, string authority,
        string prefix, SemaphoreSlim slots, CancellationToken stop)
    {
        using (client)
        using (var timeout = CancellationTokenSource.CreateLinkedTokenSource(stop))
        {
            timeout.CancelAfter(TimeSpan.FromSeconds(12));
            var token = timeout.Token;
            try
            {
                using NetworkStream stream = client.GetStream();
                var header = new byte[8192];
                int count = 0;
                int end = -1;
                while (count < header.Length && end < 0)
                {
                    int bytes = await stream.ReadAsync(header.AsMemory(count), token).ConfigureAwait(false);
                    if (bytes == 0) return;
                    int scan = Math.Max(3, count);
                    count += bytes;
                    for (; scan < count; scan++)
                        if (header[scan] == 10 && header[scan - 1] == 13 && header[scan - 2] == 10 && header[scan - 3] == 13)
                        { end = scan + 1; break; }
                }
                if (end < 0) return;
                string[] lines = Encoding.ASCII.GetString(header, 0, end).Split("\r\n", StringSplitOptions.None);
                string[] request = lines[0].Split(' ');
                if (request.Length != 3 || request[0] != "GET"
                    || !Array.Exists(lines, line => line.Equals("Host: " + authority, StringComparison.OrdinalIgnoreCase))
                    || !request[1].StartsWith(prefix, StringComparison.Ordinal))
                {
                    await Reply(stream, "404 Not Found", "text/plain", Stream.Null, 0, token).ConfigureAwait(false);
                    return;
                }
                string path = request[1][prefix.Length..];
                if (path is "" or "index.html")
                {
                    using var page = new MemoryStream(document, false);
                    await Reply(stream, "200 OK", "text/html; charset=utf-8", page, page.Length, token).ConfigureAwait(false);
                    return;
                }
                using var archive = new ZipArchive(new MemoryStream(assets, false), ZipArchiveMode.Read);
                var entry = path.StartsWith("vs/", StringComparison.Ordinal) ? archive.GetEntry(path) : null;
                if (entry is null)
                {
                    await Reply(stream, "404 Not Found", "text/plain", Stream.Null, 0, token).ConfigureAwait(false);
                    return;
                }
                using Stream asset = entry.Open();
                string mime = Path.GetExtension(path) switch
                {
                    ".js" => "text/javascript",
                    ".css" => "text/css",
                    ".ttf" => "font/ttf",
                    ".woff2" => "font/woff2",
                    ".wasm" => "application/wasm",
                    _ => "application/octet-stream"
                };
                await Reply(stream, "200 OK", mime, asset, entry.Length, token).ConfigureAwait(false);
            }
            catch (Exception failure) when (failure is IOException or SocketException or OperationCanceledException or ObjectDisposedException) { }
            finally { slots.Release(); }
        }
    }

    private static async Task Reply(NetworkStream stream, string status, string mime, Stream content, long length,
        CancellationToken token)
    {
        const string policy = "default-src 'none'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; "
            + "style-src 'self' 'unsafe-inline'; font-src 'self'; img-src 'self' data:; "
            + "worker-src 'self' blob:; connect-src 'self'; frame-ancestors 'none'; form-action 'none'; base-uri 'none'";
        byte[] header = Encoding.ASCII.GetBytes($"HTTP/1.1 {status}\r\nContent-Type: {mime}\r\nContent-Length: {length}\r\n"
            + $"Content-Security-Policy: {policy}\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(header, token).ConfigureAwait(false);
        await content.CopyToAsync(stream, token).ConfigureAwait(false);
    }
}
