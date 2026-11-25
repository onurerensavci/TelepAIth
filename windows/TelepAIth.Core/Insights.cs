using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;
using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

// Hook'lardan ve Claude Code'un durum satırından çıkan uyarılar (Mac'te Insights.swift, aynı kurallar):
// kullanım sınırları, aynı adımda takılma, iki sohbetin aynı dosyayı düzenlemesi, push sonrası CI, commit'lenmemiş iş.

/// <summary>Bir kullanım penceresi: five_hour (oturum) ya da seven_day (hafta), yüzde kaç dolu, ne zaman yenilenir.</summary>
public sealed record UsageWindow(string Kind, int Percent, DateTime? ResetsAt);

public static class UsageLimits
{
    public static TimeSpan? Length(string kind) => kind switch
    {
        "five_hour" => TimeSpan.FromHours(5),
        "seven_day" => TimeSpan.FromDays(7),
        _ => null,
    };

    public static string Name(string kind) => kind == "five_hour" ? L("Oturum", "Session") : L("Hafta", "Week");

    /// <summary>Claude Code'un durum satırına verdiği JSON'dan pencereler (rate_limits.five_hour / seven_day).</summary>
    public static List<UsageWindow> Parse(string json)
    {
        var list = new List<UsageWindow>();
        JsonObject? limits;
        try { limits = (JsonNode.Parse(json) as JsonObject)?["rate_limits"] as JsonObject; }
        catch { return list; }
        if (limits == null) return list;
        foreach (var kind in new[] { "five_hour", "seven_day" })
        {
            var w = limits[kind] as JsonObject;
            if (w.Num("used_percentage") is not { } p) continue;
            DateTime? resets = w.Num("resets_at") is { } s && s > 0
                ? DateTimeOffset.FromUnixTimeSeconds((long)s).LocalDateTime
                : null;
            list.Add(new UsageWindow(kind, (int)Math.Round(Math.Clamp(p, 0, 100)), resets));
        }
        return list;
    }

    /// <summary>Bu hızla giderse ne zaman dolar? Yenilenmeden önce dolmayacaksa ya da bilinmiyorsa null.</summary>
    public static DateTime? FillsAt(UsageWindow w, DateTime now)
    {
        if (w.ResetsAt is not { } reset || Length(w.Kind) is not { } length || w.Percent <= 0 || w.Percent >= 100) return null;
        var start = reset - length;
        var elapsed = now - start;
        if (elapsed < TimeSpan.FromMinutes(10)) return null;
        var fill = start + TimeSpan.FromTicks((long)(elapsed.Ticks * (100.0 / w.Percent)));
        return fill < reset ? fill : null;
    }

    /// <summary>"16:40" ya da başka günse "Cum 16:40"</summary>
    public static string Clock(DateTime at, DateTime now)
    {
        var culture = Lang.Current == Language.Tr ? new CultureInfo("tr-TR") : new CultureInfo("en-US");
        return at.Date == now.Date ? at.ToString("HH:mm", culture) : at.ToString("ddd HH:mm", culture);
    }

    /// <summary>Sohbet listesinin başındaki satır: "Oturum %42 · 16:40'ta dolar"</summary>
    public static string Line(UsageWindow w, DateTime now)
    {
        var text = $"{Name(w.Kind)} %{w.Percent}";
        if (Lang.Current == Language.En) text = $"{Name(w.Kind)} {w.Percent}%";
        if (FillsAt(w, now) is { } fill) return text + " · " + L($"{Clock(fill, now)}'ta dolar", $"full at {Clock(fill, now)}");
        if (w.ResetsAt is { } reset && w.Percent >= 50) return text + " · " + L($"{Clock(reset, now)}'de yenilenir", $"resets {Clock(reset, now)}");
        return text;
    }
}

/// <summary>Son bilinen kullanım sınırları ve eşik bildirimleri (%80 geçti, %95 neredeyse bitti, yenilendi).</summary>
public sealed class UsageTracker
{
    /// <summary>Durum satırı bu kadar süre bir şey demezse eski bilgi gösterilmez.</summary>
    public static readonly TimeSpan Stale = TimeSpan.FromHours(12);

