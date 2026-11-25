using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

public enum HookTarget { Claude, Codex }

/// <summary>
/// Claude Code ve Codex'e "olayları TelepAIth'e gönder" hook'larını ekler/kaldırır.
/// Hook, küçük bir yardımcı programı (TelepAIthHook.exe) çağırır: olayı okur, yerel olarak iletir, hemen çıkar.
/// Kendi kayıtlarımızı __telepaith_hook işaretiyle tanırız, başka araçların hook'larına dokunmayız.
/// </summary>
public static class HookInstaller
{
    public static string DisplayName(HookTarget t) => t == HookTarget.Claude ? "Claude Code" : "Codex (GPT)";

    public static string Source(HookTarget t) => t == HookTarget.Claude ? "claude" : "gpt";

    public static string FilePath(HookTarget t)
    {
        var home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile, Environment.SpecialFolderOption.DoNotVerify);
        if (t == HookTarget.Claude)
        {
            // Claude Code, ayar klasörünü CLAUDE_CONFIG_DIR ile değiştirmeye izin veriyor
            var dir = Environment.GetEnvironmentVariable("CLAUDE_CONFIG_DIR");
            return Path.Combine(!string.IsNullOrEmpty(dir) ? dir : Path.Combine(home, ".claude"), "settings.json");
        }
        var custom = Environment.GetEnvironmentVariable("CODEX_HOME");
        return !string.IsNullOrEmpty(custom) ? Path.Combine(custom, "hooks.json") : Path.Combine(home, ".codex", "hooks.json");
    }

    public static (string Name, string? Matcher)[] Events(HookTarget t) => t == HookTarget.Claude
        ? new (string, string?)[]
        {
            ("SessionStart", null), ("SessionEnd", null), ("UserPromptSubmit", null), ("PreToolUse", "*"), ("PostToolUse", "*"),
            ("PostToolUseFailure", "*"), ("Notification", null), ("Stop", null), ("StopFailure", null), ("SubagentStart", null), ("PreCompact", null),
        }
        : new (string, string?)[]
        {
            ("SessionStart", null), ("SessionEnd", null), ("UserPromptSubmit", null), ("PreToolUse", "*"), ("PostToolUse", "*"),
            ("PermissionRequest", "*"), ("Stop", null), ("SubagentStart", null), ("PreCompact", null), ("Interrupt", null),
        };

    /// <summary>Yolu her kabukta (bash, cmd, PowerShell) çalışacak biçimde yaz: ileri eğik çizgi, boşluk varsa tırnak.</summary>
    public static string ShellPath(string exePath)
    {
        var p = exePath.Replace('\\', '/');
        return p.Contains(' ') ? "\"" + p + "\"" : p;
    }

    /// <summary>Hook komutu: yardımcı olay JSON'unu okur, TelepAIth'e iletir, hemen çıkar.</summary>
    public static string Command(string helperPath, string source) => $"{ShellPath(helperPath)} hook {source} {AppInfo.HookMarker}";

    /// <summary>Kalkan: tehlikeli görünen komutlarda Claude Code'un onay sormasını sağlar (engellemez).</summary>
    public static string ShieldCommand(string helperPath) => $"{ShellPath(helperPath)} shield {AppInfo.HookMarker}_shield";

    /// <summary>İzin isteği: robotun cevabını bekler (en fazla ~10 dk), kararı Claude Code'a yazar.</summary>
    public static string PermissionCommand(string helperPath, string source) => $"{ShellPath(helperPath)} permission {source} {AppInfo.HookMarker}_permission";

    public static bool IsInstalled(HookTarget t)
    {
        try
        {
            var path = FilePath(t);
            return File.Exists(path) && File.ReadAllText(path).Contains(AppInfo.HookMarker);
        }
        catch { return false; }
    }

    public static void Install(HookTarget t, string helperPath, bool shield)
    {
        var path = FilePath(t);
        var root = Load(path);
        var hooks = root["hooks"] as JsonObject ?? new JsonObject();
        root["hooks"] = hooks;
        var cmd = Command(helperPath, Source(t));
        foreach (var (name, matcher) in Events(t))
        {
            var groups = Cleaned(hooks[name] as JsonArray);
            var group = new JsonObject { ["hooks"] = new JsonArray(new JsonObject { ["type"] = "command", ["command"] = cmd }) };
            if (matcher != null) group["matcher"] = matcher;
            groups.Add(group);
            if (t == HookTarget.Claude && name == "PreToolUse" && shield)
            {
                // Windows'ta Claude Code komutları Bash ya da PowerShell aracıyla çalıştırabilir
                groups.Add(new JsonObject
                {
                    ["matcher"] = "Bash|PowerShell",
                    ["hooks"] = new JsonArray(new JsonObject { ["type"] = "command", ["command"] = ShieldCommand(helperPath) }),
                });
            }
            hooks[name] = groups;
        }
        if (t == HookTarget.Claude)
        {
            // Robottan onay: Claude Code izin sormadan önce robotun balonunda İzin ver / Reddet
            var groups = Cleaned(hooks["PermissionRequest"] as JsonArray);
            groups.Add(new JsonObject
            {
                ["hooks"] = new JsonArray(new JsonObject
                {
                    ["type"] = "command", ["command"] = PermissionCommand(helperPath, Source(t)), ["timeout"] = 600,
                }),
            });
            hooks["PermissionRequest"] = groups;
        }
        Save(root, path);
    }

    public static void Uninstall(HookTarget t)
    {
        var path = FilePath(t);
        if (!File.Exists(path)) return;
        var root = Load(path);
        if (root["hooks"] is not JsonObject hooks) return;
        foreach (var name in hooks.Select(kv => kv.Key).ToList())
        {
            if (hooks[name] is not JsonArray groups) continue;
            var kept = Cleaned(groups);
            if (kept.Count == 0) hooks.Remove(name);
            else hooks[name] = kept;
        }
        if (hooks.Count == 0) root.Remove("hooks");
        Save(root, path);
    }

    /// <summary>Bizim komutlarımızı çıkarır; içinde başka komut kalmayan grubu siler.</summary>
    private static JsonArray Cleaned(JsonArray? groups)
    {
        var result = new JsonArray();
        if (groups == null) return result;
        foreach (var g in groups)
        {
            if (g is not JsonObject group) continue;
            if (group["hooks"] is not JsonArray handlers)
            {
                result.Add(group.DeepClone());
                continue;
            }
            var kept = new JsonArray();
            foreach (var h in handlers)
            {
                var command = h.Str("command") ?? "";
                if (!command.Contains(AppInfo.HookMarker)) kept.Add(h?.DeepClone());
            }
            if (kept.Count == 0 && handlers.Count > 0) continue;
            var copy = (JsonObject)group.DeepClone();
            copy["hooks"] = kept;
            result.Add(copy);
        }
        return result;
    }

    internal static JsonObject Load(string path)
    {
        if (!File.Exists(path)) return new JsonObject();
        var text = File.ReadAllText(path);
        if (string.IsNullOrWhiteSpace(text)) return new JsonObject();
        try
        {
            if (JsonNode.Parse(text) is JsonObject o) return o;
        }
        catch { /* aşağıda hata */ }
        throw new InvalidDataException(L($"{path} geçerli bir JSON değil. Dosyayı düzeltip tekrar dene.",
                                         $"{path} isn't valid JSON. Fix the file and try again."));
    }

    internal static void Save(JsonObject root, string path)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        // İlk değişiklikten önce bir kez yedek al
        var backup = path + ".telepaith-backup";
        if (File.Exists(path) && !File.Exists(backup)) File.Copy(path, backup);
        var tmp = path + ".tmp";
        File.WriteAllText(tmp, root.ToJsonString(new JsonSerializerOptions { WriteIndented = true }), new UTF8Encoding(false));
        File.Move(tmp, path, true);
    }
}

