using System.Text.RegularExpressions;
using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

/// <summary>Ekran koordinatlarında dikdörtgen (sol-üst köken, y aşağı doğru büyür)</summary>
public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public double MaxY => Y + Height;
    public double MaxX => X + Width;
    public bool Intersects(RectD o) => X < o.MaxX && o.X < MaxX && Y < o.MaxY && o.Y < MaxY;
}

public enum ButtonKind { Stop, Send, Approve }

/// <summary>Bir tarama turunda AI uygulamasının penceresinde görülenler.</summary>
public sealed class FoundUi
{
    public RectD? Stop;
    public RectD? Send;
    public bool Approve;
    public RectD? Composer;   // en alttaki yazılabilir metin alanı (yazı kutusu)
    public List<(string Text, RectD Rect)> Texts = new();
    public List<string> ButtonLabels = new();
    public List<string> Urls = new();
    public Dictionary<string, int> Roles = new();
    public string WindowsInfo = "";

    public double? ComposerTop
    {
        get
        {
            var ys = new[] { Stop, Send, Composer }.Where(r => r != null).Select(r => r!.Value.Y).ToList();
            return ys.Count == 0 ? null : ys.Min();
        }
    }
}

/// <summary>Kısa durum satırındaki fiillerden "ne yapıyor" aşaması (Türkçe ve İngilizce arayüz).</summary>
public enum WorkPhase { Understanding, Thinking, Solving, Looking, Reading, Writing, Fixing, Running, Testing, Finishing }

public static class WorkPhases
{
    public static string Phrase(this WorkPhase p) => p switch
    {
        WorkPhase.Understanding => L("İşi anlamaya çalışıyor…", "Getting the gist…"),
        WorkPhase.Thinking => L("Düşünüyor…", "Thinking…"),
        WorkPhase.Solving => L("Çözüyor…", "Working it out…"),
        WorkPhase.Looking => L("Bakıyor, araştırıyor…", "Looking around…"),
        WorkPhase.Reading => L("İnceliyor…", "Reading through…"),
        WorkPhase.Writing => L("Yazıyor…", "Writing…"),
        WorkPhase.Fixing => L("Düzeltiyor…", "Fixing things…"),
        WorkPhase.Running => L("Komut çalıştırıyor…", "Running commands…"),
        WorkPhase.Testing => L("Test ediyor…", "Testing…"),
        _ => L("Bitiriyor…", "Wrapping up…"),
    };

    public static string Emoji(this WorkPhase p) => p switch
    {
        WorkPhase.Understanding => "🤔", WorkPhase.Thinking => "🧠", WorkPhase.Solving => "🛠️", WorkPhase.Looking => "🔍",
        WorkPhase.Reading => "📖", WorkPhase.Writing => "✍️", WorkPhase.Fixing => "🔧", WorkPhase.Running => "💻",
        WorkPhase.Testing => "🧪", _ => "📦",
    };

    public static RobotState RobotState(this WorkPhase p) => p switch
    {
        WorkPhase.Looking => Core.RobotState.Searching,
        WorkPhase.Reading => Core.RobotState.Reading,
        WorkPhase.Writing or WorkPhase.Fixing => Core.RobotState.Editing,
        WorkPhase.Running or WorkPhase.Testing => Core.RobotState.Running,
        _ => Core.RobotState.Thinking,
    };

    private static readonly (WorkPhase, Regex)[] Rules = new (WorkPhase, string)[]
    {
        (WorkPhase.Testing, @"\btest"),
        (WorkPhase.Running, @"\b(ran|run|running|executing|execute|command|terminal|install|compil)|komut|çalıştır"),
        (WorkPhase.Fixing, @"\b(fix|debug|repair|patch)|düzelt|hata"),
        (WorkPhase.Writing, @"\b(writ|edit|creat|draft|updat|implement|add|generat|compos|refactor)|yaz|oluştur|ekle"),
        (WorkPhase.Reading, @"\b(read|review|analy|inspect|check|open|view|examin|load)|oku|incele"),
        (WorkPhase.Looking, @"\b(search|look|find|brows|fetch|explor|scan|gather)|ara[ıy]|bak"),
        (WorkPhase.Finishing, @"\b(publish|deliver|upload|final|wrap|summar|send|finish|complet)|yayınla|bitir|gönder"),
        (WorkPhase.Thinking, @"\b(think|reason|ponder)|düşün"),
        (WorkPhase.Solving, @"\b(plan|map|figur|consider|weigh|work|solv|design|decid)|çöz"),
    }.Select(r => (r.Item1, new Regex(r.Item2, RegexOptions.Compiled))).ToArray();

