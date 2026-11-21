using System;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading.Tasks;
using TelepAIth.Core;

namespace TelepAIth;

/// <summary>
/// Yerel olay sunucusu (127.0.0.1:19850, doluysa sonrakiler). Hook'lar, anlatıcı ve kendi araçların buraya POST eder.
/// Tarayıcıdaki sayfaların isteklerini (Origin başlığı olan) reddeder; dışarıdan bağlantı kabul etmez.
/// </summary>
internal sealed class EventServer
{
    private TcpListener? _listener;
    public int Port { get; private set; }
    public string? Error { get; private set; }

    /// <summary>Gelen olay (arka plan iş parçacığında çağrılır)</summary>
    public event Action<AgentEvent>? EventReceived;

    /// <summary>GET /state: robotun o anki durumu (teşhis ve otomatik testler için)</summary>
    public Func<string>? StateProvider;

    public void Start()
    {
        for (var port = AppInfo.DefaultPort; port < AppInfo.DefaultPort + 20; port++)
        {
            try
            {
                var l = new TcpListener(IPAddress.Loopback, port);
                l.Start();
                _listener = l;
                Port = port;
                break;
            }
            catch (SocketException)
            {
                // Port dolu: sonrakini dene
            }
        }
        if (_listener == null)
        {
            Error = Text.L("Port açılamadı (19850-19869 dolu)", "Couldn't open a port (19850-19869 are busy)");
            return;
        }
        try { File.WriteAllText(AppInfo.PortFile, Port.ToString()); } catch { }
        _ = AcceptLoop(_listener);
    }

    public void Stop()
    {
        try { _listener?.Stop(); } catch { }
        _listener = null;
    }

    private async Task AcceptLoop(TcpListener listener)
    {
        while (true)
        {
            TcpClient client;
            try { client = await listener.AcceptTcpClientAsync().ConfigureAwait(false); }
            catch { return; }
            _ = Task.Run(() => Handle(client));
        }
    }

    private async Task Handle(TcpClient client)
    {
        using (client)
        {
            try
            {
                client.ReceiveTimeout = 5000;
                var stream = client.GetStream();
                var buffer = new byte[64 * 1024];
                var length = 0;
                var sentContinue = false;
                HttpRequest? request = null;
                while (true)
                {
                    if (length == buffer.Length)
                    {
                        if (buffer.Length >= HttpRequest.MaxBytes) { await Respond(stream, 413, "too large"); return; }
                        Array.Resize(ref buffer, Math.Min(buffer.Length * 2, HttpRequest.MaxBytes));
                    }
                    var read = await stream.ReadAsync(buffer.AsMemory(length, buffer.Length - length)).ConfigureAwait(false);
                    if (read <= 0) break;
                    length += read;
                    request = HttpRequest.TryParse(buffer, length);
                    if (request != null) break;
                    if (!sentContinue && HttpRequest.WantsContinue(buffer, length))
                    {
                        sentContinue = true;
                        var cont = Encoding.ASCII.GetBytes("HTTP/1.1 100 Continue\r\n\r\n");
                        await stream.WriteAsync(cont).ConfigureAwait(false);
                    }
                }
                if (request == null) return;
                // Tarayıcıdaki bir sayfa yerel sunucuya istek atamasın
                if (request.Headers.ContainsKey("Origin")) { await Respond(stream, 403, "forbidden"); return; }
                if (request.Method == "GET" && (request.Path == "/" || request.Path == "/health"))
                {
                    await Respond(stream, 200, "{\"app\":\"TelepAIth\",\"version\":\"" + AppInfo.Version + "\"}");
                    return;
                }
                if (request.Method == "GET" && request.Path == "/state" && StateProvider != null)
                {
                    await Respond(stream, 200, StateProvider());
                    return;
                }
                if (request.Method != "POST") { await Respond(stream, 405, "method not allowed"); return; }
                var e = EventParser.Parse(request.Path, request.Query, request.Body);
                if (e == null) { await Respond(stream, 400, "unrecognized event"); return; }
                await Respond(stream, 200, "ok");
                EventReceived?.Invoke(e);
            }
            catch
            {
                // Bozuk istek: sessizce kapat
            }
        }
    }

    private static async Task Respond(NetworkStream stream, int code, string body)
    {
        var reason = code switch { 200 => "OK", 400 => "Bad Request", 403 => "Forbidden", 405 => "Method Not Allowed", 413 => "Payload Too Large", _ => "Error" };
        var payload = Encoding.UTF8.GetBytes(body);
        var head = Encoding.ASCII.GetBytes($"HTTP/1.1 {code} {reason}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n");
        await stream.WriteAsync(head).ConfigureAwait(false);
        await stream.WriteAsync(payload).ConfigureAwait(false);
    }
}