/// <summary>
/// Kullanım sınırları için Claude Code'un durum satırı (statusLine): komutumuz gelen JSON'u TelepAIth'e iletir, sonra
/// kullanıcının önceki durum satırını aynı girdiyle çalıştırıp çıktısını basar (onunki görünmeye devam eder).
/// Önceki satır ~/.telepaith/statusline-theirs.json'da saklanır, bağlantı kesilince geri konur.
/// </summary>
public static class UsageLine
{
    public const string Marker = "__telepaith_line";
    public static string TheirsFile => Path.Combine(AppInfo.SupportDir, "statusline-theirs.json");
    /// <summary>Mac'teki kabuk komutu okusun diye sadece komut metni</summary>
    public static string TheirsCommandFile => Path.Combine(AppInfo.SupportDir, "statusline-theirs");

    public static string Command(string helperPath) => $"{HookInstaller.ShellPath(helperPath)} statusline {Marker}";

    private static bool IsOurs(JsonNode? line) => (line.Str("command") ?? "").Contains(Marker);

    public static bool IsConnected()
    {
        try
        {
            var path = HookInstaller.FilePath(HookTarget.Claude);
            return File.Exists(path) && IsOurs(HookInstaller.Load(path)["statusLine"]);
        }
        catch { return false; }
    }

