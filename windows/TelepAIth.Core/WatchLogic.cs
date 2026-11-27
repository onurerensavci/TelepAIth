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
    /// <summary>Pencerenin sol tarafındaki (yan menü) öğeler: sohbet listesi ve durum noktaları</summary>
    public List<SidebarItem> Sidebar = new();
    /// <summary>Bu turda yan menü tarandı mı? (taranmadıysa arkadaki sohbetlerin durumu değişmez)</summary>
    public bool SidebarScanned;
    /// <summary>Yan menü sayfanın gezinme bölümünden (&lt;nav&gt;) mi okundu (teşhis için)</summary>
    public bool SidebarViaNav;

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
    private double? _firstSeen;

    /// <summary>
    /// Yedek yol: uygulamanın ekranı hiç okunamıyorsa (ör. Mac'te ChatGPT) çalışıp çalışmadığını işlemci kullanımından tahmin et.
    /// Cevap yazarken işlemci belirgin yükselir; 8 sn boyunca yazı kutusu görülemezse bu yola geçilir.
    /// </summary>
    public bool CpuMode => !SawComposer && _firstSeen is { } f && _lastNow - f >= CpuModeAfter;
    public const double CpuModeAfter = 8, CpuBusyPercent = 12, CpuIdlePercent = 5;
    public double CpuPercent { get; private set; }
    private double? _lastCpuSeconds, _lastCpuAt, _cpuLowSince;
    private int _cpuHighPolls;
    private double _lastNow;

    /// <summary>İşlemci kullanımından "çalışıyor mu" (yedek yol): 2 tarama üst üste yüksekse başlar, 3 sn düşük kalınca biter</summary>
    private bool CpuWorking(double? cpuSeconds, double now)
    {
        if (cpuSeconds is not { } cpu) return false;
        if (_lastCpuSeconds is { } lc && _lastCpuAt is { } la && now > la)
            CpuPercent = Math.Max(0, (cpu - lc) / (now - la) * 100);
        _lastCpuSeconds = cpu;
        _lastCpuAt = now;
        if (CpuPercent >= CpuBusyPercent)
        {
            _cpuHighPolls++;
            _cpuLowSince = null;
        }
        else
        {
            _cpuHighPolls = 0;
            if (CpuPercent < CpuIdlePercent) _cpuLowSince ??= now;
        }
        if (!Generating) return _cpuHighPolls >= 2;
        return !(_cpuLowSince is { } low && now - low >= 3);
    }
    private string? _lastTail;
    private int _growthPolls;

    public ChatAppTracker(string source, int pid, string appName)
    {
        Source = source;
        Pid = pid;
        AppName = appName;
        Background = new SidebarChats(source, pid);
    }

    /// <summary>Yan menüden izlenen, açık olmayan (arkada çalışan) sohbetler</summary>
    public SidebarChats Background { get; }

    /// <summary>Bu uygulamada açılmış sohbetler (oturum → ad, adres): listeden tıklayınca geri açabilmek için</summary>
    private readonly Dictionary<string, (string Title, string? Url)> _known = new();

    /// <summary>Oturum hangi sohbet? (açık sohbet, daha önce açılmış ya da arkadaki)</summary>
    public (string Title, string? Url)? FindChat(string sessionId) =>
        _known.TryGetValue(sessionId, out var k) ? k : Background.Find(sessionId);

    public string SessionId => $"app-{Pid}-{_chatCounter}";

    /// <summary>
    /// Henüz kaydedilmemiş yeni sohbet mi? (claude.ai/new, chatgpt.com/) İlk mesaj gidince adres /chat/…, /c/… olur;
    /// bu değişim başka sohbete geçmek sayılmamalı.
    /// </summary>
    public static bool IsDraftChat(string key)
    {
        if (!Uri.TryCreate(key, UriKind.Absolute, out var u) || u.Scheme is not ("http" or "https")) return false;
        var path = u.AbsolutePath.TrimEnd('/');
        return path.Length == 0 || path.EndsWith("/new", StringComparison.OrdinalIgnoreCase);
    }

    public string StatusText => CpuMode
            ? L($"ekran okunamıyor, işlemciden tahmini: {(Generating ? "çalışıyor" : "boşta")} (%{CpuPercent:0})",
                $"screen unreadable, guessing from CPU: {(Generating ? "working" : "idle")} ({CpuPercent:0}%)")
        : !SawComposer ? L("yazı kutusu bulunamadı", "can't find the input box")
        : Approving ? L("onay bekliyor", "waiting for approval")
        : Generating ? L("çalışıyor", "working")
        : L("izleniyor", "watching");

    /// <summary>Açık sohbetin adı (yan menüden; bilinmiyorsa null)</summary>
    public string? ChatTitle { get; private set; }

    private AgentEvent Ev(EventKind kind, RobotState? state = null, string? text = null, string? emoji = null) =>
        new(Source, SessionId, kind, state, text, project: ChatTitle != null ? Clip(ChatTitle, 40) : null, emoji: emoji) { AppPid = Pid };

    /// <summary>
    /// Claude sana soru soruyorsa (seçenekli soru ekranı: "Claude is asking: …") sorunun kendisi.
    /// Bu sırada "Durdur" düğmesi kaybolur ama tur bitmemiştir: cevabını bekliyordur.
    /// </summary>
    public static string? Question(FoundUi found)
    {
        foreach (var (text, _) in found.Texts)
        {
            var t = text.Trim();
            var l = t.ToLowerInvariant();
            if (l.StartsWith("claude is asking") || l.StartsWith("claude soruyor") || l.Contains(" is asking:"))
            {
                var i = t.IndexOf(':');
                var q = i >= 0 ? t[(i + 1)..].Trim() : "";
                return q.Length > 0 ? q : t;
            }
        }
        return null;
    }

    /// <summary>Bir tarama sonucunu işler; robota gönderilecek olayları döner. now: saniye (monoton).</summary>
    public List<AgentEvent> Update(FoundUi found, string? windowTitle, double now, double? cpuSeconds = null)
    {
        _firstSeen ??= now;
        _lastNow = now;
        var events = new List<AgentEvent>();
        var question = Question(found);
        var asking = question != null;
        if (asking)
        {
            // Soru soruyor: tur bitmedi, "bitti" deme
            _quietPolls = 0;
            _lastActiveAt = now;
        }
        if (found.Stop != null || found.Send != null || found.Composer != null) SawComposer = true;

        // Başka sohbete geçildi mi? Geçildiyse eski sohbet için "bitti" deme, tıklanan sohbete geç.
        var key = found.Urls.FirstOrDefault(u => u.Contains("/chat")) ?? found.Urls.LastOrDefault() ?? windowTitle;
        if (!string.IsNullOrEmpty(key))
        {
            // Yeni sohbette ilk mesaj gönderilince adres değişir: aynı sohbet, sadece adını aldı
            var sameChat = ChatKey != null && IsDraftChat(ChatKey) && (Generating || Approving || found.Stop != null);
            if (ChatKey != null && ChatKey != key && !sameChat)
            {
                if (Generating || Approving) events.Add(Ev(EventKind.SessionEnd));
                Generating = false;
                Approving = false;
                _quietPolls = 0;
                Phase = null;
                _chatCounter++;
                ChatTitle = null;   // yeni sohbetin adı yan menüden yeniden öğrenilecek
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
        var cpuMode = CpuMode;
        var generatingNow = found.Stop != null || streaming || (cpuMode && CpuWorking(cpuSeconds, now));

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
            if (!found.Approve && !asking)
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
        else if (Generating && !asking && !cpuMode && found.ButtonLabels.Count == 0 && found.Texts.Count == 0 && found.Composer == null)
        {
            // Hiçbir şey okunamadı (uygulama arkadayken erişilebilirlik ağacı boş gelebilir): bu "bitti" demek değil,
            // son bilinen durum kalsın. Gerçekten takılırsa 5 dk sonra kendiliğinden boşa düşer.
            _quietPolls = 0;
        }
        else if (Generating && !asking)
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
                    stop.NoNotice = cpuMode;   // işlemciden tahmin: bildirim/ses yok, sadece robot gösterir
                    events.Add(stop);
                }
                else
                {
                    events.Add(Ev(EventKind.SessionEnd));   // çok kısa sürdüyse yanlış alarm: sessizce kapat
                }
            }
        }

        var waitingNow = found.Approve || asking;
        if (waitingNow && !Approving)
        {
            Approving = true;
            var w = asking
                ? Ev(EventKind.Waiting, Core.RobotState.Waiting, L("Soru soruyor: ", "Asking you: ") + Clip(question!, 90), "❓")
                : Ev(EventKind.Waiting, Core.RobotState.Waiting, L("Onayını bekliyor", "Needs your approval"), "✋");
            w.QuietIfForegroundPid = Pid;
            events.Add(w);
        }
        else if (!waitingNow && Approving)
        {
            Approving = false;
            events.Add(Ev(Generating ? EventKind.ToolDone : EventKind.SessionEnd));
        }
        // Arkadaki sohbetler (yan menüdeki durum noktaları)
        if (found.SidebarScanned)
        {
            events.AddRange(Background.Update(found.Sidebar, ChatKey, now));
            var title = SidebarChats.CurrentTitle(found.Sidebar, ChatKey);
            if (title != null && title != ChatTitle)
            {
                ChatTitle = title;
                // Açık sohbetin adı öğrenildi ya da değişti: listede hemen görünsün ("Açık sohbet" yerine)
                if (Generating || Approving) events.Add(Ev(EventKind.Heartbeat));
            }
            if (ChatTitle != null)
            {
                if (_known.Count > 300) _known.Clear();
                _known[SessionId] = (ChatTitle, SidebarChats.NormalizeUrl(ChatKey) != null ? ChatKey : null);
            }
        }
        return events;
    }

    /// <summary>Uygulama kapandı: açık bir iş varsa kapat.</summary>
    public AgentEvent? Closed() => Generating || Approving ? Ev(EventKind.SessionEnd) : null;

    /// <summary>Uygulama kapandı: açık sohbet ve arkadaki sohbetler için kapanış olayları</summary>
    public List<AgentEvent> ClosedAll()
    {
        var events = Background.Closed();
        if (Closed() is { } e) events.Insert(0, e);
        return events;
    }
}


