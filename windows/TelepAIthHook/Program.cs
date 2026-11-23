using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using TelepAIth.Core;

// TelepAIthHook.exe hook <kaynak>   → stdin'deki olayı TelepAIth'e iletir (hiçbir şey yazmaz: Claude Code çıktıyı bağlama ekleyebilir)
// TelepAIthHook.exe permission <kaynak> → izin isteğini robota sorar, cevabı (izin ver / reddet) yazar
// TelepAIthHook.exe shield          → tehlikeli komutta "onay sor" cevabı yazar
// TelepAIthHook.exe mcp [--source claude] → anlatıcı MCP sunucusu (stdio)
var mode = args.Length > 0 ? args[0].ToLowerInvariant() : "";
try
{
    switch (mode)
    {
        case "hook":
        {
            // ClaudeBar'ın kota ölçmek için açtığı oturumları yok say
            if (Environment.GetEnvironmentVariable("CLAUDEBAR_PROBE") == "1") return 0;
            var source = args.Length > 1 && !args[1].StartsWith("__") ? args[1] : "claude";
            var body = ReadStdin();
            var query = new StringBuilder("source=" + Uri.EscapeDataString(source));
            var ppid = Native.ParentPid();
            if (ppid > 0) query.Append("&ppid=").Append(ppid);
            var term = Environment.GetEnvironmentVariable("TERM_PROGRAM");
            if (!string.IsNullOrEmpty(term)) query.Append("&term=").Append(Uri.EscapeDataString(term));
            if (!string.IsNullOrEmpty(Environment.GetEnvironmentVariable("WT_SESSION"))) query.Append("&wt=1");
            // Bir kere daha dene (TelepAIth o an meşgulse ya da yeni açılıyorsa)
            if (!Local.Post("/event?" + query, body, waitMs: 1500))
            {
                Thread.Sleep(250);
                Local.Post("/event?" + query, body, waitMs: 1500);
            }
            return 0;
        }
        case "permission":
        {
            // Claude Code izin istiyor: robotun balonundaki cevabı bekle, kararı yaz.
            // TelepAIth kapalıysa ya da cevap vermezse hiçbir şey yazmaz: soru her zamanki gibi terminalde çıkar.
            if (Environment.GetEnvironmentVariable("CLAUDEBAR_PROBE") == "1") return 0;
            var source = args.Length > 1 && !args[1].StartsWith("__") ? args[1] : "claude";
            var body = ReadStdin();
            var query = new StringBuilder("source=" + Uri.EscapeDataString(source));
            var ppid = Native.ParentPid();
            if (ppid > 0) query.Append("&ppid=").Append(ppid);
            var term = Environment.GetEnvironmentVariable("TERM_PROGRAM");
            if (!string.IsNullOrEmpty(term)) query.Append("&term=").Append(Uri.EscapeDataString(term));
            var answer = Local.Ask("/permission?" + query, body, TimeSpan.FromSeconds(590));
            if (!string.IsNullOrWhiteSpace(answer))
            {
                var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true };
                stdout.Write(answer);
            }
            return 0;
        }
        case "shield":
        {
            var decision = Shield.Decide(ReadStdin());
            if (decision != null) Console.Out.Write(decision);
            return 0;
        }
        case "mcp":
        {
            var source = "claude";
            var i = Array.IndexOf(args, "--source");
            if (i >= 0 && i + 1 < args.Length) source = args[i + 1];
            Console.InputEncoding = new UTF8Encoding(false);
            var stdout = new StreamWriter(Console.OpenStandardOutput(), new UTF8Encoding(false)) { AutoFlush = true, NewLine = "\n" };
            var server = new McpServer(source, b => Local.Post("/event?source=" + Uri.EscapeDataString(source), b.ToJsonString(), waitMs: 3000));
            string? line;
            while ((line = Console.In.ReadLine()) != null)
            {
                var reply = server.Handle(line);
                if (reply != null) stdout.WriteLine(reply);
            }
            return 0;
        }
        default:
            Console.Error.WriteLine("TelepAIthHook: hook <source> | shield | mcp [--source claude]");
            return 0;
    }
}
catch
{
    // Hook asla Claude Code'u ya da Codex'i bozmamalı
    return 0;
}

static string ReadStdin()
{
    using var stdin = Console.OpenStandardInput();
    using var reader = new StreamReader(stdin, new UTF8Encoding(false));
    return reader.ReadToEnd();
}

/// <summary>Çalışan TelepAIth'e yerel HTTP ile gönderir (HttpClient yerine ham soket: çok daha hızlı açılır).</summary>
static class Local
{
    private static int Port()
    {
        try
        {
            if (File.Exists(AppInfo.PortFile) && int.TryParse(File.ReadAllText(AppInfo.PortFile).Trim(), out var p)) return p;
        }
        catch { }
        return AppInfo.DefaultPort;
    }