    public static void Connect(string command)
    {
        var path = HookInstaller.FilePath(HookTarget.Claude);
        var root = HookInstaller.Load(path);
        var current = root["statusLine"];
        if (current is JsonObject theirs && !IsOurs(theirs))
        {
            File.WriteAllText(TheirsFile, theirs.ToJsonString());
            File.WriteAllText(TheirsCommandFile, theirs.Str("command") ?? "");
        }
        else if (current == null)
        {
            File.Delete(TheirsFile);
            File.Delete(TheirsCommandFile);
        }
        var ours = new JsonObject { ["type"] = "command", ["command"] = command };
        if (current is JsonObject old && old["padding"] is { } padding) ours["padding"] = padding.DeepClone();
        root["statusLine"] = ours;
        HookInstaller.Save(root, path);
    }

    public static void Disconnect()
    {
        var path = HookInstaller.FilePath(HookTarget.Claude);
        if (!File.Exists(path)) return;
        var root = HookInstaller.Load(path);
        if (!IsOurs(root["statusLine"])) return;
        JsonNode? theirs = null;
        try { if (File.Exists(TheirsFile)) theirs = JsonNode.Parse(File.ReadAllText(TheirsFile)); } catch { }
        if (theirs is JsonObject) root["statusLine"] = theirs;
        else root.Remove("statusLine");
        HookInstaller.Save(root, path);
        File.Delete(TheirsFile);
        File.Delete(TheirsCommandFile);
    }

    /// <summary>Kullanıcının önceki durum satırı komutu (yoksa null)</summary>
    public static string? TheirsCommand()
    {
        try { return File.Exists(TheirsFile) ? JsonNode.Parse(File.ReadAllText(TheirsFile)).Str("command") : null; }
        catch { return null; }
    }
}

/// <summary>Kalkan kuralı: komut tehlikeli görünüyorsa Claude Code'a "onay sor" cevabı.</summary>
public static class Shield
{
    public static string? Decide(string hookJson)
    {
        try
        {
            var j = JsonNode.Parse(hookJson) as JsonObject;
            var input = j.Obj("tool_input");
            var cmd = ToolDescriber.CommandString(input) ?? "";
            if (!Reactions.IsScary(cmd)) return null;
        }
        catch
        {
            return null;
        }
        var output = new JsonObject
        {
            ["hookSpecificOutput"] = new JsonObject
            {
                ["hookEventName"] = "PreToolUse",
                ["permissionDecision"] = "ask",
                ["permissionDecisionReason"] = "TelepAIth kalkanı: tehlikeli görünen komut, onayın gerekiyor.",
            },
        };
        return output.ToJsonString();
    }
}

