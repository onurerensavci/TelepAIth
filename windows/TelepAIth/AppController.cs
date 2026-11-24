using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using TelepAIth.Core;
using static TelepAIth.Core.Text;
using WinForms = System.Windows.Forms;

namespace TelepAIth;

/// <summary>Menüde bir satır: başlık, eylem, işaret, alt menü. null = ayraç.</summary>
internal sealed record MenuEntry(string Title, Action? Act = null, bool? Checked = null, bool Enabled = true, List<MenuEntry?>? Children = null,
    string? Icon = null, Rgb? Dot = null, bool Header = false);

/// <summary>Tepsi simgesi, sunucu ve robotu birbirine bağlar.</summary>
internal sealed class AppController : ISettingsHost
{
    public RobotManager Manager { get; } = new();
    private readonly EventServer _server = new();
    private WinForms.NotifyIcon? _tray;
    private string? _serverError;

    public void Start()
    {
        Theme.Apply();
        try { System.IO.Directory.CreateDirectory(AppInfo.SkinsDir); } catch { }
        try { Themes.WriteExampleConfigIfMissing(); } catch { }
        Themes.Shared.Reload();

        _tray = new WinForms.NotifyIcon { Icon = AppIcon.TrayIcon(Themes.Shared.Theme("claude").Color, false), Text = "TelepAIth", Visible = true };
        Microsoft.Win32.SystemEvents.DisplaySettingsChanged += (_, _) => Application.Current.Dispatcher.BeginInvoke(UpdateTrayIcon);
        _tray.MouseUp += (_, e) =>
        {
            if (e.Button == WinForms.MouseButtons.Left) Manager.Visible = !Manager.Visible;
            else if (e.Button == WinForms.MouseButtons.Right) ShowTrayMenu();
        };
        Notifier.Attach(_tray);

        Manager.Changed += Changed;
        Manager.BuildRobotMenu = BuildRobotMenu;
        Manager.Start();

        _server.EventReceived += e => Application.Current.Dispatcher.BeginInvoke(() => Manager.Handle(e));
        _server.PermissionRequested += p => Application.Current.Dispatcher.BeginInvoke(() => Manager.OnPermission(p));
        _server.StateProvider = () => Application.Current.Dispatcher.Invoke(Manager.StateJson);
        _server.DebugHandler = (path, query) => Application.Current.Dispatcher.Invoke(() => Debug(path, query));
        _server.Start();
        _serverError = _server.Error;

        Updater.Shared.Changed += Changed;
        Updater.Shared.Progress += text => Manager.Current?.Say(text, 30);
        Updater.Shared.StartAutomaticChecks();

        // Kurulu hook'ları güncel yolla yenile (uygulama taşınınca/güncellenince eski komut kalmasın)
        foreach (var t in new[] { HookTarget.Claude, HookTarget.Codex })
        {
            try { if (HookInstaller.IsInstalled(t)) HookInstaller.Install(t, Installer.HookExe, Prefs.Shield && t == HookTarget.Claude); } catch { }
        }
        if (Installer.IsInstalledCopy && Prefs.StartWithWindows && !Installer.AutostartEnabled) Installer.SetAutostart(true);
        Changed();

        if (!Prefs.OnboardingDone)
            Application.Current.Dispatcher.BeginInvoke(async () =>
            {
                await Task.Delay(1000);
                OnboardingWindow.Show(this);
            });
    }

    public void Stop()
    {
        Manager.Stop();
        _server.Stop();
        if (_tray != null)
        {
            _tray.Visible = false;
            _tray.Dispose();
        }
    }

    public void Changed()
    {
        var (health, text) = CurrentHealth();
        Manager.SetHealth(health, text);
        UpdateTrayIcon();
        if (_tray != null)
        {
            var waiting = Manager.AllModels.Any(m => m.State == RobotState.Waiting);
            var tip = waiting ? "TelepAIth · " + L("seni bekliyor", "waiting for you") : "TelepAIth " + AppInfo.Version;
            _tray.Text = tip.Length > 63 ? tip[..63] : tip;
        }
    }

    /// <summary>Tepsi simgesi: gözler gösterilen AI'ın renginde, seni bekleyen varsa turuncu nokta</summary>
    private void UpdateTrayIcon()
    {
        if (_tray == null) return;
        var waiting = Manager.AllModels.Any(m => m.State == RobotState.Waiting);
        var color = (Manager.Current?.Theme ?? Themes.Shared.Theme("claude")).Color;
        var icon = AppIcon.TrayIcon(color, waiting);
        if (!ReferenceEquals(_tray.Icon, icon)) _tray.Icon = icon;
    }

