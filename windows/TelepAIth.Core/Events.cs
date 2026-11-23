using System.Text.Json.Nodes;
using System.Text.RegularExpressions;
using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

public enum RobotState { Idle, Thinking, Reading, Searching, Editing, Running, Delegating, Waiting, Done, Error, Sleeping }

public static class RobotStateInfo
{
    public static bool IsWorking(this RobotState s) =>
        s is RobotState.Thinking or RobotState.Reading or RobotState.Searching or RobotState.Editing
            or RobotState.Running or RobotState.Delegating;

    /// <summary>Birden fazla oturum varken hangisinin gösterileceği.</summary>
    public static int Priority(this RobotState s) => s switch
    {
        RobotState.Waiting => 6,
        RobotState.Error => 5,
        RobotState.Done => 3,
        RobotState.Idle => 2,
        RobotState.Sleeping => 1,
        _ => 4,
    };

    public static string Label(this RobotState s) => s switch
    {
        RobotState.Idle => L("Boşta", "Idle"),
        RobotState.Thinking => L("Düşünüyor", "Thinking"),
        RobotState.Reading => L("Okuyor", "Reading"),
        RobotState.Searching => L("Arıyor", "Searching"),
        RobotState.Editing => L("Düzenliyor", "Editing"),
        RobotState.Running => L("Komut çalıştırıyor", "Running a command"),
        RobotState.Delegating => L("Alt ajan çalıştırıyor", "Running a subagent"),
        RobotState.Waiting => L("Seni bekliyor", "Waiting for you"),
        RobotState.Done => L("Bitti", "Done"),
        RobotState.Error => L("Hata", "Error"),
        _ => L("Uyuyor", "Sleeping"),
    };

    /// <summary>Olayın kendi emojisi yoksa kullanılan emoji.</summary>
    public static string Emoji(this RobotState s) => s switch
    {
        RobotState.Idle => "🙂",
        RobotState.Thinking => "🔮",
        RobotState.Reading => "📖",
        RobotState.Searching => "🔍",
        RobotState.Editing => "✍️",
        RobotState.Running => "💻",
        RobotState.Delegating => "🧙",
        RobotState.Waiting => "✋",
        RobotState.Done => "🎉",
        RobotState.Error => "💥",
        _ => "😴",
    };

    public static RobotState? Parse(string raw) => raw.ToLowerInvariant() switch
    {
        "idle" => RobotState.Idle, "thinking" => RobotState.Thinking, "reading" => RobotState.Reading,
        "searching" => RobotState.Searching, "editing" => RobotState.Editing, "running" => RobotState.Running,
        "delegating" => RobotState.Delegating, "waiting" => RobotState.Waiting, "done" => RobotState.Done,
        "error" => RobotState.Error, "sleeping" => RobotState.Sleeping,
        _ => null,
    };
}

/// <summary>Kısa süreli ruh hâli: gözlerin desenini ve emojiyi değiştirir.</summary>
public enum Mood { Pleased, Shocked, Nervous, Scared, Proud, Party, Tired, Dizzy, Denied }

public enum EventKind { SessionStart, Prompt, Tool, Status, ToolDone, Waiting, Stop, Failure, Interrupt, SessionEnd, Quota, Generic, Heartbeat, Say }

/// <summary>Tıklayınca gidilecek yer: bir süreç ya da bir uygulama (süreç adı).</summary>
public sealed record AppTarget(int? Pid, string? ProcessName)
{
    public bool IsEmpty => Pid == null && string.IsNullOrEmpty(ProcessName);

    /// <summary>Hook yardımcısının gönderdiği terminal bilgisinden süreç adı.</summary>
    public static string? ProcessFromHook(string? term, bool windowsTerminal)
    {
        switch ((term ?? "").ToLowerInvariant())
        {
            case "vscode": return "Code";
            case "warpterminal": return "warp";
            case "wezterm": return "wezterm-gui";
            case "tabby": return "Tabby";
            case "hyper": return "Hyper";
        }
        return windowsTerminal ? "WindowsTerminal" : null;
    }
}

