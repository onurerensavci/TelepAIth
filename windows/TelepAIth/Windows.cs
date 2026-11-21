using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using TelepAIth.Core;
using static TelepAIth.Core.Text;

namespace TelepAIth;

/// <summary>Ayarlar penceresinin uygulamadan istedikleri.</summary>
internal interface ISettingsHost
{
    RobotManager Manager { get; }
    void SetHook(HookTarget target, bool on, bool quiet);
    void SetNarrator(bool on);
    void SetShield(bool on);
    void ShowClaudeBarHelp();
    void Changed();
}

/// <summary>Koddan kurulan basit WPF parçaları.</summary>
internal static class Ui
{
    public static TextBlock Title(string s) => new() { Text = s, FontSize = 18, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) };
    public static TextBlock Header(string s) => new() { Text = s, FontSize = 13, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 12, 0, 4) };

    public static TextBlock Para(string s, bool muted = false) => new()
    {
        Text = s, TextWrapping = TextWrapping.Wrap, Margin = new Thickness(0, 2, 0, 6),
        Foreground = muted ? Brushes.Gray : SystemColors.ControlTextBrush,
    };

    public static CheckBox Check(string s, bool value, Action<bool> set)
    {
        var c = new CheckBox { Content = new TextBlock { Text = s, TextWrapping = TextWrapping.Wrap }, IsChecked = value, Margin = new Thickness(0, 4, 0, 4) };
        c.Checked += (_, _) => set(true);
        c.Unchecked += (_, _) => set(false);
        return c;
    }

    public static Button Button(string s, Action act)
    {
        var b = new Button { Content = s, Padding = new Thickness(10, 3, 10, 3), Margin = new Thickness(0, 4, 8, 4), HorizontalAlignment = HorizontalAlignment.Left };
        b.Click += (_, _) => act();
        return b;
    }

    public static StackPanel Row(params UIElement[] items)
    {
        var p = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var i in items) p.Children.Add(i);
        return p;
    }

    public static FrameworkElement Picker<T>(string label, IEnumerable<(T Value, string Text)> options, T current, Action<T> set)
    {
        var list = options.ToList();
        var box = new ComboBox { MinWidth = 150, Margin = new Thickness(8, 0, 0, 0) };
        foreach (var o in list) box.Items.Add(o.Text);
        var idx = list.FindIndex(o => Equals(o.Value, current));
        box.SelectedIndex = idx >= 0 ? idx : 0;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0) set(list[box.SelectedIndex].Value);
        };
        var row = new DockPanel { Margin = new Thickness(0, 4, 0, 4), LastChildFill = false };
        row.Children.Add(new TextBlock { Text = label, VerticalAlignment = VerticalAlignment.Center });
        row.Children.Add(box);
        return row;
    }

    public static TextBlock Status(bool ok, string okText, string badText) => new()
    {
        Text = (ok ? "✔ " : "⚠ ") + (ok ? okText : badText),
        Foreground = ok ? new SolidColorBrush(Color.FromRgb(0x2E, 0x9E, 0x5B)) : new SolidColorBrush(Color.FromRgb(0xD9, 0x7A, 0x1E)),
        FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 4, 0, 4),
    };

    public static ScrollViewer Page(params UIElement[] items)
    {
        var p = new StackPanel { Margin = new Thickness(16) };
        foreach (var i in items) p.Children.Add(i);
        return new ScrollViewer { Content = p, VerticalScrollBarVisibility = ScrollBarVisibility.Auto };
    }

    public static Window Window(string title, double w, double h) => new()
    {
        Title = AppInfo.Name + " — " + title, Width = w, Height = h, WindowStartupLocation = WindowStartupLocation.CenterScreen,
        FontFamily = new FontFamily("Segoe UI"), FontSize = 12.5, ShowInTaskbar = true,
        Icon = AppIcon.Image,
    };

    public static void Bring(Window w)
    {
        if (!w.IsVisible) w.Show();
        if (w.WindowState == WindowState.Minimized) w.WindowState = WindowState.Normal;
        w.Activate();
        w.Topmost = true;
        w.Topmost = false;
    }
}