    // MARK: Sağlık ışığı

    private (Health, string) CurrentHealth()
    {
        if (_serverError != null) return (Health.Broken, L("Sunucu açılamadı: ", "Server failed: ") + Clip(_serverError, 40));
        var anyHook = HookInstaller.IsInstalled(HookTarget.Claude) || HookInstaller.IsInstalled(HookTarget.Codex);
        if (!anyHook && !Prefs.WatchApps)
            return (Health.Broken, L("Hiçbir AI'a bağlı değilim. Ayarlar → Bağlantılar'dan bağla.", "I'm not connected to any AI. Connect one in Settings → Connections."));
        if (Updater.Shared.Available is { } r) return (Health.Update, r.Version);
        return (Health.Ok, "");
    }

    // MARK: Menüler

    private static readonly Rgb Green = new(0x2E, 0xC2, 0x6E), Orange = new(0xFF, 0x99, 0x33), Red = new(0xF2, 0x4C, 0x4C);

    private List<MenuEntry?> TrayEntries()
    {
        var list = new List<MenuEntry?>();
        var (health, htext) = CurrentHealth();
        var title = _server.Port > 0 ? $"TelepAIth {AppInfo.Version}" : "TelepAIth · " + (_serverError ?? L("başlatılıyor…", "starting…"));
        // Başlık tek satır: "TelepAIth 0.17.2 · Her şey yolunda"; sorun ya da güncelleme varsa ayrı satırda kalır
        var okText = FocusMode.IsActive ? L("Odak modu ", "Focus mode ") + FocusMode.StatusText : L("Her şey yolunda", "All good");
        list.Add(new MenuEntry(health == Health.Ok && _server.Port > 0 ? title + " · " + okText : title, Header: true,
            Dot: health switch { Health.Broken => Red, Health.Update => Orange, _ => Green }));
        if (health != Health.Ok)
            list.Add(new MenuEntry(health == Health.Broken ? Clip(htext, 70) : L($"Güncelleme var: {htext}", $"Update available: {htext}"), Enabled: false));
        if (Updater.Shared.Available is { } rel)
            list.Add(new MenuEntry(L($"Güncelle: {rel.Version} hazır", $"Update: {rel.Version} is ready"), Updater.Shared.PromptInstall,
                Enabled: !Updater.Shared.IsBusy, Icon: "\uE896"));
        if (Notifier.SystemDisabled)
            list.Add(new MenuEntry(L("Bildirimler Windows'ta kapalı — aç…", "Notifications are off in Windows — turn on…"), Notifier.OpenSystemSettings, Icon: "\uE7BA"));
        list.Add(null);
        foreach (var m in Manager.AllModels)
        {
            var source = m.Source;
            list.Add(new MenuEntry($"{m.Theme.DisplayName} — {m.StatusLine}", () => Manager.ShowHistory(source), Dot: m.Theme.Color));
        }
        list.Add(null);
        list.Add(new MenuEntry(L("Robotu göster", "Show robot"), () => Manager.Visible = !Manager.Visible, Manager.Visible, Icon: "\uE890"));
        list.Add(new MenuEntry(L("Odak modu", "Focus mode"), Children: FocusEntries(), Icon: "\uE708"));
        list.Add(new MenuEntry(L("Bugünün özeti", "Today's summary"), Manager.ShowSummary, Icon: "\uE787"));
        list.Add(null);
        list.Add(new MenuEntry(L("Ayarlar", "Settings"), () => SettingsWindow.Show(this), Icon: "\uE713"));
        // Az kullanılanlar Yardım'ın altında: güncelleme, robotu buraya getir, kurulum, deneme, teşhis
        var demo = new MenuEntry(L("Dene", "Try it"), Icon: "\uE768", Children: new List<MenuEntry?>
        {
            new(L("Claude: kısa bir görev", "Claude: a short task"), Demos.Claude(this), Dot: Themes.Shared.Theme("claude").Color),
            new(L("GPT: onay beklesin", "GPT: wait for approval"), Demos.GptWaiting(this), Dot: Themes.Shared.Theme("gpt").Color),
            new(L("Claude: izin istesin (İzin ver / Reddet)", "Claude: ask for permission (Allow / Deny)"), Demos.Approval(this), Icon: "\uE8FB"),
            new(L("Claude: kota uyarısı", "Claude: quota alert"), () => Manager.Handle(Demos.Quota()), Icon: "\uEBA7"),
            new(L("İki oturum aynı anda", "Two sessions at once"), Demos.Parallel(this), Icon: "\uE716"),
            null,
            new(L("Test bildirimi gönder", "Send a test notification"), SettingsWindow.SendTest, Icon: "\uEA8F"),
        });
        list.Add(new MenuEntry(L("Yardım", "Help"), Icon: "\uE897", Children: new List<MenuEntry?>
        {
            new(Updater.Shared.IsBusy ? L("Güncelleme indiriliyor…", "Downloading update…") : L("Güncellemeleri denetle", "Check for updates"),
                CheckUpdates, Enabled: !Updater.Shared.IsBusy, Icon: "\uE895"),
            new(L("Robotu bu masaüstüne getir", "Bring robot to this desktop"), Manager.BringHere, Icon: "\uE7C4"),
            new(L("Kurulum sihirbazı", "Setup assistant"), () => OnboardingWindow.Show(this), Icon: "\uE82F"),
            demo,
            null,
            new(L("Hata bildir", "Report a problem"), ReportBug, Icon: "\uEBE8"),
            new(L("Teşhis", "Diagnostics"), OpenDiagnostics, Icon: "\uE9D9"),
            new(L("Algılama günlüğünü aç", "Open detection log"), () => Shell.Open(AppInfo.DebugFile), Enabled: System.IO.File.Exists(AppInfo.DebugFile), Icon: "\uE8A5"),
            new(L("Ayar klasörünü aç", "Open settings folder"), () => Shell.Open(AppInfo.SupportDir), Icon: "\uE838"),
            new(L("Renkleri ve kostümleri yeniden yükle", "Reload colors and skins"), Manager.ReloadAppearance, Icon: "\uE72C"),
            null,
            new(L("TelepAIth'i kaldır", "Uninstall TelepAIth"), Uninstall, Icon: "\uE74D"),
        }));
        list.Add(null);
        list.Add(new MenuEntry(L("Çıkış", "Quit"), () => Application.Current.Shutdown(), Icon: "\uE711"));
        return list;
    }