public sealed class AgentEvent
{
    public string Source = "custom";
    public string SessionId = "default";
    public EventKind Kind = EventKind.Heartbeat;
    public RobotState? State;
    public string? Text;
    public string? Project;
    public string? LastMessage;
    public bool ForceNotify;
    public string? Emoji;
    public Mood? Mood;
    public double MoodSeconds = 3;
    /// <summary>Bu süreç öndeyken bildirim gösterme (kullanıcı zaten bakıyor)</summary>
    public int? QuietIfForegroundPid;
    /// <summary>Bildirim atma (ör. işlemciden tahmin edilen "bitti": emin değiliz, sadece robot gösterir)</summary>
    public bool NoNotice;
    /// <summary>Balona ya da bildirime tıklayınca öne getirilecek uygulama</summary>
    public int? AppPid;
    public string? AppProcess;
    /// <summary>Hook'u çalıştıran sürecin ebeveyni (uygulama bunu terminal penceresine çevirir)</summary>
    public int? HookParentPid;
    /// <summary>ClaudeBar'dan gelen kalan kota yüzdesi</summary>
    public int? QuotaLeft;

    public AgentEvent() { }

    public AgentEvent(string source, string sessionId, EventKind kind, RobotState? state = null, string? text = null,
                      string? project = null, string? emoji = null)
    {
        Source = source;
        SessionId = sessionId;
        Kind = kind;
        State = state;
        Text = text;
        Project = project;
        Emoji = emoji;
    }
}

internal static class J
{
    public static string? Str(this JsonNode? node, string key) =>
        node is JsonObject o && o[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;

    public static bool? Bool(this JsonNode? node, string key) =>
        node is JsonObject o && o[key] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : null;

    public static double? Num(this JsonNode? node, string key)
    {
        if (node is not JsonObject o || o[key] is not JsonValue v) return null;
        if (v.TryGetValue<double>(out var d)) return d;
        if (v.TryGetValue<long>(out var l)) return l;
        if (v.TryGetValue<int>(out var i)) return i;
        return null;
    }

    public static JsonObject Obj(this JsonNode? node, string key) =>
        node is JsonObject o && o[key] is JsonObject child ? child : new JsonObject();

    /// <summary>Nesnenin tüm metin değerleri (girdi içinde arama yapmak için)</summary>
    public static IEnumerable<string> StringValues(this JsonObject o)
    {
        foreach (var (_, v) in o)
            if (v is JsonValue jv && jv.TryGetValue<string>(out var s)) yield return s;
    }
}

/// <summary>Gelen HTTP isteğini robotun anlayacağı olaya çevirir.</summary>
public static class EventParser
{
    public static AgentEvent? Parse(string path, IReadOnlyDictionary<string, string> query, string body)
    {
        JsonNode? json = null;
        body = body.TrimStart('\uFEFF');   // Windows PowerShell boruları başa BOM ekleyebiliyor
        try { if (!string.IsNullOrWhiteSpace(body)) json = JsonNode.Parse(body); } catch { json = null; }
        var j = json as JsonObject ?? new JsonObject();
        if (path.StartsWith("/claudebar", StringComparison.Ordinal)) return ClaudeBar(j);
        query.TryGetValue("source", out var qs);
        var source = Themes.Canonical(qs ?? j.Str("agent") ?? "custom");
        var hook = j.Str("hook_event_name");
        var e = hook != null ? HookEvent(hook, j, source) : Generic(j, source);
        if (e == null) return null;
        query.TryGetValue("term", out var term);
        query.TryGetValue("wt", out var wt);
        query.TryGetValue("app", out var app);
        e.AppProcess = !string.IsNullOrWhiteSpace(app) ? app.Trim() : AppTarget.ProcessFromHook(term, wt == "1");
        if (query.TryGetValue("ppid", out var ppid) && int.TryParse(ppid, out var p) && p > 0) e.HookParentPid = p;
        return e;
    }

