using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using TelepAIth.Core;
using static TelepAIth.Core.Text;

namespace TelepAIth;

/// <summary>
/// Robotun odası (Mac'te RoomView.swift): solda robot, seviye, sayılar ve rozetler; sağda
/// Gardırop · Başarımlar · Emek · Kullanım sekmeleri.
/// </summary>
internal static class RoomWindow
{
    private static Window? _window;
    private static RobotManager? _manager;
    private static Action<bool>? _setUsageLine;
    private static string _tab = "wardrobe";
    /// <summary>Gardıropta seçili yuva (Baş, Gözlük…)</summary>
    private static string _slot = "head";
    private static int _days = 30;

    public static bool IsOpen => _window != null;

    public static void Show(RobotManager manager, Action<bool> setUsageLine)
    {
        _manager = manager;
        _setUsageLine = setUsageLine;
        if (_window == null)
        {
            _window = Ui.Window(L("Robotun odası", "Robot's room"), 980, 640);
            _window.MinWidth = 820;
            _window.MinHeight = 540;
            _window.Closed += (_, _) => _window = null;
            _window.Activated += (_, _) => Rebuild();
        }
        Rebuild();
        Ui.Bring(_window);
    }

    public static void Close() => _window?.Close();

    /// <summary>Duman testi için: sekmeyi seç</summary>
    public static void Select(string tab)
    {
        _tab = tab;
        Rebuild();
    }

    public static string CurrentTab => _tab;

    private static string Source => _manager?.CurrentSource ?? "claude";
    private static Rgb ThemeRgb => Themes.Shared.Theme(Source).Color;
    private static Color Accent => Color.FromRgb(ThemeRgb.R, ThemeRgb.G, ThemeRgb.B);

