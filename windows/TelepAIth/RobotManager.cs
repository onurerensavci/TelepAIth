using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Windows;
using System.Windows.Threading;
using TelepAIth.Core;
using static TelepAIth.Core.Text;

namespace TelepAIth;

/// <summary>AI başına durum modeli tutar, ekrandaki tek robotun hangisini göstereceğine karar verir.</summary>
internal sealed class RobotManager
{
    private readonly Dictionary<string, RobotModel> _models = new();
    private readonly List<string> _order = new();
    private RobotAvatar? _avatar;
    private RobotWindow? _window;
    private string? _pinnedSource;
    private IntPtr _dockWindow;            // robotun peşinden gittiği AI penceresi
    private IntPtr _lastForeground;
    private readonly DispatcherTimer _timer = new(DispatcherPriority.Render) { Interval = TimeSpan.FromMilliseconds(33) };
    private readonly Stopwatch _clock = Stopwatch.StartNew();
    private double _lastTick, _lastForegroundCheck, _lastDockCheck, _lastMiniCheck, _lastSlowCheck, _lastUpdateAnnounce = -1e9;
    private bool _wasFocused = FocusMode.IsActive;
    private readonly AppWatcher _watcher = new();
    private readonly Dictionary<int, (int? Pid, DateTime At)> _ancestorCache = new();

    public Dictionary<string, string> WatcherStatus { get; private set; } = new();
    public string WatcherDiagnostics => _watcher.Diagnostics;

    public event Action? Changed;
    public Func<System.Windows.Controls.ContextMenu>? BuildRobotMenu;

    private bool _visible = Prefs.RobotsVisible;

    public bool Visible
    {
        get => _visible;
        set
        {
            _visible = value;
            Prefs.RobotsVisible = value;
            if (_window == null) return;
            if (value) _window.Show(); else _window.Hide();
            Changed?.Invoke();
        }
    }

    public IEnumerable<RobotModel> AllModels => _order.Select(s => _models[s]);
    public RobotModel? Current => _avatar?.Current;
    public bool IsLocked => Prefs.RobotLocked;

    private double Now => _clock.Elapsed.TotalSeconds;

    // MARK: Başlat

    public void Start()
    {
        var known = KnownSources;
        if (known.Count == 0) known.Add("claude");
        foreach (var s in known) Model(s);

        var avatar = new RobotAvatar(Model(known[0]));
        avatar.UserMoved += () => _dockWindow = IntPtr.Zero;
        avatar.Focus = FocusMode.IsActive;
        _avatar = avatar;

        var window = new RobotWindow(avatar);
        window.Clicked += RobotClicked;
        window.DoubleClicked += OpenCurrentApp;
        // Minik kafaya tıklayınca o AI büyük kafaya geçer ve uygulaması öne gelir
        window.MiniClicked += source =>
        {
            if (!_models.TryGetValue(source, out var m)) return;
            _pinnedSource = source;
            Show(m);
            m.Wake();
            OpenCurrentApp();
        };
        // Art arda hızlı tıklanınca başı döner
        window.RapidClicked += () => _avatar?.Current.React(Mood.Dizzy, 2.5, WithEmoji("😵‍💫", L("Başım döndü!", "I'm dizzy!")));
        window.BubbleClicked += BubbleClicked;
        window.ChatRowClicked += OpenChat;
        window.ApprovalClicked += Choose;
        window.BuildMenu = () => BuildRobotMenu!();
        _window = window;

        RobotModel.PlaySound = name => Application.Current.Dispatcher.BeginInvoke(() => Sounds.Play(name));
        Notifier.OnClick = Activate;

        _watcher.EventFound += e => Application.Current.Dispatcher.BeginInvoke(() => Handle(e));
        // Claude/ChatGPT (yeniden) açıldı: robot uyansın ve söylesin
        _watcher.AppOpened += (source, name) => Application.Current.Dispatcher.BeginInvoke(() =>
        {
            Model(source).Wake(WithEmoji("👋", L($"{name} açıldı, buradayım!", $"{name} is open, I'm here!")), always: true);
            ChooseDisplay();
            Changed?.Invoke();
        });
        _watcher.StatusChanged += st => Application.Current.Dispatcher.BeginInvoke(() =>
        {
            WatcherStatus = st;
            Changed?.Invoke();
        });
        if (Prefs.WatchApps) _watcher.Start();

        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (_, _) => Application.Current.Dispatcher.BeginInvoke(() =>
        {
            if (_dockWindow != IntPtr.Zero) RefreshDock(); else _avatar?.GoHome();
        });

        _timer.Tick += (_, _) => Tick();
        _timer.Start();

        if (_visible) window.Show();
        ForegroundChanged(Native.GetForegroundWindow());
    }

