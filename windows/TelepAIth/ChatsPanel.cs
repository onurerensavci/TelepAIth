using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using TelepAIth.Core;
using static TelepAIth.Core.Text;

namespace TelepAIth;

/// <summary>
/// Robota tıklayınca açılan Sohbetler paneli: bütün sohbetler, gruplu ve kaydırılabilir
/// (Seni bekliyor · Yeni bitti · Çalışıyor · Bitti). Satıra tıklayınca o sohbet açılır.
/// Robotun penceresinden ayrı bir penceredir, sohbet sayısı sınırlı değildir. (Mac'te ChatsPanel.swift)
/// </summary>
internal sealed class ChatsPanel
{
    private Window? _window;
    private StackPanel? _list;
    private TextBlock? _summary;
    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private string _lastKey = "";

    /// <summary>Dışarı tıklanınca kapandığı an: aynı tıklama robota geldiyse paneli yeniden açmasın</summary>
    public DateTime ClosedAt { get; private set; } = DateTime.MinValue;
    /// <summary>Satırları her saniye tazeler (süreler ilerler, yeni sohbetler eklenir)</summary>
    public Func<List<RobotModel.ChatRow>> Rows { get; set; } = () => new();
    public Action<RobotModel.ChatRow>? Open { get; set; }
    /// <summary>Şu an gösterilen satırlar (duman testi için)</summary>
    public List<RobotModel.ChatRow>? Shown { get; private set; }

    public bool IsOpen => _window?.IsVisible == true;

    public ChatsPanel()
    {
        _timer.Tick += (_, _) => Refresh(false);
    }

    /// <summary>Robotun kafasının yanında aç (kafanın ortası ve boyu fiziksel piksel; m: kafanın olduğu ekran)</summary>
    public void Show(double headX, double headY, double headPx, Native.Monitor m)
    {
        var w = _window ?? Build();
        _window = w;
        Refresh(true);
        w.Show();
        w.UpdateLayout();
        // Kafa ekranın sağındaysa soluna, solundaysa sağına; üst kenarı kafayla hizalı, ekrana sığsın (fiziksel piksel)
        var s = m.Scale;
        var width = (w.ActualWidth > 0 ? w.ActualWidth : 352) * s;
        var height = (w.ActualHeight > 0 ? w.ActualHeight : 300) * s;
        var gap = 6 * s;
        var work = m.Work;
        var x = headX > (work.Left + work.Right) / 2.0 ? headX - headPx / 2 - gap - width : headX + headPx / 2 + gap;
        x = Math.Min(Math.Max(x, work.Left + 4 * s), work.Right - width - 4 * s);
        var y = Math.Min(Math.Max(headY - headPx / 2, work.Top + 4 * s), work.Bottom - height - 4 * s);
        var hwnd = new System.Windows.Interop.WindowInteropHelper(w).Handle;
        const uint SWP_NOSIZE = 0x0001, SWP_NOZORDER = 0x0004;
        Native.SetWindowPos(hwnd, IntPtr.Zero, (int)Math.Round(x), (int)Math.Round(y), 0, 0, SWP_NOSIZE | SWP_NOZORDER);
        w.Activate();
        _timer.Start();
    }

    public void Close()
    {
        if (_window is not { IsVisible: true } w) return;
        _timer.Stop();
        w.Hide();
        Shown = null;
        ClosedAt = DateTime.Now;
    }