    private readonly Dictionary<string, UsageWindow> _windows = new();
    private readonly Dictionary<string, int> _told = new();   // 0 yok, 1 %80 söylendi, 2 %95 söylendi
    private bool _first = true;
    public DateTime? UpdatedAt { get; private set; }

    public List<AgentEvent> Update(string json, DateTime now)
    {
        var events = new List<AgentEvent>();
        var fresh = UsageLimits.Parse(json);
        if (fresh.Count == 0) return events;
        UpdatedAt = now;
        foreach (var w in fresh)
        {
            // Yeni pencere başladıysa (yenilenme zamanı ileri kaydı) eşikler sıfırlanır
            if (_windows.TryGetValue(w.Kind, out var old) && old.ResetsAt != null && w.ResetsAt != null && w.ResetsAt > old.ResetsAt.Value.AddMinutes(1))
                _told[w.Kind] = 0;
            _windows[w.Kind] = w;
            var level = w.Percent >= 95 ? 2 : w.Percent >= 80 ? 1 : 0;
            var told = _told.GetValueOrDefault(w.Kind);
            if (level < told && w.Percent < 75) _told[w.Kind] = 0;   // yenilenmiş
            if (level <= told) continue;
            _told[w.Kind] = level;
            // Uygulama açılınca ilk okumada %80'i tekrar söyleme; %95 her zaman söylenir
            if (_first && level < 2) continue;
            events.Add(Notice(w, level, now));
        }
        _first = false;
        return events;
    }

    /// <summary>Zamanı gelen "yenilendi" bildirimleri (söylenmiş bir eşik varsa).</summary>
    public List<AgentEvent> Tick(DateTime now)
    {
        var events = new List<AgentEvent>();
        foreach (var w in _windows.Values.ToList())
        {
            if (w.ResetsAt is not { } reset || reset > now) continue;
            _windows[w.Kind] = w with { Percent = 0, ResetsAt = null };
            if (_told.GetValueOrDefault(w.Kind) > 0)
            {
                _told[w.Kind] = 0;
                events.Add(new AgentEvent("claude", "usage", EventKind.Insight,
                    text: L($"{UsageLimits.Name(w.Kind)} limitin yenilendi", $"Your {UsageLimits.Name(w.Kind).ToLowerInvariant()} limit is back"),
                    emoji: "🔋") { UsageLeft = 100 });
            }
        }
        return events;
    }

    /// <summary>Gösterilecek pencereler (oturum, hafta); bilgi eskiyse boş.</summary>
    public List<UsageWindow> Current(DateTime now)
    {
        if (UpdatedAt is not { } at || now - at > Stale) return new List<UsageWindow>();
        return _windows.Values
            .Select(w => w.ResetsAt is { } r && r <= now ? w with { Percent = 0, ResetsAt = null } : w)
            .OrderBy(w => w.Kind == "five_hour" ? 0 : 1).ToList();
    }

    /// <summary>Gözdeki "%" için kalan yüzde (en dolu pencereye göre).</summary>
    public int? Left(DateTime now) => Current(now) is { Count: > 0 } c ? 100 - c.Max(w => w.Percent) : null;

    private static AgentEvent Notice(UsageWindow w, int level, DateTime now)
    {
        var name = UsageLimits.Name(w.Kind);
        string text;
        if (level >= 2)
            text = L($"{name} limiti neredeyse bitti (%{w.Percent})", $"{name} limit almost used up ({w.Percent}%)");
        else
            text = L($"{name} limitinin %{w.Percent}'i doldu", $"{name} limit is {w.Percent}% used");
        if (UsageLimits.FillsAt(w, now) is { } fill) text += " · " + L($"{UsageLimits.Clock(fill, now)}'ta dolar", $"full at {UsageLimits.Clock(fill, now)}");
        else if (w.ResetsAt is { } reset) text += " · " + L($"{UsageLimits.Clock(reset, now)}'de yenilenir", $"resets {UsageLimits.Clock(reset, now)}");
        return new AgentEvent("claude", "usage", EventKind.Insight, text: text, emoji: level >= 2 ? "🪫" : "🔋")
        {
            Important = level >= 2,
            UsageLeft = 100 - w.Percent,
        };
    }
}