    public void Stop()
    {
        _watcher.Stop();
        _timer.Stop();
    }

    private static List<string> KnownSources
    {
        get => (Prefs.GetString("knownSources") ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries).ToList();
        set => Prefs.Set("knownSources", string.Join(",", value));
    }

    public RobotModel Model(string source)
    {
        if (_models.TryGetValue(source, out var existing)) return existing;
        var m = new RobotModel(source);
        m.StateChanged += () =>
        {
            ChooseDisplay();
            Changed?.Invoke();
        };
        _models[source] = m;
        _order.Add(source);
        var known = KnownSources;
        if (!known.Contains(source))
        {
            known.Add(source);
            KnownSources = known;
        }
        return m;
    }

    public void SetWatchApps(bool on)
    {
        Prefs.WatchApps = on;
        if (on) _watcher.Start(); else _watcher.Stop();
        if (!on) WatcherStatus = new();
        Changed?.Invoke();
    }

    // MARK: Olaylar

    private readonly Queue<string> _recent = new();

    public void Handle(AgentEvent e)
    {
        _recent.Enqueue($"{DateTime.Now:HH:mm:ss.fff} {e.Source}/{e.SessionId} {e.Kind} {e.State}");
        while (_recent.Count > 30) _recent.Dequeue();
        // Claude devam etti (izin verildi, reddedildi, yeni istek…): o oturumun bekleyen sorusunu bırak
        if (e.Kind != EventKind.Waiting)
            foreach (var p in _approvals.Where(p => p.Event.Source == e.Source && p.Event.SessionId == e.SessionId).ToList())
                p.Release();
        // Terminaldeki Claude Code / Codex: hook'u çalıştıran sürecin penceresi olan atası (terminal, VS Code…)
        if (e.AppPid == null && e.HookParentPid is { } ppid) e.AppPid = WindowedAncestor(ppid);
        var m = Model(e.Source);
        if (m.Apply(e) is { } notice) Deliver(notice, e.QuietIfForegroundPid);
        ChooseDisplay();
        Changed?.Invoke();
    }

    private int? WindowedAncestor(int pid)
    {
        if (_ancestorCache.TryGetValue(pid, out var c) && (DateTime.Now - c.At).TotalMinutes < 10) return c.Pid;
        var found = Native.WindowedAncestor(pid);
        if (_ancestorCache.Count > 200) _ancestorCache.Clear();
        _ancestorCache[pid] = (found, DateTime.Now);
        return found;
    }

    // MARK: Robottan onay

    private readonly List<PendingApproval> _approvals = new();

    /// <summary>Claude Code izin istiyor: robot bekliyor durumuna geçer, balonda düğmeler çıkar.</summary>
    public void OnPermission(PendingApproval p)
    {
        Model(p.Event.Source).ClearSay();   // önceki "izin verdim" yeni soruyu örtmesin
        Handle(p.Event);   // bekliyor durumu, bildirim; terminal penceresi (AppPid) de burada bulunur
        // Ayar kapalıysa ya da zaten terminale bakıyorsan soru terminalde çıksın
        if (!Prefs.ApproveFromRobot || TerminalInFront(p))
        {
            p.Release();
            return;
        }
        _approvals.Add(p);
        UpdateApproval();
    }