/// <summary>Anlatıcıyı Claude masaüstünün MCP ayarına ekler/kaldırır.</summary>
public static class NarratorInstaller
{
    public static string ClaudeDesktopConfig =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Claude", "claude_desktop_config.json");

    public static string SuggestedInstruction => L(
        "Çalışırken her önemli adımın başında telepaith_say aracıyla ne yaptığını kısa Türkçe bir cümleyle söyle, iş bitince state \"done\" ile haber ver.",
        "While working, call the telepaith_say tool with a very short sentence at the start of each meaningful step, and once with state \"done\" when you finish.");

    public static string ClaudeCodeCommand(string helperPath) =>
        $"claude mcp add --scope user telepaith -- {HookInstaller.ShellPath(helperPath)} mcp --source claude";

    public static bool IsInstalled()
    {
        try
        {
            return File.Exists(ClaudeDesktopConfig) && HookInstaller.Load(ClaudeDesktopConfig)["mcpServers"] is JsonObject s && s["telepaith"] != null;
        }
        catch { return false; }
    }

    public static void Install(string helperPath)
    {
        var root = HookInstaller.Load(ClaudeDesktopConfig);
        var servers = root["mcpServers"] as JsonObject ?? new JsonObject();
        servers["telepaith"] = new JsonObject
        {
            ["command"] = helperPath,
            ["args"] = new JsonArray("mcp", "--source", "claude"),
        };
        root["mcpServers"] = servers;
        HookInstaller.Save(root, ClaudeDesktopConfig);
    }

    public static void Uninstall()
    {
        if (!File.Exists(ClaudeDesktopConfig)) return;
        var root = HookInstaller.Load(ClaudeDesktopConfig);
        if (root["mcpServers"] is JsonObject servers) servers.Remove("telepaith");
        HookInstaller.Save(root, ClaudeDesktopConfig);
    }
}

/// <summary>Anlatıcı: küçük bir MCP sunucusu (stdio, JSON-RPC). telepaith_say aracıyla robota söyletir.</summary>
public sealed class McpServer
{
    public const string ToolName = "telepaith_say";
    private readonly string _source;
    private readonly Func<JsonObject, bool> _send;

    public McpServer(string source, Func<JsonObject, bool> send)
    {
        _source = source;
        _send = send;
    }

    private const string Instructions =
        "TelepAIth is a small robot on the user's screen. Call telepaith_say at the start of each meaningful step " +
        "(reading, searching, editing, running commands, testing) with a very short sentence in the user's language, " +
        "and once at the end with state \"done\". Keep it under ~8 words.";

    private static JsonObject ToolSpec() => new()
    {
        ["name"] = ToolName,
        ["description"] = "Show what you are doing right now in the speech bubble of the user's desktop robot (TelepAIth). " +
                          "Call it when you start a meaningful step (e.g. \"Dosyaları inceliyorum\", \"Testleri çalıştırıyorum\") " +
                          "and once when you finish (state \"done\"). Keep the text very short and in the user's language. " +
                          "It only displays the text; it has no other effect.",
        ["inputSchema"] = new JsonObject
        {
            ["type"] = "object",
            ["properties"] = new JsonObject
            {
                ["text"] = new JsonObject { ["type"] = "string", ["description"] = "Short sentence (max ~8 words) in the user's language." },
                ["state"] = new JsonObject
                {
                    ["type"] = "string",
                    ["enum"] = new JsonArray("thinking", "reading", "searching", "editing", "running", "waiting", "done", "error"),
                    ["description"] = "What kind of step this is. Use 'done' when the whole task is finished.",
                },
                ["emoji"] = new JsonObject { ["type"] = "string", ["description"] = "Optional single emoji that fits the step." },
            },
            ["required"] = new JsonArray("text"),
        },
    };

