using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Text;
using System.Threading;
using System.Windows;
using System.Windows.Automation;
using TelepAIth.Core;

namespace TelepAIth;

/// <summary>Süreç → AI eşlemesi: öndeki uygulama Claude ise turuncu, ChatGPT/Codex ise mavi robot.</summary>
internal static class AppMatcher
{
    public static string? Source(string? processName)
    {
        if (string.IsNullOrEmpty(processName)) return null;
        if (Themes.Shared.AppSource(processName) is { } custom) return custom;
        var n = processName.ToLowerInvariant().Replace(".exe", "");
        if (n == "claude") return "claude";
        if (n.Contains("chatgpt") || n.Contains("codex")) return "gpt";
        if (n.Contains("gemini")) return "gemini";
        return null;
    }

    public static string? ProcessName(int pid)
    {
        try
        {
            using var p = Process.GetProcessById(pid);
            return p.ProcessName;
        }
        catch { return null; }
    }
}

/// <summary>
/// Claude ve ChatGPT masaüstü uygulamalarını Windows'un erişilebilirlik arayüzüyle (UI Automation) izler:
/// "Durdur" düğmesi görünüyorsa ya da son mesaj büyüyorsa çalışıyor, "İzin ver" varsa onay bekliyor.
/// Ayrı bir iş parçacığında çalışır; olaylar <see cref="EventFound"/> ile bildirilir (UI iş parçacığında değil).
/// </summary>
internal sealed class AppWatcher
{
    public event Action<AgentEvent>? EventFound;
    public event Action<Dictionary<string, string>>? StatusChanged;
    /// <summary>Bir AI uygulaması açıldı (izleme başladıktan sonra): kaynak, uygulama adı</summary>
    public event Action<string, string>? AppOpened;
    private bool _firstTick = true;

    /// <summary>Tanılama: her uygulamada son taramada ne görüldü</summary>
    public string Diagnostics { get; private set; } = "";

    private Thread? _thread;
    private volatile bool _running;
    private readonly AutoResetEvent _kick = new(false);
    private readonly Dictionary<int, ChatAppTracker> _trackers = new();
    private readonly Dictionary<int, double> _nextScan = new();
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private Dictionary<string, string> _lastStatus = new();
    private readonly Dictionary<int, string> _diag = new();
    private volatile int _foregroundPid;

    private double Now => _clock.Elapsed.TotalSeconds;

    public void Start()
    {
        if (_running) return;
        _running = true;
        _firstTick = true;
        _thread = new Thread(Loop) { IsBackground = true, Name = "TelepAIth AppWatcher" };
        _thread.SetApartmentState(ApartmentState.MTA);
        _thread.Start();
    }

    public void Stop()
    {
        _running = false;
        _kick.Set();
    }

    /// <summary>Öndeki pencere değişti: o uygulamayı hemen tara.</summary>
    public void Kick(int foregroundPid)
    {
        _foregroundPid = foregroundPid;
        lock (_nextScan)
            if (_nextScan.ContainsKey(foregroundPid)) _nextScan[foregroundPid] = 0;
        _kick.Set();
    }

    private void Loop()
    {
        while (_running)
        {
            try { Tick(); }
            catch (Exception ex) { Log("tick: " + ex.Message); }
            _kick.WaitOne(250);
        }
        // Kapanırken açık işleri kapat
        foreach (var t in _trackers.Values)
            foreach (var e in t.ClosedAll()) EventFound?.Invoke(e);
        _trackers.Clear();
    }

    private sealed record App(int Pid, string Name, string Source, IntPtr Window);

    private static List<App> FindApps()
    {
        var own = Environment.ProcessId;
        var list = new List<App>();
        foreach (var p in Process.GetProcesses())
        {
            try
            {
                if (p.Id == own) continue;
                var source = AppMatcher.Source(p.ProcessName);
                if (source == null) continue;
                var hwnd = p.MainWindowHandle;
                if (hwnd == IntPtr.Zero) continue;   // pencere yok: arka plan süreci ya da terminaldeki Claude Code
                list.Add(new App(p.Id, p.ProcessName, source, hwnd));
            }
            catch { }
            finally { p.Dispose(); }
        }
        return list;
    }