/// <summary>Yan menüde görülen bir öğe: ad, ipucu/açıklama (ör. "running"), bağlantı adresi, seçili (açık) sohbet mi</summary>
public readonly record struct SidebarItem(string Name, string Help, string? Url, RectD Rect, bool Current = false);

/// <summary>
/// Arkada çalışan sohbetler: Claude uygulaması yan menüde her sohbetin yanında bir durum noktası gösterir
/// (üstüne gelince "running"; cevap beklerken "awaiting…"). Açık olmayan sohbetler bundan izlenir:
/// çalışırken minik kafa olur, nokta sönünce "bitti" bildirimi gelir. (Mac'teki SidebarChats'in aynısı.)
/// </summary>
public sealed class SidebarChats
{
    public sealed record Row(string Key, string Title, string? Url, RobotState State);

    private sealed class Chat
    {
        public required string Title;
        public string? Url;
        public RobotState State;
        public double Since, LastBeat;
    }

    private static readonly string[] WaitingWords =
    {
        "awaiting answer", "awaiting your answer", "awaiting response", "awaiting your response", "awaiting input",
        "awaiting reply", "awaiting approval", "needs input", "needs your input", "needs attention", "needs approval",
        "needs your approval", "waiting for you", "waiting for your answer", "waiting for input", "waiting for approval",
        "cevap bekliyor", "cevabını bekliyor", "yanıt bekliyor", "yanıtını bekliyor", "onay bekliyor", "seni bekliyor",
    };

