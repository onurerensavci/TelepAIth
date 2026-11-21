using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using TelepAIth.Core;

namespace TelepAIth;

/// <summary>
/// Robotun çizimi. Her şey %100 boyutta 280 × 250 birimlik alanda çizilir, ayardaki robot boyutuyla ölçeklenir
/// (ekranın DPI'ını WPF zaten uygular). Mac'teki SwiftUI çizimiyle aynı ölçüler.
/// </summary>
internal sealed class RobotView : FrameworkElement
{
    private const double W = RobotAvatar.BaseWindowW, H = RobotAvatar.BaseWindowH, M = RobotAvatar.BaseMargin, Head = RobotAvatar.BaseHead;
    private const double BubbleMaxW = 220, TailW = 14, TailH = 8, Gap = 2;

    private readonly RobotAvatar _avatar;
    private static readonly DateTime Epoch = new(2001, 1, 1, 0, 0, 0, DateTimeKind.Utc);

    /// <summary>Son çizimde balonun ve kafanın yeri (pencere içi DIP) — tıklama ve tıklama-geçirgenlik için.</summary>
    public Rect BubbleRect { get; private set; } = Rect.Empty;
    public Rect HeadRect { get; private set; } = Rect.Empty;

    private RichLayout? _body;
    private string? _bodyKey;

    public RobotView(RobotAvatar avatar)
    {
        _avatar = avatar;
        SnapsToDevicePixels = false;
        RenderOptions.SetEdgeMode(this, EdgeMode.Unspecified);
    }

    private static double Seconds(DateTime d) => (d.ToUniversalTime() - Epoch).TotalSeconds;

    // MARK: Fırçalar (önbellekli; her karede yeniden oluşturmamak için)

    private static readonly Dictionary<uint, SolidColorBrush> BrushCache = new();

    private static SolidColorBrush B(Color c, double opacity = 1)
    {
        var a = (byte)Math.Round(Math.Clamp(opacity, 0, 1) * c.A);
        var key = ((uint)a << 24) | ((uint)c.R << 16) | ((uint)c.G << 8) | c.B;
        if (BrushCache.TryGetValue(key, out var b)) return b;
        b = new SolidColorBrush(Color.FromArgb(a, c.R, c.G, c.B));
        b.Freeze();
        if (BrushCache.Count > 4000) BrushCache.Clear();
        BrushCache[key] = b;
        return b;
    }

    private static Color C(double r, double g, double b) => Color.FromRgb((byte)(r * 255), (byte)(g * 255), (byte)(b * 255));
    private static Color C(Rgb c) => Color.FromRgb(c.R, c.G, c.B);

    private static readonly Brush ShellBrush = Frozen(new LinearGradientBrush(C(0.98, 0.97, 0.95), C(0.86, 0.84, 0.92), 90));
    private static readonly Color Visor = C(0.09, 0.08, 0.16);
    private static readonly Color Bolt = C(0.74, 0.71, 0.84);
    private static readonly Color Orange = C(1.0, 0.6, 0.2);
    private static readonly Color Muted = C(0.55, 0.52, 0.66);
    private static readonly Typeface Ui = new(new FontFamily("Segoe UI Variable Text, Segoe UI"), FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
    private static readonly Typeface UiSemi = new(new FontFamily("Segoe UI Variable Text, Segoe UI"), FontStyles.Normal, FontWeights.SemiBold, FontStretches.Normal);
    private static readonly Typeface UiBold = new(new FontFamily("Segoe UI"), FontStyles.Normal, FontWeights.Black, FontStretches.Normal);

    private static T Frozen<T>(T f) where T : Freezable { f.Freeze(); return f; }

    // MARK: Koyu tema (balon rengi)

    private static bool _dark;
    private static DateTime _darkChecked = DateTime.MinValue;

    private static bool Dark
    {
        get
        {
            if ((DateTime.Now - _darkChecked).TotalSeconds < 5) return _dark;
            _darkChecked = DateTime.Now;
            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
                _dark = key?.GetValue("AppsUseLightTheme") is int v && v == 0;
            }
            catch { _dark = false; }
            return _dark;
        }
    }

    // MARK: Çizim