    private void Tick()
    {
        var apps = FindApps();
        var alive = apps.Select(a => a.Pid).ToHashSet();

        // Kapanan uygulamalar
        foreach (var pid in _trackers.Keys.Where(k => !alive.Contains(k)).ToList())
        {
            foreach (var e in _trackers[pid].ClosedAll()) EventFound?.Invoke(e);
            _trackers.Remove(pid);
            lock (_nextScan) _nextScan.Remove(pid);
            lock (_diag) _diag.Remove(pid);
        }

        var now = Now;
        foreach (var app in apps)
        {
            if (!_trackers.TryGetValue(app.Pid, out var tracker))
            {
                tracker = new ChatAppTracker(app.Source, app.Pid, app.Name);
                _trackers[app.Pid] = tracker;
                lock (_nextScan) _nextScan[app.Pid] = 0;
                // Yeni açıldı (ilk taramada zaten açık olanlar sayılmaz)
                if (!_firstTick) AppOpened?.Invoke(app.Source, Themes.Shared.Theme(app.Source).DisplayName);
            }
            double due;
            lock (_nextScan) due = _nextScan.TryGetValue(app.Pid, out var d) ? d : 0;
            if (now < due) continue;

            // Pencere simge durumundaysa düğmeler "ekran dışı" görünür: bu, işin bittiği anlamına gelmez.
            // Taramayı atla, son bilinen durum kalsın (açılınca kaldığı yerden devam eder).
            if (Native.IsIconic(app.Window))
            {
                lock (_nextScan) _nextScan[app.Pid] = Now + 1.0;
                lock (_diag) _diag[app.Pid] = $"{app.Name} (pid {app.Pid}) · {tracker.StatusText} · {Text.L("simge durumunda, bekleniyor", "minimized, waiting")}";
                continue;
            }
            var started = Now;
            var found = Scan(app);
            var title = Native.WindowTitle(app.Window);
            // Ekran okunamıyorsa yedek yol: işlemci kullanımı
            double? cpu = null;
            if (tracker.CpuMode || !tracker.SawComposer)
            {
                try { using var proc = Process.GetProcessById(app.Pid); cpu = proc.TotalProcessorTime.TotalSeconds; }
                catch { }
            }
            foreach (var e in tracker.Update(found, title, Now, cpu))
            {
                e.AppProcess ??= app.Name;
                EventFound?.Invoke(e);
            }
            LogSidebar(app.Pid, app.Name, found, tracker);
            var took = Now - started;
            // Çalışırken ya da öndeyken sık, boştayken seyrek bak
            var busy = tracker.Generating || tracker.Approving || tracker.Background.Count > 0 || app.Pid == _foregroundPid;
            lock (_nextScan) _nextScan[app.Pid] = Now + Math.Max(busy ? 0.8 : 2.0, took * 1.5);

            lock (_diag)
                _diag[app.Pid] = $"{app.Name} (pid {app.Pid}) · {tracker.StatusText} · {took * 1000:0} ms\n" +
                                 $"  roles: {string.Join(", ", found.Roles.OrderByDescending(r => r.Value).Take(8).Select(r => $"{r.Key}={r.Value}"))}\n" +
                                 $"  buttons: {string.Join(" | ", found.ButtonLabels.Take(14))}\n" +
                                 $"  composer: {(found.Composer != null ? "✓" : "✗")}  stop: {(found.Stop != null ? "✓" : "✗")}  send: {(found.Send != null ? "✓" : "✗")}  approve: {(found.Approve ? "✓" : "✗")}\n" +
                                 $"  {found.WindowsInfo}\n" +
                                 $"  {SidebarDiag(found, tracker)}\n" +
                                 $"  {Text.L("son sohbet açma", "last open-chat")}: {_openChatInfo}";
        }

        _firstTick = false;
        lock (_diag) Diagnostics = _diag.Count == 0 ? "" : string.Join("\n", _diag.Values);

        var status = new Dictionary<string, string>();
        foreach (var t in _trackers.Values)
        {
            var name = Themes.Shared.Theme(t.Source).DisplayName;
            status[name] = t.StatusText;
        }
        if (!status.OrderBy(k => k.Key).SequenceEqual(_lastStatus.OrderBy(k => k.Key)))
        {
            _lastStatus = status;
            StatusChanged?.Invoke(new Dictionary<string, string>(status));
        }
    }

    // MARK: Tarama

