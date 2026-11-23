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

public static class Tests
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

    public static void GesturesAndEyeGlyphs()
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
        // Bitti → başparmak ve kısa süre "✓"
        m.Apply(new AgentEvent("claude", "s", EventKind.ToolDone, RobotState.Thinking), t0.AddSeconds(3));
        m.Apply(new AgentEvent("claude", "s", EventKind.Stop, RobotState.Done), t0.AddSeconds(4));
        A.Eq(Gesture.ThumbsUp, m.Gesture);
        A.Eq('✓', m.EyeGlyph(m.VisualChangedAt.AddSeconds(0.5)));
        A.Eq('\0', m.EyeGlyph(m.VisualChangedAt.AddSeconds(2)));
        // Hata → alnına vurur
        m.Apply(new AgentEvent("claude", "s", EventKind.Prompt, RobotState.Thinking, "y"), t0.AddSeconds(10));
        m.Apply(new AgentEvent("claude", "s", EventKind.Failure, RobotState.Error, "patladı"), t0.AddSeconds(11));
        A.Eq(Gesture.Facepalm, m.Gesture);
        // Uyurken uygulama açılınca el sallar
        var w = new RobotModel("gpt");
        w.Apply(new AgentEvent("gpt", "s", EventKind.Prompt, RobotState.Thinking, "x"), t0.AddHours(-2));
        w.Refresh(t0);
        w.Wake("Merhaba", always: true, at: t0);
        A.Eq(Gesture.Wave, w.Gesture);
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