    private static bool TerminalInFront(PendingApproval p) =>
        p.Event.AppPid is { } pid && Native.WindowPid(Native.GetForegroundWindow()) == pid;

    /// <summary>Ekrandaki robotun cevaplayabileceği soru (gösterilen AI'ın en yeni sorusu)</summary>
    private PendingApproval? CurrentApproval()
    {
        if (_avatar == null) return null;
        var mine = _approvals.Where(p => !p.Finished && p.Event.Source == _avatar.Current.Source).ToList();
        return mine.FirstOrDefault(p => p.Event.SessionId == _avatar.Current.BestSessionId) ?? mine.LastOrDefault();
    }

    private void UpdateApproval()
    {
        _approvals.RemoveAll(p => p.Finished);
        if (_avatar == null) return;
        var current = CurrentApproval();
        _avatar.Approval = current == null ? null : new ApprovalPrompt(current.Id, current.Suggestions != null);
    }

    /// <summary>Balondaki düğme: kararı Claude Code'a gönder</summary>
    public void Choose(ApprovalChoice choice)
    {
        var p = CurrentApproval();
        if (p == null) return;
        p.Answer(Approval.Decision(choice, p.Suggestions));
        var m = Model(p.Event.Source);
        m.Say(choice == ApprovalChoice.Deny
            ? WithEmoji("🚫", L("Reddettim.", "Declined."))
            : WithEmoji("✅", choice == ApprovalChoice.Always ? L("İzin verdim, bundan sonra sormayacak.", "Allowed; it won't ask again.") : L("İzin verdim.", "Allowed.")), 2.5);
        UpdateApproval();
        Changed?.Invoke();
    }

    /// <summary>Bekleyen sorular: terminale geçtiysen, Claude vazgeçtiyse ya da çok beklediyse bırak</summary>
    private void CheckApprovals()
    {
        foreach (var p in _approvals.ToList())
        {
            if (p.Finished) continue;
            if (TerminalInFront(p) || (DateTime.Now - p.Created).TotalSeconds > 580 || !Prefs.ApproveFromRobot) p.Release();
        }
        UpdateApproval();
    }

    public bool HasApproval => _avatar?.Approval != null;

    /// <summary>Bildirimi gönderir: odak modunda sadece önemliler, kullanıcı o pencereye bakıyorsa hiç (ayara göre).</summary>
    private void Deliver(RobotModel.Notice notice, int? quietPid)
    {
        if (FocusMode.IsActive && !notice.Important) return;
        if (!Prefs.NotifyWhenFrontmost && quietPid is { } pid && Native.WindowPid(Native.GetForegroundWindow()) == pid) return;
        Notifier.Notify(notice.Title, notice.Body, notice.Target);
        if (!FocusMode.IsActive) Speech.Say(notice.Title);
    }

    /// <summary>Bir uygulamayı öne getirir (süreç kimliğiyle ya da süreç adıyla).</summary>
    public static void Activate(AppTarget target)
    {
        try
        {
            if (target.Pid is { } pid)
            {
                using var p = Process.GetProcessById(pid);
                if (p.MainWindowHandle != IntPtr.Zero)
                {
                    Native.Activate(p.MainWindowHandle);
                    return;
                }
            }
        }
        catch { }
        if (string.IsNullOrEmpty(target.ProcessName)) return;
        foreach (var p in Process.GetProcessesByName(target.ProcessName.Replace(".exe", "")))
        {
            using (p)
            {
                if (p.MainWindowHandle == IntPtr.Zero) continue;
                Native.Activate(p.MainWindowHandle);
                return;
            }
        }
    }

    private void BubbleClicked()
    {
        if (_avatar?.Current.Target is { IsEmpty: false } t) Activate(t);
        else OpenCurrentApp();
    }

