using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Microsoft.Win32;
using TelepAIth.Core;
using static TelepAIth.Core.Text;

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
    private double _hover, _lastFaceTime;

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
        // İzin sorusu: altta düğme satırı (balon biraz genişler)
        var approval = _avatar.Approval;
        var buttons = approval == null ? null : ApprovalButtons(approval, dpi);
        var rowW = buttons?.Sum(b => b.W) + (buttons?.Count - 1) * ButtonGap ?? 0;
        if (buttons != null) maxCardH -= ButtonRowH + 6;
        var innerMax = Math.Max(BubbleMaxW - 2 * padX, Math.Min(W - 2 * M - 2 * padX, rowW));

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
        var innerW = Math.Min(innerMax, Math.Max(Math.Max(body.Width, titleW), rowW));
        var cardW = Math.Max(innerW + 2 * padX, 2 * 50 + 4);
        var cardH = padY + titleH + 2 + body.Height + padY + (buttons != null ? ButtonRowH + 6 : 0);

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

        // Düğmeler: İzin ver · Hep izin ver · Reddet
        ButtonRects.Clear();
        if (buttons != null)
        {
            var scale = _avatar.PixelScale / VisualTreeHelper.GetDpi(this).DpiScaleX;
            var bx = tx;
            var by = ty + titleH + 2 + body.Height + 6;
            var hover = Mouse.GetPosition(this);
            foreach (var b in buttons)
            {
                var r = new Rect(bx, by, b.W, ButtonRowH);
                var screenRect = new Rect(r.X * scale, r.Y * scale, r.Width * scale, r.Height * scale);
                ButtonRects[b.Choice] = screenRect;
                var over = screenRect.Contains(hover);
                var (bg, fg, border) = b.Choice switch
                {
                    ApprovalChoice.Allow => (Allow, Colors.White, Allow),
                    ApprovalChoice.Deny => (Colors.Transparent, Deny, Deny),
                    _ => (Colors.Transparent, color, color),
                };
                dc.DrawRoundedRectangle(bg == Colors.Transparent ? B(border, over ? 0.16 : 0.07) : B(bg, over ? 0.85 : 1),
                    new Pen(B(border, 0.75), 1), r, ButtonRowH / 2, ButtonRowH / 2);
                var label = new FormattedText(b.Label, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, UiSemi, 10.5, B(fg), dpi);
                dc.DrawText(label, new Point(r.X + (r.Width - label.Width) / 2, r.Y + (r.Height - label.Height) / 2));
                bx += b.W + ButtonGap;
            }
        }

        var full = card;
        full.Union(below ? new Point(tailCx, cardY - TailH) : new Point(tailCx, cardY + cardH + TailH));
        return full;
    }

    // MARK: Onay düğmeleri

    private const double ButtonRowH = 22, ButtonGap = 6;
    private static readonly Color Allow = Color.FromRgb(0x23, 0x9B, 0x56);
    private static readonly Color Deny = Color.FromRgb(0xE0, 0x4F, 0x4F);

    /// <summary>Düğmelerin pencere içindeki yeri (DIP) — tıklama için</summary>
    public Dictionary<ApprovalChoice, Rect> ButtonRects { get; } = new();

    public ApprovalChoice? ButtonAt(Point p)
    {
        foreach (var (choice, r) in ButtonRects)
            if (r.Contains(p)) return choice;
        return null;
    }

    private sealed record ButtonSpec(ApprovalChoice Choice, string Label, double W);

    private static List<ButtonSpec> ApprovalButtons(ApprovalPrompt approval, double dpi)
    {
        var list = new List<(ApprovalChoice, string)> { (ApprovalChoice.Allow, L("İzin ver", "Allow")) };
        if (approval.HasAlways) list.Add((ApprovalChoice.Always, L("Hep izin ver", "Always")));
        list.Add((ApprovalChoice.Deny, L("Reddet", "Deny")));
        return list.Select(x =>
        {
            var w = new FormattedText(x.Item2, CultureInfo.CurrentUICulture, FlowDirection.LeftToRight, UiSemi, 10.5, Brushes.Black, dpi).Width;
            return new ButtonSpec(x.Item1, x.Item2, Math.Ceiling(w) + 22);
        }).ToList();
    }

    // MARK: Kafa

    private void DrawHead(DrawingContext dc, RobotModel model, double time, double look)
    {
        var state = model.State;
        var mood = model.Mood;
        var baseColor = model.Theme.Color;
        var eyeColor = C(baseColor.Mix(Rgb.White, 0.18));
        var accent = C(baseColor.Mix(Rgb.White, 0.55));

        // Yüz değişince (ör. düşünüyor → bitti) 0,35 sn'de yumuşak geçiş
        var blend = IdleMotion.Smooth((time - Seconds(model.VisualChangedAt == DateTime.MinValue ? Epoch : model.VisualChangedAt)) / 0.35);
        var idle = state == RobotState.Idle && mood == null ? IdleMotion.At(time) : default;
        var hop = HopHeight(model, time);
        var flt = Mix(FloatOffset(model.PreviousState, model.PreviousMood, time), FloatOffset(state, mood, time), blend);
        var shake = ShakeOffset(model, time) + NudgeOffset(model, time) + idle.Dx;
        var lift = hop - flt + idle.Lift;
        var tilt = Mix(HeadTilt(model.PreviousState, model.PreviousMood, time), HeadTilt(state, mood, time), blend) + idle.Tilt;

        // Gözde simge: ? soru, ! onay bekliyor, ✓ yeni bitti, % kota azaldı
        var stateAge = time - Seconds(model.VisualChangedAt == DateTime.MinValue ? Epoch : model.VisualChangedAt);
        var glyph = model.EyeGlyph(DateTime.Now);
        var prevGlyph = model.PreviousState == RobotState.Waiting ? '!' : '\0';

        // Hiçbir sohbet çalışmıyorken ve son iş biteli 20 sn olunca imlece bak; üstüne gelince gözlerini kısıp gülümse
        var dt = Math.Clamp(time - _lastFaceTime, 0, 0.1);
        _lastFaceTime = time;
        double lookU = look / 2.5, lookV = 0, hoverTarget = 0;
        if (_avatar.GazeAllowed && state is RobotState.Idle or RobotState.Done or RobotState.Error && mood is null)
        {
            var c = Native.Cursor();
            var px = _avatar.PixelScale;
            double cdx = c.X - _avatar.HeadX, cdy = c.Y - _avatar.HeadY;
            var dist = Math.Sqrt(cdx * cdx + cdy * cdy);
            if (dist < 900 * px)
            {
                lookU = Math.Clamp(cdx / (220 * px), -1, 1) * 1.6;
                lookV = Math.Clamp(cdy / (220 * px), -1, 1) * 0.9;
            }
            if (dist < _avatar.HeadPx * 0.45) hoverTarget = 1;
        }
        _hover += (hoverTarget - _hover) * Math.Min(1, dt * 8);
        var winter = WinterActive;
        var face = new FaceCtx(state, mood, model.PreviousState, model.PreviousMood, blend, idle, glyph, prevGlyph, lookU, lookV, _hover, winter);
        var gt = model.GestureStart is { } gs ? Seconds(DateTime.Now) - Seconds(gs) : -1;
        var right = look > 0;   // balonun açıldığı taraf (ekranın içi)

        // Gölge
        dc.DrawEllipse(B(Colors.Black, 0.14), null, new Point(50, 96), Math.Max(24, 58 - lift * 1.5) / 2, 3);

        dc.PushTransform(new TranslateTransform(shake, -lift));

        if (model.QuotaLeft is { } left) DrawQuota(dc, left, C(baseColor.Mix(Rgb.White, 0.25)));

        dc.PushTransform(new RotateTransform(tilt, 50, 90));
        var skin = Skins.Image(model.Source, state);
        if (skin != null)
            dc.DrawImage(skin, FitRect(skin, new Rect(2, 3, 96, 90)));
        else
            DrawFace(dc, time, eyeColor, face, C(baseColor));
        // Hata: eli alnına (yüzle birlikte hareket etsin)
        if (model.Gesture == Gesture.Facepalm && gt is >= 0 and <= 1.6) DrawFacepalm(dc, gt, right);
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

        // El hareketleri: büyük iş bitti (alkış), merhaba (el sallama), onay bekliyor (balonu göster)
        dc.PushTransform(new TranslateTransform(0, -lift));
        switch (model.Gesture)
        {
            case Gesture.Clap when gt is >= 0 and <= 2.0: DrawClap(dc, gt); break;
            case Gesture.Wave when gt is >= 0 and <= 1.8: DrawWave(dc, gt, right); break;
        }
        if (state == RobotState.Waiting && (stateAge < 3.2 || (stateAge > 30 && stateAge % 10 < 2.2)))
            DrawPoint(dc, stateAge < 3.2 ? stateAge : stateAge % 10, right, _avatar.BubbleBelow);
        dc.Pop();
        if (winter) DrawSnow(dc, time);

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

    private static double Mix(double a, double b, double t) => a + (b - a) * t;

    /// <summary>Yüzü çizmek için gereken her şey (durum, geçiş, boştaki hareket, göz simgesi, imlece bakış, kostüm)</summary>
    private readonly record struct FaceCtx(
        RobotState State, Mood? Mood, RobotState PrevState, Mood? PrevMood, double Blend, IdleMotion Idle,
        char Glyph, char PrevGlyph, double LookU, double LookV, double Hover, bool Winter);

    private void DrawFace(DrawingContext dc, double time, Color eyeColor, FaceCtx f, Color theme)
    {
        dc.DrawEllipse(B(Bolt), null, new Point(6, 50), 6, 6);
        dc.DrawEllipse(B(Bolt), null, new Point(94, 50), 6, 6);
        dc.DrawRoundedRectangle(ShellBrush, null, new Rect(7, 15, 86, 70), 24, 24);
        dc.DrawRoundedRectangle(B(Visor), null, new Rect(15, 30, 70, 44), 18, 18);
        DrawEyes(dc, time, eyeColor, f);

        // Alında sağlık ışığı (berede ponpon o renkte yanar)
        var (led, op) = _avatar.Health switch
        {
            Health.Update => (C(1.0, 0.6, 0.2), 0.6 + 0.4 * Math.Sin(time * 3)),
            Health.Broken => (C(0.97, 0.3, 0.3), Math.Sin(time * 6) > 0 ? 1.0 : 0.3),
            _ => (C(0.2, 0.83, 0.47), f.State == RobotState.Sleeping ? 0.45 : 0.85 + 0.15 * Math.Sin(time * 2)),
        };
        if (f.Winter)
        {
            DrawBeanie(dc, theme, _avatar.Health == Health.Ok ? null : led, op);
            return;
        }
        dc.DrawEllipse(B(led, 0.3 * op), null, new Point(50, 22.5), 5.5, 5.5);
        dc.DrawEllipse(B(led, op), null, new Point(50, 22.5), 2.5, 2.5);
    }

    // MARK: Kış kostümü

    private static readonly Geometry BeanieDome = Frozen(Geometry.Parse("M 15,23 C 15,8 30,1 50,1 C 70,1 85,8 85,23 Z"));

    private static void DrawBeanie(DrawingContext dc, Color theme, Color? pompomGlow, double glowOpacity)
    {
        var edge = new Pen(B(HandEdge), 1);
        dc.DrawGeometry(B(theme), null, BeanieDome);
        var rib = new Pen(B(Color.FromRgb((byte)(theme.R * 0.82), (byte)(theme.G * 0.82), (byte)(theme.B * 0.82))), 1.2);
        foreach (var x in new[] { 32.0, 41, 50, 59, 68 }) dc.DrawLine(rib, new Point(x, x == 50 ? 5 : 8), new Point(x, 19));
        dc.DrawRoundedRectangle(B(C(0.965, 0.953, 0.933)), edge, new Rect(11, 17, 78, 10), 5, 5);
        if (pompomGlow is { } g) dc.DrawEllipse(B(g, 0.35 * glowOpacity), null, new Point(50, 2), 9, 9);
        dc.DrawEllipse(pompomGlow is { } g2 ? B(g2, Math.Max(0.5, glowOpacity)) : B(C(0.965, 0.953, 0.933)), edge, new Point(50, 2), 5.5, 5.5);
    }

    private static void DrawSnow(DrawingContext dc, double time)
    {
        for (var i = 0; i < 12; i++)
        {
            var speed = 9 + i % 4 * 3;
            var y = (time * speed + i * 37) % 140 - 25;
            var x = (i * 53 % 130) - 15 + Math.Sin(time * 0.9 + i) * 5;
            var r = 0.9 + i % 3 * 0.4;
            dc.DrawEllipse(B(Colors.White, 0.75 * Math.Min(1, (115 - y) / 30)), null, new Point(x, y), r, r);
        }
    }

    public static bool WinterActive => Prefs.Costume switch
    {
        "winter" => true,
        "off" => false,
        _ => DateTime.Now is { Month: 12 } or { Month: 1, Day: <= 6 },
    };

    // MARK: Nokta matris gözler (her göz 14 × 18 nokta)

    private const int Cols = 14, Rows = 18;
    private const double Spacing = 1.75, Dot = 1.3;

    private static void DrawEyes(DrawingContext dc, double time, Color color, FaceCtx f)
    {
        var tint = f.State == RobotState.Error && f.Mood == null ? C(1, 0.42, 0.42) : color;
        var dim = B(tint, 0.09);
        double[] centers = { 50 - 14, 50 + 14 };
        const double cy = 52;
        var midC = (Cols - 1) / 2.0;
        var midR = (Rows - 1) / 2.0;
        var blinking = f.State != RobotState.Waiting && f.Mood == null && f.Idle.Kind == IdleKind.None && f.Hover < 0.5 && (time % 4.2) < 0.12;
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
                    var b = Brightness(f.State, f.Mood, u, v, eye, time, blinking, f.Idle, f.Glyph, f.LookU, f.LookV, f.Hover);
                    // Yüz değiştiyse eskisiyle yenisi arasında yumuşak geçiş
                    if (f.Blend < 1) b = Mix(Brightness(f.PrevState, f.PrevMood, u, v, eye, time, false, default, f.PrevGlyph, f.LookU, f.LookV, 0), b, f.Blend);
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

    private static double Brightness(RobotState state, Mood? mood, double u, double v, int eye, double time, bool blinking,
        IdleMotion idle, char glyph, double lookU, double lookV, double hover)
    {
        // Gözde simge: ? soru soruyor, ! onay bekliyor, ✓ bitti, % kota azaldı
        if (glyph != '\0') return Glyph(glyph, u, v) * (0.85 + 0.15 * Math.Sin(time * 6));
        var lookShift = lookU + idle.Look;
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
            // Bitti / hata yüzü de (kimse çalışmıyorken) imlece doğru bakar
            RobotState.Done => Arc(u, v, 3 + lookShift * 0.6, 6.2 + lookV * 0.5, 2.7),
            RobotState.Error => Cross(u - lookShift * 0.6, v - lookV * 0.5),
            RobotState.Sleeping => Math.Abs(v - 6) < 0.3 && Math.Abs(u - 3) <= 2.2 ? 0.5 : 0,
            RobotState.Thinking => Capsule(u, v, 3.9, 2.8, 1.5, 2.6),
            RobotState.Reading or RobotState.Searching => Capsule(u, v, 3 + Math.Sin(time * 3) * 1.5, 4.4, 1.5, 2.3),
            RobotState.Editing => Capsule(u, v, 3 + lookShift * 0.5, 5, 1.9, 1.5),
            RobotState.Running or RobotState.Delegating =>
                Capsule(u, v, 3, 4, 1.6, 2.8) * (0.75 + 0.25 * Math.Sin(time * 18 + u * 2.6 + v * 1.4)),
            RobotState.Waiting => Capsule(u, v, 3, 4, 2.5, 3.9) * (0.75 + 0.25 * Math.Sin(time * 6)),
            _ => Mix(IdleEyes(u, v, eye, lookShift, lookV, idle), Arc(u, v, 3, 6.2, 2.7), hover),
        };
    }

    /// <summary>Boştayken gözler: imlece bakan kapsül + o anki küçük hareket (göz kırpma, tarama, esneme)</summary>
    private static double IdleEyes(double u, double v, int eye, double lookShift, double lookV, IdleMotion idle)
    {
        var b = Capsule(u, v, 3 + lookShift, 4 + lookV, 1.7, 3.3);
        switch (idle.Kind)
        {
            case IdleKind.Wink when eye == idle.Side:
                return Mix(b, Capsule(u, v, 3 + lookShift, 4.6, 1.9, 0.45), idle.Env);
            case IdleKind.Scan:
            {
                var gx = eye * 7 + u;
                var bar = Math.Abs(gx - (-0.5 + 14 * idle.P)) < 0.7 && Math.Abs(v - 4) < 3.4 ? 1.0 : 0.0;
                return Mix(b, Math.Max(bar, b * 0.25), idle.Env);
            }
            case IdleKind.Yawn:
                return Mix(b, Capsule(u, v, 3, 4.9, 2.0, 0.9 + 0.4 * Math.Sin(idle.P * Math.PI)), idle.Env);
            default:
                return b;
        }
    }

    // MARK: Göz simgeleri (nokta matriste çizilen işaretler)

    private static double Seg(double u, double v, double ax, double ay, double bx, double by, double w)
    {
        double dx = bx - ax, dy = by - ay, l = dx * dx + dy * dy;
        var t = l > 0 ? Math.Clamp(((u - ax) * dx + (v - ay) * dy) / l, 0, 1) : 0;
        double px = ax + t * dx - u, py = ay + t * dy - v;
        return px * px + py * py <= w * w ? 1 : 0;
    }

    private static double DotAt(double u, double v, double cx, double cy, double r) => (u - cx) * (u - cx) + (v - cy) * (v - cy) <= r * r ? 1 : 0;

    private static double Glyph(char g, double u, double v)
    {
        switch (g)
        {
            case '!':
                return Math.Max(Seg(u, v, 3, 0.8, 3, 5.0, 0.62), DotAt(u, v, 3, 6.9, 0.72));
            case '?':
            {
                var d = Math.Sqrt((u - 3) * (u - 3) + (v - 2.4) * (v - 2.4));
                var ring = Math.Abs(d - 1.55) < 0.55 && (v <= 2.4 || (u >= 3 && v <= 3.3)) ? 1 : 0;
                return new[] { ring, Seg(u, v, 4.3, 3.3, 3.0, 4.4, 0.58), Seg(u, v, 3.0, 4.4, 3.0, 5.1, 0.58), DotAt(u, v, 3, 6.9, 0.72) }.Max();
            }
            case '✓':
                return Math.Max(Seg(u, v, 0.9, 4.4, 2.5, 6.1, 0.6), Seg(u, v, 2.5, 6.1, 5.3, 1.9, 0.6));
            case '%':
            {
                var a = Math.Abs(Math.Sqrt((u - 1.6) * (u - 1.6) + (v - 1.9) * (v - 1.9)) - 0.75) < 0.4 ? 1 : 0;
                var b = Math.Abs(Math.Sqrt((u - 4.4) * (u - 4.4) + (v - 6.1) * (v - 6.1)) - 0.75) < 0.4 ? 1 : 0;
                return new[] { a, b, Seg(u, v, 5.0, 1.0, 1.0, 7.0, 0.45) }.Max();
            }
            default:
                return 0;
        }
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

    // MARK: El hareketleri

    private static readonly Color HandEdge = C(0.54, 0.51, 0.65);
    private static readonly Color HandFill = C(0.96, 0.945, 0.965);

    /// <summary>Elin belirmesi: hafif taşan yay; sonda solarak kaybolur</summary>
    private static (double Scale, double Opacity) Pop(double t, double duration)
    {
        var x = Math.Min(1, t / 0.3);
        const double c1 = 1.70158, c3 = c1 + 1;
        var scale = 1 + c3 * Math.Pow(x - 1, 3) + c1 * Math.Pow(x - 1, 2);
        var opacity = t > duration - 0.3 ? Math.Max(0, (duration - t) / 0.3) : 1;
        return (scale, opacity);
    }

    /// <summary>Açık el (avuç): başparmak solda (-x), parmak çizgileri üstte. Bilek (0, 16).</summary>
    private static void DrawPalm(DrawingContext dc)
    {
        var edge = new Pen(B(HandEdge), 1.4);
        dc.DrawRoundedRectangle(B(Bolt), null, new Rect(-6, 13, 12, 5), 2, 2);
        dc.DrawRoundedRectangle(B(HandFill), edge, new Rect(-10, -14, 20, 28), 9, 9);
        dc.DrawRoundedRectangle(B(HandFill), edge, new Rect(-17, -2, 9, 12), 4.5, 4.5);
        var crease = new Pen(B(HandEdge), 1.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        foreach (var x in new[] { -4.5, 0.5, 5.5 }) dc.DrawLine(crease, new Point(x, -14), new Point(x, -7));
    }

    /// <summary>İşaret eden el: işaret parmağı +x yönünde</summary>
    private static void DrawPointingHand(DrawingContext dc)
    {
        var edge = new Pen(B(HandEdge), 1.4);
        dc.DrawRoundedRectangle(B(Bolt), null, new Rect(-8, 11, 16, 5), 2, 2);
        dc.DrawRoundedRectangle(B(HandFill), edge, new Rect(-12, -6, 24, 18), 7, 7);
        dc.DrawRoundedRectangle(B(HandFill), edge, new Rect(8, -6, 16, 7), 3.5, 3.5);
        var crease = new Pen(B(HandEdge), 1.2) { StartLineCap = PenLineCap.Round, EndLineCap = PenLineCap.Round };
        foreach (var y in new[] { 3.0, 8 }) dc.DrawLine(crease, new Point(2, y), new Point(10, y));
    }

    /// <summary>Merhaba: başın yanında el sallar</summary>
    private static void DrawWave(DrawingContext dc, double t, bool right)
    {
        var (scale, opacity) = Pop(t, 1.8);
        dc.PushOpacity(opacity);
        dc.PushTransform(new TranslateTransform(right ? 95 : 5, 60));
        dc.PushTransform(new ScaleTransform(right ? scale : -scale, scale, 0, 16));
        dc.PushTransform(new RotateTransform(Math.Sin(t * 14) * 22, 0, 16));
        DrawPalm(dc);
        dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop();
    }

    /// <summary>Onay bekliyor: balonu işaret eder (balon üstteyse yukarı, alttaysa aşağı doğru), dürter gibi</summary>
    private static void DrawPoint(DrawingContext dc, double t, bool right, bool bubbleBelow)
    {
        var (scale, opacity) = Pop(t, 2.2 + (t < 3.2 ? 1 : 0));
        dc.PushOpacity(opacity);
        dc.PushTransform(new TranslateTransform(right ? 90 : 10, 76));
        dc.PushTransform(new ScaleTransform(right ? scale : -scale, scale, 0, 16));
        dc.PushTransform(new RotateTransform(bubbleBelow ? 25 : -25, 0, 4));
        dc.PushTransform(new TranslateTransform(Math.Sin(t * 8) * 2.5, 0));
        DrawPointingHand(dc);
        dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop();
    }

    /// <summary>Uzun ya da gurur verici iş bitti: önde iki el alkışlar</summary>
    private static void DrawClap(DrawingContext dc, double t)
    {
        var (scale, opacity) = Pop(t, 2.0);
        var sep = 6 + Math.Abs(Math.Cos(t * 9)) * 9;
        dc.PushOpacity(opacity);
        foreach (var side in new[] { -1.0, 1.0 })
        {
            dc.PushTransform(new TranslateTransform(50 + side * sep, 84));
            dc.PushTransform(new ScaleTransform(-side * scale * 0.85, scale * 0.85, 0, 16));
            dc.PushTransform(new RotateTransform(side * -12, 0, 16));
            DrawPalm(dc);
            dc.Pop(); dc.Pop(); dc.Pop();
        }
        dc.Pop();
    }

    /// <summary>Hata: aşağıdan gelip bir gözünü kapatır (alnına vurur)</summary>
    private static void DrawFacepalm(DrawingContext dc, double t, bool right)
    {
        var (_, opacity) = Pop(t, 1.6);
        var rise = 1 - IdleMotion.Smooth(t / 0.35);
        dc.PushOpacity(opacity);
        dc.PushTransform(new TranslateTransform(right ? 64 : 36, 58 + rise * 30));
        dc.PushTransform(new ScaleTransform(right ? -1 : 1, 1, 0, 16));
        dc.PushTransform(new RotateTransform(-10, 0, 16));
        DrawPalm(dc);
        dc.Pop(); dc.Pop(); dc.Pop(); dc.Pop();
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

internal enum IdleKind { None, LookAround, Wink, Sway, Bounce, Scan, Yawn }

/// <summary>
/// Boştayken arada bir yapılan küçük hareketler: etrafa bakma, göz kırpma, sallanma, zıplama, tarama, esneme.
/// 8 sn'lik dilimlerin çoğunda bir tane; başı ve sonu yumuşak (Env), süzülmenin üstüne eklenir. Mac'teki IdleMotion'un aynısı.
/// </summary>
internal readonly record struct IdleMotion(IdleKind Kind, double P, double Env, int Side)
{
    public static double Smooth(double x)
    {
        var t = Math.Clamp(x, 0, 1);
        return t * t * (3 - 2 * t);
    }

    public static IdleMotion At(double time)
    {
        const double slot = 8;
        var n = (long)Math.Floor(time / slot);
        var local = time - n * slot;
        uint x;
        unchecked
        {
            x = (uint)(n * 2654435761L);
            x ^= x >> 15;
            x *= 2246822519u;
            x ^= x >> 13;
        }
        var h = (int)(x & 0x7fffffff);
        if (h / 3 % 10 < 3) return default;   // bazı dilimler sakin geçsin
        var kinds = new[] { IdleKind.LookAround, IdleKind.Wink, IdleKind.Sway, IdleKind.Bounce, IdleKind.Scan, IdleKind.Yawn };
        var kind = kinds[h % kinds.Length];
        var dur = kind switch { IdleKind.Wink => 1.2, IdleKind.Bounce => 1.6, IdleKind.Scan => 2.2, IdleKind.Yawn => 2.6, _ => 3.0 };
        var start = 2.0 + h / 7 % 3;
        if (local < start || local > start + dur) return default;
        var p = (local - start) / dur;
        var env = kind == IdleKind.Wink ? Smooth((p - 0.2) / 0.15) * Smooth((0.8 - p) / 0.15) : Smooth(p / 0.2) * Smooth((1 - p) / 0.2);
        return new IdleMotion(kind, p, env, h / 13 % 2);
    }

    public double Dx => Kind == IdleKind.Sway ? Math.Sin(P * Math.PI * 4) * 2.5 * Env : 0;
    public double Lift => Kind switch
    {
        IdleKind.Bounce => Math.Abs(Math.Sin(P * Math.PI * 3)) * 7 * Env,
        IdleKind.Yawn => -3 * Env,
        _ => 0,
    };
    public double Tilt => Kind switch
    {
        IdleKind.LookAround => Math.Sin(P * Math.PI * 2) * 4 * Env,
        IdleKind.Wink => (Side == 0 ? -5 : 5) * Env,
        IdleKind.Sway => Math.Sin(P * Math.PI * 4) * 6 * Env,
        IdleKind.Yawn => Math.Sin(P * Math.PI) * 3 * Env,
        _ => 0,
    };
    public double Look => Kind == IdleKind.LookAround ? Math.Sin(P * Math.PI * 2) * 1.6 * Env : 0;
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