internal static class AppIcon
{
    private static System.Windows.Media.Imaging.BitmapFrame? _image;

    public static System.Windows.Media.Imaging.BitmapFrame? Image
    {
        get
        {
            if (_image != null) return _image;
            try
            {
                using var s = typeof(AppIcon).Assembly.GetManifestResourceStream("AppIcon.ico");
                if (s != null) _image = System.Windows.Media.Imaging.BitmapFrame.Create(s, System.Windows.Media.Imaging.BitmapCreateOptions.None, System.Windows.Media.Imaging.BitmapCacheOption.OnLoad);
            }
            catch { }
            return _image;
        }
    }

    public static System.Drawing.Icon TrayIcon()
    {
        try
        {
            using var s = typeof(AppIcon).Assembly.GetManifestResourceStream("AppIcon.ico");
            if (s != null) return new System.Drawing.Icon(s, System.Windows.Forms.SystemInformation.SmallIconSize);
        }
        catch { }
        return System.Drawing.SystemIcons.Application;
    }
}

/// <summary>Ayarlar: Genel · Bildirimler · Odak ve özet · Bağlantılar</summary>
internal sealed class SettingsWindow
{
    private static Window? _window;
    private static TabControl? _tabs;

    public static void Show(ISettingsHost host)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Ayarlar", "Settings"), 560, 600);
            _window.Closed += (_, _) => { _window = null; _tabs = null; };
        }
        Rebuild(host);
        Ui.Bring(_window);
    }

    /// <summary>Durum değişince (izin, bağlantı) açık pencereyi tazele.</summary>
    public static void Refresh(ISettingsHost host)
    {
        if (_window != null) Rebuild(host);
    }

    private static void Rebuild(ISettingsHost host)
    {
        var selected = _tabs?.SelectedIndex ?? 0;
        _tabs = new TabControl { Margin = new Thickness(8) };
        _tabs.Items.Add(new TabItem { Header = L("Genel", "General"), Content = General(host) });
        _tabs.Items.Add(new TabItem { Header = L("Bildirimler", "Notifications"), Content = Notifications(host) });
        _tabs.Items.Add(new TabItem { Header = L("Odak ve özet", "Focus & summary"), Content = Focus(host) });
        _tabs.Items.Add(new TabItem { Header = L("Bağlantılar", "Connections"), Content = Connections(host) });
        _tabs.SelectedIndex = selected;
        _window!.Content = _tabs;
        _window.Title = AppInfo.Name + " — " + L("Ayarlar", "Settings");
    }

    private static UIElement General(ISettingsHost host)
    {
        var m = host.Manager;
        return Ui.Page(
            Ui.Picker(L("Dil", "Language"), new[] { (Language.Tr, "Türkçe"), (Language.En, "English") }, Lang.Current, v =>
            {
                Lang.Set(v);
                host.Changed();
                Application.Current.Dispatcher.BeginInvoke(() => Refresh(host));
            }),
            Ui.Picker(L("Robot boyutu", "Robot size"), new[] { (0.75, L("Küçük (%75)", "Small (75%)")), (1.0, L("Normal (%100)", "Normal (100%)")), (1.3, L("Büyük (%130)", "Large (130%)")), (1.6, L("Çok büyük (%160)", "Extra large (160%)")) },
                new[] { 0.75, 1.0, 1.3, 1.6 }.OrderBy(v => Math.Abs(v - Prefs.RobotScale)).First(), v => m.SetRobotScale(v)),
            Ui.Check(L("Robotu göster", "Show the robot"), m.Visible, v => m.Visible = v),
            Ui.Check(L("Her zaman üstte", "Always on top"), Prefs.AlwaysOnTop, v => m.SetAlwaysOnTop(v)),
            Ui.Check(L("Kilitli (yerinde kalsın, AI pencerelerine gitmesin)", "Locked (stay put, don't follow AI windows)"), Prefs.RobotLocked, v => m.SetLocked(v)),
            Ui.Check(L("Claude/ChatGPT'ye geçince o pencerenin köşesine gitsin", "Fly to the Claude/ChatGPT window corner"), Prefs.FollowAppWindow, v =>
            {
                Prefs.FollowAppWindow = v;
                m.FollowSettingChanged();
            }),
            Ui.Check(L("Aynı anda çalışan oturumları minik kafalarla göster", "Show other running sessions as mini heads"), Prefs.MiniHeads, v => Prefs.MiniHeads = v),
            Ui.Check(L("Eyleme göre emojiler", "Emojis for each action"), Prefs.EmojiEnabled, v => Prefs.EmojiEnabled = v),
            Ui.Check(L("Boştayken ara sıra laf atsın", "Idle chatter"), Prefs.IdleChatter, v => Prefs.IdleChatter = v),
            Ui.Check(L("Kısa sesler", "Short sounds"), Prefs.Sounds, v => Prefs.Sounds = v),
            Ui.Check(L("Önemli anları sesli söylesin", "Say important moments out loud"), Prefs.Speak, v =>
            {
                Prefs.Speak = v;
                if (v) Speech.Say(L("Merhaba, ben TelepAIth.", "Hi, I'm TelepAIth."));
            }),
            Ui.Check(L("Windows açılınca başlasın", "Start with Windows"), Installer.AutostartEnabled, v => Installer.SetAutostart(v)),
            Ui.Para(L($"Sürüm {AppInfo.Version} · deneysel Windows sürümü", $"Version {AppInfo.Version} · experimental Windows build"), true));
    }

    private static UIElement Notifications(ISettingsHost host)
    {
        var off = Notifier.SystemDisabled;
        return Ui.Page(
            Ui.Header(L("Windows bildirimleri", "Windows notifications")),
            Ui.Status(!off, L("Windows'ta bildirimler açık", "Notifications are on in Windows"),
                L("Windows'ta bildirimler kapalı: Ayarlar → Sistem → Bildirimler", "Notifications are off in Windows: Settings → System → Notifications")),
            Ui.Row(Ui.Button(L("Windows ayarlarını aç", "Open Windows settings"), Notifier.OpenSystemSettings),
                Ui.Button(L("Test bildirimi gönder", "Send a test notification"), SendTest)),
            Ui.Header(L("Ne zaman", "When")),
            Ui.Check(L("Bildirimler", "Notifications"), Prefs.NotificationsEnabled, v => { Prefs.NotificationsEnabled = v; host.Changed(); }),
            Ui.Check(L("O uygulamaya bakarken de bildir", "Notify even while I'm looking at that app"), Prefs.NotifyWhenFrontmost, v => Prefs.NotifyWhenFrontmost = v),
            Ui.Check(L("Uzun süre onay beklerse ısrar etsin (sallansın, 2 dk sonra hatırlatsın)", "Nag if it waits for approval for long (wiggle, remind after 2 min)"),
                Prefs.WaitReminders, v => Prefs.WaitReminders = v),
            Ui.Picker(L("\"Bitti\" bildirimi için en az", "\"Done\" notification after at least"),
                new[] { 0, 10, 20, 60, 180 }.Select(s => ((double)s, s == 0 ? L("her zaman", "always") : FormatDuration(s))),
                new[] { 0.0, 10, 20, 60, 180 }.OrderBy(v => Math.Abs(v - Prefs.LongTurnSeconds)).First(), v => Prefs.LongTurnSeconds = v),
            Ui.Para(L("Bildirime ya da robotun balonuna tıklayınca o işin penceresine (Claude, ChatGPT ya da terminal) gidersin.",
                "Click a notification or the robot's bubble to jump to that task's window (Claude, ChatGPT or the terminal)."), true));
    }

    public static void SendTest() =>
        Notifier.Notify("🔔 " + L("TelepAIth test bildirimi", "TelepAIth test notification"),
            L("Bunu görüyorsan bildirimler çalışıyor.", "If you can see this, notifications work."));

    private static UIElement Focus(ISettingsHost host)
    {
        var m = host.Manager;
        void After()
        {
            m.FocusChanged();
            host.Changed();
            Refresh(host);
        }
        return Ui.Page(
            Ui.Header(L("Odak modu", "Focus mode")),
            Ui.Para(FocusMode.StatusText),
            Ui.Row(Ui.Button(L("1 saat", "1 hour"), () => { FocusMode.TurnOn(3600); After(); }),
                Ui.Button(L("Kapatana kadar", "Until I turn it off"), () => { FocusMode.TurnOn(null); After(); }),
                Ui.Button(L("Kapat", "Turn off"), () => { FocusMode.TurnOff(); After(); })),
            Ui.Check(L("Toplantıdayken kendiliğinden aç (Zoom/Teams öndeyken ya da mikrofon kullanımdayken)",
                    "Turn on automatically in meetings (Zoom/Teams in front, or the microphone in use)"),
                Prefs.AutoFocusInMeetings, v => { Prefs.AutoFocusInMeetings = v; After(); }),
            Ui.Para(L("Odak modunda robot soluk durur ve susar; sadece seni bekleyen şeyleri ve hataları söyler.",
                "In focus mode the robot dims and stays quiet; it only tells you what needs you and errors."), true),
            Ui.Header(L("Günün özeti", "Daily summary")),
            Ui.Check(L("Akşam günün özetini söylesin", "Tell me a summary of the day in the evening"), Prefs.DailySummary, v => Prefs.DailySummary = v),
            Ui.Picker(L("Saat", "Time"), Enumerable.Range(15, 8).Select(h => (h, $"{h:00}:00")), Prefs.DailySummaryHour, v => Prefs.DailySummaryHour = v),
            Ui.Button(L("Bugünün özetini şimdi göster", "Show today's summary now"), m.ShowSummary));
    }

    private static UIElement Connections(ISettingsHost host)
    {
        var m = host.Manager;
        var items = new List<UIElement>
        {
            Ui.Header(L("Masaüstü uygulamaları", "Desktop apps")),
            Ui.Check(L("Claude ve ChatGPT uygulamalarını izle", "Watch the Claude and ChatGPT apps"), Prefs.WatchApps, v => { m.SetWatchApps(v); host.Changed(); }),
        };
        if (Prefs.WatchApps)
        {
            if (m.WatcherStatus.Count == 0) items.Add(Ui.Para(L("Claude ya da ChatGPT açık değil.", "Claude or ChatGPT isn't open."), true));
            foreach (var (name, status) in m.WatcherStatus) items.Add(Ui.Para($"• {name}: {status}"));
            items.Add(Ui.Para(L("Windows'ta ayrı bir izin gerekmez. Ekrandan okuduklarım bilgisayarından çıkmaz.",
                "No extra permission is needed on Windows. Nothing I read from the screen leaves your PC."), true));
        }
        items.Add(Ui.Header(L("Kodlama ajanları", "Coding agents")));
        foreach (var t in new[] { HookTarget.Claude, HookTarget.Codex })
        {
            var target = t;
            items.Add(Ui.Check(HookInstaller.DisplayName(target), HookInstaller.IsInstalled(target), v => host.SetHook(target, v, false)));
        }
        items.Add(Ui.Check(L("Kalkan: tehlikeli komutlarda onay iste", "Shield: ask before risky commands"), Prefs.Shield, v => host.SetShield(v)));
        items.Add(Ui.Header(L("Ekstralar", "Extras")));
        items.Add(Ui.Check(L("Anlatıcı (Claude ne yaptığını kendisi söylesin)", "Narrator (Claude tells it in its own words)"), NarratorInstaller.IsInstalled(), v => host.SetNarrator(v)));
        items.Add(Ui.Row(new TextBlock { Text = L("ClaudeBar kota uyarıları", "ClaudeBar quota alerts"), VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 10, 0) },
            Ui.Button(L("Nasıl bağlanır?", "How to connect"), host.ShowClaudeBarHelp)));
        return Ui.Page(items.ToArray());
    }
}