    private static readonly CacheRequest Cache = BuildCache();

    private static CacheRequest BuildCache()
    {
        var c = new CacheRequest { AutomationElementMode = AutomationElementMode.None, TreeScope = TreeScope.Element | TreeScope.Descendants };
        c.Add(AutomationElement.NameProperty);
        c.Add(AutomationElement.ControlTypeProperty);
        c.Add(AutomationElement.BoundingRectangleProperty);
        c.Add(AutomationElement.IsEnabledProperty);
        c.Add(AutomationElement.IsOffscreenProperty);
        c.Add(AutomationElement.LocalizedControlTypeProperty);
        c.Add(AutomationElement.HelpTextProperty);
        c.Add(AutomationElement.ItemStatusProperty);
        c.Add(ValuePattern.ValueProperty);
        c.TreeFilter = Automation.ControlViewCondition;
        return c;
    }

    private static FoundUi Scan(App app)
    {
        var found = new FoundUi();
        AutomationElement root;
        try
        {
            using (Cache.Activate())
            {
                // Pencereyi ve tüm alt öğelerini tek seferde (önbellekle) al
                root = AutomationElement.FromHandle(app.Window);
            }
        }
        catch (Exception ex)
        {
            found.WindowsInfo = "UIA: " + ex.GetType().Name + " " + ex.Message;
            return found;
        }

        // Yan menü: pencerenin sol %40'ı (sohbet listesi ve yanlarındaki durum noktaları)
        RectD? sidebar = null;
        try
        {
            if (root.Cached.BoundingRectangle is var wr && !wr.IsEmpty && wr.Width >= 600)
                sidebar = new RectD(wr.X, wr.Y, wr.Width * 0.4, wr.Height);
        }
        catch { }
        found.SidebarScanned = sidebar != null;

        var count = 0;
        RectD? composer = null;
        // Yan menü adayları: gezinme bölümünde mi (<nav>), sohbet içeriğinde mi (<main>)
        var entries = new List<(SidebarItem Item, bool InNav, bool InMain)>();
        var stack = new Stack<(AutomationElement El, bool InNav, bool InMain)>();
        stack.Push((root, false, false));
        while (stack.Count > 0 && count < 6000)
        {
            var (el, parentNav, parentMain) = stack.Pop();
            count++;
            try
            {
                var kind = el.GetCachedPropertyValue(AutomationElement.LocalizedControlTypeProperty) as string ?? "";
                var inMain = parentMain || SidebarChats.IsMainContent(kind);
                var inNav = parentNav || (el.GetCachedPropertyValue(AutomationElement.ControlTypeProperty) == ControlType.Group
                                          && SidebarChats.IsNavigation(kind, el.GetCachedPropertyValue(AutomationElement.NameProperty) as string ?? ""));
                Visit(el, found, ref composer, sidebar, entries, inNav, inMain);
                var children = el.CachedChildren;
                for (var i = children.Count - 1; i >= 0; i--) stack.Push((children[i], inNav, inMain));
            }
            catch { }
        }
        // Gezinme bölümü bulunduysa yalnızca onun içi, bulunamadıysa sohbet içeriği dışındakiler
        var (sideItems, viaNav) = SidebarChats.PickSidebar(entries);
        found.Sidebar.AddRange(sideItems);
        found.SidebarViaNav = viaNav;
        found.Composer = composer;
        found.WindowsInfo = $"elements: {count}" + (count <= 3 ? " (erişilebilirlik ağacı boş görünüyor)" : "");
        return found;
    }