    /// <summary>Robota çift tıklayınca: gösterdiği AI'ın uygulamasını öne getir (açık değilse aç).</summary>
    private void OpenCurrentApp()
    {
        if (_avatar == null) return;
        var source = _avatar.Current.Source;
        foreach (var p in Process.GetProcesses())
        {
            using (p)
            {
                try
                {
                    if (p.Id == Environment.ProcessId || p.MainWindowHandle == IntPtr.Zero) continue;
                    if (AppMatcher.Source(p.ProcessName) != source) continue;
                    Native.Activate(p.MainWindowHandle);
                    return;
                }
                catch { }
            }
        }
        // Açık değil: kurulu uygulamayı başlatmayı dene
        var local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        var candidates = source switch
        {
            "claude" => new[] { System.IO.Path.Combine(local, "AnthropicClaude", "claude.exe"), "claude:" },
            "gpt" => new[] { "chatgpt:" },
            _ => Array.Empty<string>(),
        };
        foreach (var c in candidates)
        {
            if (c.EndsWith(".exe") && !System.IO.File.Exists(c)) continue;
            Shell.Open(c);
            return;
        }
    }

    /// <summary>Robota tıklayınca: güncelleme varsa kur, bir sorun varsa söyle, yoksa son olayları göster.</summary>
    private void RobotClicked()
    {
        if (_avatar == null) return;
        switch (_avatar.Health)
        {
            case Health.Update:
                Updater.Shared.PromptInstall();
                break;
            case Health.Broken:
                _avatar.Current.Say(WithEmoji("🔴", _avatar.HealthText), 8);
                break;
            default:
                _avatar.Current.Wake();
                // Sohbet listesi: açıksa kapat; çalışan/bekleyen/yeni biten sohbet varsa aç, yoksa son olaylar
                if (_avatar.ChatList != null)
                {
                    _avatar.ChatList = null;
                    break;
                }
                var rows = DisplayPicker.ChatRows(AllModels, DateTime.Now);
                if (rows.Count > 0)
                {
                    _avatar.ChatList = rows;
                    _avatar.ChatListUntil = DateTime.Now.AddSeconds(10);
                }
                else
                {
                    _avatar.Current.ShowHistory();
                }
                break;
        }
    }

    /// <summary>Listeden bir sohbet seçildi: o AI'a geç ve sohbeti aç</summary>
    private void OpenChat(RobotModel.ChatRow row)
    {
        if (_avatar != null) _avatar.ChatList = null;
        if (_models.TryGetValue(row.Source, out var m))
        {
            _pinnedSource = row.Source;
            Show(m);
        }
        // Masaüstü uygulamasındaki sohbet (açık, önceden açılmış ya da arkadaki): uygulamayı öne getir, yan menüde o sohbete bas
        if (_watcher.OpenChat(row.SessionId)) return;
        // Claude Code: çalıştığı terminal; uygulama sohbeti: uygulamanın penceresi
        if (row.Target is { IsEmpty: false } target)
        {
            Activate(target);
            return;
        }
        OpenCurrentApp();
    }

    public void ShowHistory(string source)
    {
        if (!_models.TryGetValue(source, out var m) || _avatar == null) return;
        Show(m);
        m.ShowHistory();
    }

    // MARK: Sağlık ışığı

    public void SetHealth(Health health, string text)
    {
        if (_avatar == null) return;
        var wasUpdate = _avatar.Health == Health.Update;
        if (_avatar.Health == health && _avatar.HealthText == text) return;
        _avatar.SetHealth(health, text);
        if (health == Health.Update && !wasUpdate) AnnounceUpdate(text);
    }

    private void AnnounceUpdate(string version)
    {
        _lastUpdateAnnounce = Now;
        var text = L($"Güncelleme var: {version}! Bana tıkla, kurayım.", $"Update available: {version}! Click me to install.");
        _avatar?.Current.Say(WithEmoji("⬆️", text), 10);
        Speech.Say(text);
    }

    // MARK: Ayarlar

    public void SetRobotScale(double value)
    {
        Prefs.RobotScale = value;
        if (_avatar is { IsDragging: false } a)
        {
            if (_dockWindow != IntPtr.Zero) RefreshDock(); else a.GoHome();
        }
        Changed?.Invoke();
    }