    public static WorkPhase? Match(string line)
    {
        foreach (var (phase, rx) in Rules)
            if (rx.IsMatch(line)) return phase;
        return null;
    }

    private static readonly string[] Hints =
    {
        "press tab", "escape", "focus", "keyboard", "screen reader", "available to open",
        "double-tap", "shortcut", "can make mistakes", "reply", "message claude", "ask anything",
    };

    /// <summary>Ekrandaki kısa durum satırlarından ne yaptığını çıkarır; tutmazsa geçen süreye göre ilerler.</summary>
    public static WorkPhase Infer(FoundUi found, double elapsed, bool streaming)
    {
        if (found.ComposerTop is { } top)
        {
            var lines = found.Texts
                .Where(t => t.Rect.MaxY <= top - 2 && t.Rect.MaxY >= top - 500)
                .OrderByDescending(t => t.Rect.MaxY)   // en alttaki (en yeni) önce
                .Select(t => t.Text.Trim().ToLowerInvariant())
                .Where(t => t.Length >= 4 && t.Length <= 60 && !Hints.Any(t.Contains))
                .Take(8);
            foreach (var line in lines)
                if (Match(line) is { } p) return p;
        }
        if (streaming) return WorkPhase.Writing;
        if (elapsed < 8) return WorkPhase.Understanding;
        if (elapsed < 30) return WorkPhase.Thinking;
        return WorkPhase.Solving;
    }

    /// <summary>En alttaki (en yeni) mesaj metni: yazı kutusunun üstünde, ipucu olmayan, en alttaki metin.</summary>
    public static string? TailText(FoundUi found)
    {
        var limit = found.ComposerTop ?? double.MaxValue;
        string[] hints = { "press tab", "escape", "focus", "keyboard", "screen reader", "available to open",
                           "can make mistakes", "reply", "message claude", "ask anything" };
        return found.Texts
            .Where(t => t.Rect.MaxY <= limit - 2 && t.Text.Length >= 25 && !hints.Any(h => t.Text.ToLowerInvariant().Contains(h)))
            .OrderByDescending(t => t.Rect.MaxY)
            .Select(t => t.Text)
            .FirstOrDefault();
    }

    /// <summary>Düğme etiketinden türü: Durdur / Gönder / İzin ver</summary>
    public static ButtonKind? Classify(string label)
    {
        var l = label.ToLowerInvariant();
        if (l.Length == 0) return null;
        if (Regex.IsMatch(l, @"\bstop\b|stop[-_ ]?(response|generating|streaming)|durdur|yanıtı kes|cancel response")) return ButtonKind.Stop;
        if (Regex.IsMatch(l, @"^(allow|always allow|approve)\b|\ballow once\b|\ballow for\b|izin ver|onayla")) return ButtonKind.Approve;
        if (Regex.IsMatch(l, @"\bsend\b|gönder|submit")) return ButtonKind.Send;
        return null;
    }
}

/// <summary>
/// Bir AI masaüstü uygulamasının (Claude, ChatGPT) durumunu tarama sonuçlarından çıkarır ve robota olay üretir.
/// Zamana bağlıdır: tarama sıklığı değişse de aynı sonucu verir. (Mac'teki AppWatcher'ın mantığı.)
/// </summary>
public sealed class ChatAppTracker
{
    public string Source { get; }
    public int Pid { get; }
    public string AppName { get; }
    public bool Generating { get; private set; }
    public bool Approving { get; private set; }
    public bool SawComposer { get; private set; }
    public WorkPhase? Phase { get; private set; }
    public string? ChatKey { get; private set; }

    private int _quietPolls;
    private int _chatCounter;
    private double _startedAt, _lastPhaseAt, _lastHeartbeat, _lastGrowthAt, _lastActiveAt;
    private string? _lastTail;
    private int _growthPolls;

    public ChatAppTracker(string source, int pid, string appName)
    {
        Source = source;
        Pid = pid;
        AppName = appName;
    }

    public string SessionId => $"app-{Pid}-{_chatCounter}";

    public string StatusText => !SawComposer ? L("yazı kutusu bulunamadı", "can't find the input box")
        : Approving ? L("onay bekliyor", "waiting for approval")
        : Generating ? L("çalışıyor", "working")
        : L("izleniyor", "watching");

    private AgentEvent Ev(EventKind kind, RobotState? state = null, string? text = null, string? emoji = null) =>
        new(Source, SessionId, kind, state, text, emoji: emoji) { AppPid = Pid };

