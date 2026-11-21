using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
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

/// <summary>Koddan kurulan Windows 11 tarzı parçalar (kartlar, anahtar düğmeler, başlıklar).</summary>
internal static class Ui
{
    public static T Themed<T>(T e, string? fg = null, string? bg = null) where T : FrameworkElement
    {
        if (fg != null) e.SetResourceReference(TextElement.ForegroundProperty, fg);
        if (bg != null)
        {
            switch (e)
            {
                case Border b: b.SetResourceReference(Border.BackgroundProperty, bg); break;
                case Panel p: p.SetResourceReference(Panel.BackgroundProperty, bg); break;
                case Control c: c.SetResourceReference(Control.BackgroundProperty, bg); break;
            }
        }
        return e;
    }

    public static TextBlock Glyph(string code, double size = 16, string brush = "Text") =>
        Themed(new TextBlock { Text = code, FontFamily = new FontFamily(Theme.Icons), FontSize = size, VerticalAlignment = VerticalAlignment.Center }, brush);

    public static TextBlock PageTitle(string s) =>
        new TextBlock { FontFamily = new FontFamily(Theme.DisplayFont), FontSize = 26, FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 14) }.WithText(s);

    public static TextBlock Section(string s) =>
        new TextBlock { FontSize = 14, FontWeight = FontWeights.SemiBold, Margin = new Thickness(2, 18, 0, 6) }.WithText(s);

    public static TextBlock Para(string s, bool muted = false, double size = 13)
    {
        var t = new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = size, Margin = new Thickness(2, 2, 0, 8), LineHeight = size * 1.45 }.WithText(s);
        return muted ? Themed(t, "SubText") : t;
    }

    /// <summary>Yazıyı renkli emojilerle birlikte yerleştirir.</summary>
    public static TextBlock WithText(this TextBlock t, string s)
    {
        Emoji.Fill(t, s);
        return t;
    }

    /// <summary>Kart: solda başlık + açıklama, sağda denetim.</summary>
    public static Border Card(string title, string? desc, UIElement? control, string? glyph = null, Action? onClick = null)
    {
        var dock = new DockPanel { LastChildFill = true };
        if (control != null)
        {
            DockPanel.SetDock(control, Dock.Right);
            if (control is FrameworkElement fe) fe.VerticalAlignment = VerticalAlignment.Center;
            dock.Children.Add(control);
        }
        if (glyph != null)
        {
            var g = Glyph(glyph, 18);
            g.Margin = new Thickness(0, 0, 16, 0);
            DockPanel.SetDock(g, Dock.Left);
            dock.Children.Add(g);
        }
        var texts = new StackPanel { VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(0, 0, 16, 0) };
        texts.Children.Add(new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 13.5 }.WithText(title));
        if (!string.IsNullOrEmpty(desc))
            texts.Children.Add(Themed(new TextBlock { TextWrapping = TextWrapping.Wrap, FontSize = 12, Margin = new Thickness(0, 2, 0, 0) }.WithText(desc), "SubText"));
        dock.Children.Add(texts);
        var card = Themed(new Border
        {
            CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1), Padding = new Thickness(16, 12, 16, 12),
            Margin = new Thickness(0, 0, 0, 4), MinHeight = 64, Child = dock,
        }, bg: "Card");
        card.SetResourceReference(Border.BorderBrushProperty, "CardBorder");
        if (onClick != null)
        {
            card.Cursor = Cursors.Hand;
            card.MouseLeftButtonUp += (_, e) =>
            {
                if (e.OriginalSource is DependencyObject d && IsInside<ButtonBase>(d)) return;
                onClick();
            };
        }
        return card;
    }

    private static bool IsInside<T>(DependencyObject d) where T : DependencyObject
    {
        for (var x = d; x != null; x = x is Visual || x is System.Windows.Media.Media3D.Visual3D ? VisualTreeHelper.GetParent(x) : LogicalTreeHelper.GetParent(x))
            if (x is T) return true;
        return false;
    }

    public static Border SwitchCard(string title, string? desc, bool value, Action<bool> set, string? glyph = null)
    {
        var sw = new CheckBox { IsChecked = value };
        sw.SetResourceReference(FrameworkElement.StyleProperty, "Switch");
        sw.Checked += (_, _) => set(true);
        sw.Unchecked += (_, _) => set(false);
        var label = new TextBlock { Margin = new Thickness(0, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center };
        label.SetResourceReference(TextElement.ForegroundProperty, "SubText");
        void Sync() => label.Text = sw.IsChecked == true ? L("Açık", "On") : L("Kapalı", "Off");
        Sync();
        sw.Checked += (_, _) => Sync();
        sw.Unchecked += (_, _) => Sync();
        var right = new StackPanel { Orientation = Orientation.Horizontal };
        right.Children.Add(label);
        right.Children.Add(sw);
        return Card(title, desc, right, glyph, () => sw.IsChecked = sw.IsChecked != true);
    }

    public static Border PickerCard<T>(string title, string? desc, IEnumerable<(T Value, string Text)> options, T current, Action<T> set, string? glyph = null)
    {
        var list = options.ToList();
        var box = new ComboBox();
        foreach (var o in list) box.Items.Add(new ComboBoxItem { Content = o.Text });
        var idx = list.FindIndex(o => Equals(o.Value, current));
        box.SelectedIndex = idx >= 0 ? idx : 0;
        box.SelectionChanged += (_, _) =>
        {
            if (box.SelectedIndex >= 0) set(list[box.SelectedIndex].Value);
        };
        return Card(title, desc, box, glyph);
    }

    public static Button Button(string s, Action act, bool primary = false)
    {
        var b = new Button { Content = s, Margin = new Thickness(8, 0, 0, 0) };
        if (primary) b.SetResourceReference(FrameworkElement.StyleProperty, "Primary");
        b.Click += (_, _) => act();
        return b;
    }

    public static StackPanel Row(params UIElement[] items)
    {
        var p = new StackPanel { Orientation = Orientation.Horizontal };
        foreach (var i in items) p.Children.Add(i);
        return p;
    }

    /// <summary>Durum kartı: yeşil tik ya da turuncu uyarı.</summary>
    public static Border StatusCard(bool ok, string okText, string badText, UIElement? control = null) =>
        Card(ok ? okText : badText, null, control, ok ? "" : "").Also(c =>
        {
            if (((DockPanel)c.Child).Children.OfType<TextBlock>().FirstOrDefault(t => t.FontFamily.Source == Theme.Icons) is { } g)
                g.SetResourceReference(TextElement.ForegroundProperty, ok ? "Good" : "Warn");
        });

    public static T Also<T>(this T x, Action<T> a)
    {
        a(x);
        return x;
    }

    public static ScrollViewer Page(params UIElement[] items)
    {
        var p = new StackPanel { Margin = new Thickness(28, 24, 28, 28), MaxWidth = 760 };
        foreach (var i in items) p.Children.Add(i);
        return new ScrollViewer { Content = p, VerticalScrollBarVisibility = ScrollBarVisibility.Auto, HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled };
    }

    public static Window Window(string title, double w, double h)
    {
        var win = new Window
        {
            Title = AppInfo.Name + " — " + title, Width = w, Height = h, MinWidth = 520, MinHeight = 420,
            WindowStartupLocation = WindowStartupLocation.CenterScreen, ShowInTaskbar = true, Icon = AppIcon.Image,
        };
        Theme.Style(win);
        return win;
    }

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

/// <summary>Ayarlar: solda kenar çubuğu (Genel · Bildirimler · Odak ve özet · Bağlantılar), sağda kartlar.</summary>
internal static class SettingsWindow
{
    private static Window? _window;
    private static int _page;

    public static void Show(ISettingsHost host, int? page = null)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Ayarlar", "Settings"), 860, 640);
            _window.Closed += (_, _) => _window = null;
        }
        if (page is { } p) _page = p;
        Rebuild(host);
        Ui.Bring(_window);
    }

    /// <summary>Durum değişince (dil, bağlantı) açık pencereyi tazele.</summary>
    public static void Refresh(ISettingsHost host)
    {
        if (_window != null) Rebuild(host);
    }

    public static void Close() => _window?.Close();

    private static readonly (string Glyph, Func<string> Title)[] Pages =
    {
        ("", () => L("Genel", "General")),
        ("", () => L("Bildirimler", "Notifications")),
        ("", () => L("Odak ve özet", "Focus & summary")),
        ("", () => L("Bağlantılar", "Connections")),
    };

    private static void Rebuild(ISettingsHost host)
    {
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(250) });
        root.ColumnDefinitions.Add(new ColumnDefinition());

        // Kenar çubuğu
        var side = Ui.Themed(new DockPanel(), bg: "Side");
        var brand = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(20, 22, 16, 18) };
        if (AppIcon.Image != null) brand.Children.Add(new Image { Source = AppIcon.Image, Width = 36, Height = 36, Margin = new Thickness(0, 0, 12, 0) });
        var names = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        names.Children.Add(new TextBlock { Text = "TelepAIth", FontSize = 15, FontWeight = FontWeights.SemiBold });
        names.Children.Add(Ui.Themed(new TextBlock { Text = $"{AppInfo.Version} · Windows " + L("(deneysel)", "(experimental)"), FontSize = 11.5 }, "SubText"));
        brand.Children.Add(names);
        DockPanel.SetDock(brand, Dock.Top);
        side.Children.Add(brand);

        var nav = new ListBox { Margin = new Thickness(10, 0, 10, 10) };
        nav.SetResourceReference(FrameworkElement.StyleProperty, "Nav");
        nav.ItemContainerStyle = (Style)Application.Current.FindResource("NavItem");
        foreach (var (glyph, title) in Pages)
        {
            var item = new StackPanel { Orientation = Orientation.Horizontal };
            item.Children.Add(Ui.Glyph(glyph, 16).Also(g => g.Margin = new Thickness(0, 0, 14, 0)));
            item.Children.Add(new TextBlock { Text = title(), FontSize = 13.5, VerticalAlignment = VerticalAlignment.Center });
            nav.Items.Add(item);
        }
        nav.SelectedIndex = _page;
        side.Children.Add(nav);
        root.Children.Add(side);

        var content = new ContentControl();
        Grid.SetColumn(content, 1);
        root.Children.Add(content);

        void ShowPage(int i)
        {
            _page = i;
            content.Content = i switch
            {
                1 => Notifications(host),
                2 => Focus(host),
                3 => Connections(host),
                _ => General(host),
            };
        }
        nav.SelectionChanged += (_, _) => { if (nav.SelectedIndex >= 0) ShowPage(nav.SelectedIndex); };
        ShowPage(_page);

        _window!.Content = root;
        _window.Title = AppInfo.Name + " — " + L("Ayarlar", "Settings");
    }

    private static UIElement General(ISettingsHost host)
    {
        var m = host.Manager;
        return Ui.Page(
            Ui.PageTitle(L("Genel", "General")),
            Ui.Section(L("Görünüm", "Appearance")),
            Ui.PickerCard(L("Dil", "Language"), null, new[] { (Language.Tr, "Türkçe"), (Language.En, "English") }, Lang.Current, v =>
            {
                Lang.Set(v);
                host.Changed();
                Application.Current.Dispatcher.BeginInvoke(() => Refresh(host));
            }, ""),
            Ui.PickerCard(L("Robot boyutu", "Robot size"), L("Robot ve balonu bu oranda büyür", "Scales the robot and its bubble"),
                new[] { (0.75, L("Küçük (%75)", "Small (75%)")), (1.0, L("Normal (%100)", "Normal (100%)")), (1.3, L("Büyük (%130)", "Large (130%)")), (1.6, L("Çok büyük (%160)", "Extra large (160%)")) },
                new[] { 0.75, 1.0, 1.3, 1.6 }.OrderBy(v => Math.Abs(v - Prefs.RobotScale)).First(), v => m.SetRobotScale(v), ""),
            Ui.SwitchCard(L("Robotu göster", "Show the robot"), null, m.Visible, v => m.Visible = v, ""),
            Ui.SwitchCard(L("Her zaman üstte", "Always on top"), L("Diğer pencereler robotu örtmesin", "Other windows won't cover the robot"), Prefs.AlwaysOnTop, v => m.SetAlwaysOnTop(v), ""),
            Ui.SwitchCard(L("Kilitli", "Locked"), L("Yerinde kalsın, AI pencerelerine gitmesin", "Stay put, don't follow AI windows"), Prefs.RobotLocked, v => m.SetLocked(v), ""),
            Ui.SwitchCard(L("Pencereye uç", "Fly to the window"), L("Claude/ChatGPT'ye geçince o pencerenin köşesine gitsin", "Move to the Claude/ChatGPT window corner when you switch to it"),
                Prefs.FollowAppWindow, v => { Prefs.FollowAppWindow = v; m.FollowSettingChanged(); }, ""),
            Ui.SwitchCard(L("Minik kafalar", "Mini heads"), L("Aynı anda çalışan diğer oturumları robotun yanında göster", "Show other running sessions next to the robot"), Prefs.MiniHeads, v => Prefs.MiniHeads = v, ""),
            Ui.Section(L("Davranış", "Behaviour")),
            Ui.SwitchCard(L("Eyleme göre emojiler", "Emojis for each action"), null, Prefs.EmojiEnabled, v => Prefs.EmojiEnabled = v, ""),
            Ui.SwitchCard(L("Boştayken laf atsın", "Idle chatter"), L("Arada bir küçük şeyler söyler", "Says little things now and then"), Prefs.IdleChatter, v => Prefs.IdleChatter = v, ""),
            Ui.SwitchCard(L("Kısa sesler", "Short sounds"), null, Prefs.Sounds, v => Prefs.Sounds = v, ""),
            Ui.SwitchCard(L("Sesli söylesin", "Speak out loud"), L("Önemli anları Windows'un sesiyle okur", "Reads important moments with the Windows voice"), Prefs.Speak, v =>
            {
                Prefs.Speak = v;
                if (v) Speech.Say(L("Merhaba, ben TelepAIth.", "Hi, I'm TelepAIth."));
            }, ""),
            Ui.SwitchCard(L("Windows açılınca başlasın", "Start with Windows"), null, Installer.AutostartEnabled, v => Installer.SetAutostart(v), ""));
    }

    private static UIElement Notifications(ISettingsHost host)
    {
        var off = Notifier.SystemDisabled;
        return Ui.Page(
            Ui.PageTitle(L("Bildirimler", "Notifications")),
            Ui.StatusCard(!off, L("Windows'ta bildirimler açık", "Notifications are on in Windows"),
                L("Windows'ta bildirimler kapalı: Ayarlar → Sistem → Bildirimler", "Notifications are off in Windows: Settings → System → Notifications"),
                Ui.Row(Ui.Button(L("Windows ayarları", "Windows settings"), Notifier.OpenSystemSettings), Ui.Button(L("Test gönder", "Send a test"), SendTest))),
            Ui.Section(L("Ne zaman", "When")),
            Ui.SwitchCard(L("Bildirimler", "Notifications"), L("İş bitince ya da AI seni beklerken haber ver", "Tell me when a task finishes or the AI needs me"),
                Prefs.NotificationsEnabled, v => { Prefs.NotificationsEnabled = v; host.Changed(); }, ""),
            Ui.SwitchCard(L("O uygulamaya bakarken de bildir", "Notify while I'm looking at that app"), null, Prefs.NotifyWhenFrontmost, v => Prefs.NotifyWhenFrontmost = v, ""),
            Ui.SwitchCard(L("Israr etsin", "Nag me"), L("Uzun süre onay beklerse sallansın, 2 dakika sonra yeniden hatırlatsın", "Wiggle when it waits long, remind again after 2 minutes"),
                Prefs.WaitReminders, v => Prefs.WaitReminders = v, ""),
            Ui.PickerCard(L("\"Bitti\" bildirimi", "\"Done\" notification"), L("Bundan kısa süren işler için bildirim atmaz", "Shorter tasks don't notify"),
                new[] { 0, 10, 20, 60, 180 }.Select(s => ((double)s, s == 0 ? L("her zaman", "always") : L("en az ", "at least ") + FormatDuration(s))),
                new[] { 0.0, 10, 20, 60, 180 }.OrderBy(v => Math.Abs(v - Prefs.LongTurnSeconds)).First(), v => Prefs.LongTurnSeconds = v, ""),
            Ui.Para(L("Bildirime ya da robotun balonuna tıklayınca o işin penceresine (Claude, ChatGPT ya da terminal) gidersin.",
                "Click a notification or the robot's bubble to jump to that task's window (Claude, ChatGPT or the terminal)."), true, 12));
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
        var buttons = FocusMode.ManualActive
            ? Ui.Row(Ui.Button(L("Kapat", "Turn off"), () => { FocusMode.TurnOff(); After(); }))
            : Ui.Row(Ui.Button(L("1 saat", "1 hour"), () => { FocusMode.TurnOn(3600); After(); }, true),
                     Ui.Button(L("Kapatana kadar", "Until I turn it off"), () => { FocusMode.TurnOn(null); After(); }));
        return Ui.Page(
            Ui.PageTitle(L("Odak ve özet", "Focus & summary")),
            Ui.Card(L("Odak modu", "Focus mode"), FocusMode.StatusText, buttons, ""),
            Ui.SwitchCard(L("Toplantıda kendiliğinden aç", "Automatically in meetings"), L("Zoom/Teams öndeyken ya da mikrofon kullanımdayken", "When Zoom/Teams is in front or the microphone is in use"),
                Prefs.AutoFocusInMeetings, v => { Prefs.AutoFocusInMeetings = v; After(); }, ""),
            Ui.Para(L("Odak modunda robot soluk durur ve susar; sadece seni bekleyen şeyleri ve hataları söyler.",
                "In focus mode the robot dims and stays quiet; it only tells you what needs you and errors."), true, 12),
            Ui.Section(L("Günün özeti", "Daily summary")),
            Ui.SwitchCard(L("Akşam günün özetini söylesin", "Evening summary"), L("Kaç iş bitti, ne kadar sürdü, kaç kez seni bekledi", "How many tasks, how long, how often it waited for you"),
                Prefs.DailySummary, v => Prefs.DailySummary = v, ""),
            Ui.PickerCard(L("Saat", "Time"), null, Enumerable.Range(15, 8).Select(h => (h, $"{h:00}:00")), Prefs.DailySummaryHour, v => Prefs.DailySummaryHour = v, ""),
            Ui.Card(L("Bugünün özeti", "Today's summary"), null, Ui.Button(L("Şimdi göster", "Show now"), m.ShowSummary), ""));
    }

    private static UIElement Connections(ISettingsHost host)
    {
        var m = host.Manager;
        var items = new List<UIElement>
        {
            Ui.PageTitle(L("Bağlantılar", "Connections")),
            Ui.Section(L("Masaüstü uygulamaları", "Desktop apps")),
            Ui.SwitchCard(L("Claude ve ChatGPT uygulamalarını izle", "Watch the Claude and ChatGPT apps"),
                L("Ayrı izin gerekmez; ekrandan okuduklarım bilgisayarından çıkmaz", "No extra permission; nothing I read leaves your PC"),
                Prefs.WatchApps, v => { m.SetWatchApps(v); host.Changed(); }, ""),
        };
        if (Prefs.WatchApps)
        {
            if (m.WatcherStatus.Count == 0) items.Add(Ui.Para(L("Claude ya da ChatGPT şu an açık değil.", "Claude or ChatGPT isn't open right now."), true, 12));
            foreach (var (name, status) in m.WatcherStatus) items.Add(Ui.Para("• " + name + ": " + status, true, 12));
        }
        items.Add(Ui.Section(L("Kodlama ajanları", "Coding agents")));
        items.Add(Ui.SwitchCard("Claude Code", L("Terminaldeki her adımı anında görür", "Sees every step in the terminal instantly"),
            HookInstaller.IsInstalled(HookTarget.Claude), v => host.SetHook(HookTarget.Claude, v, false), ""));
        items.Add(Ui.SwitchCard("Codex", L("Codex'te bir kere /hooks yazıp onayla", "Type /hooks once in Codex and approve"),
            HookInstaller.IsInstalled(HookTarget.Codex), v => host.SetHook(HookTarget.Codex, v, false), ""));
        items.Add(Ui.SwitchCard(L("Kalkan", "Shield"), L("Tehlikeli komutlardan önce onay iste", "Ask before risky commands"), Prefs.Shield, v => host.SetShield(v), ""));
        items.Add(Ui.Section(L("Ekstralar", "Extras")));
        items.Add(Ui.SwitchCard(L("Anlatıcı", "Narrator"), L("Claude ne yaptığını kendi cümleleriyle söylesin", "Claude tells what it's doing in its own words"),
            NarratorInstaller.IsInstalled(), v => host.SetNarrator(v), ""));
        items.Add(Ui.Card(L("ClaudeBar kota uyarıları", "ClaudeBar quota alerts"), L("Kota azalınca robot uyarır", "The robot warns when quota runs low"),
            Ui.Button(L("Nasıl bağlanır?", "How to connect"), host.ShowClaudeBarHelp), ""));
        return Ui.Page(items.ToArray());
    }
}