    public void SetAlwaysOnTop(bool on)
    {
        _window?.SetAlwaysOnTop(on);
        Changed?.Invoke();
    }

    public void SetLocked(bool on)
    {
        Prefs.RobotLocked = on;
        if (on) _dockWindow = IntPtr.Zero;
        else
        {
            _lastForeground = IntPtr.Zero;
            ForegroundChanged(Native.GetForegroundWindow());
        }
        Changed?.Invoke();
    }

    public void FollowSettingChanged()
    {
        if (Prefs.FollowAppWindow)
        {
            _lastForeground = IntPtr.Zero;
            ForegroundChanged(Native.GetForegroundWindow());
        }
        else
        {
            _dockWindow = IntPtr.Zero;
            _avatar?.GoHome();
        }
    }

    /// <summary>Robotu şu anki masaüstüne ve ekrana getir.</summary>
    public void BringHere()
    {
        if (!Visible) Visible = true;
        _window?.MoveToDesktopOf(Native.GetForegroundWindow());
        _avatar?.GoHome();
    }

    public void ReloadAppearance()
    {
        Themes.Shared.Reload();
        Skins.Reload();
        foreach (var m in _models.Values) m.ReloadTheme();
    }

    // MARK: Odak modu ve günlük özet

    public void FocusChanged()
    {
        var on = FocusMode.IsActive;
        if (_avatar != null) _avatar.Focus = on;
        if (on != _wasFocused)
        {
            _wasFocused = on;
            Changed?.Invoke();
        }
    }

    private void UpdateMeeting()
    {
        var fg = Native.GetForegroundWindow();
        var name = AppMatcher.ProcessName(Native.WindowPid(fg));
        var frontIsAI = AppMatcher.Source(name) != null;
        var meeting = FocusMode.IsMeetingProcess(name) ||
                      (!frontIsAI && Native.MicrophoneInUse(app => app.Contains("TelepAIth", StringComparison.OrdinalIgnoreCase)));
        FocusMode.MeetingActive = meeting;
        FocusChanged();
    }

    public string? TodaySummaryText() =>
        DailyStats.Shared.Summary(s => _models.TryGetValue(s, out var m) ? m.Theme.DisplayName : Themes.Shared.Theme(s).DisplayName, DateTime.Now);

    public void ShowSummary()
    {
        if (_avatar == null) return;
        if (!Visible) Visible = true;
        if (TodaySummaryText() is { } text)
            _avatar.Current.Say(WithEmoji("📊", L("Bugün:\n", "Today:\n") + text), 14);
        else
            _avatar.Current.Say(WithEmoji("📊", L("Bugün henüz bitmiş bir iş yok.", "No finished tasks yet today.")), 5);
    }

    private void CheckDailySummary()
    {
        if (!Prefs.DailySummary || DailyStats.Shared.ShownToday || FocusMode.IsActive || DateTime.Now.Hour < Prefs.DailySummaryHour) return;
        if (TodaySummaryText() is not { } text) return;
        DailyStats.Shared.ShownToday = true;
        _avatar?.Current.Say(WithEmoji("📊", L("Günün özeti:\n", "Your day:\n") + text), 14);
        Notifier.Notify(WithEmoji("📊", L("TelepAIth · günün özeti", "TelepAIth · your day")), text);
    }

    // MARK: Hangi AI gösterilsin?

    private void ForegroundChanged(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || hwnd == _lastForeground) return;
        if (_window != null && hwnd == _window.Handle) return;
        _lastForeground = hwnd;
        var pid = Native.WindowPid(hwnd);
        if (pid == Environment.ProcessId) return;   // kendi pencerelerimiz (ayarlar, menü)
        var name = AppMatcher.ProcessName(pid);
        _pinnedSource = AppMatcher.Source(name);
        // AI uygulamasına geçince robot uyuyorsa uyansın
        if (_pinnedSource != null) Model(_pinnedSource).Wake(WithEmoji("👋", L("Uyandım!", "I'm up!")));
        ChooseDisplay();
        if (Prefs.WatchApps) _watcher.Kick(pid);