    /// <summary>Bir tarama sonucunu işler; robota gönderilecek olayları döner. now: saniye (monoton).</summary>
    public List<AgentEvent> Update(FoundUi found, string? windowTitle, double now)
    {
        var events = new List<AgentEvent>();
        if (found.Stop != null || found.Send != null || found.Composer != null) SawComposer = true;

        // Başka sohbete geçildi mi? Geçildiyse eski sohbet için "bitti" deme, tıklanan sohbete geç.
        var key = found.Urls.FirstOrDefault(u => u.Contains("/chat")) ?? found.Urls.LastOrDefault() ?? windowTitle;
        if (!string.IsNullOrEmpty(key))
        {
            if (ChatKey != null && ChatKey != key)
            {
                if (Generating || Approving) events.Add(Ev(EventKind.SessionEnd));
                Generating = false;
                Approving = false;
                _quietPolls = 0;
                Phase = null;
                _chatCounter++;
                var text = L("Bu sohbete geçtim", "Switched to this chat");
                var title = windowTitle?.Trim();
                if (!string.IsNullOrEmpty(title) && !title.Equals(AppName, StringComparison.OrdinalIgnoreCase))
                    text += ": " + Clip(title, 40);
                events.Add(Ev(EventKind.Say, text: text, emoji: "💬"));
            }
            ChatKey = key;
        }

        // İkinci yol: son mesaj büyümeye devam ediyorsa cevap akıyordur (düğme adı bilinmese de çalışır)
        var tail = WorkPhases.TailText(found);
        if (tail != null && _lastTail != null && tail != _lastTail)
        {
            if (tail.Length > _lastTail.Length && tail.StartsWith(_lastTail[..Math.Min(12, _lastTail.Length)], StringComparison.Ordinal))
            {
                _growthPolls = now - _lastGrowthAt < 3 ? _growthPolls + 1 : 1;
                _lastGrowthAt = now;
            }
            else
            {
                _growthPolls = 0;   // başka bir mesaj ya da kaydırma
            }
        }
        _lastTail = tail;
        var streaming = _growthPolls >= 2 && now - _lastGrowthAt < 2.5;
        var generatingNow = found.Stop != null || streaming;

        if (generatingNow)
        {
            _quietPolls = 0;
            _lastActiveAt = now;
            if (!Generating)
            {
                Generating = true;
                _lastHeartbeat = now;
                _startedAt = now;
                Phase = WorkPhase.Understanding;
                _lastPhaseAt = now;
                var p = WorkPhase.Understanding;
                events.Add(Ev(EventKind.Prompt, p.RobotState(), p.Phrase(), p.Emoji()));
            }
            else if (now - _lastHeartbeat > 20)
            {
                _lastHeartbeat = now;
                events.Add(Ev(EventKind.Heartbeat));
            }
            // Ne yaptığını kısa bir aşamayla söyle (bakıyor, inceliyor, yazıyor, düzeltiyor…)
            if (!found.Approve)
            {
                var p = WorkPhases.Infer(found, now - _startedAt, streaming);
                if (p != Phase && now - _lastPhaseAt > 1.5)
                {
                    Phase = p;
                    _lastPhaseAt = now;
                    events.Add(Ev(EventKind.Status, p.RobotState(), p.Phrase(), p.Emoji()));
                }
            }
        }
        else if (Generating)
        {
            _quietPolls++;
            if (_quietPolls >= 2 && now - _lastActiveAt >= 1.6)   // 1,6 sn boyunca "Durdur" yoksa (ve metin akmıyorsa) bitti say
            {
                Generating = false;
                Approving = false;
                if (now - _startedAt >= 4)
                {
                    var stop = Ev(EventKind.Stop, Core.RobotState.Done);
                    stop.QuietIfForegroundPid = Pid;
                    events.Add(stop);
                }
                else
                {
                    events.Add(Ev(EventKind.SessionEnd));   // çok kısa sürdüyse yanlış alarm: sessizce kapat
                }
            }
        }

        if (found.Approve && !Approving)
        {
            Approving = true;
            var w = Ev(EventKind.Waiting, Core.RobotState.Waiting, L("Onayını bekliyor", "Needs your approval"), "✋");
            w.QuietIfForegroundPid = Pid;
            events.Add(w);
        }
        else if (!found.Approve && Approving)
        {
            Approving = false;
            if (Generating) events.Add(Ev(EventKind.ToolDone));
        }
        return events;
    }

    /// <summary>Uygulama kapandı: açık bir iş varsa kapat.</summary>
    public AgentEvent? Closed() => Generating || Approving ? Ev(EventKind.SessionEnd) : null;
}