    private List<MenuEntry?> FocusEntries()
    {
        void After() { Manager.FocusChanged(); Changed(); }
        return new List<MenuEntry?>
        {
            new(FocusMode.StatusText, Header: true),
            null,
            new(L("1 saat", "1 hour"), () => { FocusMode.TurnOn(3600); After(); }, Icon: "\uE916"),
            new(L("Kapatana kadar", "Until I turn it off"), () => { FocusMode.TurnOn(null); After(); }, Icon: "\uE708"),
            new(L("Kapat", "Turn off"), () => { FocusMode.TurnOff(); After(); }, Enabled: FocusMode.ManualActive, Icon: "\uE711"),
            null,
            new(L("Toplantıda kendiliğinden aç", "Automatically in meetings"), () => { Prefs.AutoFocusInMeetings = !Prefs.AutoFocusInMeetings; After(); }, Prefs.AutoFocusInMeetings, Icon: "\uE720"),
        };
    }

    /// <summary>Robota sağ tık</summary>
    private ContextMenu BuildRobotMenu()
    {
        var current = Manager.Current;
        var entries = new List<MenuEntry?>
        {
            new(L("Son olayları göster", "Show recent events"), () => { if (current != null) Manager.ShowHistory(current.Source); }, Icon: "\uE81C"),
            null,
            new(Prefs.RobotLocked ? L("Kilidi aç", "Unlock") : L("Kilitle (yerinde kalsın)", "Lock (stay here)"), () =>
            {
                var on = !Prefs.RobotLocked;
                Manager.SetLocked(on);
                Manager.Current?.Say(on ? WithEmoji("🔒", L("Kilitlendim, yerimden kıpırdamıyorum.", "Locked. I'm staying right here."))
                                        : WithEmoji("🔓", L("Kilidim açıldı, yine Claude ve GPT'nin peşinden gelirim.", "Unlocked. I'll follow Claude and GPT again.")), 4);
            }, Icon: Prefs.RobotLocked ? "\uE785" : "\uE72E"),
            new(L("Her zaman üstte", "Always on top"), () =>
            {
                var on = !Prefs.AlwaysOnTop;
                Manager.SetAlwaysOnTop(on);
                Manager.Current?.Say(on ? WithEmoji("📌", L("Her zaman en üstteyim.", "I'll stay on top of everything."))
                                        : WithEmoji("🪟", L("Artık diğer pencerelerin arkasında kalabilirim.", "Other windows can cover me now.")), 4);
            }, Prefs.AlwaysOnTop, Icon: "\uE718"),
            new(FocusMode.ManualActive ? L("Odak modunu kapat", "Turn off focus mode") : L("Odak modu (1 saat)", "Focus mode (1 hour)"), () =>
            {
                if (FocusMode.ManualActive)
                {
                    FocusMode.TurnOff();
                    Manager.Current?.Say(WithEmoji("☀️", L("Odak modu kapandı, yine konuşuyorum.", "Focus mode off, I'm chatty again.")), 4);
                }
                else
                {
                    FocusMode.TurnOn(3600);
                    Manager.Current?.Say(WithEmoji("🌙", L("Bir saat sessizim; sadece seni bekleyen şeyleri söylerim.", "Quiet for an hour; I'll only tell you what needs you.")), 4);
                }
                Manager.FocusChanged();
                Changed();
            }, Icon: "\uE708"),
            new(Prefs.Muted ? L("Sesi aç", "Unmute") : L("Sessize al", "Mute"), () =>
            {
                Prefs.Muted = !Prefs.Muted;
                Manager.Current?.Say(Prefs.Muted
                    ? WithEmoji("🔇", L("Sessizim: bildirimler sessiz gelir, ses çıkarmam.", "Muted: notifications come silently, no sounds."))
                    : WithEmoji("🔊", L("Sesim geri geldi.", "Sound is back.")), 4);
                Changed();
            }, Prefs.Muted, Icon: Prefs.Muted ? "\uE767" : "\uE74F"),
            new(L("Bugünün özeti", "Today's summary"), Manager.ShowSummary, Icon: "\uE787"),
            null,
            new(L("Ayarlar", "Settings"), () => SettingsWindow.Show(this), Icon: "\uE713"),
            new(L("Teşhis", "Diagnostics"), OpenDiagnostics, Icon: "\uE9D9"),
            new(L("Hata bildir", "Report a problem"), ReportBug, Icon: "\uEBE8"),
            null,
            new(L("Robotu gizle", "Hide robot"), () => Manager.Visible = false, Icon: "\uED1A"),
        };
        // En üstte: robotun şu an gösterdiği AI ve ne yaptığı
        if (current != null)
        {
            entries.Insert(0, null);
            entries.Insert(0, new MenuEntry(current.Theme.DisplayName + " — " + current.StatusLine, Header: true, Dot: current.Theme.Color));
        }
        return BuildMenu(entries);
    }