    private static readonly string[] WorkingWords =
    {
        "running", "working", "responding", "generating", "in progress", "streaming",
        "çalışıyor", "yanıt veriyor", "yanıtlıyor", "devam ediyor",
    };

    /// <summary>Uzun süre yanıp sönen (takılı kalmış) nokta sonsuza kadar "çalışıyor" saymasın</summary>
    public const double MaxRunSeconds = 30 * 60;

    public string Source { get; }
    public int Pid { get; }
    private readonly Dictionary<string, Chat> _chats = new();
    /// <summary>Bitmiş ya da açılmış olsa da görülen sohbetler (oturum → ad, adres): listeden tıklayınca açabilmek için</summary>
    private readonly Dictionary<string, (string Title, string? Url)> _known = new();

    public SidebarChats(string source, int pid)
    {
        Source = source;
        Pid = pid;
    }

    public int Count => _chats.Count;

    /// <summary>Durum yazısı mı? Tam eşleşme ya da "Başlık, running" / "Başlık · running" / "Başlık (running)" gibi sonek</summary>
    public static RobotState? StatusOf(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var l = text.Trim().ToLowerInvariant().TrimEnd('.', '…', ' ');
        foreach (var w in WaitingWords) if (Matches(l, w)) return RobotState.Waiting;
        foreach (var w in WorkingWords) if (Matches(l, w)) return RobotState.Running;
        return null;
    }