/// <summary>İlk açılış sihirbazı: hoş geldin → bildirimler → uygulamalar → kodlama ajanları → hazır.</summary>
internal static class OnboardingWindow
{
    private static Window? _window;
    private static int _step;

    public static void Show(ISettingsHost host)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Kurulum", "Setup"), 520, 460);
            _window.ResizeMode = ResizeMode.NoResize;
            _window.Closed += (_, _) =>
            {
                _window = null;
                Prefs.OnboardingDone = true;
            };
            _step = 0;
        }
        Render(host);
        Ui.Bring(_window);
    }

    private static void Render(ISettingsHost host)
    {
        const int last = 4;
        var content = _step switch
        {
            0 => Ui.Page(
                Ui.Title(L("TelepAIth'e hoş geldin", "Welcome to TelepAIth")),
                Ui.Para(L("Claude ve GPT o an ne yapıyorsa ekranının köşesindeki robot söyler.",
                    "A little robot in your screen corner tells you what Claude and GPT are doing.")),
                Ui.Para(L("Birkaç adımda bildirimleri ve bağlantıları kuralım. Hepsini sonra Ayarlar'dan değiştirebilirsin.",
                    "Let's set up notifications and connections in a few steps. You can change all of it later in Settings.")),
                Ui.Para(L("Not: Bu, Windows'un ilk deneme sürümü. Bir şey ters giderse robota sağ tıkla → Hata bildir.",
                    "Note: this is the first trial build for Windows. If something goes wrong, right-click the robot → Report a problem."), true)),
            1 => Ui.Page(
                Ui.Title(L("Bildirimler", "Notifications")),
                Ui.Para(L("Uzun bir iş bitince ya da AI senden onay beklerken haber vereyim.",
                    "I'll let you know when a long task finishes or the AI needs your approval.")),
                Ui.Status(!Notifier.SystemDisabled, L("Windows'ta bildirimler açık", "Notifications are on in Windows"), L("Windows'ta bildirimler kapalı", "Notifications are off in Windows")),
                Ui.Row(Ui.Button(L("Test bildirimi gönder", "Send a test"), SettingsWindow.SendTest),
                    Ui.Button(L("Windows ayarlarını aç", "Open Windows settings"), Notifier.OpenSystemSettings)),
                Ui.Check(L("Bildirimler", "Notifications"), Prefs.NotificationsEnabled, v => Prefs.NotificationsEnabled = v)),
            2 => Ui.Page(
                Ui.Title(L("Claude ve ChatGPT uygulamaları", "The Claude and ChatGPT apps")),
                Ui.Para(L("Masaüstü uygulamalarının ne zaman çalıştığını, onay beklediğini ve bitirdiğini Windows'un erişilebilirlik arayüzüyle görürüm. Ekrandan okuduklarım hiçbir yere gönderilmez.",
                    "I use Windows' accessibility interface to see when the desktop apps are working, waiting or done. Nothing I read from the screen leaves your PC.")),
                Ui.Check(L("Claude ve ChatGPT uygulamalarını izle", "Watch the Claude and ChatGPT apps"), Prefs.WatchApps, v => host.Manager.SetWatchApps(v))),
            3 => Ui.Page(
                Ui.Title(L("Kodlama ajanları", "Coding agents")),
                Ui.Para(L("Terminalde Claude Code ya da Codex kullanıyorsan bağla; her adımı anında görürüm.",
                    "If you use Claude Code or Codex in a terminal, connect them; I'll see every step instantly.")),
                Ui.Check("Claude Code", HookInstaller.IsInstalled(HookTarget.Claude), v => host.SetHook(HookTarget.Claude, v, true)),
                Ui.Check("Codex", HookInstaller.IsInstalled(HookTarget.Codex), v => host.SetHook(HookTarget.Codex, v, true)),
                Ui.Para(L("Yeni açacağın oturumlar bağlanır. Codex'te bir kere /hooks yazıp onaylaman gerekir.",
                    "New sessions will connect. In Codex, type /hooks once and approve."), true)),
            _ => Ui.Page(
                Ui.Title(L("Hazırız 🎉", "All set 🎉")),
                Ui.Para("• " + L("Robotu sürükleyip bir köşeye bırak, oraya yapışır.", "Drag the robot near a corner and it snaps there.")),
                Ui.Para("• " + L("Balona tıkla: o işin penceresine gidersin.", "Click the bubble to jump to that task's window.")),
                Ui.Para("• " + L("Robota tıkla: son olaylar. Çift tıkla: AI uygulamasını aç.", "Click the robot for recent events. Double-click to open the AI app.")),
                Ui.Para("• " + L("Sağ tık: kilit, her zaman üstte, odak modu, günün özeti.", "Right-click: lock, always on top, focus mode, today's summary.")),
                Ui.Para("• " + L("Görev çubuğunun sağındaki robot simgesi → Ayarlar.", "The robot icon in the taskbar tray → Settings."))),
        };

        var buttons = new StackPanel { Orientation = Orientation.Horizontal, HorizontalAlignment = HorizontalAlignment.Right, Margin = new Thickness(16, 0, 16, 14) };
        if (_step > 0) buttons.Children.Add(Ui.Button(L("Geri", "Back"), () => { _step--; Render(host); }));
        if (_step < last)
            buttons.Children.Add(Ui.Button(_step == 0 ? L("Başlayalım", "Let's go") : L("İleri", "Next"), () => { _step++; Render(host); }));
        else
            buttons.Children.Add(Ui.Button(L("Bitir", "Finish"), () =>
            {
                Prefs.OnboardingDone = true;
                _window?.Close();
            }));

        var root = new DockPanel();
        DockPanel.SetDock(buttons, Dock.Bottom);
        root.Children.Add(buttons);
        root.Children.Add(content);
        _window!.Content = root;
    }
}