    public static bool Post(string pathAndQuery, string body, int waitMs)
    {
        var port = Port();
        try
        {
            using var client = new TcpClient();
            if (!client.ConnectAsync(System.Net.IPAddress.Loopback, port).Wait(1500)) return Fail($"connect timeout :{port}");
            client.ReceiveTimeout = waitMs;
            client.SendTimeout = waitMs;
            var payload = Encoding.UTF8.GetBytes(body);
            var head = Encoding.ASCII.GetBytes(
                $"POST {pathAndQuery} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n");
            using var stream = client.GetStream();
            stream.Write(head);
            stream.Write(payload);
            var buf = new byte[64];
            var n = stream.Read(buf, 0, buf.Length);
            var reply = n > 0 ? Encoding.ASCII.GetString(buf, 0, n) : "";
            var ok = reply.Contains(" 200 ");
            if (ok && Environment.GetEnvironmentVariable("TELEPAITH_HOOK_DEBUG") == "1")
                Console.Error.WriteLine($"TelepAIthHook: ok :{port} {pathAndQuery} ({payload.Length} B)");
            return ok || Fail("reply: " + reply.Split('\r')[0]);
        }
        catch (Exception ex)
        {
            return Fail(ex.GetType().Name + ": " + ex.Message);
        }
    }

    /// <summary>İstek gönderir ve cevabın gövdesini (uzun süre bekleyerek) döner; hata olursa null.</summary>
    public static string? Ask(string pathAndQuery, string body, TimeSpan wait)
    {
        try
        {
            var port = Port();
            using var client = new TcpClient();
            if (!client.ConnectAsync(System.Net.IPAddress.Loopback, port).Wait(1500)) { Fail($"connect timeout :{port}"); return null; }
            client.ReceiveTimeout = (int)wait.TotalMilliseconds;
            client.SendTimeout = 3000;
            using var stream = client.GetStream();
            var payload = Encoding.UTF8.GetBytes(body);
            var head = Encoding.ASCII.GetBytes(
                $"POST {pathAndQuery} HTTP/1.1\r\nHost: 127.0.0.1\r\nContent-Type: application/json\r\nContent-Length: {payload.Length}\r\nConnection: close\r\n\r\n");
            stream.Write(head);
            stream.Write(payload);
            using var ms = new MemoryStream();
            var buf = new byte[8192];
            int n;
            while ((n = stream.Read(buf, 0, buf.Length)) > 0) ms.Write(buf, 0, n);
            var reply = Encoding.UTF8.GetString(ms.ToArray());
            var split = reply.IndexOf("\r\n\r\n", StringComparison.Ordinal);
            if (!reply.Contains(" 200 ") || split < 0) { Fail("reply: " + reply.Split('\r')[0]); return null; }
            return reply[(split + 4)..];
        }
        catch (Exception ex)
        {
            Fail(ex.GetType().Name + ": " + ex.Message);
            return null;
        }
    }

    /// <summary>TELEPAITH_HOOK_DEBUG=1 ise nedenini stderr'e yazar (normalde sessiz: hook'lar Claude Code'u rahatsız etmesin)</summary>
    private static bool Fail(string why)
    {
        if (Environment.GetEnvironmentVariable("TELEPAITH_HOOK_DEBUG") == "1") Console.Error.WriteLine("TelepAIthHook: " + why);
        return false;
    }
}

/// <summary>Ebeveyn sürecin kimliği: TelepAIth bundan terminal penceresini bulur (balona tıklayınca oraya gitmek için).</summary>
static class Native
{
    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessBasicInformation
    {
        public IntPtr Reserved1;
        public IntPtr PebBaseAddress;
        public IntPtr Reserved2_0;
        public IntPtr Reserved2_1;
        public IntPtr UniqueProcessId;
        public IntPtr InheritedFromUniqueProcessId;
    }

    [DllImport("ntdll.dll")]
    private static extern int NtQueryInformationProcess(IntPtr process, int infoClass, ref ProcessBasicInformation info, int size, out int returned);

    [DllImport("kernel32.dll")]
    private static extern IntPtr GetCurrentProcess();

    public static int ParentPid()
    {
        if (!OperatingSystem.IsWindows()) return 0;
        try
        {
            var info = new ProcessBasicInformation();
            var status = NtQueryInformationProcess(GetCurrentProcess(), 0, ref info, Marshal.SizeOf<ProcessBasicInformation>(), out _);
            return status == 0 ? info.InheritedFromUniqueProcessId.ToInt32() : 0;
        }
        catch
        {
            return 0;
        }
    }
}