    private static readonly string[] Separators = { ", ", " · ", " - ", " — ", " – ", ": ", " | " };

    private static bool Matches(string l, string w) =>
        l == w || l.EndsWith("(" + w + ")", StringComparison.Ordinal)
        || Separators.Any(sep => l.EndsWith(sep + w, StringComparison.Ordinal) || l.StartsWith(w + sep, StringComparison.Ordinal));

    /// <summary>Addaki durum ekini at: "Tarif, running" → "Tarif"</summary>
    /// <summary>Yan menü satırındaki simge ve düğme yazıları sohbet adı değildir ("Includes an artifact", "More options")</summary>
    private static readonly string[] NoiseLabels =
    {
        "includes an artifact", "contains an artifact", "has an artifact", "artifact", "starred", "pinned", "more options",
        "options", "chat options", "open menu", "menu", "rename", "delete", "archive", "share", "new chat",
        "yıldızlı", "sabitlendi", "sabitlenmiş", "seçenekler", "daha fazla seçenek", "sohbet seçenekleri", "yeni sohbet",
        "artifact içerir", "yeniden adlandır", "sil", "arşivle", "paylaş",
        "sidebar", "kenar çubuğu", "copy", "retry", "edit", "kopyala", "yeniden dene", "düzenle",
    };

    public static bool IsNoise(string text)
    {
        var l = text.Trim().ToLowerInvariant().TrimEnd('.', '…', ' ');
        return NoiseLabels.Contains(l) || NoisePrefixes.Any(p => l.StartsWith(p, StringComparison.Ordinal)) || l.Contains('\n');
    }

    /// <summary>Sohbetin içinden gelen yazılar (mesajlar, mesaj düğmeleri, kenar çubuğu düğmesi) sohbet adı değildir</summary>
    private static readonly string[] NoisePrefixes =
    {
        "includes ", "you said:", "claude said:", "chatgpt said:", "show message actions", "message actions for",
        "open sidebar", "close sidebar", "toggle sidebar", "collapse sidebar", "expand sidebar",
        "scroll to bottom", "skip to content", "şunu dedin:",
    };

    /// <summary>Claude'un yan menüde adın sonuna eklediği işaretler ("TelepAIth Includes an artifact")</summary>
    private static readonly string[] Decorations =
    {
        "includes an artifact", "contains an artifact", "has an artifact", "artifact içerir",
        "starred", "pinned", "yıldızlı", "sabitlendi", "sabitlenmiş",
    };

    private static readonly string[] DecorationSeparators = { ", ", " · ", " - ", " — ", " | ", " " };

    /// <summary>Adın sonundaki işaretleri at: "TelepAIth Includes an artifact" → "TelepAIth" (Mac'te stripDecorations)</summary>
    public static string StripDecorations(string name)
    {
        var t = name.Trim();
        var changed = true;
        while (changed)
        {
            changed = false;
            var l = t.ToLowerInvariant();
            foreach (var d in Decorations)
            {
                var sep = DecorationSeparators.FirstOrDefault(s => l.EndsWith(s + d, StringComparison.Ordinal) && l.Length > d.Length + s.Length);
                if (sep == null) continue;
                t = t[..(t.Length - d.Length - sep.Length)].Trim();
                changed = true;
                break;
            }
        }
        return t;
    }

    /// <summary>Addaki durum ekini ve işaretleri at: "Tarif, running" → "Tarif", "Kod Includes an artifact" → "Kod"</summary>
    public static string StripStatus(string name) => StripDecorations(StripStatusOnly(StripDecorations(name)));

    private static string StripStatusOnly(string name)
    {
        var t = name.Trim();
        if (IsNoise(t)) return "";
        var l = t.ToLowerInvariant().TrimEnd('.', '…', ' ');
        foreach (var w in WaitingWords.Concat(WorkingWords))
        {
            if (l == w) return "";
            if (l.EndsWith("(" + w + ")", StringComparison.Ordinal)) return t[..(l.Length - w.Length - 2)].Trim();
            foreach (var sep in Separators)
            {
                if (l.EndsWith(sep + w, StringComparison.Ordinal)) return t[..(l.Length - w.Length - sep.Length)].Trim();
                if (l.StartsWith(w + sep, StringComparison.Ordinal)) return t[(w.Length + sep.Length)..].Trim();
            }
        }
        return t;
    }