        // Sadece AI uygulamasına geçince robot o pencerenin sağ-alt köşesine uçsun; başka yerde olduğu yerde kalsın.
        if (_pinnedSource != null && Prefs.FollowAppWindow && !Prefs.RobotLocked)
        {
            _dockWindow = hwnd;
            RefreshDock();
        }
        else
        {
            _dockWindow = IntPtr.Zero;
        }
        // AI başka bir sanal masaüstündeyse robot da oraya geçsin
        if (_pinnedSource != null && Visible && !Prefs.RobotLocked && _window is { IsOnCurrentDesktop: false })
            _window.MoveToDesktopOf(hwnd);
    }

    private void RefreshDock()
    {
        if (_dockWindow == IntPtr.Zero || _avatar == null) return;
        if (Native.IsWindowVisible(_dockWindow) && !Native.IsIconic(_dockWindow) &&
            Native.WindowFrame(_dockWindow) is { } frame && frame.Width >= 320 && frame.Height >= 240)
            _avatar.Dock(frame);
        else
            _avatar.GoHome();   // pencere küçültülmüş ya da kapalı
    }

    /// <summary>Öndeki uygulama bir AI'sa onu göster. Değilse en acil olanı (seni bekleyen > çalışan), eşitlikte en son hareket edeni.</summary>
    private void ChooseDisplay()
    {
        if (_avatar == null) return;
        // Öndeki AI uygulaması (tıkladığın) her zaman büyük kafada; öteki çalışıyorsa yanında minik kafa olur
        if (_pinnedSource != null && _models.TryGetValue(_pinnedSource, out var pinned))
        {
            Show(pinned);
            return;
        }
        if (DisplayPicker.Pick(AllModels, _avatar.Current, DateTime.Now) is { } next) Show(next);
    }

    /// <summary>Büyük kafayı değiştir ve minik kafaları hemen yenile (aynı AI hem büyük hem minik görünmesin)</summary>
    private void Show(RobotModel model)
    {
        if (_avatar == null || ReferenceEquals(model, _avatar.Current)) return;
        _avatar.Show(model);
        _avatar.Minis = DisplayPicker.Minis(AllModels, model, DateTime.Now);
        _avatar.Extras = DisplayPicker.Extras(model, DateTime.Now);
    }

    /// <summary>Robotun o anki durumu (JSON) — teşhis ve otomatik testler için</summary>
    public string StateJson()
    {
        var o = new System.Text.Json.Nodes.JsonObject
        {
            ["visible"] = Visible,
            ["windowVisible"] = _window?.IsVisible ?? false,
            ["source"] = _avatar?.Current.Source,
            ["state"] = _avatar?.Current.State.ToString(),
            ["bubble"] = _avatar?.Current.BubbleText,
            ["subtitle"] = _avatar?.Current.BubbleSubtitle,
            ["minis"] = _avatar?.Minis.Count ?? 0,
            ["extras"] = _avatar?.Extras.Count ?? 0,
            ["chatList"] = _avatar?.ChatList is { } cl
                ? new System.Text.Json.Nodes.JsonArray(cl.Select(r => (System.Text.Json.Nodes.JsonNode?)$"{r.Source}/{r.Title}: {r.Status}").ToArray())
                : null,
            ["health"] = _avatar?.Health.ToString(),
            ["alignLeft"] = _avatar?.AlignLeft,
            ["bubbleBelow"] = _avatar?.BubbleBelow,
            ["focus"] = FocusMode.IsActive,
            ["approval"] = _avatar?.Approval is { } ap ? new System.Text.Json.Nodes.JsonObject
            {
                ["always"] = ap.HasAlways,
                ["buttons"] = _window?.ApprovalButtonsJson(),
            } : null,
            ["gazeAllowed"] = _avatar?.GazeAllowed ?? false,
            ["glyph"] = _avatar?.Current.EyeGlyph(DateTime.Now) is { } g && g != '\0' ? g.ToString() : "",
            ["mood"] = _avatar?.Current.Mood?.ToString(),
            ["celebrating"] = _avatar?.Current.CelebrateStart is { } cs && (DateTime.Now - cs).TotalSeconds is >= 0 and <= 2.4,
            ["recent"] = new System.Text.Json.Nodes.JsonArray(_recent.Select(r => (System.Text.Json.Nodes.JsonNode?)r).ToArray()),
            ["sessions"] = new System.Text.Json.Nodes.JsonArray(AllModels.SelectMany(m => m.SessionStates.Select(x => (System.Text.Json.Nodes.JsonNode?)$"{m.Source}/{x.Id}={x.State}")).ToArray()),
        };
        if (_avatar != null)
        {
            var r = _avatar.WindowRect;
            o["window"] = new System.Text.Json.Nodes.JsonObject { ["x"] = r.X, ["y"] = r.Y, ["w"] = r.W, ["h"] = r.H };
            o["head"] = new System.Text.Json.Nodes.JsonObject { ["x"] = Math.Round(_avatar.HeadX), ["y"] = Math.Round(_avatar.HeadY), ["size"] = Math.Round(_avatar.HeadPx) };
        }
        return o.ToJsonString();
    }

    // MARK: Döngü

    private void Tick()
    {
        var now = Now;
        var dt = Math.Min(0.1, now - _lastTick);
        _lastTick = now;
        var date = DateTime.Now;
        foreach (var m in _models.Values) m.Refresh(date);
        if (_avatar != null) _avatar.GazeAllowed = DisplayPicker.CanGaze(_models.Values, date);

        // Öndeki pencere değişti mi? (saniyede 10 kez)
        if (now - _lastForegroundCheck > 0.1)
        {
            _lastForegroundCheck = now;
            ForegroundChanged(Native.GetForegroundWindow());
            if (_approvals.Count > 0 || _avatar?.Approval != null) CheckApprovals();
        }
        // Takip edilen pencere taşındı mı? (saniyede 5 kez)
        if (_dockWindow != IntPtr.Zero && now - _lastDockCheck > 0.2)
        {
            _lastDockCheck = now;
            RefreshDock();
        }
        // Güncelleme hâlâ bekliyorsa, robot boştayken arada bir hatırlatsın
        if (_avatar is { Health: Health.Update } a && now - _lastUpdateAnnounce > 45 * 60 && a.Current.State == RobotState.Idle)
            AnnounceUpdate(a.HealthText);
        // Bekleme hatırlatmaları gibi zamanlayıcı bildirimleri
        foreach (var m in _models.Values.Where(m => m.PendingNotices.Count > 0))
        {
            var notices = m.PendingNotices.ToList();
            m.PendingNotices.Clear();
            foreach (var n in notices) Deliver(n, n.Target?.Pid);
        }
        // Minik kafalar: gösterilenin dışında çalışan/bekleyen tüm oturumlar
        if (now - _lastMiniCheck > 0.5 && _avatar != null)
        {
            _lastMiniCheck = now;
            ChooseDisplay();   // bitiş kutlaması bitince sıradaki çalışana geç
            _avatar.Minis = DisplayPicker.Minis(AllModels, _avatar.Current, date);
            // Açık sohbet listesi canlı kalsın (süreler ilerler), süresi dolunca kapansın
            if (_avatar.ChatList != null)
            {
                var rows = DisplayPicker.ChatRows(AllModels, date);
                _avatar.ChatList = date > _avatar.ChatListUntil || rows.Count == 0 ? null : rows;
            }
            _avatar.Extras = DisplayPicker.Extras(_avatar.Current, date);
        }
        // Toplantı, odak süresi, günlük özet (5 sn'de bir)
        if (now - _lastSlowCheck > 5)
        {
            _lastSlowCheck = now;
            UpdateMeeting();
            CheckDailySummary();
        }
        _window?.Frame(dt);
    }
}