/// <summary>Bir sohbet aynı adımı (aynı komut ya da aynı dosya) üst üste 3 kez başarısız deniyorsa "takıldı".</summary>
public sealed class StuckWatch
{
    public const int At = 3;
    private sealed record Run(string Key, int Fails, bool Told);
    private readonly Dictionary<string, Run> _runs = new();

    /// <summary>Takıldıysa denenen şeyin kısa adı (bir kez), yoksa null.</summary>
    public string? Step(string chat, string hook, JsonObject j)
    {
        if (hook is "UserPromptSubmit" or "SessionEnd") { _runs.Remove(chat); return null; }
        if (hook is not ("PostToolUse" or "PostToolUseFailure")) return null;
        var tool = j.Str("tool_name");
        if (string.IsNullOrEmpty(tool)) return null;
        var input = j.Obj("tool_input");
        var target = ToolDescriber.CommandString(input) ?? input.Str("file_path") ?? "";
        if (target == "") return null;
        var key = tool + "\n" + target;
        var failed = hook == "PostToolUseFailure" || Reactions.LooksFailed(j["tool_response"]);
        _runs.TryGetValue(chat, out var run);
        if (!failed)
        {
            if (run?.Key == key) _runs.Remove(chat);
            return null;
        }
        var same = run?.Key == key;
        var fails = same ? run!.Fails + 1 : 1;
        var stuck = fails >= At && !(same && run!.Told);
        _runs[chat] = new Run(key, fails, (same && run!.Told) || stuck);
        return stuck ? Clip(input.Str("file_path") is { } f && ToolDescriber.CommandString(input) == null ? Path.GetFileName(f) : target, 50) : null;
    }
}

/// <summary>İki farklı sohbet 30 dakika içinde aynı dosyayı düzenlerse (bir kez söylenir).</summary>
public sealed class ClashWatch
{
    public static readonly TimeSpan Window = TimeSpan.FromMinutes(30);
    private static readonly string[] EditTools = { "Edit", "Write", "MultiEdit", "NotebookEdit" };
    private sealed record Edit(string Chat, string Path, DateTime At);
    private readonly List<Edit> _edits = new();
    private readonly HashSet<string> _told = new();

    /// <summary>Çakışma varsa diğer sohbet ve dosya yolu.</summary>
    public (string Other, string Path)? Step(string chat, string hook, JsonObject j, DateTime now)
    {
        if (hook != "PostToolUse" || !EditTools.Contains(j.Str("tool_name") ?? "")) return null;
        var input = j.Obj("tool_input");
        var path = input.Str("file_path") ?? input.Str("notebook_path");
        if (string.IsNullOrEmpty(path)) return null;
        _edits.RemoveAll(e => now - e.At > Window || (e.Chat == chat && e.Path == path));
        var other = _edits.Where(e => e.Chat != chat && e.Path == path).OrderByDescending(e => e.At).FirstOrDefault();
        _edits.Add(new Edit(chat, path, now));
        if (other == null) return null;
        var key = string.Join("\n", new[] { chat, other.Chat }.OrderBy(x => x, StringComparer.Ordinal)) + "\n" + path;
        return _told.Add(key) ? (other.Chat, path) : null;
    }
}

/// <summary>`gh run list --commit SHA --json status,conclusion,name,url` çıktısının özeti.</summary>
public static class CiStatus
{
    public sealed record Result(bool Done, bool Ok, string? Failed, string? Url, int Count);