    private static void Visit(AutomationElement el, FoundUi found, ref RectD? composer, RectD? sidebar,
                              List<(SidebarItem Item, bool InNav, bool InMain)> entries, bool inNav, bool inMain)
    {
        var type = el.GetCachedPropertyValue(AutomationElement.ControlTypeProperty) as ControlType;
        var name = el.GetCachedPropertyValue(AutomationElement.NameProperty) as string ?? "";
        var role = type?.ProgrammaticName.Replace("ControlType.", "") ?? "?";
        found.Roles[role] = found.Roles.TryGetValue(role, out var n) ? n + 1 : 1;

        if (el.GetCachedPropertyValue(AutomationElement.IsOffscreenProperty) is true) return;
        var r = el.GetCachedPropertyValue(AutomationElement.BoundingRectangleProperty) is Rect rr && !rr.IsEmpty
            ? new RectD(rr.X, rr.Y, rr.Width, rr.Height)
            : (RectD?)null;

        // Yan menüdeki öğeler: arkada çalışan sohbetlerin durum noktaları burada
        if (sidebar is { } zone && r is { } sr && sr.X + sr.Width / 2 < zone.MaxX && !inMain && entries.Count < 1500)
        {
            var help = string.Join(" ", new[]
            {
                el.GetCachedPropertyValue(AutomationElement.HelpTextProperty) as string,
                el.GetCachedPropertyValue(AutomationElement.ItemStatusProperty) as string,
            }.Where(t => !string.IsNullOrWhiteSpace(t)));
            var link = type == ControlType.Hyperlink && el.GetCachedPropertyValue(ValuePattern.ValueProperty) is string href
                       && href.Contains("://", StringComparison.Ordinal) ? href : null;
            if (name.Length > 0 || help.Length > 0 || link != null)
                entries.Add((new SidebarItem(name, help, link, sr), inNav, inMain));
        }

        if (type == ControlType.Button || type == ControlType.SplitButton)
        {
            if (name.Length > 0 && found.ButtonLabels.Count < 60) found.ButtonLabels.Add(Text.Clip(name, 30));
            switch (WorkPhases.Classify(name))
            {
                case ButtonKind.Stop when r != null: found.Stop = r; break;
                case ButtonKind.Send when r != null: found.Send = r; break;
                case ButtonKind.Approve: found.Approve = true; break;
            }
        }
        else if (type == ControlType.Edit || (type == ControlType.Document && IsComposerHint(name)))
        {
            // En alttaki yazılabilir alan yazı kutusudur
            if (r is { } er && er.Width > 120 && (composer == null || er.Y > composer.Value.Y)) composer = er;
        }
        else if (type == ControlType.Text || type == ControlType.Hyperlink || type == ControlType.ListItem)
        {
            if (name.Length > 0 && r != null && found.Texts.Count < 4000) found.Texts.Add((name, r.Value));
        }

        if (type == ControlType.Document && el.GetCachedPropertyValue(ValuePattern.ValueProperty) is string url &&
            url.Contains("://", StringComparison.Ordinal))
            found.Urls.Add(url);
    }

    /// <summary>
    /// Listeden seçilen sohbeti aç: uygulamayı öne getir; açık sohbet değilse yan menüde o sohbetin bağlantısını bul ve bas.
    /// false: oturum bir masaüstü uygulamasının değil ya da uygulama kapalı.
    /// </summary>
    public bool OpenChat(string sessionId)
    {
        var parts = sessionId.Split('-');
        if (parts.Length < 3 || parts[0] is not ("app" or "bg") || !int.TryParse(parts[1], out var pid)) return false;
        (string Title, string? Url)? chat = null;
        var isOpen = false;
        var source = "";
        try
        {
            if (_trackers.TryGetValue(pid, out var tr))
            {
                chat = tr.FindChat(sessionId);
                isOpen = tr.SessionId == sessionId;
                source = tr.Source;
            }
        }
        catch { }   // izleyici aynı anda güncelliyor olabilir
        IntPtr hwnd;
        try { using var p = Process.GetProcessById(pid); hwnd = p.MainWindowHandle; }
        catch { return false; }
        if (hwnd == IntPtr.Zero) return false;
        Native.Activate(hwnd);
        if (isOpen) { NoteOpenChat(Text.L("zaten açık sohbet, uygulama öne getirildi", "already the open chat, app brought forward")); return true; }
        if (chat is not { } c)
        {
            NoteOpenChat(Text.L("bu sohbetin adı bilinmiyor, sadece uygulama öne geldi", "chat name unknown, only brought the app forward"), true);
            return true;
        }
        // Claude sohbeti: resmî bağlantı (claude://claude.ai/chat/<id>); yan menü kapalı ya da kaydırılmış olsa da açılır
        if (source == "claude" && SidebarChats.DeepLink(c.Url) is { } link)
        {
            try
            {
                Process.Start(new ProcessStartInfo(link) { UseShellExecute = true })?.Dispose();
                NoteOpenChat(Text.L($"açıldı (claude:// bağlantısı): {c.Title}", $"opened (claude:// link): {c.Title}"));
                return true;
            }
            catch (Exception ex) { NoteOpenChat("claude:// " + ex.Message); }
        }
        System.Threading.Tasks.Task.Run(() =>
        {
            try
            {
                var (found, text) = ClickSidebarLink(hwnd, c.Title, c.Url);
                NoteOpenChat(text, !found);
            }
            catch (Exception ex) { NoteOpenChat("hata: " + ex.Message, true); }
        });
        return true;
    }