    private static object ToWpf(MenuEntry? e)
    {
        if (e == null) return new Separator();
        var header = new TextBlock { VerticalAlignment = VerticalAlignment.Center, TextTrimming = TextTrimming.CharacterEllipsis, MaxWidth = 380 }.WithText(e.Title);
        if (e.Header)
        {
            header.FontWeight = FontWeights.SemiBold;
            header.FontSize = 12;
        }
        var item = new MenuItem { Header = header, IsEnabled = e.Enabled && !e.Header, IsCheckable = false, IsChecked = e.Checked == true };
        if (e.Dot is { } dot)
        {
            item.Icon = new System.Windows.Shapes.Ellipse
            {
                Width = 9, Height = 9, Margin = new Thickness(3, 0, 0, 0),
                Fill = new System.Windows.Media.SolidColorBrush(System.Windows.Media.Color.FromRgb(dot.R, dot.G, dot.B)),
            };
        }
        else if (e.Icon != null)
        {
            item.Icon = new TextBlock { Text = e.Icon, FontFamily = new System.Windows.Media.FontFamily(Theme.Icons), FontSize = 15, VerticalAlignment = VerticalAlignment.Center };
        }
        if (e.Children != null)
            foreach (var c in e.Children) item.Items.Add(ToWpf(c));
        else if (e.Act is { } act)
            item.Click += (_, _) => act();
        return item;
    }

    private Window? _menuHost;
    private ContextMenu? _trayMenu;