    public static Result? Summarize(string ghJson)
    {
        JsonArray? runs;
        try { runs = JsonNode.Parse(ghJson) as JsonArray; }
        catch { return null; }
        if (runs == null || runs.Count == 0) return null;
        var list = runs.OfType<JsonObject>().ToList();
        var done = list.All(r => (r.Str("status") ?? "") == "completed");
        var bad = list.FirstOrDefault(r => r.Str("conclusion") is { Length: > 0 } c && c is not ("success" or "skipped" or "neutral"));
        return new Result(done, done && bad == null, bad?.Str("name") ?? bad?.Str("workflowName"), (bad ?? list[0]).Str("url"), list.Count);
    }
}

/// <summary>Tur bittiğinde commit'lenmemiş değişiklik var ve son commit 1,5 saatten eskiyse bir kez hatırlat.</summary>
public sealed class CommitNudge
{
    public static readonly TimeSpan After = TimeSpan.FromMinutes(90);
    public static readonly TimeSpan CheckEvery = TimeSpan.FromMinutes(10);
    private readonly Dictionary<string, DateTime> _checked = new();
    private readonly Dictionary<string, DateTime> _toldFor = new();   // klasör → hatırlatılan son commit zamanı

    /// <summary>Bu klasöre şimdi bakmaya değer mi (10 dk'da bir)?</summary>
    public bool ShouldCheck(string dir, DateTime now)
    {
        if (_checked.TryGetValue(dir, out var at) && now - at < CheckEvery) return false;
        _checked[dir] = now;
        return true;
    }

    public bool ShouldTell(string dir, bool dirty, DateTime? lastCommit, DateTime now)
    {
        if (!dirty || lastCommit is not { } last || now - last < After) return false;
        if (_toldFor.TryGetValue(dir, out var told) && told == last) return false;
        _toldFor[dir] = last;
        return true;
    }
}

/// <summary>
/// Hook olaylarını ve durum satırını dinler; robotun söyleyeceği uyarıları ve uygulamanın yapacağı işleri
/// (CI'yi izle, commit durumuna bak) döner. Uygulama işleri kendisi çalıştırır (git/gh).
/// </summary>
public sealed class Insights
{
    public sealed record Job(string Kind, string Dir, string Source, string SessionId);   // Kind: "ci" | "commit"

    public readonly UsageTracker Usage = new();
    public readonly CommitNudge Nudge = new();
    private readonly StuckWatch _stuck = new();
    private readonly ClashWatch _clash = new();
    private readonly Dictionary<string, string> _projects = new();

    public (List<AgentEvent> Events, List<Job> Jobs) Handle(string path, IReadOnlyDictionary<string, string> query, string body, DateTime now)
    {
        var events = new List<AgentEvent>();
        var jobs = new List<Job>();
        if (path.StartsWith("/statusline", StringComparison.Ordinal))
        {
            events.AddRange(Usage.Update(body, now));
            return (events, jobs);
        }
        JsonObject? j;
        try { j = JsonNode.Parse(body) as JsonObject; }
        catch { return (events, jobs); }
        var hook = j.Str("hook_event_name");
        if (j == null || hook == null) return (events, jobs);
        var source = Themes.Canonical(query.TryGetValue("source", out var s) ? s : "claude");
        var session = j.Str("session_id") ?? "default";
        var chat = source + ":" + session;
        var cwd = j.Str("cwd");
        if (!string.IsNullOrEmpty(cwd)) _projects[chat] = Path.GetFileName(cwd.TrimEnd('/', '\\'));

        if (_stuck.Step(chat, hook, j) is { } what)
            events.Add(new AgentEvent(source, session, EventKind.Insight,
                text: L($"Takıldı gibi: aynı adım {StuckWatch.At} kez başarısız ({what})", $"Looks stuck: the same step failed {StuckWatch.At} times ({what})"),
                emoji: "🔁") { Mood = Core.Mood.Nervous, MoodSeconds = 4 });

        if (_clash.Step(chat, hook, j, now) is { } clash)
        {
            var mine = _projects.GetValueOrDefault(chat);
            var theirs = _projects.GetValueOrDefault(clash.Other);
            var who = mine != null && theirs != null && mine != theirs ? $" ({mine} · {theirs})" : "";
            events.Add(new AgentEvent(source, session, EventKind.Insight,
                text: L($"İki sohbet aynı dosyayı düzenliyor: {Path.GetFileName(clash.Path)}{who}",
                        $"Two chats are editing the same file: {Path.GetFileName(clash.Path)}{who}"),
                emoji: "⚠️") { Mood = Core.Mood.Nervous, MoodSeconds = 3, Important = true });
        }

        if (!string.IsNullOrEmpty(cwd))
        {
            if (hook == "PostToolUse" && !Reactions.LooksFailed(j["tool_response"])
                && Reactions.IsPush(ToolDescriber.CommandString(j.Obj("tool_input")) ?? ""))
                jobs.Add(new Job("ci", cwd, source, session));
            if (hook == "Stop" && Nudge.ShouldCheck(cwd, now))
                jobs.Add(new Job("commit", cwd, source, session));
        }
        return (events, jobs);
    }