    // Claude Code ve Codex hook'ları (ikisi aynı formatı kullanıyor)
    private static AgentEvent HookEvent(string name, JsonObject j, string source)
    {
        var session = j.Str("session_id") ?? "default";
        var cwd = j.Str("cwd");
        var project = cwd != null ? LastPathComponent(cwd) : null;
        var e = new AgentEvent(source, session, EventKind.Heartbeat, project: project);
        var tool = j.Str("tool_name") ?? "";
        var input = j.Obj("tool_input");

        switch (name)
        {
            case "SessionStart":
                e.Kind = EventKind.SessionStart;
                e.State = RobotState.Idle;
                e.Emoji = "👋";
                e.Text = L("Yeni oturum", "New session") + (project != null ? ": " + project : "");
                break;
            case "UserPromptSubmit":
                e.Kind = EventKind.Prompt;
                e.State = RobotState.Thinking;
                e.Emoji = "🔮";
                e.Text = L("Düşünüyor…", "Thinking…");
                var prompt = j.Str("prompt");
                if (!string.IsNullOrWhiteSpace(prompt))
                {
                    e.Text = L("Düşünüyor…", "Thinking…") + "\n«" + Clip(prompt, 60) + "»";
                    var r = Reactions.OnPrompt(prompt);
                    if (r != null)
                    {
                        e.Mood = r.Value.Mood;
                        e.MoodSeconds = r.Value.Seconds;
                        e.Emoji = r.Value.Emoji;
                    }
                }
                break;
            case "PreToolUse":
            {
                var d = ToolDescriber.Describe(tool, input);
                e.Kind = d.State == RobotState.Waiting ? EventKind.Waiting : EventKind.Tool;
                e.State = d.State;
                e.Text = d.Text;
                e.Emoji = d.Emoji;
                var cmd = ToolDescriber.CommandString(input);
                if (d.State == RobotState.Running && cmd != null)
                {
                    if (Reactions.IsScary(cmd))
                    {
                        e.Mood = Core.Mood.Scared;
                        e.MoodSeconds = 5;
                        e.Emoji = "😱";
                        e.Text = L("Dikkat! ", "Careful! ") + Clip(cmd, 60);
                    }
                    else if (Reactions.IsTest(cmd))
                    {
                        e.Mood = Core.Mood.Nervous;
                        e.MoodSeconds = 4;
                    }
                }
                break;
            }
            case "PostToolUse":
            case "PostToolUseFailure":
            {
                e.Kind = EventKind.ToolDone;
                var response = j["tool_response"];
                var failed = name == "PostToolUseFailure" || Reactions.LooksFailed(response);
                var cmd = ToolDescriber.CommandString(input) ?? "";
                if (failed)
                {
                    e.State = RobotState.Error;   // sadece sayaç için; oturumun durumu değişmez
                    if (Reactions.IsTest(cmd))
                    {
                        e.Text = L("Testler kırıldı", "Tests failed");
                        e.Emoji = "😵";
                        e.Mood = Core.Mood.Dizzy;
                        e.MoodSeconds = 6;
                    }
                    else if (Reactions.WasRefused(response))
                    {
                        e.Text = L("İzin verilmedi: ", "Not allowed: ") + ToolDescriber.ShortName(tool);
                        e.Emoji = "🙅";
                        e.Mood = Core.Mood.Denied;
                        e.MoodSeconds = 4;
                    }
                    else
                    {
                        e.Text = L("Hata: ", "Error: ") + ToolDescriber.ShortName(tool);
                        e.Emoji = "😬";
                        e.Mood = Core.Mood.Nervous;
                        e.MoodSeconds = 4;
                    }
                }
                else if (cmd.Length > 0)
                {
                    if (Reactions.IsTest(cmd))
                    {
                        e.Text = L("Testler geçti!", "Tests passed!");
                        e.Emoji = "🎉";
                        e.Mood = Core.Mood.Party;
                        e.MoodSeconds = 5;
                    }
                    else if (Reactions.IsPush(cmd))
                    {
                        e.Text = L("Gönderildi!", "Pushed!");
                        e.Emoji = "🚀";
                        e.Mood = Core.Mood.Party;
                        e.MoodSeconds = 5;
                    }
                    else if (Reactions.IsCommit(cmd))
                    {
                        e.Text = L("Commit atıldı", "Committed");
                        e.Emoji = "💾";
                        e.Mood = Core.Mood.Proud;
                        e.MoodSeconds = 4;
                    }
                }
                break;
            }
            case "PermissionRequest":
            {
                e.Kind = EventKind.Waiting;
                e.State = RobotState.Waiting;
                e.Emoji = "✋";
                var desc = input.Str("description");
                var cmd = ToolDescriber.CommandString(input);
                var detail = desc != null ? " — " + Clip(desc, 60) : cmd != null ? " — " + Clip(cmd, 60) : "";
                e.Text = L("Onayını bekliyor: ", "Needs your approval: ") + ToolDescriber.ShortName(tool) + detail;
                break;
            }
            case "Notification":
            {
                e.Kind = EventKind.Waiting;
                e.State = RobotState.Waiting;
                var (text, emoji) = TranslateNotification(j.Str("message"));
                e.Text = text;
                e.Emoji = emoji;
                break;
            }
            case "Stop":
                e.Kind = EventKind.Stop;
                e.State = RobotState.Done;
                e.LastMessage = j.Str("last_assistant_message");
                break;
            case "StopFailure":
                e.Kind = EventKind.Failure;
                e.State = RobotState.Error;
                e.Emoji = "💥";
                var err = j.Str("error");
                e.Text = L("Bir hatayla durdu", "Stopped with an error") + (err != null ? ": " + Clip(err, 60) : "");
                break;
            case "SubagentStart":
                e.Kind = EventKind.Tool;
                e.State = RobotState.Delegating;
                e.Emoji = "🧙";
                e.Text = L("Alt ajan: ", "Subagent: ") + (j.Str("agent_type") ?? L("başladı", "started"));
                break;
            case "PreCompact":
                e.Kind = EventKind.Tool;
                e.State = RobotState.Thinking;
                e.Emoji = "🧠";
                e.Text = L("Hafızasını toparlıyor", "Tidying up its memory");
                break;
            case "Interrupt":
                e.Kind = EventKind.Interrupt;
                e.State = RobotState.Idle;
                e.Emoji = "⏹️";
                e.Text = L("Durduruldu", "Interrupted");
                e.Mood = Core.Mood.Shocked;
                e.MoodSeconds = 3;
                break;
            case "SessionEnd":
                e.Kind = EventKind.SessionEnd;
                e.Emoji = "👋";
                e.Text = L("Oturum kapandı", "Session ended");
                break;
            default:
                e.Kind = EventKind.Heartbeat;
                break;
        }
        return e;
    }

