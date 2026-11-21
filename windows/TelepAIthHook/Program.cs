using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json.Nodes;
using TelepAIth.Core;

// TelepAIthHook.exe hook <kaynak>   → stdin'deki olayı TelepAIth'e iletir (hiçbir şey yazmaz: Claude Code çıktıyı bağlama ekleyebilir)
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
            Local.Post("/event?" + query, body, waitMs: 1500);
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
    public static bool Post(string pathAndQuery, string body, int waitMs)
    {
        var port = AppInfo.DefaultPort;
        try
        {
            if (File.Exists(AppInfo.PortFile) && int.TryParse(File.ReadAllText(AppInfo.PortFile).Trim(), out var p)) port = p;
        }
        catch { }
        try
        {
            using var client = new TcpClient();
            if (!client.ConnectAsync("127.0.0.1", port).Wait(500)) return false;
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
            return n > 12 && Encoding.ASCII.GetString(buf, 0, n).Contains(" 200 ");
        }
        catch
        {
            return false;
        }
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