    /// <summary>CI bitti: "CI geçti" / "CI kırmızı: Build"</summary>
    public static AgentEvent CiEvent(Job job, CiStatus.Result r)
    {
        var project = Path.GetFileName(job.Dir.TrimEnd('/', '\\'));
        return r.Ok
            ? new AgentEvent(job.Source, job.SessionId, EventKind.Insight,
                text: L($"CI geçti ({project})", $"CI passed ({project})"), emoji: "✅") { Mood = Core.Mood.Pleased, MoodSeconds = 3 }
            : new AgentEvent(job.Source, job.SessionId, EventKind.Insight,
                text: L($"CI kırmızı: {r.Failed ?? "?"} ({project})", $"CI failed: {r.Failed ?? "?"} ({project})"), emoji: "❌")
              { Mood = Core.Mood.Nervous, MoodSeconds = 4, Important = true };
    }

    /// <summary>Commit'lenmemiş iş hatırlatması</summary>
    public static AgentEvent CommitEvent(Job job, DateTime lastCommit, DateTime now)
    {
        var project = Path.GetFileName(job.Dir.TrimEnd('/', '\\'));
        return new AgentEvent(job.Source, job.SessionId, EventKind.Insight,
            text: L($"Commit'lenmemiş değişiklikler var · son commit {ShortDuration((now - lastCommit).TotalSeconds)} önce ({project})",
                    $"Uncommitted changes · last commit {ShortDuration((now - lastCommit).TotalSeconds)} ago ({project})"),
            emoji: "💾");
    }
}

/// <summary>
/// Sakin çizim: robot boştayken (hiçbir şey olmuyorsa) yeniden çizilmez; sadece göz kırpma anlarında birkaç kare.
/// Süzülme sakinleşirken 0,8 sn'de yumuşakça durur, iş gelince yumuşakça başlar.
/// </summary>
public static class Calm
{
    public const double Settle = 0.8;

    /// <summary>Göz kırpması 4,2 sn'de bir, 0,12 sn sürer; biraz öncesinden sonrasına kadar çiz.</summary>
    public static bool InBlink(double time)
    {
        var m = time % 4.2;
        if (m < 0) m += 4.2;
        return m > 4.1 || m < 0.22;
    }

    /// <summary>0 = normal hareket, 1 = tamamen dingin (süzülme, sallanma yok).</summary>
    /// <summary>from: geçiş anındaki dinginlik (yarıda kalan geçiş sıçramasın).</summary>
    public static double Stillness(bool calm, double since, double time, double from)
    {
        var t = Math.Clamp((time - since) / Settle, 0, 1);
        return calm ? from + (1 - from) * t : from * (1 - t);
    }

    /// <summary>Çizim durabilir mi: dingin, yerleşmiş ve göz kırpma anında değil.</summary>
    public static bool Paused(bool calm, double since, double time) =>
        calm && time - since >= Settle && !InBlink(time);
}