    private static (string Text, string Emoji) TranslateNotification(string? msg)
    {
        if (string.IsNullOrEmpty(msg)) return (L("Seni bekliyor", "Waiting for you"), "👀");
        var lower = msg.ToLowerInvariant();
        if (lower.Contains("permission"))
        {
            var i = msg.IndexOf("to use ", StringComparison.Ordinal);
            if (i >= 0) return (L("Onayını bekliyor: ", "Needs your approval: ") + msg[(i + 7)..], "✋");
            return (L("Onayını bekliyor", "Needs your approval"), "✋");
        }
        if (lower.Contains("waiting for your input")) return (L("Cevabını bekliyor", "Waiting for your reply"), "👀");
        return (Clip(msg, 90), "🔔");
    }

    // ClaudeBar webhook'u (JSON kanalı)
    private static AgentEvent ClaudeBar(JsonObject j)
    {
        var source = Themes.Canonical(j.Str("provider") ?? "claude");
        var type = j.Str("type") ?? "test";
        RobotState? state = null;
        string text;
        var emoji = "⚠️";
        int? quotaLeft = null;
        switch (type)
        {
            case "quota":
                emoji = "🔋";
                var left = j.Num("left");
                if (left != null)
                {
                    quotaLeft = (int)left.Value;
                    text = L($"Kalan kota: %{quotaLeft}", $"Quota left: {quotaLeft}%");
                }
                else
                {
                    text = L("Kota azalıyor", "Quota is running low");
                }
                break;
            case "status":
                switch (j.Str("status") ?? "")
                {
                    case "critical":
                        text = L("Kota kritik seviyede!", "Quota is critical!");
                        emoji = "🪫";
                        break;
                    case "depleted":
                        text = L("Kota bitti!", "Quota is used up!");
                        emoji = "🪫";
                        state = RobotState.Error;
                        break;
                    default:
                        text = L("Kota uyarısı", "Quota warning");
                        break;
                }
                break;
            case "signedOut":
                text = L("Oturumu kapanmış, tekrar giriş yap", "Signed out, please log in again");
                emoji = "🔑";
                break;
            case "recap":
                text = L("Haftalık özet geldi", "Your weekly recap is here");
                emoji = "📊";
                break;
            default:
                text = L("ClaudeBar bağlantısı çalışıyor", "ClaudeBar connection works");
                emoji = "🔗";
                break;
        }
        var login = j.Str("login");
        if (!string.IsNullOrEmpty(login)) text += $" ({login})";
        return new AgentEvent(source, "claudebar", EventKind.Quota, state, text, emoji: emoji)
        {
            ForceNotify = type != "recap",
            QuotaLeft = quotaLeft,
        };
    }