    /// <summary>Adres: sorgu ve son eğik çizgi olmadan (aynı sohbetin adresleri eşleşsin)</summary>
    public static string? NormalizeUrl(string? url)
    {
        if (string.IsNullOrWhiteSpace(url) || !Uri.TryCreate(url, UriKind.Absolute, out var u)) return null;
        return (u.Host + u.AbsolutePath).TrimEnd('/').ToLowerInvariant();
    }

    private static string KeyOf(string? url, string title) => NormalizeUrl(url) ?? "t:" + title.ToLowerInvariant();

    /// <summary>Yan menü öğelerinden durumu belli sohbetler (aynı sohbet bir kez; açık olan da dahil, Current işaretiyle)</summary>
    public static List<(Row Row, bool Current)> Parse(IReadOnlyList<SidebarItem> items)
    {
        var rows = new Dictionary<string, (Row Row, bool Current)>();
        foreach (var item in items)
        {
            var st = StatusOf(item.Help) ?? StatusOf(item.Name);
            if (st == null) continue;
            var title = StripStatus(item.Name);
            var url = item.Url;
            var current = item.Current;
            if (title.Length < 2 || url == null)
            {
                // Nokta tek başına bir öğe: aynı satırdaki sohbet bağlantısını bul
                var cy = item.Rect.Y + item.Rect.Height / 2;
                SidebarItem? row = null;
                foreach (var o in items)
                {
                    if (o == item || StatusOf(o.Name) != null && StripStatus(o.Name).Length < 2) continue;
                    if (o.Url == null || StripStatus(o.Name).Length < 2) continue;   // sadece sohbet bağlantıları
                    var oc = o.Rect.Y + o.Rect.Height / 2;
                    if (Math.Abs(oc - cy) > Math.Max(o.Rect.Height / 2, 12)) continue;
                    // Bağlantısı olan, sonra satıra en yakın olan
                    if (row == null || (o.Url != null && row.Value.Url == null)
                        || ((o.Url != null) == (row.Value.Url != null) && Math.Abs(oc - cy) < Math.Abs(row.Value.Rect.Y + row.Value.Rect.Height / 2 - cy)))
                        row = o;
                }
                if (row is { } r)
                {
                    if (title.Length < 2) title = StripStatus(r.Name);
                    url ??= r.Url;
                    current |= r.Current;
                }
            }
            // Sohbet satırı bir bağlantıdır: adresi olmayan (sohbetin içindeki mesaj, düğme…) satır sayılmaz.
            // Tek istisna: durumu kendi adında taşıyan satır ("Tarif · running")
            // (Bir sohbet adı kısadır: uzun metin bir mesajdır, sohbet satırı değil)
            var ownName = StatusOf(item.Name) != null && StripStatus(item.Name).Length is >= 2 and <= 80;
            if (title.Length < 2 || (url == null && !ownName)) continue;
            var key = KeyOf(url, title);
            if (rows.TryGetValue(key, out var old) && old.Row.State.Priority() >= st.Value.Priority()) continue;
            rows[key] = (new Row(key, title, url, st.Value), current);
        }
        return rows.Values.ToList();
    }

    public string SessionIdFor(string key) => $"bg-{Pid}-{Fnv(key):x8}";

    private static uint Fnv(string s)
    {
        var h = 2166136261u;
        foreach (var c in s) h = (h ^ c) * 16777619u;
        return h;
    }