/// <summary>İlk açılış sihirbazı: hoş geldin → bildirimler → uygulamalar → kodlama ajanları → hazır.</summary>
internal static class OnboardingWindow
{
    private static Window? _window;
    private static int _step;
    private const int Last = 4;

    public static void Show(ISettingsHost host)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Kurulum", "Setup"), 620, 560);
            _window.ResizeMode = ResizeMode.CanMinimize;
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

    public static void Close() => _window?.Close();

    private static void Render(ISettingsHost host)
    {
        var content = _step switch
        {
            0 => Ui.Page(
                Header(),
                Ui.PageTitle(L("TelepAIth'e hoş geldin 👋", "Welcome to TelepAIth 👋")),
                Ui.Para(L("Claude ve GPT o an ne yapıyorsa ekranının köşesindeki robot söyler.",
                    "A little robot in your screen corner tells you what Claude and GPT are doing.")),
                Ui.Para(L("Birkaç adımda bildirimleri ve bağlantıları kuralım. Hepsini sonra Ayarlar'dan değiştirebilirsin.",
                    "Let's set up notifications and connections in a few steps. You can change all of it later in Settings.")),
                Ui.Card(L("Deneme sürümü", "Trial build"), L("Bir şey ters giderse robota sağ tıkla → Hata bildir.", "If something goes wrong, right-click the robot → Report a problem."), null, "")),
            1 => Ui.Page(
                Ui.PageTitle(L("Bildirimler 🔔", "Notifications 🔔")),
                Ui.Para(L("Uzun bir iş bitince ya da AI senden onay beklerken haber vereyim.",
                    "I'll let you know when a long task finishes or the AI needs your approval.")),
                Ui.StatusCard(!Notifier.SystemDisabled, L("Windows'ta bildirimler açık", "Notifications are on in Windows"), L("Windows'ta bildirimler kapalı", "Notifications are off in Windows"),
                    Ui.Row(Ui.Button(L("Test gönder", "Send a test"), SettingsWindow.SendTest), Ui.Button(L("Windows ayarları", "Windows settings"), Notifier.OpenSystemSettings))),
                Ui.SwitchCard(L("Bildirimler", "Notifications"), null, Prefs.NotificationsEnabled, v => Prefs.NotificationsEnabled = v, "")),
            2 => Ui.Page(
                Ui.PageTitle(L("Claude ve ChatGPT 👀", "Claude and ChatGPT 👀")),
                Ui.Para(L("Masaüstü uygulamalarının ne zaman çalıştığını, onay beklediğini ve bitirdiğini Windows'un erişilebilirlik arayüzüyle görürüm. Ekrandan okuduklarım hiçbir yere gönderilmez.",
                    "I use Windows' accessibility interface to see when the desktop apps are working, waiting or done. Nothing I read from the screen leaves your PC.")),
                Ui.SwitchCard(L("Claude ve ChatGPT uygulamalarını izle", "Watch the Claude and ChatGPT apps"), null, Prefs.WatchApps, v => host.Manager.SetWatchApps(v), "")),
            3 => Ui.Page(
                Ui.PageTitle(L("Kodlama ajanları 💻", "Coding agents 💻")),
                Ui.Para(L("Terminalde Claude Code ya da Codex kullanıyorsan bağla; her adımı anında görürüm.",
                    "If you use Claude Code or Codex in a terminal, connect them; I'll see every step instantly.")),
                Ui.SwitchCard("Claude Code", L("Yeni açacağın oturumlar bağlanır", "New sessions connect"), HookInstaller.IsInstalled(HookTarget.Claude), v => host.SetHook(HookTarget.Claude, v, true), ""),
                Ui.SwitchCard("Codex", L("Codex'te bir kere /hooks yazıp onayla", "Type /hooks once in Codex and approve"), HookInstaller.IsInstalled(HookTarget.Codex), v => host.SetHook(HookTarget.Codex, v, true), "")),
            _ => Ui.Page(
                Ui.PageTitle(L("Hazırız 🎉", "All set 🎉")),
                Ui.Card(L("Köşeye bırak", "Drop it in a corner"), L("Robotu sürükleyip bir köşeye bırak, oraya yapışır.", "Drag the robot near a corner and it snaps there."), null, ""),
                Ui.Card(L("Balona tıkla", "Click the bubble"), L("O işin penceresine gidersin.", "Jump to that task's window."), null, ""),
                Ui.Card(L("Robota tıkla", "Click the robot"), L("Son olaylar. Çift tıkla: AI uygulamasını aç.", "Recent events. Double-click to open the AI app."), null, ""),
                Ui.Card(L("Sağ tık", "Right-click"), L("Kilit, her zaman üstte, odak modu, günün özeti.", "Lock, always on top, focus mode, today's summary."), null, ""),
                Ui.Card(L("Tepsi simgesi", "Tray icon"), L("Görev çubuğunun sağındaki robot simgesi → Ayarlar.", "The robot icon in the taskbar tray → Settings."), null, "")),
        };

        var bar = Ui.Themed(new DockPanel { LastChildFill = false }, bg: "Side");
        var dots = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center, Margin = new Thickness(24, 0, 0, 0) };
        for (var i = 0; i <= Last; i++)
        {
            var current = i == _step;
            var d = new Ellipse { Width = current ? 8 : 6, Height = current ? 8 : 6, Margin = new Thickness(0, 0, 7, 0), VerticalAlignment = VerticalAlignment.Center };
            d.SetResourceReference(Shape.FillProperty, current ? "Accent" : "CardBorder");
            dots.Children.Add(d);
        }
        DockPanel.SetDock(dots, Dock.Left);
        bar.Children.Add(dots);
        var buttons = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 14, 24, 14) };
        if (_step > 0) buttons.Children.Add(Ui.Button(L("Geri", "Back"), () => { _step--; Render(host); }));
        if (_step < Last)
            buttons.Children.Add(Ui.Button(_step == 0 ? L("Başlayalım", "Let's go") : L("İleri", "Next"), () => { _step++; Render(host); }, true));
        else
            buttons.Children.Add(Ui.Button(L("Bitir", "Finish"), () =>
            {
                Prefs.OnboardingDone = true;
                _window?.Close();
            }, true));
        DockPanel.SetDock(buttons, Dock.Right);
        bar.Children.Add(buttons);

        var root = new DockPanel();
        DockPanel.SetDock(bar, Dock.Bottom);
        root.Children.Add(bar);
        root.Children.Add(content);
        _window!.Content = root;
    }

    private static UIElement Header()
    {
        var img = new Image { Source = AppIcon.Image, Width = 64, Height = 64, HorizontalAlignment = HorizontalAlignment.Left, Margin = new Thickness(0, 0, 0, 12) };
        return img;
    }
}