    // Genel format — başka bir AI'ı bağlamak için
    // POST /event?source=gemini  {"state": "running", "text": "Testler çalışıyor", "emoji": "🧪"}
    private static AgentEvent? Generic(JsonObject j, string source)
    {
        var synonyms = new Dictionary<string, RobotState>
        {
            ["working"] = RobotState.Thinking, ["busy"] = RobotState.Thinking, ["writing"] = RobotState.Editing,
            ["coding"] = RobotState.Editing, ["finished"] = RobotState.Done, ["complete"] = RobotState.Done,
            ["completed"] = RobotState.Done, ["blocked"] = RobotState.Waiting, ["needs_input"] = RobotState.Waiting,
            ["failed"] = RobotState.Error,
        };
        var raw = j.Str("state")?.ToLowerInvariant();
        RobotState? state = raw == null ? null : RobotStateInfo.Parse(raw) ?? (synonyms.TryGetValue(raw, out var syn) ? syn : null);
        var text = j.Str("text");
        if (state == null && text == null) return null;

        var kind = state switch
        {
            RobotState.Done => EventKind.Stop,
            RobotState.Waiting => EventKind.Waiting,
            RobotState.Error => EventKind.Failure,
            _ => EventKind.Generic,
        };
        return new AgentEvent(source, j.Str("session") ?? "default", kind, state, text, j.Str("project"),
                              j.Str("emoji") ?? state?.Emoji())
        {
            ForceNotify = j.Bool("notify") ?? false,
        };
    }
}

/// <summary>Araç çağrısını kısa bir cümleye ve emojiye çevirir.</summary>
public static class ToolDescriber
{
    public readonly record struct Description(RobotState State, string Text, string Emoji);

    public static Description Describe(string tool, JsonObject input)
    {
        var t = tool.ToLowerInvariant();
        string? Str(params string[] keys)
        {
            foreach (var k in keys)
            {
                var v = input.Str(k);
                if (!string.IsNullOrEmpty(v)) return v;
            }
            return null;
        }
        string FileName()
        {
            var p = Str("file_path", "path", "notebook_path", "filePath");
            return p != null ? LastPathComponent(p) : L("dosya", "a file");
        }

        switch (t)
        {
            case "bash": case "shell": case "exec_command": case "local_shell": case "unified_exec": case "container.exec": case "powershell":
                var cmd = CommandString(input) ?? "…";
                return new(RobotState.Running, L("Komut: ", "Command: ") + Clip(cmd, 70), CommandEmoji(cmd));
            case "read": case "read_file": case "view_image": case "notebookread":
                return new(RobotState.Reading, L("Okuyor: ", "Reading ") + FileName(), "📖");
            case "edit": case "multiedit": case "notebookedit": case "str_replace_based_edit_tool":
                return new(RobotState.Editing, L("Düzenliyor: ", "Editing ") + FileName(), "✍️");
            case "write": case "create_file":
                return new(RobotState.Editing, L("Yazıyor: ", "Writing ") + FileName(), "📝");
            case "apply_patch":
                var f = PatchFile(input);
                return f != null
                    ? new(RobotState.Editing, L("Düzenliyor: ", "Editing ") + f, "✍️")
                    : new(RobotState.Editing, L("Kod düzenliyor", "Editing code"), "✍️");
            case "grep": case "search": case "rg":
                return new(RobotState.Searching, L("Arıyor: ", "Searching for ") + Clip(Str("pattern", "query") ?? "…", 40), "🔍");
            case "glob": case "ls": case "list_dir": case "list_files":
                var pat = Str("pattern", "path");
                return new(RobotState.Searching, L("Dosyalara bakıyor", "Looking through files") + (pat != null ? ": " + Clip(pat, 40) : ""), "🗂️");
            case "websearch": case "web_search": case "web_search_preview":
                var q = Str("query");
                return new(RobotState.Searching, L("Web'de arıyor", "Searching the web") + (q != null ? ": " + Clip(q, 50) : ""), "🌐");
            case "webfetch":
                var url = Str("url");
                var host = url != null && Uri.TryCreate(url, UriKind.Absolute, out var u) ? u.Host : "web";
                return new(RobotState.Reading, L("Sayfa okuyor: ", "Reading page: ") + host, "🌍");
            case "task": case "agent":
                return new(RobotState.Delegating, L("Alt ajan: ", "Subagent: ") + Clip(Str("description", "subagent_type") ?? L("çalışıyor", "working"), 50), "🧙");
            case "todowrite": case "update_plan":
                return new(RobotState.Thinking, L("Plan yapıyor", "Making a plan"), "🗺️");
            case "askuserquestion": case "request_user_input":
                return new(RobotState.Waiting, L("Sana bir soru soruyor", "Has a question for you"), "❓");
            case "exitplanmode":
                return new(RobotState.Waiting, L("Planını onaylamanı bekliyor", "Wants you to approve the plan"), "📋");
            default:
                var label = L("Araç: ", "Tool: ");
                if (t.StartsWith("mcp__")) return new(RobotState.Running, label + ShortName(tool), "🔌");
                if (t.Contains("search") || t.Contains("find")) return new(RobotState.Searching, label + tool, "🔍");
                if (t.Contains("read") || t.Contains("get") || t.Contains("fetch")) return new(RobotState.Reading, label + tool, "📖");
                if (t.Contains("write") || t.Contains("edit") || t.Contains("patch")) return new(RobotState.Editing, label + tool, "✍️");
                return new(RobotState.Running, label + tool, "🛠️");
        }
    }