    protected override void OnRender(DrawingContext dc)
    {
        // Pencere hangi ekranın ölçeğiyle çiziliyorsa ona göre: robot, kafanın bulunduğu ekranın ölçeğinde görünsün
        // (iki farklı ölçekli ekran arasında geçerken kesilmesin)
        var scale = _avatar.PixelScale / VisualTreeHelper.GetDpi(this).DpiScaleX;
        dc.PushTransform(new ScaleTransform(scale, scale));
        // Görünmez zemin yok: boş alanlar tamamen saydam (tıklamalar alttaki pencereye geçer)

        var model = _avatar.Current;
        var time = Seconds(DateTime.Now);
        var alignLeft = _avatar.AlignLeft;
        var below = _avatar.BubbleBelow;
        var urgent = model.State == RobotState.Waiting || model.State == RobotState.Error || model.BubbleIsExplicit;
        var focus = _avatar.Focus;

        var headX = alignLeft ? M : W - M - Head;
        var headY = below ? M : H - M - Head;
        HeadRect = new Rect(headX * scale, headY * scale, Head * scale, Head * scale);

        // Yeni robota geçerken küçük bir "belirme"
        var pop = Math.Min(1, (DateTime.Now - _avatar.CurrentSince).TotalSeconds / 0.25);
        var popScale = 0.4 + 0.6 * EaseOut(pop);

        dc.PushOpacity(focus && !urgent ? 0.5 : 1);
        dc.PushOpacity(pop);

        // Balon
        BubbleRect = Rect.Empty;
        if (model.BubbleText is { } text && (!focus || urgent))
        {
            var r = DrawBubble(dc, model, text, alignLeft, below, headY);
            BubbleRect = new Rect(r.X * scale, r.Y * scale, r.Width * scale, r.Height * scale);
        }

        // Kafa ve yanında minik kafalar
        dc.PushTransform(new ScaleTransform(popScale, popScale, headX + 50, headY + 50));
        dc.PushTransform(new TranslateTransform(headX, headY));
        DrawHead(dc, model, time, alignLeft ? 2.5 : -2.5);
        if (_avatar.Locked) DrawLock(dc);
        dc.Pop();
        dc.Pop();

        if (Prefs.MiniHeads && _avatar.Minis.Count > 0)
            DrawMinis(dc, _avatar.Minis, time, alignLeft ? headX + Head + 6 : headX - 6, headY + Head - 14, alignLeft);

        // Kafa ve balon her pikselinde tıklanabilir olsun (saydam pencerede tamamen saydam noktalar tıklamayı geçirir)
        var hit = B(Colors.Black, 0.004);
        dc.DrawRectangle(hit, null, new Rect(headX + 4, headY + 4, Head - 8, Head - 8));
        if (!BubbleRect.IsEmpty)
            dc.DrawRectangle(hit, null, new Rect(BubbleRect.X / scale, BubbleRect.Y / scale, BubbleRect.Width / scale, BubbleRect.Height / scale));

        dc.Pop();
        dc.Pop();
        dc.Pop();
    }

    private static double EaseOut(double t) => 1 - (1 - t) * (1 - t) * (1 - t);

    // MARK: Balon

