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
            if (t.Closed() is { } e) EventFound?.Invoke(e);
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
            if (_trackers[pid].Closed() is { } e) EventFound?.Invoke(e);
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
            foreach (var e in tracker.Update(found, title, Now))
            {
                e.AppProcess ??= app.Name;
                EventFound?.Invoke(e);
            }
            var took = Now - started;
            // Çalışırken ya da öndeyken sık, boştayken seyrek bak
            var busy = tracker.Generating || tracker.Approving || app.Pid == _foregroundPid;
            lock (_nextScan) _nextScan[app.Pid] = Now + Math.Max(busy ? 0.8 : 2.0, took * 1.5);

            lock (_diag)
                _diag[app.Pid] = $"{app.Name} (pid {app.Pid}) · {tracker.StatusText} · {took * 1000:0} ms\n" +
                                 $"  roles: {string.Join(", ", found.Roles.OrderByDescending(r => r.Value).Take(8).Select(r => $"{r.Key}={r.Value}"))}\n" +
                                 $"  buttons: {string.Join(" | ", found.ButtonLabels.Take(14))}\n" +
                                 $"  composer: {(found.Composer != null ? "✓" : "✗")}  stop: {(found.Stop != null ? "✓" : "✗")}  send: {(found.Send != null ? "✓" : "✗")}  approve: {(found.Approve ? "✓" : "✗")}\n" +
                                 $"  {found.WindowsInfo}";
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

        var count = 0;
        RectD? composer = null;
        var stack = new Stack<AutomationElement>();
        stack.Push(root);
        while (stack.Count > 0 && count < 6000)
        {
            var el = stack.Pop();
            count++;
            try
            {
                Visit(el, found, ref composer);
                var children = el.CachedChildren;
                for (var i = children.Count - 1; i >= 0; i--) stack.Push(children[i]);
            }
            catch { }
        }
        found.Composer = composer;
        found.WindowsInfo = $"elements: {count}" + (count <= 3 ? " (erişilebilirlik ağacı boş görünüyor)" : "");
        return found;
    }

    private static void Visit(AutomationElement el, FoundUi found, ref RectD? composer)
    {
        var type = el.GetCachedPropertyValue(AutomationElement.ControlTypeProperty) as ControlType;
        var name = el.GetCachedPropertyValue(AutomationElement.NameProperty) as string ?? "";
        var role = type?.ProgrammaticName.Replace("ControlType.", "") ?? "?";
        found.Roles[role] = found.Roles.TryGetValue(role, out var n) ? n + 1 : 1;

        if (el.GetCachedPropertyValue(AutomationElement.IsOffscreenProperty) is true) return;
        var r = el.GetCachedPropertyValue(AutomationElement.BoundingRectangleProperty) is Rect rr && !rr.IsEmpty
            ? new RectD(rr.X, rr.Y, rr.Width, rr.Height)
            : (RectD?)null;

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