    /// <summary>
    /// Bir taramanın yan menü öğelerini işler; robota gönderilecek olayları döner.
    /// currentChat: açık sohbetin adresi (o zaten büyük kafada izleniyor, burada sayılmaz).
    /// </summary>
    public List<AgentEvent> Update(IReadOnlyList<SidebarItem> items, string? currentChat, double now)
    {
        var events = new List<AgentEvent>();
        var currentKey = NormalizeUrl(currentChat);
        bool IsCurrent(string key, bool flagged) => flagged || (currentKey != null && key == currentKey);

        var rows = new Dictionary<string, Row>();
        var currentRows = new HashSet<string>();
        foreach (var (row, cur) in Parse(items))
        {
            if (IsCurrent(row.Key, cur)) currentRows.Add(row.Key);
            else rows[row.Key] = row;
        }
        // Ekranda görünen (noktası sönmüş olsa da) sohbetler: "bitti" demek için satırın hâlâ görünmesi gerekir
        var visible = new HashSet<string>();
        foreach (var it in items)
        {
            var title = StripStatus(it.Name);
            if (it.Url != null) visible.Add(KeyOf(it.Url, title));
            if (title.Length >= 2) visible.Add("t:" + title.ToLowerInvariant());
            if (it.Current && (it.Url != null || title.Length >= 2)) currentRows.Add(KeyOf(it.Url, title));
        }
        if (currentKey != null) currentRows.Add(currentKey);

        foreach (var row in rows.Values)
        {
            var id = SessionIdFor(row.Key);
            if (_known.Count > 300) _known.Clear();
            _known[id] = (row.Title, row.Url);
            if (!_chats.TryGetValue(row.Key, out var chat))
            {
                chat = new Chat { Title = row.Title, Url = row.Url, State = row.State, Since = now, LastBeat = now };
                _chats[row.Key] = chat;
                events.Add(row.State == RobotState.Waiting
                    ? Ev(id, row.Title, EventKind.Waiting, RobotState.Waiting, L("Cevabını bekliyor", "Waiting for your reply"), "✋")
                    : Ev(id, row.Title, EventKind.Prompt, RobotState.Thinking, L("Arkada çalışıyor", "Working in the background"), "🔄"));
                continue;
            }
            chat.Title = row.Title;
            chat.Url ??= row.Url;
            if (row.State != chat.State)
            {
                chat.State = row.State;
                chat.LastBeat = now;
                events.Add(row.State == RobotState.Waiting
                    ? Ev(id, row.Title, EventKind.Waiting, RobotState.Waiting, L("Cevabını bekliyor", "Waiting for your reply"), "✋")
                    : Ev(id, row.Title, EventKind.Status, RobotState.Thinking, L("Arkada çalışıyor", "Working in the background"), "🔄"));
            }
            else if (now - chat.LastBeat > 20 && now - chat.Since < MaxRunSeconds)
            {
                chat.LastBeat = now;
                events.Add(Ev(id, row.Title, EventKind.Heartbeat));
            }
        }

        foreach (var key in _chats.Keys.Where(k => !rows.ContainsKey(k)).ToList())
        {
            var chat = _chats[key];
            _chats.Remove(key);
            var id = SessionIdFor(key);
            // Satır görünüyor ve noktası söndüyse iş bitti; açıldıysa, kaydırıldıysa ya da menü kapandıysa sessizce bırak
            var finished = visible.Contains(key) && !currentRows.Contains(key) && chat.State != RobotState.Waiting;
            if (finished && now - chat.Since >= 4)
            {
                var stop = Ev(id, chat.Title, EventKind.Stop, RobotState.Done);
                stop.ForceNotify = true;
                events.Add(stop);
            }
            else
            {
                events.Add(Ev(id, chat.Title, EventKind.SessionEnd));
            }
        }
        return events;
    }

    /// <summary>Bu oturum hangi sohbet? (yan menüde bulup açmak için: ad ve adres)</summary>
    public (string Title, string? Url)? Find(string sessionId)
    {
        foreach (var (key, chat) in _chats)
            if (SessionIdFor(key) == sessionId) return (chat.Title, chat.Url);
        return _known.TryGetValue(sessionId, out var k) ? k : null;
    }