    private Rect DrawBubble(DrawingContext dc, RobotModel model, string text, bool alignLeft, bool below, double headY)
    {
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var dark = Dark;
        var fill = dark ? Color.FromRgb(0x2B, 0x2A, 0x33) : Color.FromRgb(0xFB, 0xFA, 0xF8);
        var primary = dark ? Colors.White : Color.FromRgb(0x1E, 0x1C, 0x26);
        var secondary = dark ? Color.FromRgb(0xA8, 0xA5, 0xB8) : Color.FromRgb(0x77, 0x74, 0x86);
        var color = C(model.Theme.Color);
        var clickable = model.Target is { IsEmpty: false };

        const double padX = 10, padY = 7, titleH = 14;
        var maxCardH = H - 2 * M - Head - Gap - TailH;
        var innerMax = BubbleMaxW - 2 * padX;

        // Gövde: kelime kaydırmalı, renkli emojili yerleşim (yazı değişmedikçe yeniden hesaplanmaz)
        var maxBodyH = Math.Max(15, maxCardH - 2 * padY - titleH - 2);
        var key = $"{text}|{dark}|{_avatar.PixelScale}";
        if (_bodyKey != key || _body == null)
        {
            var lineH = 15.0;
            _body = RichLayout.Create(text, Ui, 11, B(primary), innerMax, Math.Max(1, (int)(maxBodyH / lineH)), _avatar.PixelScale);
            _bodyKey = key;
        }
        var body = _body;
        var title = new FormattedText(model.Theme.DisplayName, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, UiSemi, 10, B(color), dpi);
        FormattedText? sub = null;
        if (model.BubbleSubtitle is { } s)
        {
            sub = new FormattedText("· " + s, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, Ui, 10, B(secondary), dpi)
            {
                MaxTextWidth = Math.Max(10, innerMax - 11 - title.Width - 4 - (clickable ? 14 : 0)),
                MaxLineCount = 1,
                Trimming = TextTrimming.CharacterEllipsis,
            };
        }
        var titleW = 11 + title.Width + (sub != null ? 4 + sub.WidthIncludingTrailingWhitespace : 0) + (clickable ? 16 : 0);
        var innerW = Math.Min(innerMax, Math.Max(body.Width, titleW));
        var cardW = Math.Max(innerW + 2 * padX, 2 * 50 + 4);
        var cardH = padY + titleH + 2 + body.Height + padY;

        var cardX = alignLeft ? M : W - M - cardW;
        double cardY;
        if (below)
            cardY = headY + Head + Gap + TailH;
        else
            cardY = headY - Gap - TailH - cardH;

        var card = new Rect(cardX, cardY, cardW, cardH);
        var tailCx = alignLeft ? M + 50 : W - M - 50;
        var tail = new StreamGeometry();
        using (var g = tail.Open())
        {
            if (below)
            {
                g.BeginFigure(new Point(tailCx - TailW / 2, cardY + 0.5), true, true);
                g.LineTo(new Point(tailCx + TailW / 2, cardY + 0.5), true, false);
                g.LineTo(new Point(tailCx, cardY - TailH), true, false);
            }
            else
            {
                g.BeginFigure(new Point(tailCx - TailW / 2, cardY + cardH - 0.5), true, true);
                g.LineTo(new Point(tailCx + TailW / 2, cardY + cardH - 0.5), true, false);
                g.LineTo(new Point(tailCx, cardY + cardH + TailH), true, false);
            }
        }
        tail.Freeze();

        // Yumuşak gölge
        for (var i = 3; i >= 1; i--)
        {
            var sh = card;
            sh.Inflate(i, i);
            sh.Offset(0, 2);
            dc.DrawRoundedRectangle(B(Colors.Black, 0.045), null, sh, 12 + i, 12 + i);
        }
        dc.DrawRoundedRectangle(B(fill, 0.97), new Pen(B(color, 0.35), 1), card, 12, 12);
        dc.DrawGeometry(B(fill, 0.97), null, tail);

        // Başlık satırı: renkli nokta, uygulama adı, alt başlık, (tıklanabilirse) ↗
        var tx = cardX + padX;
        var ty = cardY + padY;
        dc.DrawEllipse(B(color), null, new Point(tx + 3.5, ty + titleH / 2), 3.5, 3.5);
        dc.DrawText(title, new Point(tx + 11, ty + (titleH - title.Height) / 2));
        if (sub != null) dc.DrawText(sub, new Point(tx + 11 + title.Width + 4, ty + (titleH - sub.Height) / 2));
        if (clickable)
        {
            // Küçük "dışarı git" işareti
            var ix = cardX + cardW - padX - 9;
            var iy = ty + 3;
            var pen = new Pen(B(secondary), 1.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
            dc.DrawRoundedRectangle(null, pen, new Rect(ix, iy + 1, 7, 7), 1.5, 1.5);
            dc.DrawLine(pen, new Point(ix + 4, iy + 4), new Point(ix + 9, iy - 1));
            dc.DrawLine(pen, new Point(ix + 6, iy - 1), new Point(ix + 9, iy - 1));
            dc.DrawLine(pen, new Point(ix + 9, iy - 1), new Point(ix + 9, iy + 2));
        }
        body.Draw(dc, new Point(tx, ty + titleH + 2));

        var full = card;
        full.Union(below ? new Point(tailCx, cardY - TailH) : new Point(tailCx, cardY + cardH + TailH));
        return full;
    }

    // MARK: Kafa

    private void DrawHead(DrawingContext dc, RobotModel model, double time, double look)
    {
        var state = model.State;
        var mood = model.Mood;
        var baseColor = model.Theme.Color;
        var eyeColor = C(baseColor.Mix(Rgb.White, 0.18));
        var accent = C(baseColor.Mix(Rgb.White, 0.55));

        var hop = HopHeight(model, time);
        var flt = FloatOffset(state, mood, time);
        var shake = ShakeOffset(model, time) + NudgeOffset(model, time);
        var lift = hop - flt;

        // Gölge
        dc.DrawEllipse(B(Colors.Black, 0.14), null, new Point(50, 96), Math.Max(24, 58 - lift * 1.5) / 2, 3);

        dc.PushTransform(new TranslateTransform(shake, -lift));

        if (model.QuotaLeft is { } left) DrawQuota(dc, left, C(baseColor.Mix(Rgb.White, 0.25)));

        dc.PushTransform(new RotateTransform(HeadTilt(state, mood, time), 50, 90));
        var skin = Skins.Image(model.Source, state);
        if (skin != null)
            dc.DrawImage(skin, FitRect(skin, new Rect(2, 3, 96, 90)));
        else
            DrawFace(dc, state, mood, time, look, eyeColor);
        dc.Pop();

        if (state is RobotState.Thinking or RobotState.Delegating or RobotState.Reading or RobotState.Searching)
            DrawWaves(dc, time, accent);
        dc.Pop();

        var celebrating = model.CelebrateStart is { } cs && Seconds(DateTime.Now) - Seconds(cs) is >= 0 and <= 1.6;
        if (celebrating || state == RobotState.Editing || mood is Mood.Party or Mood.Proud)
        {
            dc.PushTransform(new TranslateTransform(0, -lift));
            DrawSparkles(dc, time, accent, state == RobotState.Editing ? 40 : 50);
            dc.Pop();
        }
        if (state == RobotState.Sleeping) DrawZzz(dc, time);

        if (IsNudging(model, time))
        {
            dc.PushTransform(new TranslateTransform(shake, -lift));
            var s = 1 + 0.12 * Math.Sin(time * 6);
            dc.DrawEllipse(B(Orange), null, new Point(12, 16), 8.5 * s, 8.5 * s);
            var bang = Txt("!", UiBold, 11, Colors.White);
            dc.DrawText(bang, new Point(12 - bang.Width / 2, 16 - bang.Height / 2));
            dc.Pop();
        }
    }

    private static Rect FitRect(ImageSource img, Rect box)
    {
        var r = Math.Min(box.Width / img.Width, box.Height / img.Height);
        var w = img.Width * r;
        var h = img.Height * r;
        return new Rect(box.X + (box.Width - w) / 2, box.Y + (box.Height - h) / 2, w, h);
    }

    private FormattedText Txt(string s, Typeface face, double size, Color color) =>
        new(s, CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, size, B(color), VisualTreeHelper.GetDpi(this).PixelsPerDip);

    private void DrawFace(DrawingContext dc, RobotState state, Mood? mood, double time, double look, Color eyeColor)
    {
        dc.DrawEllipse(B(Bolt), null, new Point(6, 50), 6, 6);
        dc.DrawEllipse(B(Bolt), null, new Point(94, 50), 6, 6);
        dc.DrawRoundedRectangle(ShellBrush, null, new Rect(7, 15, 86, 70), 24, 24);
        dc.DrawRoundedRectangle(B(Visor), null, new Rect(15, 30, 70, 44), 18, 18);
        DrawEyes(dc, state, mood, time, look, eyeColor);

        // Alında sağlık ışığı
        var (led, op) = _avatar.Health switch
        {
            Health.Update => (C(1.0, 0.6, 0.2), 0.6 + 0.4 * Math.Sin(time * 3)),
            Health.Broken => (C(0.97, 0.3, 0.3), Math.Sin(time * 6) > 0 ? 1.0 : 0.3),
            _ => (C(0.2, 0.83, 0.47), state == RobotState.Sleeping ? 0.45 : 0.85 + 0.15 * Math.Sin(time * 2)),
        };
        dc.DrawEllipse(B(led, 0.3 * op), null, new Point(50, 22.5), 5.5, 5.5);
        dc.DrawEllipse(B(led, op), null, new Point(50, 22.5), 2.5, 2.5);
    }

    // MARK: Nokta matris gözler (her göz 14 × 18 nokta)

    private const int Cols = 14, Rows = 18;
    private const double Spacing = 1.75, Dot = 1.3;

    private static void DrawEyes(DrawingContext dc, RobotState state, Mood? mood, double time, double look, Color color)
    {
        var tint = state == RobotState.Error && mood == null ? C(1, 0.42, 0.42) : color;
        var dim = B(tint, 0.09);
        double[] centers = { 50 - 14, 50 + 14 };
        const double cy = 52;
        var midC = (Cols - 1) / 2.0;
        var midR = (Rows - 1) / 2.0;
        var blinking = state != RobotState.Waiting && mood == null && (time % 4.2) < 0.12;
        for (var eye = 0; eye < 2; eye++)
        {
            for (var r = 0; r < Rows; r++)
            {
                for (var c = 0; c < Cols; c++)
                {
                    var x = centers[eye] + (c - midC) * Spacing;
                    var y = cy + (r - midR) * Spacing;
                    var u = (c - midC) / 2 + 3;
                    var v = (r - midR) / 2 + 4;
                    var b = Brightness(state, mood, u, v, eye, time, look, blinking);
                    if (b > 0.05)
                    {
                        dc.DrawEllipse(B(tint, 0.25 * b), null, new Point(x, y), Dot / 2 + 0.8, Dot / 2 + 0.8);
                        dc.DrawEllipse(B(tint, b), null, new Point(x, y), Dot / 2, Dot / 2);
                    }
                    else
                    {
                        dc.DrawEllipse(dim, null, new Point(x, y), Dot / 2, Dot / 2);
                    }
                }
            }
        }
    }

    private static double Brightness(RobotState state, Mood? mood, double u, double v, int eye, double time, double look, bool blinking)
    {
        var lookShift = look / 2.5;
        if (mood is { } m)
        {
            return m switch
            {
                Mood.Pleased => Heart(u, v) * (0.8 + 0.2 * Math.Sin(time * 6)),
                Mood.Shocked => Capsule(u, v, 3, 4, 2.9, 4.2),
                Mood.Nervous => Capsule(u, v, 3 + Math.Sin(time * 14) * 1.1, 4.5, 1.2, 2),
                Mood.Scared => Capsule(u, v, 3 + Math.Sin(time * 40) * 0.4, 4, 1.4, 3.8),
                Mood.Proud or Mood.Party => Arc(u, v, 3, 6.2, 2.7),
                Mood.Tired => Capsule(u, v, 3, 5.2, 2.1, 1.1) * 0.8,
                Mood.Dizzy => Spiral(u, v, eye, time),
                _ => Capsule(u, v, 3, 6, 1.7, 1.3),
            };
        }
        if (blinking) return Capsule(u, v, 3 + lookShift, 4.5, 2, 0.5);
        return state switch
        {
            RobotState.Done => Arc(u, v, 3, 6.2, 2.7),
            RobotState.Error => Cross(u, v),
            RobotState.Sleeping => Math.Abs(v - 6) < 0.3 && Math.Abs(u - 3) <= 2.2 ? 0.5 : 0,
            RobotState.Thinking => Capsule(u, v, 3.9, 2.8, 1.5, 2.6),
            RobotState.Reading or RobotState.Searching => Capsule(u, v, 3 + Math.Sin(time * 3) * 1.5, 4.4, 1.5, 2.3),
            RobotState.Editing => Capsule(u, v, 3 + lookShift * 0.5, 5, 1.9, 1.5),
            RobotState.Running or RobotState.Delegating =>
                Capsule(u, v, 3, 4, 1.6, 2.8) * (0.75 + 0.25 * Math.Sin(time * 18 + u * 2.6 + v * 1.4)),
            RobotState.Waiting => Capsule(u, v, 3, 4, 2.5, 3.9) * (0.75 + 0.25 * Math.Sin(time * 6)),
            _ => Capsule(u, v, 3 + lookShift, 4, 1.7, 3.3),
        };
    }

    private static double Capsule(double u, double v, double cx, double cy, double rx, double ry)
    {
        var dx = (u - cx) / rx;
        var dy = (v - cy) / ry;
        var d = dx * dx + dy * dy;
        return d <= 1 ? 1 : d <= 1.22 ? 0.35 : 0;
    }

    private static double Arc(double u, double v, double cx, double cy, double radius)
    {
        if (v > cy) return 0;
        var d = Math.Sqrt((u - cx) * (u - cx) + (v - cy) * (v - cy));
        return Math.Abs(d - radius) < 0.45 ? 1 : 0;
    }

    private static double Cross(double u, double v)
    {
        var x = u - 3;
        var y = v - 4;
        if (Math.Abs(x) > 2.6 || Math.Abs(y) > 2.6) return 0;
        return Math.Abs(x - y) < 0.4 || Math.Abs(x + y) < 0.4 ? 1 : 0;
    }

    private static double Heart(double u, double v)
    {
        var x = (u - 3) / 2.6;
        var y = -(v - 4.3) / 2.6;
        var a = x * x + y * y - 1;
        return a * a * a - x * x * y * y * y <= 0 ? 1 : 0;
    }

    private static double Spiral(double u, double v, int eye, double time)
    {
        var x = u - 3;
        var y = v - 4;
        var d = Math.Sqrt(x * x + y * y);
        if (Math.Abs(d - 2.4) >= 0.5) return d < 0.45 ? 1 : 0;
        var angle = Math.Atan2(y, x);
        var phase = time * (eye == 0 ? 6 : -6);
        return 0.35 + 0.65 * Math.Max(0, Math.Cos(angle - phase));
    }

    // MARK: Hareketler

    private static double FloatOffset(RobotState state, Mood? mood, double t)
    {
        if (mood == Mood.Scared) return Math.Sin(t * 40) * 1.2;
        return state switch
        {
            RobotState.Idle => Math.Sin(t * 1.6) * 2.5,
            RobotState.Running => Math.Sin(t * 9) * 1.5,
            RobotState.Waiting => Math.Sin(t * 5) * 3,
            RobotState.Sleeping => -2 + Math.Sin(t * 0.8) * 1.2,
            RobotState.Done or RobotState.Error => 0,
            _ => Math.Sin(t * 3.2) * 3,
        };
    }

    private static double HeadTilt(RobotState state, Mood? mood, double t)
    {
        switch (mood)
        {
            case Mood.Dizzy: return Math.Sin(t * 6) * 9;
            case Mood.Tired: return 6;
            case Mood.Pleased: return Math.Sin(t * 3) * 4;
        }
        return state switch
        {
            RobotState.Thinking => Math.Sin(t * 1.2) * 5,
            RobotState.Reading or RobotState.Searching => Math.Sin(t * 2) * 3,
            RobotState.Sleeping => 8,
            _ => 0,
        };
    }

    private static double HopHeight(RobotModel m, double now)
    {
        if (m.CelebrateStart is not { } start) return 0;
        var t = now - Seconds(start);
        if (t < 0 || t > 1.3) return 0;
        return Math.Abs(Math.Sin(t * Math.PI * 2.3)) * 14;
    }

    private static double ShakeOffset(RobotModel m, double now)
    {
        if (m.ErrorStart is not { } start) return 0;
        var t = now - Seconds(start);
        if (t < 0 || t > 0.6) return 0;
        return Math.Sin(t * 45) * (1 - t / 0.6) * 5;
    }

    private static double? WaitAge(RobotModel m, double now)
    {
        if (!Prefs.WaitReminders || m.State != RobotState.Waiting || m.WaitingSince is not { } since) return null;
        return now - Seconds(since);
    }

    private static bool IsNudging(RobotModel m, double now) => (WaitAge(m, now) ?? 0) > 30;

    private static double NudgeOffset(RobotModel m, double now)
    {
        if (WaitAge(m, now) is not { } age || age <= 30) return 0;
        var phase = age % 4;
        if (phase >= 0.6) return 0;
        return Math.Sin(phase * 40) * (1 - phase / 0.6) * 4;
    }

    // MARK: Efektler

    private static void DrawWaves(DrawingContext dc, double time, Color color)
    {
        for (var i = 0; i < 2; i++)
        {
            var p = (time * 0.7 + i * 0.5) % 1;
            var size = 96 + p * 50;
            dc.DrawEllipse(null, new Pen(B(color, (1 - p) * 0.5), 1.3), new Point(50, 50), size / 2, size / 2);
        }
    }

    private static readonly Geometry SparkleShape = Frozen(Geometry.Parse("M0,-5 C0.6,-1.2 1.2,-0.6 5,0 C1.2,0.6 0.6,1.2 0,5 C-0.6,1.2 -1.2,0.6 -5,0 C-1.2,-0.6 -0.6,-1.2 0,-5 Z"));

    private static void DrawSparkles(DrawingContext dc, double time, Color color, double radius)
    {
        for (var i = 0; i < 3; i++)
        {
            var angle = time * 2 + i * 2.09;
            var x = 50 + Math.Cos(angle) * radius;
            var y = 50 + Math.Sin(angle) * radius * 0.6;
            dc.PushTransform(new TranslateTransform(x, y));
            dc.DrawGeometry(B(color, 0.5 + 0.5 * Math.Sin(time * 5 + i)), null, SparkleShape);
            dc.Pop();
        }
    }

    private void DrawZzz(DrawingContext dc, double time)
    {
        for (var i = 0; i < 3; i++)
        {
            var p = (time * 0.6 + i / 3.0) % 1;
            var z = new FormattedText("z", CultureInfo.InvariantCulture, FlowDirection.LeftToRight, UiSemi, 10 + i * 2,
                B(Muted, 1 - p), VisualTreeHelper.GetDpi(this).PixelsPerDip);
            dc.DrawText(z, new Point(82 + p * 12 - z.Width / 2, 22 - p * 22 - z.Height / 2));
        }
    }

    private static void DrawQuota(DrawingContext dc, int left, Color color)
    {
        var fraction = Math.Clamp(left, 0, 100) / 100.0;
        var tint = left <= 20 ? C(0.97, 0.35, 0.35) : color;
        const double r = 49;
        dc.DrawEllipse(null, new Pen(B(Colors.White, 0.18), 2.5), new Point(50, 50), r, r);
        if (fraction <= 0) return;
        var pen = new Pen(B(tint), 2.5) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        if (fraction >= 0.999)
        {
            dc.DrawEllipse(null, pen, new Point(50, 50), r, r);
            return;
        }
        var angle = fraction * 2 * Math.PI;
        var end = new Point(50 + r * Math.Sin(angle), 50 - r * Math.Cos(angle));
        var g = new StreamGeometry();
        using (var ctx = g.Open())
        {
            ctx.BeginFigure(new Point(50, 50 - r), false, false);
            ctx.ArcTo(end, new Size(r, r), 0, fraction > 0.5, SweepDirection.Clockwise, true, false);
        }
        g.Freeze();
        dc.DrawGeometry(null, pen, g);
    }

    private static void DrawLock(DrawingContext dc)
    {
        var c = new Point(89.5, 16.5);
        dc.DrawEllipse(B(C(0.97, 0.96, 0.94)), null, c, 8.5, 8.5);
        var pen = new Pen(B(Muted), 1.4);
        dc.DrawRoundedRectangle(B(Muted), null, new Rect(c.X - 3.5, c.Y - 1, 7, 5.5), 1, 1);
        var g = new StreamGeometry();
        using (var ctx = g.Open())
        {
            ctx.BeginFigure(new Point(c.X - 2.2, c.Y - 0.5), false, false);
            ctx.LineTo(new Point(c.X - 2.2, c.Y - 2.5), true, false);
            ctx.ArcTo(new Point(c.X + 2.2, c.Y - 2.5), new Size(2.2, 2.2), 0, false, SweepDirection.Clockwise, true, false);
            ctx.LineTo(new Point(c.X + 2.2, c.Y - 0.5), true, false);
        }
        g.Freeze();
        dc.DrawGeometry(null, pen, g);
    }

    // MARK: Minik kafalar

    private void DrawMinis(DrawingContext dc, List<RobotModel.MiniSession> minis, double time, double edgeX, double bottomY, bool growRight)
    {
        var shown = minis.Take(4).ToList();
        var extra = minis.Count - shown.Count;
        const double w = 22, h = 18, gap = 4;
        var x = growRight ? edgeX : edgeX - (shown.Count * (w + gap) - gap) - (extra > 0 ? 18 : 0);
        for (var i = 0; i < shown.Count; i++)
        {
            var mini = shown[i];
            var t = time + i * 0.7;
            var waiting = mini.State == RobotState.Waiting;
            var bob = Math.Sin(t * (waiting ? 5 : 3)) * (waiting ? 2 : 1.2);
            var cx = x + i * (w + gap) + w / 2;
            var cy = bottomY - h / 2 - bob;
            var color = C(Themes.Shared.Theme(mini.Source).Color.Mix(Rgb.White, 0.18));
            dc.DrawRoundedRectangle(B(Colors.Black, 0.1), null, new Rect(cx - w / 2, cy - h / 2 + 1, w, h), 6, 6);
            dc.DrawRoundedRectangle(ShellBrush, null, new Rect(cx - w / 2, cy - h / 2, w, h), 6, 6);
            dc.DrawRoundedRectangle(B(Visor), null, new Rect(cx - 8.5, cy - 4, 17, 10), 4, 4);
            var eh = waiting ? 6 : 5;
            dc.DrawRoundedRectangle(B(color), null, new Rect(cx - 3.5 - 1.5, cy + 1 - eh / 2.0, 3, eh), 1.5, 1.5);
            dc.DrawRoundedRectangle(B(color), null, new Rect(cx + 3.5 - 1.5, cy + 1 - eh / 2.0, 3, eh), 1.5, 1.5);
            if (waiting) dc.DrawEllipse(B(Orange), null, new Point(cx + 10, cy - 8), 3, 3);
        }
        if (extra > 0)
        {
            var more = Txt("+" + extra, UiBold, 9, Muted);
            var mx = growRight ? x + shown.Count * (w + gap) : x + shown.Count * (w + gap);
            dc.DrawText(more, new Point(mx, bottomY - h / 2 - more.Height / 2));
        }
    }
}

/// <summary>Kendi robot görünüşü: ~/.telepaith/skins/&lt;kaynak&gt;/&lt;durum&gt;.png (yoksa skins/default).</summary>
internal static class Skins
{
    private static readonly Dictionary<string, Dictionary<RobotState, ImageSource>> Cache = new();