    /// <summary>Komutun ne yaptığına göre emoji: test 🧪, paket 📦, git push 🚀…</summary>
    public static string CommandEmoji(string command)
    {
        var c = " " + command.ToLowerInvariant() + " ";
        bool Has(params string[] words) => words.Any(c.Contains);

        if (Has(" git push")) return "🚀";
        if (Has(" git commit")) return "💾";
        if (Has(" git ")) return "🌿";
        if (Has(" npm install", " npm i ", " yarn add", " pnpm add", " pnpm install", " yarn install",
                " pip install", " pip3 install", " brew install", " cargo add", " pod install", " bun add", " bun install",
                " winget install", " choco install", " dotnet add")) return "📦";
        if (Has(" test", "test ", "test:", " jest", " vitest", " pytest", " rspec")) return "🧪";
        if (Has(" build", " make ", " xcodebuild", " tsc", " webpack", " vite build", " gradle", " msbuild")) return "🔨";
        if (Has(" lint", " eslint", " swiftlint", " prettier", " ruff", " black ")) return "🧹";
        if (Has(" docker")) return "🐳";
        if (Has(" curl ", " wget ", " invoke-webrequest")) return "🌐";
        if (Has(" rm ", " rmdir ", " del ", " remove-item")) return "🗑️";
        if (Has(" npm run dev", " npm start", " yarn dev", " pnpm dev", " serve ", " uvicorn", " flask run")) return "🏃";
        if (Has(" ls ", " cat ", " grep ", " rg ", " find ", " head ", " tail ", " dir ", " type ", " get-content")) return "👀";
        return "💻";
    }

    /// <summary>mcp__github__create_issue → "create_issue (github)"</summary>
    public static string ShortName(string tool)
    {
        if (!tool.StartsWith("mcp__")) return tool.Length == 0 ? L("araç", "tool") : tool;
        var parts = tool.Split("__");
        if (parts.Length < 3) return tool;
        return string.Join("__", parts.Skip(2)) + $" ({parts[1]})";
    }

    public static string? CommandString(JsonObject input)
    {
        var node = input["command"];
        if (node is JsonValue v && v.TryGetValue<string>(out var s)) return s.Trim();
        if (node is JsonArray arr && arr.Count > 0)
        {
            var items = arr.Select(x => x is JsonValue xv && xv.TryGetValue<string>(out var xs) ? xs : "").ToList();
            var shells = new[] { "bash", "zsh", "sh", "pwsh", "powershell", "cmd" };
            var first = LastPathComponent(items[0]).ToLowerInvariant().Replace(".exe", "");
            if (items.Count >= 3 && shells.Contains(first) && (items[1].StartsWith('-') || items[1].StartsWith('/')))
                return items[^1];
            return string.Join(" ", items);
        }
        return input.Str("cmd");
    }

    /// <summary>Codex'in apply_patch girdisinden dosya adını bulur.</summary>
    public static string? PatchFile(JsonObject input)
    {
        var blob = string.Join("\n", input.StringValues());
        if (input["command"] is JsonArray arr)
            blob += "\n" + string.Join("\n", arr.Select(x => x is JsonValue xv && xv.TryGetValue<string>(out var xs) ? xs : ""));
        foreach (var marker in new[] { "*** Update File: ", "*** Add File: ", "*** Delete File: " })
        {
            var i = blob.IndexOf(marker, StringComparison.Ordinal);
            if (i < 0) continue;
            var rest = blob[(i + marker.Length)..];
            var nl = rest.IndexOf('\n');
            var path = (nl >= 0 ? rest[..nl] : rest).Trim();
            if (path.Length > 0) return LastPathComponent(path);
        }
        return null;
    }
}

/// <summary>Mochi'den esinlenen tepkiler: istemin tonu, tehlikeli komutlar, test/commit/push.</summary>
public static class Reactions
{
    public readonly record struct PromptReaction(Mood Mood, double Seconds, string Emoji);