/// <summary>Teşhis: robot ne görüyor? (genel durum + izlenen uygulamalar)</summary>
internal static class DiagnosticsWindow
{
    private static Window? _window;
    private static System.Windows.Threading.DispatcherTimer? _timer;

    public static void Close() => _window?.Close();

    public static void Show(Func<string> report)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Teşhis", "Diagnostics"), 760, 580);
            var box = new TextBox();
            box.SetResourceReference(FrameworkElement.StyleProperty, "Mono");
            var card = Ui.Themed(new Border { CornerRadius = new CornerRadius(6), BorderThickness = new Thickness(1), Padding = new Thickness(14, 10, 6, 10), Child = box }, bg: "Card");
            card.SetResourceReference(Border.BorderBrushProperty, "CardBorder");

            var top = new DockPanel { Margin = new Thickness(0, 0, 0, 14) };
            var copy = Ui.Button(L("Panoya kopyala", "Copy to clipboard"), () => { try { Clipboard.SetText(report()); } catch { } }, true);
            DockPanel.SetDock(copy, Dock.Right);
            top.Children.Add(copy);
            top.Children.Add(new TextBlock { Text = L("Robot ne görüyor?", "What does the robot see?"), FontFamily = new FontFamily(Theme.DisplayFont), FontSize = 22, FontWeight = FontWeights.SemiBold, VerticalAlignment = VerticalAlignment.Center });

            var root = new DockPanel { Margin = new Thickness(24, 20, 24, 24) };
            DockPanel.SetDock(top, Dock.Top);
            root.Children.Add(top);
            root.Children.Add(card);
            _window.Content = root;
            void Update()
            {
                var keep = box.VerticalOffset;
                box.Text = report();
                box.ScrollToVerticalOffset(keep);
            }
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