    public static void Reload()
    {
        lock (Cache) Cache.Clear();
    }

    public static bool HasSkin(string source) => Load(source).Count > 0;

    public static ImageSource? Image(string source, RobotState state)
    {
        var images = Load(source);
        if (images.Count == 0) return null;
        if (images.TryGetValue(state, out var img)) return img;
        if (state == RobotState.Delegating && images.TryGetValue(RobotState.Thinking, out img)) return img;
        return images.TryGetValue(RobotState.Idle, out img) ? img : null;
    }

    private static Dictionary<RobotState, ImageSource> Load(string source)
    {
        lock (Cache)
        {
            if (Cache.TryGetValue(source, out var cached)) return cached;
            var result = LoadFolder(Path.Combine(AppInfo.SkinsDir, source));
            if (result.Count == 0) result = LoadFolder(Path.Combine(AppInfo.SkinsDir, "default"));
            Cache[source] = result;
            return result;
        }
    }

    private static Dictionary<RobotState, ImageSource> LoadFolder(string folder)
    {
        var result = new Dictionary<RobotState, ImageSource>();
        if (!Directory.Exists(folder)) return result;
        foreach (var state in Enum.GetValues<RobotState>())
        {
            var file = Path.Combine(folder, state.ToString().ToLowerInvariant() + ".png");
            if (!File.Exists(file)) continue;
            try
            {
                var bmp = new BitmapImage();
                bmp.BeginInit();
                bmp.CacheOption = BitmapCacheOption.OnLoad;
                bmp.UriSource = new Uri(file);
                bmp.EndInit();
                bmp.Freeze();
                result[state] = bmp;
            }
            catch { }
        }
        return result;
    }
}