    /// <summary>Bir JSON-RPC satırını işler; cevap gerekiyorsa cevap satırını döner.</summary>
    public string? Handle(string line)
    {
        JsonObject? msg;
        try { msg = JsonNode.Parse(line) as JsonObject; } catch { return null; }
        if (msg == null) return null;
        var id = msg["id"]?.DeepClone();
        var method = msg.Str("method") ?? "";
        var p = msg.Obj("params");
        switch (method)
        {
            case "initialize":
                return Reply(id, new JsonObject
                {
                    ["protocolVersion"] = p.Str("protocolVersion") ?? "2025-06-18",
                    ["capabilities"] = new JsonObject { ["tools"] = new JsonObject() },
                    ["serverInfo"] = new JsonObject { ["name"] = "telepaith", ["version"] = AppInfo.Version },
                    ["instructions"] = Instructions,
                });
            case "ping":
                return Reply(id, new JsonObject());
            case "tools/list":
                return Reply(id, new JsonObject { ["tools"] = new JsonArray(ToolSpec()) });
            case "tools/call":
            {
                var name = p.Str("name") ?? "";
                if (name != ToolName) return Error(id, -32602, "Unknown tool: " + name);
                var args = p.Obj("arguments");
                var body = new JsonObject
                {
                    ["session"] = "mcp",
                    ["text"] = args.Str("text") ?? "",
                    ["state"] = args.Str("state") ?? "thinking",
                };
                var emoji = args.Str("emoji");
                if (!string.IsNullOrEmpty(emoji)) body["emoji"] = emoji;
                var ok = _send(body);
                var text = ok ? "ok" : "TelepAIth is not running; message not shown.";
                return Reply(id, new JsonObject
                {
                    ["content"] = new JsonArray(new JsonObject { ["type"] = "text", ["text"] = text }),
                    ["isError"] = false,
                });
            }
            default:
                // Bildirimlere (id'siz) cevap verilmez
                if (id != null && !method.StartsWith("notifications/")) return Error(id, -32601, "Method not found: " + method);
                return null;
        }
    }

    public string Source => _source;

    private static string Reply(JsonNode? id, JsonObject result) =>
        new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id, ["result"] = result }.ToJsonString();

    private static string Error(JsonNode? id, int code, string message) =>
        new JsonObject { ["jsonrpc"] = "2.0", ["id"] = id, ["error"] = new JsonObject { ["code"] = code, ["message"] = message } }.ToJsonString();
}

/// <summary>Yerel HTTP isteği (sadece TelepAIth'in ihtiyacı kadar).</summary>
public sealed class HttpRequest
{
    public string Method = "";
    public string Path = "/";
    public Dictionary<string, string> Query = new();
    public Dictionary<string, string> Headers = new(StringComparer.OrdinalIgnoreCase);
    public string Body = "";

    public const int MaxBytes = 8 * 1024 * 1024;

    /// <summary>
    /// Ham baytlardan isteği çıkarır. Tamamlanmadıysa null; çok büyükse InvalidDataException.
    /// </summary>
    public static HttpRequest? TryParse(byte[] data, int length)
    {
        if (length > MaxBytes) throw new InvalidDataException("too large");
        var headerEnd = IndexOf(data, length, "\r\n\r\n"u8);
        if (headerEnd < 0) return null;
        var head = Encoding.ASCII.GetString(data, 0, headerEnd);
        var lines = head.Split("\r\n");
        var first = lines[0].Split(' ');
        if (first.Length < 2) throw new InvalidDataException("bad request line");
        var req = new HttpRequest { Method = first[0].ToUpperInvariant() };
        var target = first[1];
        var q = target.IndexOf('?');
        req.Path = q >= 0 ? target[..q] : target;
        if (q >= 0)
        {
            foreach (var pair in target[(q + 1)..].Split('&', StringSplitOptions.RemoveEmptyEntries))
            {
                var eq = pair.IndexOf('=');
                var k = Uri.UnescapeDataString((eq >= 0 ? pair[..eq] : pair).Replace('+', ' '));
                var v = eq >= 0 ? Uri.UnescapeDataString(pair[(eq + 1)..].Replace('+', ' ')) : "";
                req.Query[k] = v;
            }
        }
        foreach (var line in lines.Skip(1))
        {
            var c = line.IndexOf(':');
            if (c > 0) req.Headers[line[..c].Trim()] = line[(c + 1)..].Trim();
        }
        var contentLength = req.Headers.TryGetValue("Content-Length", out var cl) && int.TryParse(cl, out var n) ? n : 0;
        if (contentLength > MaxBytes) throw new InvalidDataException("too large");
        var bodyStart = headerEnd + 4;
        if (length - bodyStart < contentLength) return null;
        req.Body = Encoding.UTF8.GetString(data, bodyStart, contentLength);
        return req;
    }