/// <summary>Teşhis: robot ne görüyor? (genel durum + izlenen uygulamalar)</summary>
internal static class DiagnosticsWindow
{
    private static Window? _window;
    private static System.Windows.Threading.DispatcherTimer? _timer;

    public static void Show(Func<string> report)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Teşhis", "Diagnostics"), 680, 540);
            var box = new TextBox
            {
                IsReadOnly = true, FontFamily = new FontFamily("Consolas"), FontSize = 11.5, TextWrapping = TextWrapping.Wrap,
                VerticalScrollBarVisibility = ScrollBarVisibility.Auto, Margin = new Thickness(12, 0, 12, 12), BorderThickness = new Thickness(0),
            };
            var top = new DockPanel { Margin = new Thickness(12, 10, 12, 8) };
            var copy = Ui.Button(L("Panoya kopyala", "Copy to clipboard"), () => { try { Clipboard.SetText(report()); } catch { } });
            DockPanel.SetDock(copy, Dock.Right);
            top.Children.Add(copy);
            top.Children.Add(new TextBlock { Text = L("Robot ne görüyor?", "What does the robot see?"), FontSize = 14, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });
            var root = new DockPanel();
            DockPanel.SetDock(top, Dock.Top);
            root.Children.Add(top);
            root.Children.Add(box);
            _window.Content = root;
            void Update() => box.Text = report();
            Update();
            _timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromSeconds(1.5) };
            _timer.Tick += (_, _) => Update();
            _timer.Start();
            _window.Closed += (_, _) =>
            {
                _timer?.Stop();
                _timer = null;
                _window = null;
            };
        }
        Ui.Bring(_window);
    }
}