    /// <summary>Sohbet listeden açılamadı (yan menüde yok…): robot söylesin (UI iş parçacığında çağrılır)</summary>
    public event Action<string>? OpenChatFailed;

    /// <summary>Listeden son sohbet açma denemesinin sonucu (teşhis için)</summary>
    private string _openChatInfo = "—";

    private void NoteOpenChat(string text, bool failed = false)
    {
        _openChatInfo = $"{DateTime.Now:HH:mm:ss} {text}";
        Log("open chat: " + text);
        if (failed) System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => OpenChatFailed?.Invoke(text));
    }

    /// <summary>Aynı sohbet adı mı? (büyük/küçük harf fark etmez; yan menü uzun adı kısaltıyorsa baştan eşleşme de sayılır)</summary>
    private static bool SameChatTitle(string a, string b)
    {
        var x = a.Trim().ToLowerInvariant();
        var y = b.Trim().ToLowerInvariant();
        if (x.Length == 0 || y.Length == 0) return false;
        if (x == y) return true;
        x = x.Trim('…', '.');
        y = y.Trim('…', '.');
        return Math.Min(x.Length, y.Length) >= 8 && (x.StartsWith(y, StringComparison.Ordinal) || y.StartsWith(x, StringComparison.Ordinal));
    }

    /// <summary>Yan menüde sohbete bas; bulunduysa Found = true, metin teşhis için</summary>
    private static (bool Found, string Text) ClickSidebarLink(IntPtr hwnd, string title, string? url)
    {
        var window = AutomationElement.FromHandle(hwnd);
        // Yan menü: sayfanın gezinme bölümü (<nav>); bulunamazsa bütün pencere (ama bağlantısız öğelerde sadece sol taraf)
        var nav = FindNavigation(window);
        var root = nav ?? window;
        var key = SidebarChats.NormalizeUrl(url);
        AutomationElement? best = null;
        var links = root.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Hyperlink));
        foreach (AutomationElement link in links)
        {
            var href = link.TryGetCurrentPattern(ValuePattern.Pattern, out var vp) ? ((ValuePattern)vp).Current.Value : null;
            if (key != null && SidebarChats.NormalizeUrl(href) == key) { best = link; break; }
            if (best == null && SameChatTitle(SidebarChats.StripStatus(link.Current.Name), title)) best = link;
        }
        if (best == null)
        {
            // Bağlantı yoksa (ör. Code oturumları gibi düz liste) aynı adlı öğeye tıkla
            var named = root.FindFirst(TreeScope.Descendants, new PropertyCondition(AutomationElement.NameProperty, title));
            if (named != null && nav == null)
            {
                // Gezinme bölümü yoksa sohbet içeriğindeki aynı yazıya tıklamamak için sadece pencerenin sol tarafı
                var wr = window.Current.BoundingRectangle;
                var nr = named.Current.BoundingRectangle;
                if (wr.IsEmpty || nr.IsEmpty || nr.X + nr.Width / 2 > wr.X + wr.Width * 0.4) named = null;
            }
            if (named == null) return (false, Text.L($"yan menüde bulunamadı: {title}", $"not found in the sidebar: {title}"));
            ScrollIntoView(named);
            if (named.TryGetClickablePoint(out var pt))
            {
                Native.Click((int)pt.X, (int)pt.Y);
                return (true, Text.L($"aynı adlı öğeye tıklandı: {title}", $"clicked the item with that name: {title}"));
            }
            return (true, Text.L($"bulundu ama tıklanamadı: {title}", $"found but couldn't click: {title}"));
        }
        ScrollIntoView(best);
        if (best.TryGetCurrentPattern(InvokePattern.Pattern, out var ip))
        {
            ((InvokePattern)ip).Invoke();
            return (true, Text.L($"açıldı (bağlantıya basıldı): {title}", $"opened (pressed link): {title}"));
        }
        if (best.TryGetClickablePoint(out var p2))
        {
            Native.Click((int)p2.X, (int)p2.Y);
            return (true, Text.L($"bağlantıya tıklandı: {title}", $"clicked link: {title}"));
        }
        return (true, Text.L($"bağlantıya basılamadı: {title}", $"couldn't press link: {title}"));
    }

    /// <summary>Sayfanın gezinme bölümü (yan menü): en uzun olanı</summary>
    private static AutomationElement? FindNavigation(AutomationElement window)
    {
        try
        {
            AutomationElement? best = null;
            var groups = window.FindAll(TreeScope.Descendants, new PropertyCondition(AutomationElement.ControlTypeProperty, ControlType.Group));
            foreach (AutomationElement g in groups)
            {
                if (!SidebarChats.IsNavigation(g.Current.LocalizedControlType ?? "", g.Current.Name ?? "")) continue;
                if (best == null || g.Current.BoundingRectangle.Height > best.Current.BoundingRectangle.Height) best = g;
            }
            return best;
        }
        catch { return null; }
    }

    /// <summary>Liste kaydırılmışsa öğeyi görünür yap</summary>
    private static void ScrollIntoView(AutomationElement element)
    {
        try
        {
            if (element.TryGetCurrentPattern(ScrollItemPattern.Pattern, out var sp)) ((ScrollItemPattern)sp).ScrollIntoView();
        }
        catch { }
    }

    private readonly Dictionary<int, (string Text, double At)> _sidebarLogged = new();

    /// <summary>Algılama günlüğüne: yan menüde ne görüldü (değişince, en fazla 30 sn'de bir; ilk taramada da)</summary>
    private void LogSidebar(int pid, string name, FoundUi found, ChatAppTracker tracker)
    {
        if (!found.SidebarScanned) return;
        var summary = string.Join(" | ", SidebarChats.Parse(found.Sidebar).Select(r => $"{r.Row.Title}={r.Row.State}{(r.Current ? "*" : "")}"));
        var had = _sidebarLogged.TryGetValue(pid, out var last);
        if (had && (last.Text == summary || Now - last.At < 30)) return;
        _sidebarLogged[pid] = (summary, Now);
        Log($"[{AppInfo.Version}] {name} yan menü ({(found.SidebarViaNav ? "nav" : "sol %40")}, {found.Sidebar.Count} öğe): " +
            (summary.Length == 0 ? "durumlu sohbet yok" : summary) + " · açık: " + (SidebarChats.CurrentTitle(found.Sidebar, tracker.ChatKey) ?? "?"));
    }

    /// <summary>Teşhis: yan menüde durum gibi görünen öğeler ve ipucu/açıklaması olanlar (algılamayı ayarlamak için)</summary>
    private static string SidebarDiag(FoundUi found, ChatAppTracker tracker)
    {
        if (!found.SidebarScanned) return "sidebar: —";
        var rows = SidebarChats.Parse(found.Sidebar);
        var hinted = found.Sidebar.Where(i => i.Help.Length > 0 || SidebarChats.StatusOf(i.Name) != null)
            .Take(12).Select(i => $"{Text.Clip(i.Name, 30)}{(i.Help.Length > 0 ? " {" + Text.Clip(i.Help, 30) + "}" : "")}");
        return $"sidebar ({(found.SidebarViaNav ? "nav" : "sol %40")}): {found.Sidebar.Count} öğe, {found.Sidebar.Count(i => i.Url != null)} bağlantı · " +
               $"durumlu: {string.Join(", ", rows.Select(r => $"{Text.Clip(r.Row.Title, 24)}={r.Row.State}{(r.Current ? "*" : "")}"))} · " +
               $"arkada izlenen: {tracker.Background.Count}\n  sidebar ipuçları: {string.Join(" | ", hinted)}";
    }

    private static bool IsComposerHint(string name)
    {
        var l = name.ToLowerInvariant();
        return l.Contains("message") || l.Contains("reply") || l.Contains("ask anything") || l.Contains("mesaj") || l.Contains("sor");
    }

    private static void Log(string s)
    {
        try { System.IO.File.AppendAllText(AppInfo.DebugFile, $"{DateTime.Now:HH:mm:ss} {s}\n"); } catch { }
    }
}
