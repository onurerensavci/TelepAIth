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
    void SetUsageLine(bool on);
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

    // MARK: Tepsi simgesi

    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern bool DestroyIcon(IntPtr handle);
    [System.Runtime.InteropServices.DllImport("user32.dll")] private static extern int GetSystemMetricsForDpi(int index, uint dpi);

    private static System.Drawing.Icon? _tray;
    private static IntPtr _trayHandle;
    private static string? _trayKey;

    /// <summary>Tepsideki simgenin piksel boyutu (görev çubuğunun ekranının ölçeğine göre: 16, 20, 24, 32…)</summary>
    public static int TraySize
    {
        get
        {
            var scale = Native.MonitorAt(0, 0).Scale;
            try
            {
                var px = GetSystemMetricsForDpi(49 /* SM_CXSMICON */, (uint)Math.Round(96 * scale));
                if (px > 0) return px;
            }
            catch { }
            return (int)Math.Round(16 * scale);
        }
    }

    /// <summary>
    /// Tepsi simgesi: kenarlara kadar dolu robot kafası (uygulama ikonundaki boşluklar 16 pikselde onu minicik yapıyordu).
    /// Gözler gösterilen AI'ın renginde; seni bekleyen bir şey varsa köşede turuncu nokta.
    /// </summary>
    public static System.Drawing.Icon TrayIcon(Rgb eyes, bool waiting)
    {
        var px = TraySize;
        var key = $"{px}|{eyes}|{waiting}";
        if (_tray != null && key == _trayKey) return _tray;
        using var bmp = DrawTray(px, eyes, waiting);
        var handle = bmp.GetHicon();
        var icon = System.Drawing.Icon.FromHandle(handle);
        var oldHandle = _trayHandle;
        _tray = icon;
        _trayHandle = handle;
        _trayKey = key;
        if (oldHandle != IntPtr.Zero) DestroyIcon(oldHandle);
        return icon;
    }

    public static System.Drawing.Bitmap DrawTray(int px, Rgb eyes, bool waiting)
    {
        var bmp = new System.Drawing.Bitmap(px, px, System.Drawing.Imaging.PixelFormat.Format32bppArgb);
        using var g = System.Drawing.Graphics.FromImage(bmp);
        g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
        g.PixelOffsetMode = System.Drawing.Drawing2D.PixelOffsetMode.HighQuality;
        g.Clear(System.Drawing.Color.Transparent);
        var k = px / 16f;   // 16 birimlik tuval
        System.Drawing.RectangleF R(float x, float y, float w, float h) => new(x * k, y * k, w * k, h * k);
        System.Drawing.Color C(int r, int gg, int b, int a = 255) => System.Drawing.Color.FromArgb(a, r, gg, b);

        System.Drawing.Drawing2D.GraphicsPath Round(System.Drawing.RectangleF r, float radius)
        {
            var d = Math.Min(radius * 2 * k, Math.Min(r.Width, r.Height));
            var path = new System.Drawing.Drawing2D.GraphicsPath();
            path.AddArc(r.X, r.Y, d, d, 180, 90);
            path.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            path.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            path.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }

        // Yan cıvatalar
        using (var bolt = new System.Drawing.SolidBrush(C(0xB9, 0xB1, 0xD3)))
        {
            using var l = Round(R(0f, 6.4f, 2f, 3.4f), 1f);
            using var r = Round(R(14f, 6.4f, 2f, 3.4f), 1f);
            g.FillPath(bolt, l);
            g.FillPath(bolt, r);
        }
        // Kafa: açık renk kabuk, ince koyu kenar (açık görev çubuğunda da seçilsin)
        using (var shell = Round(R(1.1f, 1.6f, 13.8f, 13.2f), 3.8f))
        {
            using var fill = new System.Drawing.Drawing2D.LinearGradientBrush(R(0, 1.6f, 16, 13.2f), C(0xFB, 0xF8, 0xF3), C(0xD6, 0xD0, 0xE8), 90f);
            g.FillPath(fill, shell);
            using var edge = new System.Drawing.Pen(C(0x2A, 0x26, 0x3D, 150), Math.Max(1f, 0.55f * k));
            g.DrawPath(edge, shell);
        }
        // Vizör
        using (var visor = Round(R(3f, 4.6f, 10f, 7.6f), 2.4f))
        using (var dark = new System.Drawing.SolidBrush(C(0x17, 0x14, 0x2A)))
            g.FillPath(dark, visor);
        // Gözler (AI'ın renginde, hafif açık)
        var eye = eyes.Mix(Rgb.White, 0.15);
        using (var eb = new System.Drawing.SolidBrush(C(eye.R, eye.G, eye.B)))
        {
            using var le = Round(R(5f, 6.3f, 2.3f, 4.2f), 1.15f);
            using var re = Round(R(8.7f, 6.3f, 2.3f, 4.2f), 1.15f);
            g.FillPath(eb, le);
            g.FillPath(eb, re);
        }
        // Alındaki ışık (büyük boyutlarda)
        if (px >= 24)
            using (var led = new System.Drawing.SolidBrush(C(0x33, 0xD4, 0x78)))
                g.FillEllipse(led, R(7.3f, 2.5f, 1.4f, 1.4f));
        // Seni bekliyor: turuncu nokta
        if (waiting)
        {
            using var badge = new System.Drawing.SolidBrush(C(0xFF, 0x99, 0x33));
            using var ring = new System.Drawing.Pen(C(0x17, 0x14, 0x2A), Math.Max(1f, 0.7f * k));
            var b = R(10.4f, 10.4f, 5.4f, 5.4f);
            g.FillEllipse(badge, b);
            g.DrawEllipse(ring, b);
        }
        return bmp;
    }

    /// <summary>Test için: simgenin ne kadarı dolu (0…1)</summary>
    public static double TrayFill(int px)
    {
        using var bmp = DrawTray(px, new Rgb(0xD9, 0x77, 0x57), false);
        var filled = 0;
        for (var x = 0; x < px; x++)
            for (var y = 0; y < px; y++)
                if (bmp.GetPixel(x, y).A > 128) filled++;
        return filled / (double)(px * px);
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
        ("\uE767", () => L("Ses", "Sound")),
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
                2 => Sound(host),
                3 => Focus(host),
                4 => Connections(host),
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
            Ui.SwitchCard(L("Windows açılınca başlasın", "Start with Windows"), null, Installer.AutostartEnabled, v => Installer.SetAutostart(v), ""),
            Ui.SwitchCard(L("Güncellemeleri otomatik kur", "Install updates automatically"),
                L("Yeni sürüm çıkınca, hiçbir sohbet çalışmıyor ya da seni beklemiyorken kendini günceller ve neyin yeni olduğunu söyler",
                  "When a new version is out, it updates itself while no chat is working or waiting for you, then tells you what's new"),
                Prefs.AutoUpdate, v => Prefs.AutoUpdate = v, ""));
    }

    private static UIElement Notifications(ISettingsHost host)
    {
        var off = Notifier.SystemDisabled;
        var items = new List<UIElement>
        {
            Ui.PageTitle(L("Bildirimler", "Notifications")),
            Ui.Para(L("Robot önemli anları balonunda söyler ve kısa bir ses çalar; hangi anlarda ses çıkacağını Ses sayfasından seçersin. Biten sohbetler için bildirim gelmez.",
                "The robot says important moments in its bubble and plays a short sound; pick which moments make a sound on the Sound page. Finished chats don't notify."), true, 12),
            Ui.SwitchCard(L("Israr etsin", "Nag me"), L("Uzun süre onay beklerse sallansın, 2 dakika sonra yeniden hatırlatsın", "Wiggle when it waits long, remind again after 2 minutes"),
                Prefs.WaitReminders, v => Prefs.WaitReminders = v, "\uE7E8"),
            Ui.Section(L("Windows bildirimleri", "Windows notifications")),
            Ui.SwitchCard(L("Seni bekleyenler ve hatalar Windows bildirimi olarak da gelsin", "Also send waiting and errors as Windows notifications"),
                L("Robot gizliyken işe yarar. Kapalıyken her şeyi robot söyler.", "Useful when the robot is hidden. When off, the robot tells you everything."),
                Prefs.NotificationsEnabled, v => { Prefs.NotificationsEnabled = v; host.Changed(); Application.Current.Dispatcher.BeginInvoke(() => Refresh(host)); }, "\uEA8F"),
        };
        if (Prefs.NotificationsEnabled)
        {
            items.Add(Ui.StatusCard(!off, L("Windows'ta bildirimler açık", "Notifications are on in Windows"),
                L("Windows'ta bildirimler kapalı: Ayarlar → Sistem → Bildirimler", "Notifications are off in Windows: Settings → System → Notifications"),
                Ui.Row(Ui.Button(L("Windows ayarları", "Windows settings"), Notifier.OpenSystemSettings), Ui.Button(L("Test gönder", "Send a test"), SendTest))));
            items.Add(Ui.SwitchCard(L("O uygulamaya bakarken de bildir", "Notify while I'm looking at that app"), null, Prefs.NotifyWhenFrontmost, v => Prefs.NotifyWhenFrontmost = v, "\uE7B3"));
        }
        items.Add(Ui.Para(L("Robotun balonuna ya da bildirime tıklayınca o sohbete gidersin (Claude, ChatGPT ya da terminal).",
            "Click the robot's bubble or a notification to jump to that chat (Claude, ChatGPT or the terminal)."), true, 12));
        return Ui.Page(items.ToArray());
    }

    private static readonly Dictionary<string, string> SoundGlyphs = new()
    {
        ["done"] = "\uE73E", ["background"] = "\uE895", ["waiting"] = "\uE8BD", ["reminder"] = "\uE823", ["error"] = "\uE7BA",
        ["usage"] = "\uE9D2", ["alert"] = "\uE7E8", ["summary"] = "\uE787",
    };

    /// <summary>Ses: neye ses çıksın (bildirim sesi, kısa ses, sesli söyleme), sessize al.</summary>
    private static UIElement Sound(ISettingsHost host)
    {
        var items = new List<UIElement>
        {
            Ui.PageTitle(L("Ses", "Sound")),
            Ui.SwitchCard(L("Sessize al", "Mute"), L("Hiçbir şey ses çıkarmaz; bildirimler sessiz gelir", "Nothing makes a sound; notifications arrive silently"),
                Prefs.Muted, v => { Prefs.Muted = v; host.Changed(); Application.Current.Dispatcher.BeginInvoke(() => Refresh(host)); }, "\uE74F"),
            Ui.Section(L("Neye ses çıksın", "What makes a sound")),
        };
        foreach (var (id, title, detail) in TelepAIth.Core.Text.SoundKinds)
            items.Add(Ui.SwitchCard(title(), detail(), Prefs.Sound(id), v => Prefs.SetSound(id, v), SoundGlyphs.GetValueOrDefault(id, "\uE767")));
        items.Add(Ui.Para(Prefs.Muted
            ? L("Sessize alındığı için şu an hiçbiri çalmaz.", "Muted, so none of these play right now.")
            : L("Kapattıkların bildirim olarak yine gelir, sadece sessiz gelir.", "The ones you turn off still notify, just silently."), true, 12));
        items.Add(Ui.Section(L("Ses türleri", "Kinds of sound")));
        items.Add(Ui.SwitchCard(L("Robotun kısa sesleri", "Robot's short sounds"), L("Bitince, beklerken ya da hata verince kısa bir ses", "A short sound when done, waiting or on errors"),
            Prefs.Sounds, v => Prefs.Sounds = v, "\uE767"));
        items.Add(Ui.SwitchCard(L("Sesli söylesin", "Speak out loud"), L("Önemli anları Windows'un sesiyle okur", "Reads important moments with the Windows voice"), Prefs.Speak, v =>
        {
            Prefs.Speak = v;
            if (v) Speech.Say(L("Merhaba, ben TelepAIth.", "Hi, I'm TelepAIth."));
        }, "\uE995"));
        return Ui.Page(items.ToArray());
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
        items.Add(Ui.SwitchCard(L("Robottan onay ver", "Approve from the robot"),
            L("Claude Code izin isteyince balonda İzin ver / Reddet çıkar. Terminale bakıyorsan soru terminalde sorulur.",
              "When Claude Code asks for permission, the bubble shows Allow / Deny. If you're looking at the terminal, it asks there."),
            Prefs.ApproveFromRobot, v => Prefs.ApproveFromRobot = v, "\uE8FB"));
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

/// <summary>İlk açılış sihirbazı: hoş geldin → bildirimler ve ses → uygulamalar → kodlama ajanları → robotun odası → hazır.</summary>
internal static class OnboardingWindow
{
    private static Window? _window;
    private static int _step;
    private const int Last = 5;

    public static void Show(ISettingsHost host)
    {
        if (_window == null)
        {
            _window = Ui.Window(L("Kurulum", "Setup"), 640, 620);
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
                Ui.PageTitle(L("Bildirimler ve ses 🔔", "Notifications & sound 🔔")),
                Ui.Para(L("Bir iş bitince, AI seni beklerken ya da hata verince robot balonunda söyler ve kısa bir ses çalar. Hangi anlarda ses çıkacağını sonra Ayarlar → Ses'ten tek tek seçebilirsin.",
                    "When a task finishes, the AI needs you or something fails, the robot says it in its bubble and plays a short sound. Later you can pick each moment in Settings → Sound.")),
                Ui.SwitchCard(L("Robotun kısa sesleri", "Robot's short sounds"), L("Bitince, beklerken, hata verince", "When done, waiting or on errors"), Prefs.Sounds, v => Prefs.Sounds = v, "\uE767"),
                Ui.SwitchCard(L("Sesli söylesin", "Speak out loud"), L("Önemli anları Windows'un sesiyle okur", "Reads important moments with the Windows voice"), Prefs.Speak, v =>
                {
                    Prefs.Speak = v;
                    if (v) Speech.Say(L("Merhaba, ben TelepAIth.", "Hi, I'm TelepAIth."));
                }, "\uE995"),
                Ui.SwitchCard(L("Windows bildirimleri de gelsin", "Windows notifications too"), L("Seni bekleyenler ve hatalar; robot gizliyken işe yarar", "Waiting and errors; useful when the robot is hidden"),
                    Prefs.NotificationsEnabled, v => Prefs.NotificationsEnabled = v, "\uEA8F")),
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
            4 => RoomStep(),
            _ => Ui.Page(
                Ui.PageTitle(L("Hazırız 🎉", "All set 🎉")),
                Ui.Card(L("Köşeye bırak", "Drop it in a corner"), L("Robotu sürükleyip bir köşeye bırak, oraya yapışır.", "Drag the robot near a corner and it snaps there."), null, ""),
                Ui.Card(L("Balona tıkla", "Click the bubble"), L("O işin penceresine gidersin.", "Jump to that task's window."), null, ""),
                Ui.Card(L("Robota tıkla", "Click the robot"), L("Son olaylar. Çift tıkla: AI uygulamasını aç.", "Recent events. Double-click to open the AI app."), null, ""),
                Ui.Card(L("Sağ tık", "Right-click"), L("Kilit, her zaman üstte, odak modu, günün özeti.", "Lock, always on top, focus mode, today's summary."), null, ""),
                Ui.Card(L("Tepsi simgesi", "Tray icon"), L("Görev çubuğunun sağındaki robot simgesi → Ayarlar.", "The robot icon in the taskbar tray → Settings."), null, ""),
                Ui.Section(L("Başlangıç", "Startup")),
                Ui.SwitchCard(L("Windows açılınca başlasın", "Start with Windows"), L("Robot her zaman hazır olsun", "Keep the robot ready"),
                    Installer.AutostartEnabled, v => Installer.SetAutostart(v), "\uE7E8")),
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

    /// <summary>Robotun odası: tipler, gizli ödüller, efektler (Mac'te roomStep)</summary>
    private static UIElement RoomStep()
    {
        var theme = Themes.Shared.Theme("claude").Color;
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 10) };
        foreach (var type in new[] { "coder", "police", "king" })
            row.Children.Add(new RoomWindow.RobotPreview(theme, Outfits.ItemsOf(type).Where(i => !i.Legendary).ToList(), 0.9, simple: true) { Width = 150, Height = 120 });
        return Ui.Page(
            Ui.PageTitle(L("Robotun odası 🎒", "The robot's room 🎒")),
            Ui.Para(L("Sen çalıştıkça robot seviye atlar ve gardıropta yeni parçalar açılır. Robota sağ tıkla → Robotun Odası.",
                "As you work, the robot levels up and new pieces open in the wardrobe. Right-click the robot → Robot's Room.")),
            row,
            Ui.Card(L("30 parça", "30 pieces"), L("Baş, gözlük, yüz, boyun ve yanına: her yuvadan istediğini giy, kendi kombinini yap.",
                "Head, eyes, face, neck and side: wear anything per slot and make your own combo."), null, "\uE7BF"),
            Ui.Card(L("Gizli ödüller ✨", "Secret rewards ✨"), L("Bazı parçalar parıltılı bir sürpriz; belli bir seviyede açılır.",
                "Some pieces are shiny surprises that open at a certain level."), null, "\uE734"),
            Ui.Card(L("Efektler", "Effects"), L("Mevsime göre kar, güneş, yaprak; sohbette aşk geçerse kalpler, kutlamada konfeti. Odadan değiştirebilirsin.",
                "Snow, sun or leaves by season; hearts when love comes up in a chat, confetti for celebrations. Change it in the room."), null, "\uE790"));
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
