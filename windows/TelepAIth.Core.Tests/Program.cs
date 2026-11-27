using System.Reflection;
using System.Text;
using System.Text.Json.Nodes;
using TelepAIth.Core;

// Her test ayrı bir geçici klasörde çalışır (ayarlar, hook dosyaları).
var tmp = Path.Combine(Path.GetTempPath(), "telepaith-tests-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(tmp);
Environment.SetEnvironmentVariable("TELEPAITH_HOME", Path.Combine(tmp, "home", ".telepaith"));
Environment.SetEnvironmentVariable("HOME", Path.Combine(tmp, "home"));
Environment.SetEnvironmentVariable("USERPROFILE", Path.Combine(tmp, "home"));
Environment.SetEnvironmentVariable("CODEX_HOME", Path.Combine(tmp, "codex"));
Environment.SetEnvironmentVariable("CLAUDE_CONFIG_DIR", Path.Combine(tmp, "home", ".claude"));
Directory.CreateDirectory(Path.Combine(tmp, "home"));
Prefs.UseFile(Path.Combine(tmp, "prefs.json"));
Lang.Set(Language.Tr);

var failures = 0;
var count = 0;
foreach (var m in typeof(Tests).GetMethods(BindingFlags.Public | BindingFlags.Static).OrderBy(m => m.Name))
{
    count++;
    try
    {
        m.Invoke(null, null);
        Console.WriteLine("✔ " + m.Name);
    }
    catch (TargetInvocationException e)
    {
        failures++;
        Console.WriteLine("✘ " + m.Name + ": " + e.InnerException?.Message);
    }
}
try { Directory.Delete(tmp, true); } catch { }
Console.WriteLine($"{count} test, {failures} hata");
return failures == 0 ? 0 : 1;

static class A
{
    public static void True(bool c, string msg = "") { if (!c) throw new Exception("beklenen true " + msg); }
    public static void Eq<T>(T expected, T actual, string msg = "")
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new Exception($"beklenen «{expected}», gelen «{actual}» {msg}");
    }
}

public static partial class Tests
{
    static AgentEvent? Hook(string json, string source = "claude", Dictionary<string, string>? extra = null)
    {
        var q = new Dictionary<string, string> { ["source"] = source };
        if (extra != null) foreach (var kv in extra) q[kv.Key] = kv.Value;
        return EventParser.Parse("/event", q, json);
    }

    public static void ScaryCommands()
    {
        A.True(Reactions.IsScary("rm -rf build"));
        A.True(Reactions.IsScary("git push --force origin main"));
        A.True(Reactions.IsScary("git reset --hard HEAD~1"));
        A.True(Reactions.IsScary("Remove-Item -Recurse -Force C:\\x"));
        A.True(Reactions.IsScary("rd /s /q build"));
        A.True(!Reactions.IsScary("git push origin main"));
        A.True(!Reactions.IsScary("ls -la"));
    }

    public static void TestAndGitCommands()
    {
        A.True(Reactions.IsTest("npm test"));
        A.True(Reactions.IsTest("dotnet test"));
        A.True(!Reactions.IsTest("npm install foo@latest"));
        A.True(Reactions.IsCommit("git commit -m 'x'"));
        A.True(Reactions.IsPush("git push origin main"));
    }

    public static void CommandEmoji()
    {
        A.Eq("🚀", ToolDescriber.CommandEmoji("git push"));
        A.Eq("📦", ToolDescriber.CommandEmoji("npm install react"));
        A.Eq("🧪", ToolDescriber.CommandEmoji("npm test"));
        A.Eq("💻", ToolDescriber.CommandEmoji("echo hi"));
    }

    public static void PromptReactions()
    {
        A.Eq(Mood.Pleased, Reactions.OnPrompt("teşekkürler harika oldu")?.Mood);
        A.Eq(Mood.Shocked, Reactions.OnPrompt("NEDEN ÇALIŞMIYOR BU")?.Mood);
        A.Eq(Mood.Nervous, Reactions.OnPrompt("yine bozuk")?.Mood);
        A.True(Reactions.OnPrompt("bir fonksiyon yaz") == null);
    }

    public static void HookParsing()
    {
        var e = Hook("""{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"C:\\Users\\a\\proje","tool_name":"Bash","tool_input":{"command":"npm test"}}""");
        A.Eq(EventKind.Tool, e!.Kind);
        A.Eq(RobotState.Running, e.State);
        A.Eq("proje", e.Project);
        A.Eq("🧪", e.Emoji);
        var stop = Hook("""{"hook_event_name":"Stop","session_id":"s1","last_assistant_message":"Bitti"}""");
        A.Eq(EventKind.Stop, stop!.Kind);
        A.Eq("Bitti", stop.LastMessage);
        var perm = Hook("""{"hook_event_name":"Notification","session_id":"s1","message":"Claude needs your permission to use Bash"}""");
        A.Eq(RobotState.Waiting, perm!.State);
        A.True(perm.Text!.Contains("Bash"));
    }

    public static void HookTerminalInfo()
    {
        var e = Hook("""{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"merhaba"}""",
                     extra: new() { ["wt"] = "1", ["ppid"] = "4242" });
        A.Eq("WindowsTerminal", e!.AppProcess);
        A.Eq(4242, e.HookParentPid);
        var v = Hook("""{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"x"}""", extra: new() { ["term"] = "vscode" });
        A.Eq("Code", v!.AppProcess);
    }

    public static void CodexPatchFile()
    {
        var input = JsonNode.Parse("""{"command":["apply_patch","*** Begin Patch\n*** Update File: src/app.ts\n@@"]}""")!.AsObject();
        A.Eq("app.ts", ToolDescriber.PatchFile(input));
    }

    public static void GenericEventAndAliases()
    {
        var e = EventParser.Parse("/event", new Dictionary<string, string> { ["source"] = "openai" }, """{"state":"finished","text":"Hepsi geçti"}""");
        A.Eq("gpt", e!.Source);
        A.Eq(EventKind.Stop, e.Kind);
        A.Eq(RobotState.Done, e.State);
        A.True(EventParser.Parse("/event", new Dictionary<string, string>(), "{}") == null);
    }

    public static void ClaudeBarWebhook()
    {
        var e = EventParser.Parse("/claudebar", new Dictionary<string, string>(), """{"type":"quota","provider":"claude","left":18}""");
        A.Eq(EventKind.Quota, e!.Kind);
        A.Eq(18, e.QuotaLeft);
        var m = new RobotModel("claude");
        m.Apply(e);
        A.Eq(18, m.QuotaLeft);
    }