    /// <summary>
    /// Tepsi menüsü: robotun sağ tık menüsüyle aynı (Windows 11 görünümlü WPF menüsü). Dışarı tıklayınca kapanması için
    /// görünmez küçük bir pencere öne alınır (tepsi menülerinin bilinen kuralı).
    /// </summary>
    public void ShowTrayMenu()
    {
        if (_menuHost == null)
        {
            _menuHost = new Window
            {
                WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent,
                ShowInTaskbar = false, Width = 1, Height = 1, Left = -100, Top = -100, Topmost = true, Title = "TelepAIth menu",
            };
        }
        _menuHost.Show();
        _menuHost.Activate();
        var menu = BuildMenu(TrayEntries());
        menu.PlacementTarget = _menuHost;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        menu.HorizontalOffset = -10;
        menu.VerticalOffset = -6;
        menu.Closed += (_, _) => _menuHost?.Hide();
        _trayMenu = menu;
        menu.IsOpen = true;
    }

    public static ContextMenu BuildMenu(IEnumerable<MenuEntry?> entries)
    {
        Theme.Apply();
        var menu = new ContextMenu();
        foreach (var e in entries) menu.Items.Add(ToWpf(e));
        return menu;
    }

    // MARK: Test kancaları (sadece TELEPAITH_HOOK_DEBUG=1)

    private ContextMenu? _debugMenu;