    private Window Build()
    {
        var dark = Theme.IsDark;
        var w = new Window
        {
            WindowStyle = WindowStyle.None, AllowsTransparency = true, Background = Brushes.Transparent,
            ShowInTaskbar = false, Topmost = true, ResizeMode = ResizeMode.NoResize, SizeToContent = SizeToContent.Height,
            Width = 352, FontFamily = new FontFamily(Theme.Font), Title = L("Sohbetler", "Chats"),
        };
        var root = new StackPanel();
        var header = new DockPanel { Margin = new Thickness(14, 12, 14, 8) };
        _summary = new TextBlock { FontSize = 11, Foreground = Muted(dark), VerticalAlignment = VerticalAlignment.Bottom };
        DockPanel.SetDock(_summary, Dock.Right);
        header.Children.Add(_summary);
        header.Children.Add(new TextBlock { Text = L("Sohbetler", "Chats"), FontSize = 14, FontWeight = FontWeights.Bold, Foreground = Fore(dark) });
        root.Children.Add(header);
        root.Children.Add(new Border { Height = 1, Background = new SolidColorBrush(Color.FromArgb(0x22, 0x80, 0x80, 0x80)) });
        _list = new StackPanel { Margin = new Thickness(8) };
        root.Children.Add(new ScrollViewer
        {
            Content = _list, MaxHeight = 430, VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
        });
        w.Content = new Border
        {
            Child = root, CornerRadius = new CornerRadius(14), Margin = new Thickness(10),
            Background = new SolidColorBrush(dark ? Color.FromRgb(0x2B, 0x2A, 0x33) : Color.FromRgb(0xFB, 0xFA, 0xF8)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(0x26, 0x80, 0x80, 0x80)), BorderThickness = new Thickness(1),
            Effect = new DropShadowEffect { BlurRadius = 18, ShadowDepth = 3, Opacity = 0.3 },
        };
        // Dışarı tıklanınca (başka pencere öne gelince) ya da Esc'e basınca kapanır
        w.Deactivated += (_, _) => Close();
        w.KeyDown += (_, e) => { if (e.Key == Key.Escape) Close(); };
        return w;
    }

    private static Brush Fore(bool dark) => dark ? Brushes.White : new SolidColorBrush(Color.FromRgb(0x1E, 0x1C, 0x26));
    private static Brush Muted(bool dark) => new SolidColorBrush(dark ? Color.FromRgb(0xA8, 0xA5, 0xB8) : Color.FromRgb(0x77, 0x74, 0x86));

    /// <summary>Satırları tazele: liste değiştiyse baştan kur, değilse sadece süreleri güncelle</summary>
    private void Refresh(bool force)
    {
        if (_list == null || _summary == null) return;
        var rows = Rows();
        Shown = rows;
        _summary.Text = rows.Count == 0 ? "" : DisplayPicker.ChatSummary(rows);
        var key = string.Join("|", rows.Select(r => $"{r.Source}/{r.SessionId}/{r.Rank}/{r.State}/{r.Unread}/{r.Title}/{r.Label}"));
        if (!force && key == _lastKey) return;
        _lastKey = key;
        var dark = Theme.IsDark;
        _list.Children.Clear();
        if (rows.Count == 0)
        {
            _list.Children.Add(new TextBlock { Text = L("Şu an sohbet yok", "No chats right now"), FontSize = 12.5, FontWeight = FontWeights.Medium, Foreground = Fore(dark), Margin = new Thickness(6, 4, 6, 2) });
            _list.Children.Add(new TextBlock
            {
                Text = L("Bir sohbet çalışınca, seni bekleyince ya da bitince burada görünür; son 2 saatte bitenler de kalır.",
                    "Chats show up here when they work, need you or finish; ones finished in the last 2 hours stay too."),
                FontSize = 11, Foreground = Muted(dark), TextWrapping = TextWrapping.Wrap, Margin = new Thickness(6, 0, 6, 6),
            });
            return;
        }
        // Gruplar: seni bekleyenler, yeni bitenler (bakılmamış), çalışanlar, bitenler
        var groups = new (int Rank, string Title)[]
        {
            (0, L("Seni bekliyor", "Needs you")), (1, L("Yeni bitti", "Just finished")), (2, L("Çalışıyor", "Working")), (3, L("Bitti", "Done")),
        };
        foreach (var (rank, title) in groups)
        {
            var g = rows.Where(r => r.Rank == rank).ToList();
            if (g.Count == 0) continue;
            _list.Children.Add(new TextBlock
            {
                Text = $"{title.ToUpper(System.Globalization.CultureInfo.CurrentUICulture)}  {g.Count}", FontSize = 10, FontWeight = FontWeights.SemiBold,
                Foreground = Muted(dark), Margin = new Thickness(6, _list.Children.Count == 0 ? 0 : 8, 6, 3),
            });
            foreach (var row in g) _list.Children.Add(RowView(row, dark));
        }
    }