    public static void VersionCompareWorks()
    {
        A.True(VersionCompare.IsNewer("0.10.1", "0.9.12"));
        A.True(VersionCompare.IsNewer("v1.0.0", "0.10.1"));
        A.True(!VersionCompare.IsNewer("0.10.1", "0.10.1"));
    }

    public static void Duration()
    {
        A.Eq("45 sn", Text.FormatDuration(45));
        A.Eq("1 dk 15 sn", Text.FormatDuration(75));
        A.Eq("2 sa 10 dk", Text.FormatDuration(7800));
    }

    public static void WorkPhasesMatch()
    {
        A.Eq(WorkPhase.Looking, WorkPhases.Match("searching the web"));
        A.Eq(WorkPhase.Running, WorkPhases.Match("ran 3 commands"));
        A.Eq(WorkPhase.Testing, WorkPhases.Match("running tests"));
        A.Eq(ButtonKind.Stop, WorkPhases.Classify("Stop response"));
        A.Eq(ButtonKind.Approve, WorkPhases.Classify("Allow once"));
        A.Eq(ButtonKind.Send, WorkPhases.Classify("Send message"));
    }

    public static void HttpParsing()
    {
        var raw = "POST /event?source=claude&term=vscode HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{}";
        var bytes = Encoding.UTF8.GetBytes(raw);
        var r = HttpRequest.TryParse(bytes, bytes.Length)!;
        A.Eq("/event", r.Path);
        A.Eq("vscode", r.Query["term"]);
        A.Eq("{}", r.Body);
        var partial = Encoding.UTF8.GetBytes("POST / HTTP/1.1\r\nContent-Length: 10\r\n\r\n{}");
        A.True(HttpRequest.TryParse(partial, partial.Length) == null);
    }