    /// <summary>"Expect: 100-continue" gönderen istemciler gövdeyi göndermeden önce cevap bekler.</summary>
    public static bool WantsContinue(byte[] data, int length)
    {
        var headerEnd = IndexOf(data, length, "\r\n\r\n"u8);
        if (headerEnd < 0) return false;
        return Encoding.ASCII.GetString(data, 0, headerEnd).Contains("100-continue", StringComparison.OrdinalIgnoreCase);
    }

    private static int IndexOf(byte[] data, int length, ReadOnlySpan<byte> pattern) =>
        data.AsSpan(0, length).IndexOf(pattern);
}


/// <summary>Robottan onay: Claude Code'un PermissionRequest hook'una dönen karar.</summary>
public enum ApprovalChoice { Allow, Always, Deny }

public static class Approval
{
    /// <summary>Balondan izin verilebilecek en uzun komut (tamamı balonda okunabilsin).</summary>
    public const int MaxAllowLength = 120;
    private static readonly string[] PlainKeys = { "command", "description", "timeout", "run_in_background" };

    /// <summary>
    /// "İzin ver" sadece tamamı okunabilen kısa, tek satırlık bir kabuk komutunda gösterilir. Dosya düzenlemesi (balon
    /// değişikliği göstermez), uzun komut ya da ne yaptığını söylemeyen araç balondan sadece reddedilebilir.
    /// </summary>
    public static bool CanAllow(string? tool, JsonObject input)
    {
        if (tool is not ("Bash" or "PowerShell")) return false;
        var cmd = ToolDescriber.CommandString(input);
        if (string.IsNullOrWhiteSpace(cmd) || cmd.Contains('\n') || cmd.Contains('\r') || cmd.Length > MaxAllowLength) return false;
        return input.All(kv => PlainKeys.Contains(kv.Key));
    }

    public static bool CanAllow(string body)
    {
        try { return JsonNode.Parse(body) is JsonObject j && CanAllow(j.Str("tool_name"), j.Obj("tool_input")); }
        catch { return false; }
    }

    /// <summary>Claude'un önerdiği izin kuralları (permission_suggestions) varsa "Hep izin ver" gösterilir.</summary>
    public static JsonArray? Suggestions(string body)
    {
        try { return (JsonNode.Parse(body) as JsonObject)?["permission_suggestions"] as JsonArray is { Count: > 0 } a ? a : null; }
        catch { return null; }
    }

    public static string Decision(ApprovalChoice choice, JsonArray? suggestions)
    {
        var decision = new JsonObject();
        switch (choice)
        {
            case ApprovalChoice.Deny:
                decision["behavior"] = "deny";
                decision["message"] = L("Kullanıcı bunu TelepAIth robotundan reddetti.", "The user declined this from the TelepAIth robot.");
                break;
            case ApprovalChoice.Always when suggestions != null:
                decision["behavior"] = "allow";
                decision["updatedPermissions"] = suggestions.DeepClone();
                break;
            default:
                decision["behavior"] = "allow";
                break;
        }
        return new JsonObject
        {
            ["hookSpecificOutput"] = new JsonObject { ["hookEventName"] = "PermissionRequest", ["decision"] = decision },
        }.ToJsonString();
    }
}