    /// <summary>
    /// Claude masaüstünün resmî bağlantısı: claude.ai/chat/&lt;id&gt; → claude://claude.ai/chat/&lt;id&gt;.
    /// Uygulama bu bağlantıyla o sohbeti doğrudan açar (yan menüde aramaya gerek kalmaz). (Mac'te deepLink)
    /// </summary>
    public static string? DeepLink(string? url)
    {
        if (url == null || !Uri.TryCreate(url, UriKind.Absolute, out var u)) return null;
        var host = u.Host.ToLowerInvariant();
        if (host != "claude.ai" && !host.EndsWith(".claude.ai", StringComparison.Ordinal)) return null;
        var parts = u.AbsolutePath.Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length < 2) return null;
        var kind = parts[0].ToLowerInvariant();
        if (kind is not ("chat" or "project")) return null;
        var id = parts[1];
        if (id.Length < 8 || !id.All(c => Uri.IsHexDigit(c) || c == '-')) return null;
        return $"claude://claude.ai/{kind}/{id}";
    }

    /// <summary>
    /// Gezinme bölümü mü? (sayfadaki &lt;nav&gt;: Mac'te alt rolü AXLandmarkNavigation, Windows'ta yerel türü "navigation";
    /// ya da adı "Sidebar" olan grup). Yan menü budur; sohbet içeriği burada değildir. (Mac'te isNavigation)
    /// </summary>
    public static bool IsNavigation(string kind, string name)
    {
        var k = kind.Trim().ToLowerInvariant();
        if (k is "axlandmarknavigation" or "navigation" or "gezinti" or "gezinme") return true;
        return name.Trim().ToLowerInvariant().TrimEnd('.', '…', ' ') is "sidebar" or "kenar çubuğu" or "yan menü" or "yan çubuk";
    }

    /// <summary>Ana içerik bölümü mü? (&lt;main&gt;: sohbetin kendisi; buradaki yazılar asla sohbet listesi sayılmaz)</summary>
    public static bool IsMainContent(string kind) => kind.Trim().ToLowerInvariant() is "axlandmarkmain" or "main" or "ana" or "ana içerik";

    /// <summary>
    /// Taranan öğelerden yan menüdekiler: gezinme bölümü bulunduysa yalnızca onun içindekiler,
    /// bulunamadıysa ana içerik dışındakiler. ViaNav: gezinme bölümü bulundu mu (teşhis için)
    /// </summary>
    public static (List<SidebarItem> Items, bool ViaNav) PickSidebar(IReadOnlyList<(SidebarItem Item, bool InNav, bool InMain)> entries)
    {
        if (entries.Any(e => e.InNav)) return (entries.Where(e => e.InNav).Select(e => e.Item).ToList(), true);
        return (entries.Where(e => !e.InMain).Select(e => e.Item).ToList(), false);
    }

    /// <summary>Yan menüdeki gezinme sekmeleri (seçili olsalar da sohbet adı değildir)</summary>
    private static readonly HashSet<string> NavWords = new()
    {
        "chat", "chats", "code", "cowork", "projects", "artifacts", "recents", "home", "search", "new chat", "settings",
        "sohbet", "sohbetler", "kod", "projeler", "son kullanılanlar", "ana sayfa", "ara", "yeni sohbet", "ayarlar",
    };

    /// <summary>
    /// Yan menüde açık sohbetin adı: önce adresi açık sohbetinkiyle aynı olan bağlantı, sonra seçili bağlantı,
    /// en son seçili satır (Code oturumları gibi bağlantısız listeler). Gezinme sekmeleri ("Chats", "Code") sayılmaz.
    /// </summary>
    public static string? CurrentTitle(IReadOnlyList<SidebarItem> items, string? currentChat)
    {
        var key = NormalizeUrl(currentChat);
        // Sohbet adresi (claude.ai/chat/…, chatgpt.com/c/…) taşıyan bağlantının adı, "Kod" gibi sekme adlarına benzese de sohbet adıdır
        static bool IsChatLink(string? url) => NormalizeUrl(url) is { } u && (u.Contains("/chat/") || u.Contains("/c/"));
        string? Usable(SidebarItem it, int min)
        {
            var title = StripStatus(it.Name);
            return title.Length >= min && (IsChatLink(it.Url) || !NavWords.Contains(title.Trim().ToLowerInvariant().TrimEnd('.', '…', ' '))) ? title : null;
        }
        if (key != null)
            foreach (var it in items)
                if (it.Url != null && NormalizeUrl(it.Url) == key && StripStatus(it.Name) is { Length: >= 2 } t) return t;
        foreach (var it in items)
            if (it.Current && it.Url != null && Usable(it, 2) is { } t) return t;
        foreach (var it in items)
            if (it.Current && it.Url == null && Usable(it, 4) is { } t) return t;
        return null;
    }

    /// <summary>Uygulama kapandı: arkadaki sohbetleri kapat</summary>
    public List<AgentEvent> Closed()
    {
        var events = _chats.Select(kv => Ev(SessionIdFor(kv.Key), kv.Value.Title, EventKind.SessionEnd)).ToList();
        _chats.Clear();
        return events;
    }

    // Uygulama öndeyken arkadaki sohbetin bildirimi/sesi gelmez (robot balonda söyler)
    private AgentEvent Ev(string id, string title, EventKind kind, RobotState? state = null, string? text = null, string? emoji = null) =>
        new(Source, id, kind, state, text, project: Clip(title, 40), emoji: emoji) { AppPid = Pid, QuietIfForegroundPid = Pid };
}
