using System;
using System.Threading;
using System.IO;
using System.Linq;
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

    /// <summary>Claude Code izin istiyor: bağlantı açık kalır, robotun cevabı (ya da boş cevap) dönene kadar.</summary>
    public event Action<PendingApproval>? PermissionRequested;

    /// <summary>GET /state: robotun o anki durumu (teşhis ve otomatik testler için)</summary>
    public Func<string>? StateProvider;

    /// <summary>Sadece TELEPAITH_HOOK_DEBUG=1 iken: /debug/... (otomatik testler pencere/menü açabilsin)</summary>
    public Func<string, System.Collections.Generic.Dictionary<string, string>, string>? DebugHandler;

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
                if (Debug && DebugHandler != null && request.Path.StartsWith("/debug/", StringComparison.Ordinal))
                {
                    await Respond(stream, 200, DebugHandler(request.Path, request.Query));
                    return;
                }
                if (request.Method != "POST") { await Respond(stream, 405, "method not allowed"); return; }
                var e = EventParser.Parse(request.Path, request.Query, request.Body);
                if (Debug) Log($"{request.Method} {request.Path} q={string.Join("&", request.Query.Select(kv => kv.Key + "=" + kv.Value))} body={request.Body.Length} → {(e == null ? "400" : e.Source + "/" + e.SessionId + " " + e.Kind)}");
                if (e == null) { await Respond(stream, 400, "unrecognized event"); return; }
                if (request.Path == "/permission" && PermissionRequested != null)
                {
                    var pending = new PendingApproval(e, request.Body);
                    PermissionRequested.Invoke(pending);
                    var answer = await pending.WaitAsync(client, TimeSpan.FromSeconds(585)).ConfigureAwait(false);
                    if (Debug) Log($"permission {e.Source}/{e.SessionId} → {(string.IsNullOrEmpty(answer) ? "(terminalde sorulacak)" : answer)}");
                    try { await Respond(stream, 200, answer ?? ""); } catch { }
                    return;
                }
                // Önce olayı ilet, sonra cevap ver: hook yardımcısı cevabın başını okuyunca bağlantıyı kapatıyor,
                // cevap yazılırken bağlantı koparsa olay kaybolmasın.
                EventReceived?.Invoke(e);
                try { await Respond(stream, 200, "ok"); } catch { }
            }
            catch
            {
                // Bozuk istek: sessizce kapat
            }
        }
    }

    private static readonly bool Debug = Environment.GetEnvironmentVariable("TELEPAITH_HOOK_DEBUG") == "1";

    private static void Log(string s)
    {
        try { lock (typeof(EventServer)) File.AppendAllText(AppInfo.DebugFile, $"{DateTime.Now:HH:mm:ss.fff} server: {s}\n"); } catch { }
    }

    private static async Task Respond(NetworkStream stream, int code, string body)
    {
        var reason = code switch { 200 => "OK", 400 => "Bad Request", 403 => "Forbidden", 405 => "Method Not Allowed", 413 => "Payload Too Large", _ => "Error" };
        var payload = Encoding.UTF8.GetBytes(body);
        var head = Encoding.ASCII.GetBytes($"HTTP/1.1 {code} {reason}\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n");
        var all = new byte[head.Length + payload.Length];
        head.CopyTo(all, 0);
        payload.CopyTo(all, head.Length);
        await stream.WriteAsync(all).ConfigureAwait(false);
    }
}


/// <summary>
/// Robotun cevabını bekleyen bir izin isteği. Answer: karar JSON'u; Release: boş cevap (soru terminalde çıkar).
/// Hook yardımcısı bağlantıyı kapatırsa (Claude Code vazgeçti) Closed olur.
/// </summary>
internal sealed class PendingApproval
{
    private static int _counter;
    private readonly TaskCompletionSource<string> _answer = new(TaskCreationOptions.RunContinuationsAsynchronously);

    public int Id { get; } = Interlocked.Increment(ref _counter);
    public AgentEvent Event { get; }
    public System.Text.Json.Nodes.JsonArray? Suggestions { get; }
    public DateTime Created { get; } = DateTime.Now;
    public bool Finished => _answer.Task.IsCompleted;
    public bool Closed { get; private set; }

    public PendingApproval(AgentEvent e, string body)
    {
        Event = e;
        Suggestions = Approval.Suggestions(body);
    }

    public void Answer(string json) => _answer.TrySetResult(json);
    public void Release() => _answer.TrySetResult("");

    public async Task<string?> WaitAsync(TcpClient client, TimeSpan max)
    {
        var until = DateTime.Now + max;
        while (!_answer.Task.IsCompleted && DateTime.Now < until)
        {
            await Task.WhenAny(_answer.Task, Task.Delay(400)).ConfigureAwait(false);
            try
            {
                // Karşı taraf kapattı mı? (okunacak veri yok ama okunabilir = bağlantı bitti)
                if (!_answer.Task.IsCompleted && client.Client.Poll(0, SelectMode.SelectRead) && client.Available == 0)
                {
                    Closed = true;
                    _answer.TrySetResult("");
                }
            }
            catch
            {
                Closed = true;
                _answer.TrySetResult("");
            }
        }
        _answer.TrySetResult("");
        return await _answer.Task.ConfigureAwait(false);
    }
}