    /// <summary>Satırın renk kodu (Mac'te ChatListBubble.toneColor, aynı renkler)</summary>
    private static Color ToneColor(string tone, Color ai) => tone switch
    {
        "waiting" => Color.FromRgb(0xF5, 0x8C, 0x1A),
        "working" => ai,
        "error" => Color.FromRgb(0xE6, 0x4D, 0x4D),
        "fresh" => Color.FromRgb(0x33, 0xB8, 0x66),
        _ => Color.FromRgb(0x8E, 0x8C, 0x99),
    };

    private static Color A(Color c, double a) => Color.FromArgb((byte)(255 * Math.Clamp(a, 0, 1)), c.R, c.G, c.B);

    /// <summary>Bir sohbet satırı: AI şeridi, durum simgesi, ad, uygulama ve durum, süre; renk kodlu zemin</summary>
    private UIElement RowView(RobotModel.ChatRow row, bool dark)
    {
        var theme = Themes.Shared.Theme(row.Source);
        var ai = Color.FromRgb(theme.Color.R, theme.Color.G, theme.Color.B);
        var tone = ToneColor(row.Tone, ai);
        var seen = row.Tone == "seen";
        var baseAlpha = seen ? 0.06 : 0.14;

        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        // Hangi AI: solda ince şerit
        grid.Children.Add(new Border { Width = 3, Height = 26, CornerRadius = new CornerRadius(1.5), Background = new SolidColorBrush(ai), Margin = new Thickness(0, 0, 8, 0) });
        var icon = StateIcon(row.State, row.Tone, ai);
        Grid.SetColumn(icon, 1);
        grid.Children.Add(icon);
        var texts = new StackPanel { Margin = new Thickness(8, 0, 6, 0), VerticalAlignment = VerticalAlignment.Center };
        texts.Children.Add(new TextBlock
        {
            Text = row.Title, FontSize = 12.5, FontWeight = row.Unread ? FontWeights.Bold : FontWeights.Medium,
            Foreground = seen ? Muted(dark) : Fore(dark), TextTrimming = TextTrimming.CharacterEllipsis,
        });
        texts.Children.Add(new TextBlock { Text = theme.DisplayName + " · " + Kind(row), FontSize = 10.5, Foreground = Muted(dark), TextTrimming = TextTrimming.CharacterEllipsis });
        Grid.SetColumn(texts, 2);
        grid.Children.Add(texts);
        var right = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        right.Children.Add(new TextBlock
        {
            Text = row.Label, FontSize = 11, FontWeight = seen ? FontWeights.Normal : FontWeights.SemiBold,
            Foreground = seen ? Muted(dark) : new SolidColorBrush(tone), VerticalAlignment = VerticalAlignment.Center,
        });
        if (row.Unread)
            right.Children.Add(new System.Windows.Shapes.Ellipse { Width = 7, Height = 7, Fill = new SolidColorBrush(Color.FromRgb(0x0A, 0x84, 0xFF)), Margin = new Thickness(6, 0, 0, 0) });
        Grid.SetColumn(right, 3);
        grid.Children.Add(right);

        var fill = new SolidColorBrush(A(tone, baseAlpha));
        var layers = new Grid();
        // Çalışıyor: satırın üstünden ışık geçer
        if (row.Tone == "working")
        {
            var sweep = new LinearGradientBrush { StartPoint = new Point(0, 0.5), EndPoint = new Point(1, 0.5), MappingMode = BrushMappingMode.RelativeToBoundingBox };
            var s0 = new GradientStop(A(tone, 0), 0);
            var s1 = new GradientStop(A(tone, 0.35), 0.2);
            var s2 = new GradientStop(A(tone, 0), 0.4);
            sweep.GradientStops.Add(s0);
            sweep.GradientStops.Add(s1);
            sweep.GradientStops.Add(s2);
            var move = new TranslateTransform();
            sweep.RelativeTransform = move;
            move.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(-0.4, 1.0, TimeSpan.FromSeconds(2)) { RepeatBehavior = RepeatBehavior.Forever });
            layers.Children.Add(new Border { CornerRadius = new CornerRadius(8), Background = sweep });
        }
        layers.Children.Add(grid);
        var card = new Border
        {
            Child = layers, CornerRadius = new CornerRadius(8), Padding = new Thickness(8, 6, 8, 6), Margin = new Thickness(0, 0, 0, 3),
            Background = fill, Cursor = Cursors.Hand, ToolTip = row.Title,
        };
        // Seni bekliyor: kenarı atar
        if (row.Tone == "waiting")
        {
            var edge = new SolidColorBrush(A(tone, 0.6));
            card.BorderBrush = edge;
            card.BorderThickness = new Thickness(1.2);
            edge.BeginAnimation(Brush.OpacityProperty, new DoubleAnimation(0.45, 1, TimeSpan.FromSeconds(0.8)) { AutoReverse = true, RepeatBehavior = RepeatBehavior.Forever });
        }
        card.MouseEnter += (_, _) => card.Background = new SolidColorBrush(A(tone, baseAlpha + 0.12));
        card.MouseLeave += (_, _) => card.Background = fill;
        card.MouseLeftButtonUp += (_, _) =>
        {
            Close();
            Open?.Invoke(row);
        };
        return card;
    }

    /// <summary>Durum simgesi: dönen halka (çalışıyor), turuncu ! (seni bekliyor), yeşil ✓ (bitti), kırmızı ✕ (hata)</summary>
    private static FrameworkElement StateIcon(RobotState state, string tone, Color ai)
    {
        const double size = 14;
        if (tone == "working")
        {
            var ring = new Grid { Width = size, Height = size, VerticalAlignment = VerticalAlignment.Center };
            ring.Children.Add(new System.Windows.Shapes.Ellipse { Stroke = new SolidColorBrush(A(ai, 0.25)), StrokeThickness = 2 });
            var arc = new System.Windows.Shapes.Path
            {
                Stroke = new SolidColorBrush(ai), StrokeThickness = 2, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
                Data = Geometry.Parse("M 7,1 A 6,6 0 0 1 12.7,5.1"), RenderTransformOrigin = new Point(0.5, 0.5),
            };
            var spin = new RotateTransform();
            arc.RenderTransform = spin;
            spin.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, 360, TimeSpan.FromSeconds(1)) { RepeatBehavior = RepeatBehavior.Forever });
            ring.Children.Add(arc);
            return ring;
        }
        var color = tone switch
        {
            "waiting" => Color.FromRgb(0xF5, 0x8C, 0x1A),
            "error" => Color.FromRgb(0xE6, 0x4D, 0x4D),
            _ => state == RobotState.Error ? Color.FromRgb(0xE6, 0x4D, 0x4D) : Color.FromRgb(0x33, 0xB8, 0x66),
        };
        var glyph = tone == "waiting" ? "!" : (tone == "error" || state == RobotState.Error) ? "✕" : "✓";
        return new Border
        {
            Width = size, Height = size, CornerRadius = new CornerRadius(size / 2), Background = new SolidColorBrush(color), VerticalAlignment = VerticalAlignment.Center,
            Child = new TextBlock { Text = glyph, FontSize = 9, FontWeight = FontWeights.Bold, Foreground = Brushes.White, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center },
        };
    }

    /// <summary>Ne tür sohbet: uygulamada açık olan, uygulamada arkada, terminal (Claude Code / Codex)</summary>
    private static string Kind(RobotModel.ChatRow row) =>
        row.SessionId.StartsWith("app-", StringComparison.Ordinal) ? L("uygulamada açık", "open in the app")
        : row.SessionId.StartsWith("bg-", StringComparison.Ordinal) ? L("uygulamada arkada", "in the app, background")
        : L("terminal", "terminal");
}