    public static void HookInstallAndUninstall()
    {
        var path = HookInstaller.FilePath(HookTarget.Claude);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, """{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"say done"}]}]}}""");
        HookInstaller.Install(HookTarget.Claude, @"C:\Users\Ada Lovelace\AppData\Local\Programs\TelepAIth\TelepAIthHook.exe", shield: true);
        A.True(HookInstaller.IsInstalled(HookTarget.Claude));
        var root = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        A.Eq("opus", root["model"]!.GetValue<string>());
        var stop = root["hooks"]!["Stop"]!.AsArray();
        A.Eq(2, stop.Count, "kullanıcının hook'u korunmalı");
        var cmd = stop[1]!["hooks"]![0]!["command"]!.GetValue<string>();
        A.True(cmd.StartsWith("\"C:/Users/Ada Lovelace/"), cmd);
        A.True(cmd.EndsWith("hook claude " + AppInfo.HookMarker), cmd);
        A.Eq(2, root["hooks"]!["PreToolUse"]!.AsArray().Count, "kalkan eklenmeli");
        // İkinci kurulum çoğaltmamalı
        HookInstaller.Install(HookTarget.Claude, @"C:\x\TelepAIthHook.exe", shield: false);
        root = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        A.Eq(2, root["hooks"]!["Stop"]!.AsArray().Count);
        A.Eq(1, root["hooks"]!["PreToolUse"]!.AsArray().Count);
        HookInstaller.Uninstall(HookTarget.Claude);
        A.True(!HookInstaller.IsInstalled(HookTarget.Claude));
        root = JsonNode.Parse(File.ReadAllText(path))!.AsObject();
        A.Eq(1, root["hooks"]!["Stop"]!.AsArray().Count);
        A.True(File.Exists(path + ".telepaith-backup"));
    }

    public static void CodexInstallUsesCodexHome()
    {
        HookInstaller.Install(HookTarget.Codex, @"C:\x\TelepAIthHook.exe", shield: true);
        A.True(HookInstaller.FilePath(HookTarget.Codex).Contains("codex"));
        A.True(HookInstaller.IsInstalled(HookTarget.Codex));
        var root = JsonNode.Parse(File.ReadAllText(HookInstaller.FilePath(HookTarget.Codex)))!.AsObject();
        A.True(root["hooks"]!["PermissionRequest"] != null);
        A.Eq(1, root["hooks"]!["PreToolUse"]!.AsArray().Count, "kalkan sadece Claude Code'da");
    }

    public static void ShieldDecision()
    {
        A.True(Shield.Decide("""{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/x"}}""")!.Contains("\"ask\""));
        A.True(Shield.Decide("""{"tool_name":"PowerShell","tool_input":{"command":"Remove-Item -Recurse -Force dist"}}""") != null);
        A.True(Shield.Decide("""{"tool_name":"Bash","tool_input":{"command":"ls"}}""") == null);
        A.True(Shield.Decide("bozuk") == null);
    }

    public static void McpServerFlow()
    {
        JsonObject? sent = null;
        var server = new McpServer("claude", body => { sent = body; return true; });
        var init = JsonNode.Parse(server.Handle("""{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18"}}""")!)!;
        A.Eq("telepaith", init["result"]!["serverInfo"]!["name"]!.GetValue<string>());
        var list = JsonNode.Parse(server.Handle("""{"jsonrpc":"2.0","id":2,"method":"tools/list"}""")!)!;
        A.Eq(McpServer.ToolName, list["result"]!["tools"]![0]!["name"]!.GetValue<string>());
        server.Handle("""{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"telepaith_say","arguments":{"text":"Okuyorum","state":"reading"}}}""");
        A.Eq("Okuyorum", sent!["text"]!.GetValue<string>());
        A.Eq("mcp", sent["session"]!.GetValue<string>());
        A.True(server.Handle("""{"jsonrpc":"2.0","method":"notifications/initialized"}""") == null);
    }

    public static void ModelSessionsAndMinis()
    {
        var m = new RobotModel("claude");
        m.Apply(new AgentEvent("claude", "a", EventKind.Prompt, RobotState.Thinking, "x") { AppProcess = "WindowsTerminal" });
        m.Apply(new AgentEvent("claude", "b", EventKind.Waiting, RobotState.Waiting, "onay"));
        A.Eq(RobotState.Waiting, m.State);
        A.True(m.WaitingSince != null);
        var minis = m.MiniSessions(m.BestSessionId, DateTime.Now);
        A.Eq(1, minis.Count);
        A.Eq(RobotState.Thinking, minis[0].State);
    }

    public static void HookToMinis()
    {
        var q = new Dictionary<string, string> { ["source"] = "gpt", ["ppid"] = "123" };
        var e1 = EventParser.Parse("/event", q, """{"hook_event_name":"UserPromptSubmit","session_id":"g1","cwd":"C:\\proj\\api","prompt":"testleri düzelt"}""");
        A.True(e1 != null, "UserPromptSubmit");
        A.Eq("gpt", e1!.Source);
        A.Eq(123, e1.HookParentPid);
        var q2 = new Dictionary<string, string> { ["source"] = "claude" };
        var e2 = EventParser.Parse("/event", q2, """{"hook_event_name":"PreToolUse","session_id":"s2","cwd":"C:\\proj\\mobile","tool_name":"Bash","tool_input":{"command":"npm test"}}""");
        A.True(e2 != null, "PreToolUse");
        var g = new RobotModel("gpt");
        g.Apply(e1);
        A.Eq(1, g.MiniSessions(null, DateTime.Now).Count);
    }

    public static void UpdatePlanChoosesPackage()
    {
        A.True(UpdatePlan.UseSmall("8.0.11|8.0.11", "8.0.11|8.0.11\n", true), "aynı çalışma zamanı: küçük paket");
        A.True(!UpdatePlan.UseSmall("8.0.10|8.0.10", "8.0.11|8.0.11", true), "çalışma zamanı değişti: tam paket");
        A.True(!UpdatePlan.UseSmall(null, "8.0.11|8.0.11", true), "eski tek dosya kurulum: tam paket");
        A.True(!UpdatePlan.UseSmall("8.0.11|8.0.11", "8.0.11|8.0.11", false), "küçük paket yoksa: tam paket");
        A.Eq("1.5 / 60.0 MB", UpdatePlan.Progress(1572864, 62914560));
    }

    public static void WakeFromSleep()
    {
        var m = new RobotModel("claude");
        var later = DateTime.Now.AddSeconds(700);
        m.Refresh(later);
        A.Eq(RobotState.Sleeping, m.State);
        m.Wake("👋 Uyandım!", at: later);
        A.Eq(RobotState.Idle, m.State);
        A.True(m.BubbleText?.Contains("Uyandım") == true, "uyanınca selam verir");
        // Uyanıkken (always olmadan) selam vermez
        var awake = new RobotModel("gpt");
        awake.Wake("👋 Uyandım!");
        A.True(awake.BubbleText?.Contains("Uyandım") != true, "uyanıkken sessiz");
        awake.Wake("ChatGPT açıldı", always: true);
        A.True(awake.BubbleText?.Contains("açıldı") == true, "always: her zaman söyler");
    }

    public static void MiniHeadsNoDuplicates()
    {
        var m = new RobotModel("claude");
        m.Apply(new AgentEvent("claude", "app-100-0", EventKind.Prompt, RobotState.Thinking, "Düşünüyor…"));
        m.Apply(new AgentEvent("claude", "mcp", EventKind.Status, RobotState.Editing, "Düzenliyor"));
        m.Apply(new AgentEvent("claude", "term-1", EventKind.Tool, RobotState.Running, "npm test") { Project = "api" });
        var all = m.MiniSessions(null, DateTime.Now);
        A.Eq(2, all.Count);   // masaüstü sohbeti (app + anlatıcı) tek kafa + terminal
        var shown = m.MiniSessions(m.BestSessionId, DateTime.Now);
        A.Eq(1, shown.Count); // ana robot birini gösteriyor, diğeri minik kafa
        A.True(RobotModel.SessionGroup(shown[0].Id.Split('/')[1]) != RobotModel.SessionGroup(m.BestSessionId!), "ana robotla aynı sohbet minik kafa olmaz");
    }

    public static void ApprovalDecisions()
    {
        var body = """{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"npm install"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm install"}],"behavior":"allow","destination":"localSettings"}]}""";
        var sug = Approval.Suggestions(body);
        A.True(sug != null && sug.Count == 1, "öneri okundu");
        var allow = JsonNode.Parse(Approval.Decision(ApprovalChoice.Allow, sug))!;
        A.Eq("PermissionRequest", allow["hookSpecificOutput"]!["hookEventName"]!.GetValue<string>());
        A.Eq("allow", allow["hookSpecificOutput"]!["decision"]!["behavior"]!.GetValue<string>());
        A.True(allow["hookSpecificOutput"]!["decision"]!["updatedPermissions"] == null, "tek seferlik izinde kural yok");
        var always = JsonNode.Parse(Approval.Decision(ApprovalChoice.Always, sug))!;
        A.Eq("npm install", always["hookSpecificOutput"]!["decision"]!["updatedPermissions"]![0]!["rules"]![0]!["ruleContent"]!.GetValue<string>());
        var deny = JsonNode.Parse(Approval.Decision(ApprovalChoice.Deny, sug))!;
        A.Eq("deny", deny["hookSpecificOutput"]!["decision"]!["behavior"]!.GetValue<string>());
        A.True(deny["hookSpecificOutput"]!["decision"]!["message"] != null, "red gerekçesi var");
        A.True(Approval.Suggestions("""{"tool_name":"Edit"}""") == null, "öneri yoksa Hep izin ver yok");
        // Hook kurulumu: PermissionRequest bekleyen komutla, 600 sn zaman aşımıyla
        HookInstaller.Install(HookTarget.Claude, "C:/x/TelepAIthHook.exe", false);
        var root = JsonNode.Parse(File.ReadAllText(HookInstaller.FilePath(HookTarget.Claude)))!;
        var pr = root["hooks"]!["PermissionRequest"]![0]!["hooks"]![0]!;
        A.True(pr["command"]!.GetValue<string>().Contains(" permission claude "), "izin komutu");
        A.Eq(600, pr["timeout"]!.GetValue<int>());
        HookInstaller.Uninstall(HookTarget.Claude);
    }

    public static void ClaudeAskingIsWaitingNotDone()
    {
        var t = new ChatAppTracker("claude", 42, "Claude");
        var composer = new RectD(100, 900, 600, 60);
        var stop = new RectD(700, 910, 30, 30);
        // Çalışıyor (Durdur görünüyor)
        t.Update(new FoundUi { Stop = stop, Composer = composer }, "Claude", 0);
        t.Update(new FoundUi { Stop = stop, Composer = composer }, "Claude", 5);
        A.True(t.Generating, "çalışıyor");
        // Soru ekranı: Durdur yok, Gönder var, "Claude is asking: …"
        var asking = new FoundUi { Send = stop, Composer = composer };
        asking.Texts.Add(("Claude is asking: Deneme sorusu: robot şu an 'seni bekliyor' diyor mu?", new RectD(100, 800, 500, 20)));
        A.Eq("Deneme sorusu: robot şu an 'seni bekliyor' diyor mu?", ChatAppTracker.Question(asking));
        var all = new List<AgentEvent>();
        for (var i = 0; i < 6; i++) all.AddRange(t.Update(asking, "Claude", 6 + i));
        A.True(!all.Any(e => e.Kind == EventKind.Stop), "soru sırasında 'bitti' demez");
        var w = all.Single(e => e.Kind == EventKind.Waiting);
        A.True(w.Text!.Contains("Deneme sorusu") && w.Emoji == "❓", "soruyu söyler");
        // Cevaplandı, Claude devam ediyor
        var after = t.Update(new FoundUi { Stop = stop, Composer = composer }, "Claude", 13);
        A.True(after.Any(e => e.Kind == EventKind.ToolDone), "cevaptan sonra çalışmaya döner");
    }

    public static void EyeGlyphsAndMoods()
    {
        var m = new RobotModel("claude");
        var t0 = DateTime.Now;
        // Onay bekliyor → "!", soru soruyor → "?"
        m.Apply(new AgentEvent("claude", "s", EventKind.Prompt, RobotState.Thinking, "x"), t0);
        m.Apply(new AgentEvent("claude", "s", EventKind.Waiting, RobotState.Waiting, "onay"), t0.AddSeconds(1));
        A.Eq('!', m.EyeGlyph(t0.AddSeconds(1.5)));
        A.True(!m.IsAsking);
        m.Apply(new AgentEvent("claude", "s", EventKind.Waiting, RobotState.Waiting, "Bir soru?") { Emoji = "❓" }, t0.AddSeconds(2));
        A.True(m.IsAsking, "soru");
        A.Eq('?', m.EyeGlyph(t0.AddSeconds(2.5)));
        // Bitti → kısa süre "✓"
        m.Apply(new AgentEvent("claude", "s", EventKind.ToolDone, RobotState.Thinking), t0.AddSeconds(3));
        m.Apply(new AgentEvent("claude", "s", EventKind.Stop, RobotState.Done), t0.AddSeconds(4));
        A.Eq('✓', m.EyeGlyph(m.VisualChangedAt.AddSeconds(0.5)));
        A.Eq('\0', m.EyeGlyph(m.VisualChangedAt.AddSeconds(2)));
        // Uygulama açılınca selam verir
        var w = new RobotModel("gpt");
        w.Apply(new AgentEvent("gpt", "s", EventKind.Prompt, RobotState.Thinking, "x"), t0.AddHours(-2));
        w.Refresh(t0);
        w.Wake("Merhaba", always: true, at: t0);
        A.Eq("Merhaba", w.BubbleText);
        // Art arda tıklama tepkisi
        w.React(Mood.Dizzy, 2.5, "Başım döndü!");
        A.Eq(Mood.Dizzy, w.Mood);
        A.Eq('\0', w.EyeGlyph(DateTime.Now));
    }

    public static void ModelStopNotice()
    {
        var m = new RobotModel("claude");
        var t0 = DateTime.Now;
        m.Apply(new AgentEvent("claude", "s", EventKind.Prompt, RobotState.Thinking, "x") { AppPid = 77 }, t0);
        m.Apply(new AgentEvent("claude", "s", EventKind.Tool, RobotState.Editing, "Düzenliyor: a.cs"), t0.AddSeconds(5));
        var n = m.Apply(new AgentEvent("claude", "s", EventKind.Stop, RobotState.Done), t0.AddSeconds(30));
        A.True(n != null, "30 sn > 20 sn: bildirim");
        A.Eq(77, n!.Target!.Pid);
        A.True(m.BubbleText!.Contains("1 araç"), m.BubbleText);
    }

    public static void TrackerDetectsWorkAndStop()
    {
        var t = new ChatAppTracker("claude", 10, "Claude");
        var composer = new RectD(100, 800, 600, 60);
        var working = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        working.Texts.Add(("Searching the web", new RectD(100, 700, 300, 20)));
        var ev = t.Update(working, "Claude", 0);
        A.Eq(EventKind.Prompt, ev[0].Kind);
        A.Eq(10, ev[0].AppPid);
        ev = t.Update(working, "Claude", 2);
        A.True(ev.Any(e => e.Kind == EventKind.Status && e.State == RobotState.Searching));
        var idle = new FoundUi { Send = new RectD(650, 810, 30, 30), Composer = composer };
        t.Update(idle, "Claude", 6);
        ev = t.Update(idle, "Claude", 8);
        A.True(ev.Any(e => e.Kind == EventKind.Stop), "durdur kaybolunca bitti");
        A.Eq("izleniyor", t.StatusText);
    }

    public static void TrackerChatSwitch()
    {
        var t = new ChatAppTracker("gpt", 11, "ChatGPT");
        var ui = new FoundUi { Composer = new RectD(0, 800, 600, 60) };
        t.Update(ui, "Tarif", 0);
        var ev = t.Update(ui, "Kod sorusu", 1);
        A.True(ev.Any(e => e.Kind == EventKind.Say && e.Text!.Contains("Kod sorusu")));
        A.True(t.SessionId.EndsWith("-1"));
    }

    public static void TrackerNewChatGetsAddress()
    {
        // Yeni sohbette ilk mesaj gidince adres /new → /chat/<id> olur: "başka sohbete geçtim" deme, iş kesilmesin
        var t = new ChatAppTracker("claude", 12, "Claude");
        var composer = new RectD(0, 800, 600, 60);
        var draft = new FoundUi { Send = new RectD(650, 810, 30, 30), Composer = composer };
        draft.Urls.Add("https://claude.ai/new");
        t.Update(draft, "Claude", 0);
        var sending = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        sending.Urls.Add("https://claude.ai/new");
        var ev = t.Update(sending, "Claude", 1);
        A.True(ev.Any(e => e.Kind == EventKind.Prompt));
        var id = t.SessionId;
        var named = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        named.Urls.Add("https://claude.ai/chat/3f2a9c1e-1111-2222-3333-444455556666");
        ev = t.Update(named, "Claude", 2);
        A.True(!ev.Any(e => e.Kind is EventKind.SessionEnd or EventKind.Say), "yeni sohbet adını aldı, geçiş değil");
        A.Eq(id, t.SessionId);
        A.True(t.Generating);
        // ChatGPT: kök adres → /c/<id> (ilk taramada düğme zaten "Durdur")
        var g = new ChatAppTracker("gpt", 13, "ChatGPT");
        var root = new FoundUi { Send = new RectD(650, 810, 30, 30), Composer = composer };
        root.Urls.Add("https://chatgpt.com/");
        g.Update(root, "ChatGPT", 0);
        var c = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        c.Urls.Add("https://chatgpt.com/c/6741a2b3-aaaa");
        ev = g.Update(c, "ChatGPT", 1);
        A.True(!ev.Any(e => e.Kind is EventKind.SessionEnd or EventKind.Say));
        A.True(g.SessionId.EndsWith("-0"));
        // Gerçek geçiş hâlâ algılanır
        var other = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        other.Urls.Add("https://chatgpt.com/c/9999");
        ev = g.Update(other, "ChatGPT", 2);
        A.True(ev.Any(e => e.Kind == EventKind.SessionEnd));
        A.True(g.SessionId.EndsWith("-1"));
        A.True(ChatAppTracker.IsDraftChat("https://claude.ai/new") && ChatAppTracker.IsDraftChat("https://chatgpt.com/?model=gpt-5"));
        A.True(!ChatAppTracker.IsDraftChat("https://claude.ai/chat/abc") && !ChatAppTracker.IsDraftChat("ChatGPT"));
    }

    public static void DisplayStaysPutWhileBothWork()
    {
        var claude = new RobotModel("claude");
        var gpt = new RobotModel("gpt");
        var all = new[] { claude, gpt };
        var t0 = DateTime.Now;
        claude.Apply(new AgentEvent("claude", "app-1-0", EventKind.Prompt, RobotState.Thinking, "a"), t0);
        var shown = DisplayPicker.Pick(all, claude, t0) ?? claude;
        A.Eq(claude, shown);
        // ChatGPT'ye de yazdın: en son başlayan öne çıkar
        gpt.Apply(new AgentEvent("gpt", "app-2-0", EventKind.Prompt, RobotState.Thinking, "b"), t0.AddSeconds(5));
        shown = DisplayPicker.Pick(all, shown, t0.AddSeconds(5)) ?? shown;
        A.Eq(gpt, shown);
        // İkisi de çalışırken Claude'un aşama mesajları kafayı geri çekmez (eskiden her mesajda gidip geliyordu)
        for (var i = 0; i < 10; i++)
        {
            var at = t0.AddSeconds(6 + i * 2);
            claude.Apply(new AgentEvent("claude", "app-1-0", EventKind.Status, i % 2 == 0 ? RobotState.Reading : RobotState.Editing, "aşama " + i), at);
            gpt.Refresh(at);
            A.True(DisplayPicker.Pick(all, shown, at) == null, "aşama mesajında kafa değişmemeli " + i);
        }
        // Minik kafa: gösterilmeyen Claude; gösterilen ChatGPT minik olarak tekrar çıkmaz
        var minis = DisplayPicker.Minis(all, shown, t0.AddSeconds(30));
        A.Eq(1, minis.Count);
        A.Eq("claude", minis[0].Source);
        // Claude onay isteyince öne geçer
        claude.Apply(new AgentEvent("claude", "app-1-0", EventKind.Waiting, RobotState.Waiting, "onay"), t0.AddSeconds(31));
        gpt.Refresh(t0.AddSeconds(31));
        shown = DisplayPicker.Pick(all, shown, t0.AddSeconds(31)) ?? shown;
        A.Eq(claude, shown);
        minis = DisplayPicker.Minis(all, shown, t0.AddSeconds(31));
        A.Eq(1, minis.Count);
        A.Eq("gpt", minis[0].Source);
    }

    public static void GazeWaitsUntilAllQuiet()
    {
        var claude = new RobotModel("claude");
        var gpt = new RobotModel("gpt");
        var all = new[] { claude, gpt };
        var t0 = DateTime.Now;
        A.True(DisplayPicker.CanGaze(all, t0), "hiç iş yokken izler");
        claude.Apply(new AgentEvent("claude", "s", EventKind.Prompt, RobotState.Thinking, "a"), t0);
        gpt.Apply(new AgentEvent("gpt", "g", EventKind.Prompt, RobotState.Thinking, "b"), t0);
        A.True(!DisplayPicker.CanGaze(all, t0.AddSeconds(1)), "çalışırken izlemez");
        // Claude bitti ama ChatGPT hâlâ çalışıyor: izlemez
        claude.Apply(new AgentEvent("claude", "s", EventKind.Stop, RobotState.Done), t0.AddSeconds(10));
        gpt.Refresh(t0.AddSeconds(40));
        claude.Refresh(t0.AddSeconds(40));
        A.True(!DisplayPicker.CanGaze(all, t0.AddSeconds(40)), "öteki AI çalışırken izlemez");
        // ChatGPT de bitti: 20 sn dolmadan izlemez, dolunca izler
        gpt.Refresh(t0.AddSeconds(49.9));   // uygulamada her karede yenilenir
        gpt.Apply(new AgentEvent("gpt", "g", EventKind.Stop, RobotState.Done), t0.AddSeconds(50));
        claude.Refresh(t0.AddSeconds(60));
        gpt.Refresh(t0.AddSeconds(60));
        A.True(!DisplayPicker.CanGaze(all, t0.AddSeconds(60)), "bitince 20 sn beklenir");
        claude.Refresh(t0.AddSeconds(71));
        gpt.Refresh(t0.AddSeconds(71));
        A.True(DisplayPicker.CanGaze(all, t0.AddSeconds(71)), "20 sn sonra izler");
    }

    public static void SidebarStatusWords()
    {
        A.Eq(RobotState.Running, SidebarChats.StatusOf("Running"));
        A.Eq(RobotState.Running, SidebarChats.StatusOf("Tarif önerisi, running"));
        A.Eq(RobotState.Waiting, SidebarChats.StatusOf("Kod incelemesi · Awaiting answer"));
        A.Eq(RobotState.Waiting, SidebarChats.StatusOf("Yanıt bekliyor"));
        A.True(SidebarChats.StatusOf("Running a marathon plan") == null, "başlıktaki kelime durum değil");
        A.True(SidebarChats.StatusOf("Working with CSV files") == null);
        A.Eq("Tarif önerisi", SidebarChats.StripStatus("Tarif önerisi, running"));
        A.Eq("Kod", SidebarChats.StripStatus("Kod (running)"));
    }

    public static void SidebarBackgroundChats()
    {
        var bg = new SidebarChats("claude", 77);
        RectD Row(int i) => new(10, 100 + i * 30, 240, 28);
        RectD Dot(int i) => new(230, 108 + i * 30, 8, 8);
        // Açık sohbet A (seçili), arkada B çalışıyor (nokta ayrı öğe, ipucu "running"), C boşta
        var items = new List<SidebarItem>
        {
            new("Sohbet A", "", "https://claude.ai/chat/aaa", Row(0), Current: true),
            new("", "Running", null, Dot(0)),   // açık sohbetin noktası: sayılmaz
            new("Sohbet B", "", "https://claude.ai/chat/bbb", Row(1)),
            new("", "Running", null, Dot(1)),
            new("Sohbet C", "", "https://claude.ai/chat/ccc", Row(2)),
        };
        var ev = bg.Update(items, "https://claude.ai/chat/aaa", 0);
        A.Eq(1, ev.Count);
        A.Eq(EventKind.Prompt, ev[0].Kind);
        A.Eq("Sohbet B", ev[0].Project);
        A.Eq(77, ev[0].AppPid);
        A.Eq(77, ev[0].QuietIfForegroundPid);   // Claude öndeyken arkadaki sohbetin bildirimi/sesi gelmez
        A.True(ev[0].SessionId.StartsWith("bg-77-"));
        A.True(RobotModel.SessionGroup(ev[0].SessionId) != "desktop", "açık sohbetle birleşmesin");
        var id = ev[0].SessionId;
        // Çalışmaya devam: 20 sn'de bir canlı tut
        A.Eq(0, bg.Update(items, "https://claude.ai/chat/aaa", 10).Count);
        ev = bg.Update(items, "https://claude.ai/chat/aaa", 25);
        A.True(ev.Count == 1 && ev[0].Kind == EventKind.Heartbeat);
        // B cevap bekliyor (satırın kendi adında durum)
        items[2] = new("Sohbet B, awaiting answer", "", "https://claude.ai/chat/bbb", Row(1));
        items.RemoveAt(3);
        ev = bg.Update(items, "https://claude.ai/chat/aaa", 30);
        A.True(ev.Count == 1 && ev[0].Kind == EventKind.Waiting && ev[0].SessionId == id);
        // Tekrar çalışıyor, sonra nokta söner → bitti (bildirimli)
        items[2] = new("Sohbet B", "", "https://claude.ai/chat/bbb", Row(1));
        items.Add(new("", "Running", null, Dot(1)));
        ev = bg.Update(items, "https://claude.ai/chat/aaa", 40);
        A.True(ev.Count == 1 && ev[0].Kind == EventKind.Status);
        items.RemoveAt(items.Count - 1);
        ev = bg.Update(items, "https://claude.ai/chat/aaa", 60);
        A.True(ev.Count == 1 && ev[0].Kind == EventKind.Stop && ev[0].ForceNotify && ev[0].SessionId == id);
        A.Eq(0, bg.Count);
    }

    public static void SidebarChatOpenedOrHidden()
    {
        var bg = new SidebarChats("claude", 5);
        var b = new SidebarItem("Sohbet B · running", "", "https://claude.ai/chat/bbb?x=1", new RectD(10, 130, 240, 28));
        bg.Update(new[] { b }, "https://claude.ai/chat/aaa", 0);
        A.Eq(1, bg.Count);
        // B'ye tıkladın: artık açık sohbet → "bitti" değil, sessizce bırak (büyük kafa izler)
        var ev = bg.Update(new[] { b }, "https://claude.ai/chat/bbb", 30);
        A.True(ev.Count == 1 && ev[0].Kind == EventKind.SessionEnd);
        // Menü kapandı / kaydırıldı: satır görünmüyor → bitti deme
        bg.Update(new[] { b }, "https://claude.ai/chat/aaa", 40);
        ev = bg.Update(Array.Empty<SidebarItem>(), "https://claude.ai/chat/aaa", 80);
        A.True(ev.Count == 1 && ev[0].Kind == EventKind.SessionEnd);
        // Takılı kalan nokta: 30 dk'dan sonra canlı tutma
        bg.Update(new[] { b }, null, 100);
        var beats = 0;
        for (var t = 120.0; t < 100 + SidebarChats.MaxRunSeconds + 200; t += 21)
            beats += bg.Update(new[] { b }, null, t).Count(e => e.Kind == EventKind.Heartbeat);
        A.True(beats > 50 && beats < 90, "takılı noktada canlı tutma sınırlı: " + beats);
        // Tracker üzerinden: yan menü olayları açık sohbetin olaylarıyla birlikte gelir
        var tr = new ChatAppTracker("claude", 9, "Claude");
        var ui = new FoundUi { Composer = new RectD(0, 800, 600, 60), SidebarScanned = true };
        ui.Urls.Add("https://claude.ai/chat/aaa");
        ui.Sidebar.Add(b);
        A.True(tr.Update(ui, "Claude", 0).Any(e => e.Kind == EventKind.Prompt && e.SessionId.StartsWith("bg-9-")));
        A.True(tr.ClosedAll().Any(e => e.Kind == EventKind.SessionEnd));
    }

    public static void BackgroundChatMiniAndDone()
    {
        // Açık sohbet bitti, arkadaki hâlâ çalışıyor: Claude çalışıyor sayılır, minik kafa çıkar
        var m = new RobotModel("claude");
        var t0 = DateTime.Now;
        m.Apply(new AgentEvent("claude", "app-1-0", EventKind.Prompt, RobotState.Thinking, "a"), t0);
        m.Apply(new AgentEvent("claude", "bg-1-abc", EventKind.Prompt, RobotState.Thinking, "Arkada çalışıyor", project: "Sohbet B"), t0.AddSeconds(1));
        m.Apply(new AgentEvent("claude", "app-1-0", EventKind.Stop, RobotState.Done), t0.AddSeconds(10));
        A.True(m.State.IsWorking(), "arkadaki sohbet çalışırken Claude çalışıyor görünür");
        m.Refresh(t0.AddSeconds(11));
        A.True(!DisplayPicker.CanGaze(new[] { m }, t0.AddSeconds(11)), "arkadaki sohbet çalışırken gözler imleci izlemez");
        var stop = new AgentEvent("claude", "bg-1-abc", EventKind.Stop, RobotState.Done, project: "Sohbet B") { ForceNotify = true };
        var notice = m.Apply(stop, t0.AddSeconds(12));
        A.True(notice != null && notice.Body.Contains("Sohbet B"), "arkadaki sohbet bitince bildirim");
    }

    public static void OneMiniPerOtherAi()
    {
        var claude = new RobotModel("claude");
        var gpt = new RobotModel("gpt");
        var t0 = DateTime.Now;
        foreach (var id in new[] { "a", "b", "bg-1-x" })
            claude.Apply(new AgentEvent("claude", id, EventKind.Prompt, RobotState.Thinking, "iş"), t0);
        gpt.Apply(new AgentEvent("gpt", "g1", EventKind.Prompt, RobotState.Thinking, "iş"), t0);
        gpt.Apply(new AgentEvent("gpt", "g2", EventKind.Waiting, RobotState.Waiting, "onay"), t0);
        var minis = DisplayPicker.Minis(new[] { claude, gpt }, claude, t0.AddSeconds(1));
        A.Eq(1, minis.Count);
        A.Eq("gpt", minis[0].Id);
        A.Eq(RobotState.Waiting, minis[0].State);   // en acil olanı
        A.True(minis[0].Label.Contains("+1"), minis[0].Label);
        minis = DisplayPicker.Minis(new[] { claude, gpt }, gpt, t0.AddSeconds(1));
        A.Eq(1, minis.Count);
        A.Eq("claude", minis[0].Id);
        // Kafadaki ışıklar: sadece büyük kafadaki AI'ın sohbetleri (Claude büyükken gösterilen dışındaki 2 Claude sohbeti)
        claude.Refresh(t0.AddSeconds(1));
        gpt.Refresh(t0.AddSeconds(1));
        var extras = DisplayPicker.Extras(claude, t0.AddSeconds(1));
        A.Eq(2, extras.Count);
        // GPT büyükken: GPT'nin kendi diğer sohbeti (Claude'unkiler karışmaz)
        extras = DisplayPicker.Extras(gpt, t0.AddSeconds(1));
        A.Eq(1, extras.Count);
    }

    public static void ChatListRows()
    {
        var claude = new RobotModel("claude");
        var gpt = new RobotModel("gpt");
        var t0 = DateTime.Now;
        claude.Apply(new AgentEvent("claude", "app-1-0", EventKind.Prompt, RobotState.Thinking, "a", project: "Tarif"), t0);
        claude.Apply(new AgentEvent("claude", "bg-1-x", EventKind.Prompt, RobotState.Thinking, "Arkada", project: "Kod incelemesi"), t0.AddSeconds(10));
        claude.Apply(new AgentEvent("claude", "bg-1-x", EventKind.Stop, RobotState.Done, project: "Kod incelemesi"), t0.AddSeconds(70));
        gpt.Apply(new AgentEvent("gpt", "app-2-0", EventKind.Waiting, RobotState.Waiting, "onay"), t0.AddSeconds(100));
        var rows = DisplayPicker.ChatRows(new[] { claude, gpt }, t0.AddSeconds(220));
        A.Eq(3, rows.Count);
        A.Eq("gpt", rows[0].Source);                       // seni bekleyen önce
        A.True(rows[0].Status.Contains(Text.L("2 dk", "2 min")), rows[0].Status);
        A.True(rows[0].Unread);
        A.Eq("Kod incelemesi", rows[1].Title);             // sonra yeni biten (bakılmadı: nokta)
        A.True(rows[1].Unread && rows[1].Status.Contains(Text.L("2 dk", "2 min")), rows[1].Status);
        A.Eq(Text.L("2 dk önce", "2 min ago"), rows[1].Time);
        A.Eq("Tarif", rows[2].Title);                      // sonra çalışan
        A.True(!rows[2].Unread && rows[2].Status.StartsWith(Text.L("çalışıyor", "working")) && rows[2].Status.Contains(Text.L("3 dk", "3 min")), rows[2].Status);
        A.Eq(Text.L("1 bekliyor · 1 yeni · 1 çalışıyor", "1 waiting · 1 new · 1 working"), DisplayPicker.ChatSummary(rows));
        // Bakılınca nokta söner, biten sona iner
        claude.MarkSeen("bg-1-x", t0.AddSeconds(200));
        rows = DisplayPicker.ChatRows(new[] { claude, gpt }, t0.AddSeconds(220));
        A.Eq("Kod incelemesi", rows[2].Title);
        A.True(!rows[2].Unread && rows[2].State == RobotState.Done);
        // Renk kodu ve sağdaki yazı
        A.Eq("seen", rows[2].Tone);
        A.Eq("waiting", rows[0].Tone);
        A.True(rows[0].Label.StartsWith(Text.L("bekliyor · ", "waiting · ")), rows[0].Label);
        A.Eq("working", rows[1].Tone);
        // 2 saatten eski bitenler listede yok
        A.True(DisplayPicker.ChatRows(new[] { claude, gpt }, t0.AddSeconds(70 + 16 * 60)).Any(r => r.Title == "Kod incelemesi"));
        A.True(DisplayPicker.ChatRows(new[] { claude, gpt }, t0.AddSeconds(70 + 121 * 60)).All(r => r.Title != "Kod incelemesi"));
        A.Eq(Text.L("1 sa 6 dk", "1 h 6 min"), Text.ShortDuration(3960));
        A.Eq(Text.L("40 sn", "40 s"), Text.ShortDuration(40));
        // Yan menüdeki açık sohbetin adı
        var items = new[] { new SidebarItem("Tarif", "", "https://claude.ai/chat/aaa", new RectD(0, 0, 100, 20)) };
        A.Eq("Tarif", SidebarChats.CurrentTitle(items, "https://claude.ai/chat/aaa/"));
    }

    public static void TrackerHoldsWhenBlind()
    {
        // Uygulama arkadayken ağaç boş gelirse "bitti" deme; gerçekten bitince (yazı kutusu var, Durdur yok) de
        var t = new ChatAppTracker("claude", 21, "Claude");
        var composer = new RectD(0, 800, 600, 60);
        var working = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        t.Update(working, "Claude", 0);
        var blind = new FoundUi();
        for (var s = 1.0; s < 20; s += 1) A.True(!t.Update(blind, "Claude", s).Any(e => e.Kind is EventKind.Stop or EventKind.SessionEnd), "boş ağaç: bitti değil");
        A.True(t.Generating);
        var idle = new FoundUi { Send = new RectD(650, 810, 30, 30), Composer = composer };
        idle.ButtonLabels.Add("Send");
        t.Update(idle, "Claude", 21);
        A.True(t.Update(idle, "Claude", 23).Any(e => e.Kind == EventKind.Stop), "görünür ve Durdur yok: bitti");
        // Kayıtlı sohbetler: açık sohbetin adı ve adresi oturumla eşleşir, sohbet değişse de bulunur
        var tr = new ChatAppTracker("claude", 22, "Claude");
        var ui = new FoundUi { Composer = composer, SidebarScanned = true };
        ui.Urls.Add("https://claude.ai/chat/aaa");
        ui.Sidebar.Add(new SidebarItem("Tarif", "", "https://claude.ai/chat/aaa", new RectD(0, 100, 200, 20)));
        tr.Update(ui, "Claude", 0);
        var firstId = tr.SessionId;
        var ui2 = new FoundUi { Composer = composer, SidebarScanned = true };
        ui2.Urls.Add("https://claude.ai/chat/bbb");
        ui2.Sidebar.Add(new SidebarItem("Kod", "", "https://claude.ai/chat/bbb", new RectD(0, 130, 200, 20)));
        tr.Update(ui2, "Claude", 5);
        A.True(tr.SessionId != firstId);
        A.Eq("Tarif", tr.FindChat(firstId)?.Title);
        A.Eq("https://claude.ai/chat/aaa", tr.FindChat(firstId)?.Url);
        A.Eq("Kod", tr.FindChat(tr.SessionId)?.Title);
        // Biten arkadaki sohbet de bulunur
        var bg = new SidebarChats("claude", 3);
        var row = new SidebarItem("Sohbet B · running", "", "https://claude.ai/chat/ccc", new RectD(0, 0, 200, 20));
        var id = bg.Update(new[] { row }, null, 0)[0].SessionId;
        bg.Update(new[] { row with { Name = "Sohbet B" } }, null, 30);
        A.Eq(0, bg.Count);
        A.Eq("Sohbet B", bg.Find(id)?.Title);
        // Çalışırken açık sohbetin adı öğrenilince hemen bir sinyal gider (listede "Açık sohbet" yerine ad görünsün)
        var tn = new ChatAppTracker("claude", 23, "Claude");
        var gen = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer };
        tn.Update(gen, "Claude", 0);
        var named = new FoundUi { Stop = new RectD(650, 810, 30, 30), Composer = composer, SidebarScanned = true };
        named.Urls.Add("https://claude.ai/chat/ddd");
        named.Sidebar.Add(new SidebarItem("SCAM OR LEGIT video Includes an artifact", "", "https://claude.ai/chat/ddd", new RectD(0, 100, 200, 20)));
        var evs = tn.Update(named, "Claude", 1);
        A.True(evs.Any(e => e.Project == "SCAM OR LEGIT video"), "ad hemen gelir, ek temizlenir");
    }

    public static void TrackerCpuFallback()
    {
        // Ekran hiç okunamıyor (Mac'te ChatGPT gibi): 8 sn sonra işlemci kullanımından tahmin
        var t = new ChatAppTracker("gpt", 31, "ChatGPT");
        var blind = new FoundUi();
        double cpu = 0;
        var events = new List<AgentEvent>();
        for (var s = 0.0; s <= 8; s += 1) { cpu += 0.01; events.AddRange(t.Update(blind, "ChatGPT", s, cpu)); }
        A.True(t.CpuMode, "8 sn sonra yedek yol");
        A.True(!events.Any(e => e.Kind == EventKind.Prompt), "boştayken çalışıyor sanma");
        // Cevap yazıyor: işlemci %40
        for (var s = 9.0; s <= 12; s += 1) { cpu += 0.4; events.AddRange(t.Update(blind, "ChatGPT", s, cpu)); }
        A.True(events.Any(e => e.Kind == EventKind.Prompt) && t.Generating, "işlemci yükselince çalışıyor");
        // Kısa bir düşüş bitirmez
        cpu += 0.02; t.Update(blind, "ChatGPT", 13, cpu);
        cpu += 0.4; t.Update(blind, "ChatGPT", 14, cpu);
        A.True(t.Generating, "kısa düşüş bitirmez");
        // Bitti: işlemci düştü ve 3 sn+ düşük kaldı
        events.Clear();
        for (var s = 15.0; s <= 22; s += 1) { cpu += 0.01; events.AddRange(t.Update(blind, "ChatGPT", s, cpu)); }
        A.True(events.Any(e => e.Kind == EventKind.Stop) && !t.Generating, "işlemci düşünce bitti");
        A.True(events.First(e => e.Kind == EventKind.Stop).NoNotice, "tahmini bitti bildirim atmaz");
        var gm = new RobotModel("gpt");
        gm.Apply(new AgentEvent("gpt", "g", EventKind.Prompt, RobotState.Thinking, "x"), DateTime.Now.AddMinutes(-2));
        var silent = new AgentEvent("gpt", "g", EventKind.Stop, RobotState.Done) { ForceNotify = true, NoNotice = true };
        A.True(gm.Apply(silent, DateTime.Now) == null, "NoNotice: bildirim yok");
        A.True(t.StatusText.Contains("%") || t.StatusText.Contains("CPU"), t.StatusText);
        // Ekranı okunabilen uygulamada yedek yol devreye girmez
        var c = new ChatAppTracker("claude", 32, "Claude");
        var ui = new FoundUi { Composer = new RectD(0, 800, 600, 60) };
        for (var s = 0.0; s <= 12; s += 1) c.Update(ui, "Claude", s, s * 0.5);
        A.True(!c.CpuMode && !c.Generating);
    }

    public static void DailySummaryText()
    {
        var stats = new DailyStats(null);
        var day = new DateTime(2026, 11, 21, 12, 0, 0);
        stats.RecordTurn("claude", 125, 4, 3, day);
        stats.RecordTurn("claude", 60, 1, 0, day);
        var text = stats.Summary(_ => "Claude", day) ?? "";
        A.True(text.StartsWith("Claude: 2 iş"), text);
        A.True(text.Contains("3 düzenleme"), text);
    }

    public static void FocusModeWorks()
    {
        FocusMode.TurnOn(60);
        A.True(FocusMode.ManualActive);
        FocusMode.TurnOff();
        A.True(!FocusMode.ManualActive);
        A.True(FocusMode.IsMeetingProcess("Zoom.exe"));
        A.True(!FocusMode.IsMeetingProcess("chrome"));
    }

    public static void RobotScaleClamped()
    {
        Prefs.RobotScale = 5;
        A.Eq(1.8, Prefs.RobotScale);
        Prefs.RobotScale = 1.3;
        A.Eq(1.3, Prefs.RobotScale);
    }
}