    public static PromptReaction? OnPrompt(string text)
    {
        var said = text.Trim();
        var low = said.ToLowerInvariant();

        string[] thanks = { "teşekkür", "tesekkur", "sağol", "sagol", "sağ ol", "eyvallah", "tşk", "tsk", "eline sağlık",
                            "harika", "süper", "super", "mükemmel", "aferin", "bravo", "helal", "efsane", "şahane",
                            "thanks", "thank you", "thx", "great job", "awesome", "perfect", "well done", "nice work", "love it" };
        if (thanks.Any(low.Contains)) return new(Mood.Pleased, 3, "🥰");

        var letters = said.Where(char.IsLetter).ToList();
        var upper = letters.Count(char.IsUpper);
        if (letters.Count >= 8 && (double)upper / letters.Count > 0.7) return new(Mood.Shocked, 2.5, "😳");

        string[] frustration = { "çalışmıyor", "calismiyor", "bozuk", "olmadı", "olmadi", "neden", "niye", "yine", "hala ",
                                 "hâlâ", "saçma", "yanlış", "??", "doesn't work", "not working", "broken", "still", "why", "again", "wtf" };
        if (frustration.Any(low.Contains)) return new(Mood.Nervous, 3, "😬");
        return null;
    }

    private static readonly Regex[] ScaryPatterns = new[]
    {
        @"\brm\s+-[a-z]*r[a-z]*f", @"\brm\s+-[a-z]*f[a-z]*r", @"git\s+push\b.*(--force|\s-f\b)",
        @"git\s+reset\s+--hard", @"git\s+clean\s+-[a-z]*f", @"\bdrop\s+(table|database)\b",
        @"\bmkfs\b", @"\bdd\s+if=", @"chmod\s+-r\s+777", @"sudo\s+rm\b",
        // Windows
        @"remove-item\b.*-recurse.*-force", @"remove-item\b.*-force.*-recurse", @"\brd\s+/s\s+/q", @"\brmdir\s+/s\s+/q",
        @"\bdel\s+/[fsq]\b.*/[fsq]\b", @"\bformat\s+[a-z]:", @"\bdiskpart\b",
    }.Select(p => new Regex(p, RegexOptions.Compiled)).ToArray();

    public static bool IsScary(string command)
    {
        var c = command.ToLowerInvariant();
        return ScaryPatterns.Any(r => r.IsMatch(c));
    }

    public static bool IsTest(string command)
    {
        var c = (" " + command.ToLowerInvariant() + " ").Replace("latest", "");
        return new[] { " test", "test ", "test:", " jest", " vitest", " pytest", " rspec", "go test", "swift test", "cargo test", "dotnet test" }
            .Any(c.Contains);
    }

    public static bool IsCommit(string command) => Regex.IsMatch(command, @"git\s+commit\b", RegexOptions.IgnoreCase);

    public static bool IsPush(string command) => Regex.IsMatch(command, @"git\s+push\b", RegexOptions.IgnoreCase);

    /// <summary>Aracın cevabı hata gibi mi? (Claude Code ve Codex farklı alanlar kullanıyor)</summary>
    public static bool LooksFailed(JsonNode? response)
    {
        if (response is not JsonObject r) return false;
        if (r.Bool("is_error") == true || r.Bool("isError") == true) return true;
        var code = r.Num("exit_code") ?? r.Num("exitCode");
        if (code != null) return code.Value != 0;
        if (r.Bool("success") == false) return true;
        return false;
    }

    public static bool WasRefused(JsonNode? response)
    {
        string text = response switch
        {
            JsonObject o => string.Join(" ", o.StringValues()),
            JsonValue v when v.TryGetValue<string>(out var s) => s,
            _ => "",
        };
        return Regex.IsMatch(text, @"doesn't want to proceed|user (rejected|denied|declined)|permission.*denied|was rejected",
                             RegexOptions.IgnoreCase);
    }
}