    private static void Rebuild()
    {
        if (_window == null) return;
        var p = Progress.Shared.Snapshot();
        var root = new Grid();
        root.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(260) });
        root.ColumnDefinitions.Add(new ColumnDefinition());
        var side = SidePanel(p);
        root.Children.Add(side);

        var right = new DockPanel();
        Grid.SetColumn(right, 1);
        var tabs = Tabs(p);
        DockPanel.SetDock(tabs, Dock.Top);
        right.Children.Add(tabs);
        var page = _tab switch
        {
            "achievements" => AchievementsPage(p),
            "effects" => EffectsPage(),
            "effort" => EffortPage(),
            "usage" => UsagePage(),
            _ => WardrobePage(p),
        };
        right.Children.Add(new ScrollViewer
        {
            Content = new Border { Padding = new Thickness(24, 18, 24, 24), Child = page },
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        });
        root.Children.Add(right);
        _window.Content = root;
    }

    // MARK: Yardımcılar

    private static TextBlock T(string s, double size = 13, FontWeight? weight = null, bool muted = false, Color? color = null)
    {
        var t = new TextBlock { Text = s, FontSize = size, FontWeight = weight ?? FontWeights.Normal, TextWrapping = TextWrapping.Wrap };
        if (color is { } c) t.Foreground = new SolidColorBrush(c);
        else Ui.Themed(t, muted ? "SubText" : "Text");
        return t;
    }

    /// <summary>İnce ilerleme çubuğu</summary>
    private static Grid Bar(double fraction, Color color, double width, double height = 6)
    {
        var g = new Grid { Width = width, Height = height, HorizontalAlignment = HorizontalAlignment.Left, VerticalAlignment = VerticalAlignment.Center };
        g.Children.Add(new Border { CornerRadius = new CornerRadius(height / 2), Background = new SolidColorBrush(Color.FromArgb(0x40, 0x80, 0x80, 0x80)) });
        g.Children.Add(new Border
        {
            CornerRadius = new CornerRadius(height / 2), Background = new SolidColorBrush(color), HorizontalAlignment = HorizontalAlignment.Left,
            Width = Math.Max(0, Math.Min(1, fraction)) * width,
        });
        return g;
    }

    private static Border CardBox(UIElement child, bool highlight = false, Color? border = null)
    {
        var b = new Border { CornerRadius = new CornerRadius(12), Padding = new Thickness(10), Margin = new Thickness(0, 0, 10, 10), Child = child, BorderThickness = new Thickness(2) };
        Ui.Themed(b, bg: "Card");
        b.BorderBrush = highlight && border is { } c ? new SolidColorBrush(c) : Brushes.Transparent;
        return b;
    }

    private static Color TierColor(int tier) => tier switch
    {
        0 => Color.FromRgb(0xD9, 0x8C, 0x5C),
        1 => Color.FromRgb(0x6B, 0x9E, 0xF2),
        2 => Color.FromRgb(0xF2, 0xBD, 0x40),
        _ => Color.FromRgb(0xA8, 0x7A, 0xF2),
    };

    // MARK: Sol panel

    private static UIElement SidePanel(ProgressData p)
    {
        var panel = new StackPanel { Margin = new Thickness(22, 18, 22, 18) };
        panel.Children.Add(new RobotPreview(ThemeRgb, Outfits.Worn(p), 1.6) { Height = 200, HorizontalAlignment = HorizontalAlignment.Center, Width = 216 });
        panel.Children.Add(T(L($"Seviye {Levels.Level(p)}", $"Level {Levels.Level(p)}"), 24, FontWeights.Bold).Also(t => t.Margin = new Thickness(0, 6, 0, 8)));
        var (fraction, left) = Levels.Next(p);
        panel.Children.Add(Bar(fraction, Accent, 216));
        panel.Children.Add(T(L($"sonraki seviyeye {left} XP", $"{left} XP to next level"), 11, muted: true).Also(t => t.Margin = new Thickness(0, 4, 0, 14)));
        var stats = new UniformGrid { Columns = 3, Margin = new Thickness(0, 0, 0, 14) };
        void Stat(string v, string label)
        {
            var s = new StackPanel();
            s.Children.Add(T(v, 18, FontWeights.SemiBold));
            s.Children.Add(T(label, 10.5, muted: true));
            stats.Children.Add(s);
        }
        Stat(p.Streak.ToString(CultureInfo.InvariantCulture), L("gün seri", "day streak"));
        Stat(DailyStats.Shared.TurnsOn(DateTime.Now).ToString(CultureInfo.InvariantCulture), L("bugün tur", "turns today"));
        Stat(p.ActiveDays.ToString(CultureInfo.InvariantCulture), L("aktif gün", "active days"));
        panel.Children.Add(stats);
        var badges = new WrapPanel();
        foreach (var a in Achievements.All.Where(a => a.Done(p)).TakeLast(20))
            badges.Children.Add(new Ellipse(18, TierColor(a.Tier)) { Margin = new Thickness(0, 0, 5, 5), ToolTip = a.Title + " · " + a.Description });
        panel.Children.Add(badges);
        panel.Children.Add(T(L("Gerçek işle XP kazanır: her tur, düzenleme, çalışılan dakika ve aktif gün.",
                                "Earns XP from real work: every turn, edit, minute worked and active day."), 10.5, muted: true)
            .Also(t => t.Margin = new Thickness(0, 14, 0, 0)));
        var side = Ui.Themed(new Border { Child = panel }, bg: "Side");
        return side;
    }

    // MARK: Sekmeler

    private static UIElement Tabs(ProgressData p)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(24, 14, 24, 0) };
        void Tab(string id, string title, string? count)
        {
            var selected = _tab == id;
            var label = new StackPanel { Orientation = Orientation.Horizontal };
            label.Children.Add(T(title, 13.5, selected ? FontWeights.SemiBold : FontWeights.Normal, muted: !selected));
            if (count != null) label.Children.Add(T(" " + count, 11.5, muted: true).Also(t => t.VerticalAlignment = VerticalAlignment.Center));
            var stack = new StackPanel();
            stack.Children.Add(label);
            stack.Children.Add(new Border { Height = 2, Margin = new Thickness(0, 8, 0, 0), Background = selected ? new SolidColorBrush(Accent) : Brushes.Transparent });
            var b = new Border { Child = stack, Margin = new Thickness(0, 0, 24, 0), Cursor = Cursors.Hand, Background = Brushes.Transparent };
            b.MouseLeftButtonUp += (_, _) => { _tab = id; Rebuild(); };
            row.Children.Add(b);
        }
        Tab("wardrobe", L("Gardırop", "Wardrobe"), $"{Outfits.All.Count(i => Outfits.Unlocked(i, p))}/{Outfits.All.Count}");
        Tab("effects", L("Efektler", "Effects"), null);
        Tab("achievements", L("Başarımlar", "Achievements"), $"{Achievements.All.Count(a => a.Done(p))}/{Achievements.All.Count}");
        Tab("effort", L("Emek", "Effort"), null);
        Tab("usage", L("Kullanım", "Usage"), null);
        var wrap = new StackPanel();
        wrap.Children.Add(row);
        wrap.Children.Add(Ui.Themed(new Border { Height = 1, Margin = new Thickness(0, 0, 0, 0) }, bg: "CardBorder"));
        return wrap;
    }

    // MARK: Gardırop

    private static UIElement WardrobePage(ProgressData p)
    {
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(180) });
        grid.ColumnDefinitions.Add(new ColumnDefinition());
        // Yuvalar (Baş, Gözlük…): her yuvadan istediğini seç, kendi kombinini yap
        var list = new StackPanel { Margin = new Thickness(0, 0, 20, 0) };
        foreach (var slot in Outfits.Slots)
        {
            var items = Outfits.All.Where(i => i.Slot == slot).ToList();
            var open = items.Count(i => Outfits.Unlocked(i, p));
            var row = new DockPanel { LastChildFill = true };
            var count = T($"{open}/{items.Count}", 11, muted: true);
            DockPanel.SetDock(count, Dock.Right);
            row.Children.Add(count);
            row.Children.Add(T(Outfits.SlotName(slot), 13, FontWeights.Medium));
            var b = new Border
            {
                Child = row, Padding = new Thickness(10, 7, 10, 7), CornerRadius = new CornerRadius(8), Cursor = Cursors.Hand,
                Background = _slot == slot ? new SolidColorBrush(Color.FromArgb(0x30, Accent.R, Accent.G, Accent.B)) : Brushes.Transparent,
                Margin = new Thickness(0, 0, 0, 4),
            };
            var sl = slot;
            b.MouseLeftButtonUp += (_, _) => { _slot = sl; Rebuild(); };
            list.Children.Add(b);
        }
        var off = T(L("Hepsini çıkar", "Take all off"), 11.5, color: Accent);
        off.Cursor = Cursors.Hand;
        off.Margin = new Thickness(10, 10, 0, 0);
        off.MouseLeftButtonUp += (_, _) => { Outfits.TakeOffAll(); Rebuild(); };
        list.Children.Add(off);
        grid.Children.Add(list);

        var right = new StackPanel();
        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        Border Card(OutfitItem item, string subtitle)
        {
            var open = Outfits.Unlocked(item, p);
            var selected = open && Prefs.Outfit(item.Slot) == item.Id;
            void Toggle()
            {
                if (!open) return;
                Prefs.SetOutfit(item.Slot, Prefs.Outfit(item.Slot) == item.Id ? null : item.Id);
                Rebuild();
            }
            return item.Legendary
                ? LegendaryCard(item, open, selected, Toggle)
                : OutfitCard(item.Name, open ? subtitle : Outfits.UnlockHint(item), selected, !open, new[] { item }, Toggle);
        }
        right.Children.Add(T(Outfits.SlotName(_slot), 18, FontWeights.Bold));
        right.Children.Add(T(L("Her yuvadan istediğini seç, kendi kombinini yap.", "Pick anything for each slot and make your own combo."), 11.5, muted: true)
            .Also(t => t.Margin = new Thickness(0, 2, 0, 12)));
        var cards = new WrapPanel();
        cards.Children.Add(OutfitCard(L("Hiçbiri", "None"), null, Prefs.Outfit(_slot) == null, false, Array.Empty<OutfitItem>(), () =>
        {
            Prefs.SetOutfit(_slot, null);
            Rebuild();
        }));
        foreach (var item in Outfits.All.Where(i => i.Slot == _slot)) cards.Children.Add(Card(item, " "));
        right.Children.Add(cards);
        return grid;
    }

    private static readonly Color Gold = Color.FromRgb(0xFF, 0xD1, 0x5C);

    /// <summary>Gizli ödül kartı: kilitliyken soru işareti ve parıltı, açılınca altın çerçeve ve "Efsanevi" (Mac'te LegendaryCard)</summary>
    private static Border LegendaryCard(OutfitItem item, bool open, bool selected, Action click)
    {
        var s = new StackPanel { Width = 104 };
        var stage = new Grid { Width = 104, Height = 76 };
        var halo = new System.Windows.Shapes.Ellipse
        {
            Width = 84, Height = 84,
            Fill = new RadialGradientBrush(Color.FromArgb(0x99, Gold.R, Gold.G, Gold.B), Color.FromArgb(0, Gold.R, Gold.G, Gold.B)),
        };
        halo.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.5, 1, TimeSpan.FromSeconds(1.4)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        stage.Children.Add(halo);
        double[] sx = { -30, 28, -24, 31 }, sy = { -24, -20, 24, 18 };
        for (var i = 0; i < 4; i++)
        {
            var sp = new TextBlock
            {
                Text = "✦", FontSize = i % 2 == 0 ? 9 : 12, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center, RenderTransform = new TranslateTransform(sx[i], sy[i]),
            };
            sp.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0.15, 1, TimeSpan.FromSeconds(0.9))
            {
                AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever, BeginTime = TimeSpan.FromSeconds(i * 0.45),
            });
            stage.Children.Add(sp);
        }
        if (open)
            stage.Children.Add(new RobotPreview(ThemeRgb, new[] { item }, 0.62, simple: true) { Width = 104, Height = 76 });
        else
        {
            var q = new TextBlock
            {
                Text = "?", FontSize = 40, FontWeight = FontWeights.Black, HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center, RenderTransformOrigin = new Point(0.5, 0.5),
                Foreground = new LinearGradientBrush(new GradientStopCollection
                {
                    new GradientStop(Colors.White, 0), new GradientStop(Gold, 0.5), new GradientStop(Color.FromRgb(0xD9, 0x8C, 0x26), 1),
                }, 90),
                Effect = new DropShadowEffect { Color = Gold, BlurRadius = 14, ShadowDepth = 0, Opacity = 0.9 },
            };
            var pulse = new ScaleTransform(1, 1);
            q.RenderTransform = pulse;
            var anim = new DoubleAnimation(1, 1.08, TimeSpan.FromSeconds(1.2)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever };
            pulse.BeginAnimation(ScaleTransform.ScaleXProperty, anim);
            pulse.BeginAnimation(ScaleTransform.ScaleYProperty, anim);
            stage.Children.Add(q);
        }
        s.Children.Add(stage);
        s.Children.Add(T(open ? item.Name : L("Gizli ödül", "Secret reward"), 11.5, FontWeights.Bold, color: open ? Gold : null)
            .Also(t => { t.TextAlignment = TextAlignment.Center; t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; }));
        s.Children.Add(T(open ? "✨ " + L("Efsanevi", "Legendary") : "🔒 " + Outfits.UnlockHint(item), 9.5, muted: true)
            .Also(t => { t.TextAlignment = TextAlignment.Center; t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; }));
        var border = new LinearGradientBrush(new GradientStopCollection
        {
            new GradientStop(Gold, 0), new GradientStop(Colors.White, 0.25), new GradientStop(Gold, 0.5), new GradientStop(Color.FromRgb(0xF2, 0x8C, 0x33), 0.75), new GradientStop(Gold, 1),
        }, new Point(0, 0), new Point(1, 1));
        var spin = new RotateTransform(0, 0.5, 0.5);
        border.RelativeTransform = spin;
        spin.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(4)) { RepeatBehavior = RepeatBehavior.Forever });
        var card = new Border
        {
            CornerRadius = new CornerRadius(12), Padding = new Thickness(10), Margin = new Thickness(0, 0, 10, 10), Child = s,
            BorderThickness = new Thickness(selected ? 3 : 1.8), BorderBrush = border, Cursor = open ? Cursors.Hand : Cursors.Arrow,
            Background = new LinearGradientBrush(Color.FromArgb(0x59, 0x5C, 0x3D, 0x80), Color.FromArgb(0x4D, 0x8C, 0x61, 0x1A), 45),
        };
        card.MouseLeftButtonUp += (_, _) => click();
        return card;
    }

    private static Border OutfitCard(string title, string? hint, bool selected, bool locked, IReadOnlyList<OutfitItem> items, Action click)
    {
        var s = new StackPanel { Width = 104 };
        var preview = new RobotPreview(ThemeRgb, items, 0.62, simple: true) { Width = 104, Height = 76, Opacity = locked ? 0.35 : 1 };
        s.Children.Add(preview);
        s.Children.Add(T((locked ? "🔒 " : "") + title, 11.5, FontWeights.SemiBold).Also(t => { t.TextAlignment = TextAlignment.Center; t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; }));
        s.Children.Add(T(hint ?? " ", 9.5, muted: true).Also(t => { t.TextAlignment = TextAlignment.Center; t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; }));
        var card = CardBox(s, selected, Accent);
        card.Cursor = locked ? Cursors.Arrow : Cursors.Hand;
        card.MouseLeftButtonUp += (_, _) => click();
        return card;
    }

    // MARK: Efektler

    private static UIElement EffectsPage()
    {
        var page = new StackPanel();
        page.Children.Add(T(L("Efektler", "Effects"), 16, FontWeights.SemiBold));
        page.Children.Add(T(L("Robotun çevresinde dolaşır; bitince, beklerken ya da hata verince canlanıp parlar.",
            "They float around the robot and light up when a task finishes, needs you or fails."), 11.5, muted: true).Also(t => t.Margin = new Thickness(0, 4, 0, 12)));
        var current = Prefs.Costume == "off" || Effects.All.Any(e => e.Id == Prefs.Costume) ? Prefs.Costume : "auto";
        var cards = new WrapPanel();
        void Card(string id, string title, string? subtitle, string? preview)
        {
            var s = new StackPanel { Width = 112 };
            s.Children.Add(new RobotPreview(ThemeRgb, Array.Empty<OutfitItem>(), 0.62, simple: true, effect: preview) { Width = 112, Height = 84 });
            s.Children.Add(T(title, 11.5, FontWeights.SemiBold).Also(t => { t.TextAlignment = TextAlignment.Center; t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; }));
            s.Children.Add(T(subtitle ?? " ", 9.5, muted: true).Also(t => { t.TextAlignment = TextAlignment.Center; t.TextWrapping = TextWrapping.NoWrap; }));
            var card = CardBox(s, current == id, Accent);
            card.Cursor = Cursors.Hand;
            card.MouseLeftButtonUp += (_, _) => { Prefs.Costume = id; Rebuild(); };
            cards.Children.Add(card);
        }
        Card("auto", L("Otomatik", "Automatic"), L("Mevsim + duygular", "Season + feelings"), Effects.Season(DateTime.Now));
        Card("off", L("Kapalı", "Off"), null, null);
        foreach (var (id, name) in Effects.All) Card(id, name(), null, id);
        page.Children.Add(cards);
        var info = new StackPanel();
        info.Children.Add(T(L("Otomatik mod nasıl seçer?", "How does Automatic choose?"), 12.5, FontWeights.SemiBold).Also(t => t.Margin = new Thickness(0, 0, 0, 6)));
        info.Children.Add(T(L("• Mevsime göre: kışın kar, baharda gökkuşağı, yazın güneş, sonbaharda yapraklar. Yılbaşında konfeti, sevgililer gününde kalpler.\n• Sohbette bir duygu geçerse ona göre tepki verir: aşk → kalpler, kutlama → konfeti, övgü → yıldızlar, üzüntü → yağmur, iyi geceler → ateş böcekleri.\n• Robot bir şey yaparken görünür, boşta kalınca yavaşça söner.",
            "• By season: snow in winter, a rainbow in spring, sun in summer, leaves in autumn. Confetti on New Year's, hearts on Valentine's Day.\n• Reacts to feelings in a chat: love → hearts, celebration → confetti, praise → stars, sadness → rain, good night → fireflies.\n• Shows while the robot is busy and slowly fades when it's idle."), 11.5, muted: true));
        page.Children.Add(CardBox(info).Also(b => b.Margin = new Thickness(0, 4, 0, 0)));
        return page;
    }

    // MARK: Başarımlar

    private static UIElement AchievementsPage(ProgressData p)
    {
        var page = new StackPanel();
        var all = Achievements.All;
        var done = all.Count(a => a.Done(p));
        var top = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 16) };
        var total = new StackPanel { Margin = new Thickness(0, 0, 40, 0) };
        var big = new TextBlock();
        big.Inlines.Add(new System.Windows.Documents.Run(done.ToString(CultureInfo.InvariantCulture)) { FontSize = 34, FontWeight = FontWeights.Bold });
        big.Inlines.Add(new System.Windows.Documents.Run($" / {all.Count}") { FontSize = 15 });
        Ui.Themed(big, "Text");
        total.Children.Add(big);
        total.Children.Add(T(L($"{all.Count} başarımın {done} tanesi tamam", $"{done} of {all.Count} achievements done"), 11.5, muted: true));
        total.Children.Add(Bar((double)done / all.Count, Accent, 240).Also(b => b.Margin = new Thickness(0, 6, 0, 0)));
        top.Children.Add(total);
        var tiers = new StackPanel();
        for (var tier = 0; tier < 4; tier++)
        {
            var inTier = all.Where(a => a.Tier == tier).ToList();
            var ok = inTier.Count(a => a.Done(p));
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 5) };
            row.Children.Add(T(Achievements.TierName(tier), 11.5, FontWeights.SemiBold).Also(t => t.Width = 70));
            row.Children.Add(T($"{ok}/{inTier.Count}", 11, muted: true).Also(t => { t.Width = 40; t.TextAlignment = TextAlignment.Right; t.Margin = new Thickness(0, 0, 8, 0); }));
            row.Children.Add(Bar(inTier.Count == 0 ? 0 : (double)ok / inTier.Count, TierColor(tier), 160, 4));
            tiers.Children.Add(row);
        }
        top.Children.Add(tiers);
        page.Children.Add(top);

        foreach (var cat in Achievements.Categories)
        {
            var items = all.Where(a => a.Category == cat).ToList();
            var ok = items.Count(a => a.Done(p));
            var head = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 6, 0, 10) };
            head.Children.Add(T(Achievements.CategoryName(cat), 14, FontWeights.SemiBold));
            head.Children.Add(T($"  {ok}/{items.Count}", 11, muted: true).Also(t => t.VerticalAlignment = VerticalAlignment.Center));
            page.Children.Add(head);
            var grid = new UniformGrid { Columns = 3 };
            foreach (var a in items) grid.Children.Add(AchievementCard(a, p));
            page.Children.Add(grid);
        }
        return page;
    }

    private static Border AchievementCard(Achievement a, ProgressData p)
    {
        var done = a.Done(p);
        var value = a.Value(p);
        var row = new DockPanel();
        var icon = new Ellipse(34, done ? TierColor(a.Tier) : Color.FromArgb(0x50, 0x80, 0x80, 0x80)) { Margin = new Thickness(0, 0, 10, 0), VerticalAlignment = VerticalAlignment.Top };
        DockPanel.SetDock(icon, Dock.Left);
        row.Children.Add(icon);
        var text = new StackPanel();
        var title = new DockPanel();
        var tier = T(Achievements.TierName(a.Tier), 9.5, FontWeights.SemiBold, color: TierColor(a.Tier));
        DockPanel.SetDock(tier, Dock.Right);
        title.Children.Add(tier);
        title.Children.Add(T(a.Title, 12.5, FontWeights.SemiBold));
        text.Children.Add(title);
        text.Children.Add(T(a.Description, 10.5, muted: true));
        if (!done && value > 0)
        {
            var prog = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 4, 0, 0) };
            prog.Children.Add(Bar(a.Fraction(p), TierColor(a.Tier), 50, 4));
            prog.Children.Add(T($"  {(long)value} / {(long)a.Target}", 9.5, muted: true));
            text.Children.Add(prog);
        }
        row.Children.Add(text);
        var card = CardBox(row);
        card.Opacity = done ? 1 : 0.8;
        return card;
    }

    // MARK: Emek

    private static UIElement EffortPage()
    {
        var e = DailyStats.Shared.Effort(DateTime.Now, _days);
        var page = new StackPanel();
        var head = new DockPanel { Margin = new Thickness(0, 0, 0, 12) };
        var toggle = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Top };
        foreach (var d in new[] { 7, 30 })
        {
            var days = d;
            var b = new Border
            {
                Child = T(L($"{d} gün", $"{d} days"), 11.5, _days == d ? FontWeights.SemiBold : FontWeights.Normal),
                Padding = new Thickness(10, 4, 10, 4), CornerRadius = new CornerRadius(6), Cursor = Cursors.Hand,
                Background = _days == d ? new SolidColorBrush(Color.FromArgb(0x30, 0x80, 0x80, 0x80)) : Brushes.Transparent,
            };
            b.MouseLeftButtonUp += (_, _) => { _days = days; Rebuild(); };
            toggle.Children.Add(b);
        }
        DockPanel.SetDock(toggle, Dock.Right);
        head.Children.Add(toggle);
        var titles = new StackPanel();
        titles.Children.Add(T(e.Headline(_days), 18, FontWeights.SemiBold));
        if (e.TopLine is { } top) titles.Children.Add(T(top, 12.5));
        titles.Children.Add(T(L($"{e.Projects.Count} proje · {e.TotalTurns} tur · {e.TotalEdits} düzenleme",
                                 $"{e.Projects.Count} projects · {e.TotalTurns} turns · {e.TotalEdits} edits"), 11.5, muted: true));
        head.Children.Add(titles);
        page.Children.Add(head);
        page.Children.Add(new EffortChart(e) { Height = 200, Margin = new Thickness(0, 0, 0, 10) });

        var chips = new WrapPanel { Margin = new Thickness(0, 0, 0, 10) };
        foreach (var (src, secs) in e.BySource.OrderByDescending(kv => kv.Value))
        {
            var theme = Themes.Shared.Theme(src);
            var chip = new StackPanel { Orientation = Orientation.Horizontal };
            chip.Children.Add(new Ellipse(8, Color.FromRgb(theme.Color.R, theme.Color.G, theme.Color.B)) { Margin = new Thickness(0, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center });
            chip.Children.Add(T(theme.DisplayName, 11.5, FontWeights.SemiBold));
            chip.Children.Add(T("  " + ShortDuration(secs), 10.5, muted: true));
            chips.Children.Add(new Border
            {
                Child = chip, Padding = new Thickness(9, 4, 9, 4), CornerRadius = new CornerRadius(10), Margin = new Thickness(0, 0, 8, 0),
                Background = new SolidColorBrush(Color.FromArgb(0x18, 0x80, 0x80, 0x80)),
            });
        }
        page.Children.Add(chips);
        page.Children.Add(Ui.Themed(new Border { Height = 1, Margin = new Thickness(0, 4, 0, 12) }, bg: "CardBorder"));
        page.Children.Add(T(L("Projeler", "Projects"), 14, FontWeights.SemiBold).Also(t => t.Margin = new Thickness(0, 0, 0, 8)));
        if (e.Projects.Count == 0)
        {
            page.Children.Add(T(L("Henüz proje yok. Claude Code ve Codex'teki işler burada projelerine göre görünür.",
                                   "No projects yet. Work in Claude Code and Codex shows up here by project."), 11.5, muted: true));
            return page;
        }
        var table = new Grid();
        table.ColumnDefinitions.Add(new ColumnDefinition());
        table.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(240) });
        table.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(60) });
        void Cell(UIElement el, int r, int c)
        {
            Grid.SetRow(el, r);
            Grid.SetColumn(el, c);
            table.Children.Add(el);
        }
        table.RowDefinitions.Add(new RowDefinition { Height = new GridLength(22) });
        Cell(T(L("Proje", "Project"), 10.5, FontWeights.SemiBold, muted: true), 0, 0);
        Cell(T(L("Ajan saati", "Agent time"), 10.5, FontWeights.SemiBold, muted: true), 0, 1);
        Cell(T(L("Tur", "Turns"), 10.5, FontWeights.SemiBold, muted: true).Also(t => t.TextAlignment = TextAlignment.Right), 0, 2);
        var max = e.Projects[0].Seconds;
        var r = 1;
        foreach (var pr in e.Projects.Take(12))
        {
            table.RowDefinitions.Add(new RowDefinition { Height = new GridLength(26) });
            Cell(T(pr.Name, 12, FontWeights.Medium).Also(t => { t.TextTrimming = TextTrimming.CharacterEllipsis; t.TextWrapping = TextWrapping.NoWrap; t.VerticalAlignment = VerticalAlignment.Center; }), r, 0);
            var cell = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
            cell.Children.Add(Bar(max > 0 ? pr.Seconds / max : 0, Accent, 110, 5));
            cell.Children.Add(T("  " + ShortDuration(pr.Seconds), 11.5, FontWeights.SemiBold));
            cell.Children.Add(T($"  %{Math.Round(pr.Share * 100)}", 10.5, muted: true));
            Cell(cell, r, 1);
            Cell(T(pr.Turns.ToString(CultureInfo.InvariantCulture), 11.5).Also(t => { t.TextAlignment = TextAlignment.Right; t.VerticalAlignment = VerticalAlignment.Center; }), r, 2);
            r++;
        }
        page.Children.Add(table);
        return page;
    }

    // MARK: Kullanım

    private static UIElement UsagePage()
    {
        var page = new StackPanel();
        page.Children.Add(T(L("Kullanım sınırları", "Usage limits"), 16, FontWeights.SemiBold).Also(t => t.Margin = new Thickness(0, 0, 0, 10)));
        var usage = _manager?.Insights.Usage.Current(DateTime.Now) ?? new List<UsageWindow>();
        if (usage.Count == 0)
        {
            page.Children.Add(T(L("Claude Code'un oturum (5 saat) ve haftalık limitini burada ve robotun altında görmek için durum satırını bağla. Senin durum satırın varsa görünmeye devam eder.",
                                   "Connect the status line to see Claude Code's session (5-hour) and weekly limits here and under the robot. Your own status line keeps showing."), 12, muted: true));
            if (UsageLine.IsConnected())
                page.Children.Add(T(L("Bağlı. Claude Code'da bir sonraki mesajda dolacak.", "Connected. It fills in with your next Claude Code message."), 11.5)
                    .Also(t => t.Margin = new Thickness(0, 8, 0, 0)));
            else
                page.Children.Add(Ui.Button(L("Durum satırını bağla", "Connect the status line"), () => { _setUsageLine?.Invoke(true); Rebuild(); }, primary: true)
                    .Also(b => { b.HorizontalAlignment = HorizontalAlignment.Left; b.Margin = new Thickness(0, 10, 0, 0); }));
        }
        else
        {
            var rings = new StackPanel { Orientation = Orientation.Horizontal };
            foreach (var w in usage)
            {
                var col = new StackPanel { Margin = new Thickness(0, 0, 44, 0) };
                col.Children.Add(new UsageDial(w.Percent, Accent) { Width = 100, Height = 100, HorizontalAlignment = HorizontalAlignment.Center });
                col.Children.Add(T(UsageLimits.Name(w.Kind), 13, FontWeights.SemiBold).Also(t => { t.TextAlignment = TextAlignment.Center; t.Margin = new Thickness(0, 8, 0, 2); }));
                var detail = string.Join(" · ", UsageLimits.Line(w, DateTime.Now).Split(" · ").Skip(1));
                col.Children.Add(T(detail, 11.5, muted: true).Also(t => t.TextAlignment = TextAlignment.Center));
                rings.Children.Add(col);
            }
            page.Children.Add(rings);
        }
        page.Children.Add(Ui.Themed(new Border { Height = 1, Margin = new Thickness(0, 16, 0, 12) }, bg: "CardBorder"));
        page.Children.Add(T(L("Bugün", "Today"), 16, FontWeights.SemiBold).Also(t => t.Margin = new Thickness(0, 0, 0, 8)));
        var today = DailyStats.Shared.Today(DateTime.Now).Where(kv => kv.Value.Turns > 0).OrderByDescending(kv => kv.Value.Seconds).ToList();
        if (today.Count == 0) page.Children.Add(T(L("Bugün henüz bir iş bitmedi.", "No work finished yet today."), 12, muted: true));
        foreach (var (src, d) in today)
        {
            var theme = Themes.Shared.Theme(src);
            var row = new StackPanel { Orientation = Orientation.Horizontal, Margin = new Thickness(0, 0, 0, 6) };
            row.Children.Add(new Ellipse(10, Color.FromRgb(theme.Color.R, theme.Color.G, theme.Color.B)) { Margin = new Thickness(0, 0, 10, 0), VerticalAlignment = VerticalAlignment.Center });
            row.Children.Add(T(theme.DisplayName, 12.5, FontWeights.SemiBold).Also(t => t.Width = 90));
            row.Children.Add(T(L($"{d.Turns} tur · {ShortDuration(d.Seconds)} · {d.Edits} düzenleme · {d.Waits} kez bekledi",
                                  $"{d.Turns} turns · {ShortDuration(d.Seconds)} · {d.Edits} edits · waited {d.Waits}×"), 12, muted: true));
            page.Children.Add(row);
        }
        return page;
    }

    // MARK: Çizim parçaları

    /// <summary>Dolu daire (rozet, renk noktası)</summary>
    private sealed class Ellipse : FrameworkElement
    {
        private readonly Color _color;

        public Ellipse(double size, Color color)
        {
            Width = size;
            Height = size;
            _color = color;
        }

        protected override void OnRender(DrawingContext dc)
        {
            var r = Width / 2;
            dc.DrawEllipse(new SolidColorBrush(_color), null, new Point(r, r), r, r);
            if (Width >= 18)
                dc.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromArgb(0x70, 0xFF, 0xFF, 0xFF)), Width * 0.06), new Point(r, r), r * 0.8, r * 0.8);
        }
    }

    /// <summary>Odadaki robot: kabuk, vizör, gözler ve takılı parçalar (RobotView.DrawOutfit ile)</summary>
    internal sealed class RobotPreview : FrameworkElement
    {
        private readonly Rgb _theme;
        private readonly IReadOnlyList<OutfitItem> _items;
        private readonly double _scale;
        private readonly bool _simple;
        private readonly string? _effect;
        private System.Windows.Threading.DispatcherTimer? _timer;

        /// <param name="effect">Efekt önizlemesi (kar, güneş…): verilirse saniyede 24 kez yeniden çizilir</param>
        public RobotPreview(Rgb theme, IReadOnlyList<OutfitItem> items, double scale, bool simple = false, string? effect = null)
        {
            _theme = theme;
            _items = items;
            _scale = scale;
            _simple = simple;
            _effect = effect;
            if (effect == null) return;
            Loaded += (_, _) =>
            {
                _timer = new System.Windows.Threading.DispatcherTimer { Interval = TimeSpan.FromMilliseconds(42) };
                _timer.Tick += (_, _) => InvalidateVisual();
                _timer.Start();
            };
            Unloaded += (_, _) => { _timer?.Stop(); _timer = null; };
        }

        protected override void OnRender(DrawingContext dc)
        {
            var w = ActualWidth;
            var h = ActualHeight;
            dc.PushTransform(new TranslateTransform((w - 100 * _scale) / 2, (h - 100 * _scale) / 2 + (_simple ? 4 : 8)));
            dc.PushTransform(new ScaleTransform(_scale, _scale));
            var t = (DateTime.UtcNow - DateTime.UnixEpoch).TotalSeconds;
            var e = Math.Pow(Math.Max(0, Math.Sin(t * 1.1)), 3);
            if (_effect != null && Effects.IsBackground(_effect)) RobotView.DrawEffect(dc, _effect, t, e);
            if (!_simple) dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(0x24, 0, 0, 0)), null, new Point(50, 96), 28, 3);
            RobotView.DrawShell(dc);
            var eye = new SolidColorBrush(Color.FromRgb(_theme.Mix(Rgb.White, 0.18).R, _theme.Mix(Rgb.White, 0.18).G, _theme.Mix(Rgb.White, 0.18).B));
            dc.DrawRoundedRectangle(eye, null, new Rect(31, 43, 10, 18), 5, 5);
            dc.DrawRoundedRectangle(eye, null, new Rect(59, 43, 10, 18), 5, 5);
            RobotView.DrawGlass(dc);
            RobotView.DrawOutfit(dc, _items, _theme);
            // Alındaki sağlık ışığı her zaman üstte (kep ve berede delikten görünür)
            dc.DrawEllipse(new SolidColorBrush(Color.FromArgb(0x4D, 0x33, 0xD4, 0x78)), null, new Point(50, 22.5), 5.5, 5.5);
            dc.DrawEllipse(new SolidColorBrush(Color.FromRgb(0x33, 0xD4, 0x78)), null, new Point(50, 22.5), 2.5, 2.5);
            if (_effect == "winter") RobotView.DrawSnow(dc, t);
            else if (_effect != null && !Effects.IsBackground(_effect)) RobotView.DrawEffect(dc, _effect, t, e);
            dc.Pop();
            dc.Pop();
        }
    }

    /// <summary>Kullanım halkası: ortada yüzde</summary>
    private sealed class UsageDial : FrameworkElement
    {
        private readonly int _percent;
        private readonly Color _accent;

        public UsageDial(int percent, Color accent)
        {
            _percent = percent;
            _accent = accent;
        }

        protected override void OnRender(DrawingContext dc)
        {
            var c = new Point(ActualWidth / 2, ActualHeight / 2);
            var r = Math.Min(ActualWidth, ActualHeight) / 2 - 6;
            dc.DrawEllipse(null, new Pen(new SolidColorBrush(Color.FromArgb(0x40, 0x80, 0x80, 0x80)), 8), c, r, r);
            var color = _percent >= 85 ? Color.FromRgb(0xF2, 0x54, 0x54) : _percent >= 60 ? Color.FromRgb(0xF5, 0xA8, 0x33) : _accent;
            var f = Math.Clamp(_percent / 100.0, 0, 1);
            var pen = new Pen(new SolidColorBrush(color), 8) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            if (f >= 0.999) dc.DrawEllipse(null, pen, c, r, r);
            else if (f > 0)
            {
                var a = f * 2 * Math.PI;
                var g = new StreamGeometry();
                using (var ctx = g.Open())
                {
                    ctx.BeginFigure(new Point(c.X, c.Y - r), false, false);
                    ctx.ArcTo(new Point(c.X + r * Math.Sin(a), c.Y - r * Math.Cos(a)), new Size(r, r), 0, f > 0.5, SweepDirection.Clockwise, true, false);
                }
                dc.DrawGeometry(null, pen, g);
            }
            var text = new FormattedText($"%{_percent}", CultureInfo.CurrentUICulture, FlowDirection.LeftToRight,
                new Typeface(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal), 22,
                Theme.IsDark ? Brushes.White : Brushes.Black, VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(text, new Point(c.X - text.Width / 2, c.Y - text.Height / 2));
        }
    }

    /// <summary>Emek grafiği: her gün AI'lara göre yığılmış çubuklar (saat)</summary>
    private sealed class EffortChart : FrameworkElement
    {
        private readonly Effort _effort;

        public EffortChart(Effort effort) => _effort = effort;

        protected override void OnRender(DrawingContext dc)
        {
            var w = ActualWidth;
            var h = ActualHeight;
            const double left = 34, bottom = 20, top = 6;
            var days = _effort.Days;
            if (days.Count == 0 || w <= left) return;
            var maxHours = Math.Max(1, days.Max(d => d.SecondsBySource.Values.Sum()) / 3600);
            var step = maxHours <= 4 ? 1 : maxHours <= 10 ? 2 : maxHours <= 24 ? 5 : 10;
            var axisMax = Math.Ceiling(maxHours / step) * step;
            var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
            var sub = Theme.IsDark ? Color.FromRgb(0xA8, 0xA8, 0xA8) : Color.FromRgb(0x5F, 0x5F, 0x5F);
            var grid = new Pen(new SolidColorBrush(Color.FromArgb(0x30, 0x80, 0x80, 0x80)), 1);
            var ui = new Typeface("Segoe UI");
            for (double v = 0; v <= axisMax + 0.001; v += step)
            {
                var y = h - bottom - (h - bottom - top) * (v / axisMax);
                dc.DrawLine(grid, new Point(left, y), new Point(w, y));
                var label = new FormattedText(L($"{v:0} sa", $"{v:0} h"), CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, ui, 10, new SolidColorBrush(sub), dpi);
                dc.DrawText(label, new Point(0, y - label.Height / 2));
            }
            var slot = (w - left) / days.Count;
            var barW = Math.Max(3, slot * 0.62);
            var order = _effort.BySource.OrderByDescending(kv => kv.Value).Select(kv => kv.Key).ToList();
            for (var i = 0; i < days.Count; i++)
            {
                var x = left + i * slot + (slot - barW) / 2;
                var y = h - bottom;
                foreach (var src in order)
                {
                    if (!days[i].SecondsBySource.TryGetValue(src, out var secs) || secs <= 0) continue;
                    var bh = (h - bottom - top) * (secs / 3600 / axisMax);
                    var c = Themes.Shared.Theme(src).Color;
                    dc.DrawRoundedRectangle(new SolidColorBrush(Color.FromRgb(c.R, c.G, c.B)), null, new Rect(x, y - bh, barW, Math.Max(0, bh)), 2, 2);
                    y -= bh;
                }
                var every = days.Count > 7 ? 7 : 1;
                if (i % every == 0 || i == days.Count - 1)
                {
                    var date = DateTime.ParseExact(days[i].Day, "yyyy-MM-dd", CultureInfo.InvariantCulture);
                    var culture = Lang.Current == TelepAIth.Core.Language.Tr ? new CultureInfo("tr-TR") : new CultureInfo("en-US");
                    var label = new FormattedText(date.ToString("d MMM", culture), culture, FlowDirection.LeftToRight, ui, 10, new SolidColorBrush(sub), dpi);
                    dc.DrawText(label, new Point(Math.Min(w - label.Width, x + barW / 2 - label.Width / 2), h - bottom + 4));
                }
            }
        }
    }
}