    private string Debug(string path, Dictionary<string, string> query)
    {
        try
        {
            switch (path)
            {
                case "/debug/emoji":
                {
                    var (ok, colored, opaque) = Emoji.Probe(query.TryGetValue("e", out var e) ? e : "🎉");
                    return $"{{\"ok\":{(ok ? "true" : "false")},\"colored\":{colored},\"opaque\":{opaque},\"error\":\"{Emoji.LastError?.Replace("\"", "'")}\"}}";
                }
                case "/debug/tray":
                {
                    var px = AppIcon.TraySize;
                    return $"{{\"px\":{px},\"fill16\":{AppIcon.TrayFill(16).ToString(System.Globalization.CultureInfo.InvariantCulture)},\"fill\":{AppIcon.TrayFill(px).ToString(System.Globalization.CultureInfo.InvariantCulture)}}}";
                }
                case "/debug/ui":
                {
                    var what = query.TryGetValue("open", out var o) ? o : "";
                    _debugMenu?.SetCurrentValue(ContextMenu.IsOpenProperty, false);
                    _trayMenu?.SetCurrentValue(ContextMenu.IsOpenProperty, false);
                    switch (what)
                    {
                        case "settings": SettingsWindow.Show(this, query.TryGetValue("page", out var pg) && int.TryParse(pg, out var pi) ? pi : 0); break;
                        case "onboarding": OnboardingWindow.Show(this); break;
                        case "diagnostics": OpenDiagnostics(); break;
                        case "traymenu": ShowTrayMenu(); break;
                        case "robotmenu":
                            _debugMenu = BuildRobotMenu();
                            _debugMenu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
                            _debugMenu.IsOpen = true;
                            break;
                        case "close":
                            SettingsWindow.Close();
                            OnboardingWindow.Close();
                            DiagnosticsWindow.Close();
                            break;
                    }
                    return "ok";
                }
            }
            return "unknown";
        }
        catch (Exception ex)
        {
            return "error: " + ex;
        }
    }

    // MARK: Eylemler

    private async void CheckUpdates()
    {
        var message = await Updater.Shared.CheckAsync(true);
        if (Updater.Shared.Available != null) Updater.Shared.PromptInstall();
        else if (message != null) MessageBox.Show(message, AppInfo.Name);
        Changed();
    }

    public string ReportText(bool includeTexts)
    {
        var lines = new List<string>
        {
            $"TelepAIth (Windows) teşhis raporu — {DateTime.Now:yyyy-MM-dd HH:mm:ss}",
            $"{L("Sürüm", "Version")}: {AppInfo.Version}",
            $"Windows: {Environment.OSVersion.VersionString} ({(Environment.Is64BitOperatingSystem ? "x64" : "x86")})",
            $"{L("Konum", "Location")}: {AppContext.BaseDirectory}",
            $".NET: {System.Runtime.InteropServices.RuntimeInformation.FrameworkDescription}",
            $"{L("Sunucu", "Server")}: {(_server.Port > 0 ? "127.0.0.1:" + _server.Port : _serverError ?? "—")}",
            $"{L("Masaüstü izleme", "Desktop watching")}: {(Prefs.WatchApps ? L("açık", "on") : L("kapalı", "off"))}",
            $"{L("Bildirimler", "Notifications")}: {(Prefs.NotificationsEnabled ? L("açık", "on") : L("kapalı", "off"))}{(Notifier.SystemDisabled ? L(" (Windows'ta kapalı)", " (off in Windows)") : "")}",
            $"Claude Code: {(HookInstaller.IsInstalled(HookTarget.Claude) ? L("bağlı", "connected") : L("bağlı değil", "not connected"))}",
            $"Codex: {(HookInstaller.IsInstalled(HookTarget.Codex) ? L("bağlı", "connected") : L("bağlı değil", "not connected"))}",
            $"{L("Anlatıcı", "Narrator")}: {(NarratorInstaller.IsInstalled() ? L("ekli", "added") : L("ekli değil", "not added"))}",
            $"{L("Odak modu", "Focus mode")}: {FocusMode.StatusText}",
            $"{L("Ekranlar", "Displays")}: {string.Join("; ", Native.Monitors().Select(m => $"{m.Device} {m.Bounds.Width}x{m.Bounds.Height} @{m.Scale * 100:0}%"))}",
            $"{L("Robot", "Robot")}: {Manager.Current?.Source} · {Manager.Current?.State} · {L("boyut", "size")} {Prefs.RobotScale * 100:0}%",
        };
        var diag = Manager.WatcherDiagnostics;
        lines.Add("");
        lines.Add("== " + L("İzlenen uygulamalar", "Watched apps") + " ==");
        lines.Add(string.IsNullOrEmpty(diag) ? L("Claude/ChatGPT uygulaması açık değil (ya da izleme kapalı).", "No Claude/ChatGPT app open (or watching is off).") : diag);
        if (!includeTexts) return string.Join("\n", lines);
        return string.Join("\n", lines);
    }

    private void OpenDiagnostics() => DiagnosticsWindow.Show(() => ReportText(true));

    /// <summary>Tek tıkla hata raporu: bilgilerle dolu bir GitHub issue'su açar, tam raporu panoya kopyalar.</summary>
    private void ReportBug()
    {
        var full = ReportText(true);
        try { Clipboard.SetText(full); } catch { }
        var report = ReportText(false);
        if (report.Length > 5000) report = report[..5000] + "\n…";
        var body = L(
            "**Ne oldu?**\n<!-- Ne yapıyordun, ne bekliyordun, ne oldu? -->\n\n\n**Ortam**\n- Windows: " + Environment.OSVersion.VersionString +
            "\n\n<details><summary>Teşhis raporu</summary>\n\n```\n" + report + "\n```\n</details>\n",
            "**What happened?**\n<!-- What were you doing, what did you expect, what happened? -->\n\n\n**Environment**\n- Windows: " + Environment.OSVersion.VersionString +
            "\n\n<details><summary>Diagnostics</summary>\n\n```\n" + report + "\n```\n</details>\n");
        var title = "[Windows] " + L("Sorun: ", "Problem: ");
        var url = $"https://github.com/{AppInfo.Repo}/issues/new?labels=windows&title={Uri.EscapeDataString(title)}&body={Uri.EscapeDataString(body)}";
        if (url.Length > 7500) url = url[..7500];
        Shell.Open(url);
        Notifier.Notify("🐞 " + L("Hata raporu açıldı", "Bug report opened"),
            L("Tam teşhis raporu panoya kopyalandı; gerekirse yapıştır.", "The full diagnostics report is on your clipboard; paste it if needed."));
    }

    private void Uninstall()
    {
        var answer = MessageBox.Show(
            L("TelepAIth kaldırılsın mı?\n\nClaude Code/Codex bağlantıları, otomatik başlatma, kısayol ve program dosyaları silinir. Ayarların (~/.telepaith) kalır.",
              "Uninstall TelepAIth?\n\nClaude Code/Codex connections, autostart, the shortcut and program files will be removed. Your settings (~/.telepaith) stay."),
            AppInfo.Name, MessageBoxButton.YesNo, MessageBoxImage.Question);
        if (answer != MessageBoxResult.Yes) return;
        Installer.Uninstall();
        Application.Current.Shutdown();
    }

    // MARK: ISettingsHost

    public void SetHook(HookTarget target, bool on, bool quiet)
    {
        try
        {
            if (!on)
            {
                if (HookInstaller.IsInstalled(target)) HookInstaller.Uninstall(target);
            }
            else if (!HookInstaller.IsInstalled(target))
            {
                HookInstaller.Install(target, Installer.HookExe, Prefs.Shield && target == HookTarget.Claude);
                Manager.Model(HookInstaller.Source(target));
                if (!quiet)
                {
                    var info = target == HookTarget.Claude
                        ? L("Yeni açacağın Claude Code oturumları robota haber verecek. Açık oturumlar yeniden başlatılınca bağlanır.\n\nAyarların yedeği: %USERPROFILE%\\.claude\\settings.json.telepaith-backup",
                            "New Claude Code sessions will report to the robot. Open sessions connect after a restart.\n\nBackup of your settings: %USERPROFILE%\\.claude\\settings.json.telepaith-backup")
                        : L("Codex yeni hook'lar için onay istiyor: Codex'i bir sonraki açışında /hooks yazıp TelepAIth hook'larını onayla.",
                            "Codex asks you to approve new hooks: next time you open Codex, type /hooks and approve the TelepAIth hooks.");
                    MessageBox.Show(info, HookInstaller.DisplayName(target) + L(" bağlandı", " connected"));
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, L("Bağlanamadı", "Couldn't connect"));
        }
        Changed();
    }

    public void SetShield(bool on)
    {
        Prefs.Shield = on;
        if (HookInstaller.IsInstalled(HookTarget.Claude))
        {
            try { HookInstaller.Install(HookTarget.Claude, Installer.HookExe, on); } catch { }
        }
        Changed();
    }

    public void SetNarrator(bool on)
    {
        try
        {
            if (!on)
            {
                if (NarratorInstaller.IsInstalled()) NarratorInstaller.Uninstall();
            }
            else if (!NarratorInstaller.IsInstalled())
            {
                NarratorInstaller.Install(Installer.HookExe);
                var cmd = NarratorInstaller.ClaudeCodeCommand(Installer.HookExe);
                var text = L("1) Claude uygulamasını kapatıp yeniden aç.\n2) Claude'un ne zaman haber vereceğini bilmesi için bu talimatı Claude → Ayarlar → Profil'deki tercihlere ekle (Evet'e basınca panoya kopyalanır):\n\n",
                               "1) Quit and reopen the Claude app.\n2) Add this to Claude → Settings → Profile preferences so Claude knows when to report (press Yes to copy it):\n\n")
                           + NarratorInstaller.SuggestedInstruction
                           + L("\n\nClaude Code için terminalde bir kere:\n", "\n\nFor Claude Code, run once in a terminal:\n") + cmd;
                if (MessageBox.Show(text, L("Anlatıcı eklendi", "Narrator added"), MessageBoxButton.YesNo) == MessageBoxResult.Yes)
                {
                    try { Clipboard.SetText(NarratorInstaller.SuggestedInstruction); } catch { }
                }
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, L("Anlatıcı eklenemedi", "Couldn't add the narrator"));
        }
        Changed();
    }

    public void ShowClaudeBarHelp()
    {
        var url = $"http://localhost:{(_server.Port > 0 ? _server.Port : AppInfo.DefaultPort)}/claudebar";
        var text = L($"ClaudeBar → Settings → Sync & Alerts → Webhooks → Add Webhook:\n\nURL: {url}\nChannel: JSON\nSends: Quota alerts ve Status alerts\n\nEvet'e basınca URL panoya kopyalanır.",
                     $"ClaudeBar → Settings → Sync & Alerts → Webhooks → Add Webhook:\n\nURL: {url}\nChannel: JSON\nSends: Quota alerts and Status alerts\n\nPress Yes to copy the URL.");
        if (MessageBox.Show(text, "ClaudeBar", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
        {
            try { Clipboard.SetText(url); } catch { }
        }
    }
}

/// <summary>Menüdeki "Dene" örnekleri</summary>
internal static class Demos
{
    private static string Id() => "demo-" + Random.Shared.Next(1000, 9999);

    private static void Play(AppController c, params (double Delay, AgentEvent Event)[] steps)
    {
        foreach (var (delay, e) in steps)
        {
            var ev = e;
            _ = Application.Current.Dispatcher.InvokeAsync(async () =>
            {
                await Task.Delay(TimeSpan.FromSeconds(delay));
                c.Manager.Handle(ev);
            });
        }
    }

    private static AgentEvent E(string source, string session, EventKind kind, RobotState? state = null, string? text = null, string? project = null,
        string? emoji = null, string? lastMessage = null, bool force = false) =>
        new(source, session, kind, state, text, emoji: emoji) { Project = project, LastMessage = lastMessage, ForceNotify = force };

    public static Action Claude(AppController c) => () =>
    {
        var s = Id();
        const string p = "demo-app";
        Play(c,
            (0, E("claude", s, EventKind.Prompt, RobotState.Thinking, L("Düşünüyor…", "Thinking…"), p, "🔮")),
            (2, E("claude", s, EventKind.Tool, RobotState.Reading, L("Okuyor: ", "Reading ") + "App.cs", p, "📖")),
            (5, E("claude", s, EventKind.Tool, RobotState.Editing, L("Düzenliyor: ", "Editing ") + "App.cs", p, "✍️")),
            (8, E("claude", s, EventKind.Tool, RobotState.Running, L("Komut: ", "Command: ") + "dotnet test", p, "🧪")),
            (12, E("claude", s, EventKind.Stop, RobotState.Done, project: p, lastMessage: L("Testler geçti, değişiklik hazır.", "Tests pass, the change is ready."), force: true)));
    };

    public static Action GptWaiting(AppController c) => () =>
    {
        var s = Id();
        const string p = "web-app";
        Play(c,
            (0, E("gpt", s, EventKind.Prompt, RobotState.Thinking, L("Düşünüyor…", "Thinking…"), p, "🔮")),
            (2, E("gpt", s, EventKind.Tool, RobotState.Searching, L("Arıyor: ", "Searching for ") + "useEffect", p, "🔍")),
            (5, E("gpt", s, EventKind.Waiting, RobotState.Waiting, L("Onayını bekliyor: ", "Needs your approval: ") + "PowerShell — npm install", p, "✋")),
            (11, E("gpt", s, EventKind.ToolDone)),
            (12, E("gpt", s, EventKind.Tool, RobotState.Running, L("Komut: ", "Command: ") + "npm install", p, "📦")),
            (15, E("gpt", s, EventKind.Stop, RobotState.Done, project: p)));
    };

    /// <summary>Robottan onayı denemek için: gerçek akışın aynısı, sadece karar Claude Code yerine bu örneğe gider</summary>
    public static Action Approval(AppController c) => () =>
    {
        var s = Id();
        const string p = "demo-app";
        c.Manager.Handle(E("claude", s, EventKind.Prompt, RobotState.Thinking, L("Düşünüyor…", "Thinking…"), p, "🔮"));
        _ = Application.Current.Dispatcher.InvokeAsync(async () =>
        {
            await Task.Delay(1500);
            var e = E("claude", s, EventKind.Waiting, RobotState.Waiting, L("Onayını bekliyor: ", "Needs your approval: ") + "Bash — npm install", p, "✋");
            var pending = new PendingApproval(e,
                """{"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm install"}],"behavior":"allow","destination":"localSettings"}]}""");
            c.Manager.OnPermission(pending);
            var answer = await pending.Result;
            if (string.IsNullOrEmpty(answer)) return;
            if (answer.Contains("\"deny\""))
                Play(c, (2.6, E("claude", s, EventKind.Stop, RobotState.Done, L("Peki, npm install'ı atladım (demo).", "OK, skipped npm install (demo)."), p)));
            else
                Play(c, (2.6, E("claude", s, EventKind.Tool, RobotState.Running, L("Komut: ", "Command: ") + "npm install", p, "📦")),
                        (5.5, E("claude", s, EventKind.Stop, RobotState.Done, project: p)));
        });
    };

    public static AgentEvent Quota() =>
        E("claude", "claudebar", EventKind.Quota, text: L("Kalan kota: %18 (demo)", "Quota left: 18% (demo)"), emoji: "🔋", force: true);

    public static Action Parallel(AppController c) => () =>
    {
        var a = Id();
        var b = Id();
        Play(c,
            (0, E("claude", a, EventKind.Prompt, RobotState.Thinking, L("Düşünüyor…", "Thinking…"), "api", "🔮")),
            (1, E("claude", b, EventKind.Prompt, RobotState.Thinking, L("Düşünüyor…", "Thinking…"), "web", "🔮")),
            (2, E("gpt", b + "g", EventKind.Tool, RobotState.Running, L("Komut: ", "Command: ") + "npm test", "mobile", "🧪")),
            (4, E("claude", a, EventKind.Tool, RobotState.Editing, L("Düzenliyor: ", "Editing ") + "server.ts", "api", "✍️")),
            (6, E("claude", b, EventKind.Waiting, RobotState.Waiting, L("Onayını bekliyor: ", "Needs your approval: ") + "Remove-Item dist", "web", "✋")),
            (12, E("claude", b, EventKind.ToolDone)),
            (13, E("gpt", b + "g", EventKind.Stop, RobotState.Done, project: "mobile")),
            (15, E("claude", a, EventKind.Stop, RobotState.Done, project: "api")),
            (16, E("claude", b, EventKind.Stop, RobotState.Done, project: "web")));
    };
}
