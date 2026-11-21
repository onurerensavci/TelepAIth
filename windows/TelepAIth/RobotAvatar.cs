using System;
using System.Collections.Generic;
using System.Linq;
using TelepAIth.Core;

namespace TelepAIth;

public enum Corner { BottomLeft, BottomRight, TopLeft, TopRight }

public enum Health { Ok, Update, Broken }

/// <summary>
/// Robotun yeri: köşeye yapışma, sürükleme, AI penceresine uçma. Konumlar fiziksel piksel (ekran), kafanın merkezi.
/// Ölçüler %100 boyutta DIP olarak tanımlı; ekranın DPI'ı ve ayardaki robot boyutuyla çarpılır.
/// </summary>
internal sealed class RobotAvatar
{
    // %100 boyuttaki ölçüler (DIP) — Mac'tekiyle aynı
    public const double BaseWindowW = 280, BaseWindowH = 250, BaseHead = 100, BaseMargin = 16, EdgeInset = 14;
    private const double SnapDistance = 260, DockOffsetX = 95, DockOffsetY = 100;

    public RobotModel Current { get; private set; }
    public DateTime CurrentSince { get; private set; } = DateTime.Now;
    public bool AlignLeft { get; private set; }
    public bool BubbleBelow { get; private set; }
    public Health Health { get; private set; } = Health.Ok;
    public string HealthText { get; private set; } = "";
    public bool Locked => Prefs.RobotLocked;
    public bool IsDragging { get; private set; }
    public List<RobotModel.MiniSession> Minis { get; set; } = new();
    public bool Focus { get; set; }

    /// <summary>Kafanın merkezi (fiziksel piksel)</summary>
    public double HeadX { get; private set; }
    public double HeadY { get; private set; }
    private (double X, double Y)? _target;
    private double _dragStartX, _dragStartY, _dragCursorX, _dragCursorY;

    public event Action? UserMoved;

    public RobotAvatar(RobotModel initial)
    {
        Current = initial;
        RestorePosition();
    }

    public void Show(RobotModel model)
    {
        if (ReferenceEquals(model, Current)) return;
        Current = model;
        CurrentSince = DateTime.Now;
    }

    public void SetHealth(Health h, string text)
    {
        Health = h;
        HealthText = text;
    }

    /// <summary>Kafanın bulunduğu ekranın DPI çarpanı × robot boyutu</summary>
    public double PixelScale => Native.MonitorAt((int)HeadX, (int)HeadY).Scale * Prefs.RobotScale;

    public double HeadPx => BaseHead * PixelScale;

    public (int X, int Y, int W, int H) WindowRect
    {
        get
        {
            var s = PixelScale;
            var w = BaseWindowW * s;
            var h = BaseWindowH * s;
            var localX = AlignLeft ? (BaseMargin + BaseHead / 2) * s : w - (BaseMargin + BaseHead / 2) * s;
            var localY = BubbleBelow ? (BaseMargin + BaseHead / 2) * s : h - (BaseMargin + BaseHead / 2) * s;
            return ((int)Math.Round(HeadX - localX), (int)Math.Round(HeadY - localY), (int)Math.Round(w), (int)Math.Round(h));
        }
    }

    public Native.RECT HeadRect
    {
        get
        {
            var half = HeadPx / 2;
            return new Native.RECT { Left = (int)(HeadX - half), Top = (int)(HeadY - half), Right = (int)(HeadX + half), Bottom = (int)(HeadY + half) };
        }
    }

    // MARK: Ekranlar ve köşeler

    private static Native.Monitor MonitorFor(double x, double y) => Native.MonitorAt((int)x, (int)y);

    private static (double X, double Y) CornerPoint(Corner c, Native.Monitor m)
    {
        var s = m.Scale * Prefs.RobotScale;
        var hw = (BaseHead / 2 + EdgeInset) * s;
        var w = m.Work;
        return c switch
        {
            Corner.BottomLeft => (w.Left + hw, w.Bottom - hw),
            Corner.BottomRight => (w.Right - hw, w.Bottom - hw),
            Corner.TopLeft => (w.Left + hw, w.Top + hw),
            _ => (w.Right - hw, w.Top + hw),
        };
    }

    private static (double X, double Y) Clamp(double x, double y, Native.Monitor m)
    {
        var hw = (BaseHead / 2 + EdgeInset) * m.Scale * Prefs.RobotScale;
        var w = m.Work;
        return (Math.Min(Math.Max(x, w.Left + hw), w.Right - hw), Math.Min(Math.Max(y, w.Top + hw), w.Bottom - hw));
    }

    /// <summary>Ev konumu: kullanıcının bıraktığı köşe ya da nokta, hangi ekranda olursa.</summary>
    private (double X, double Y) HomePoint
    {
        get
        {
            var monitors = Native.Monitors();
            if (Enum.TryParse<Corner>(Prefs.AvatarCorner, out var corner))
            {
                var m = monitors.FirstOrDefault(x => x.Device == Prefs.AvatarScreen) ?? Native.MonitorAt(0, 0);
                return CornerPoint(corner, m);
            }
            var px = Prefs.AvatarX;
            var py = Prefs.AvatarY;
            if (!double.IsNaN(px) && !double.IsNaN(py)) return Clamp(px, py, MonitorFor(px, py));
            return CornerPoint(Corner.BottomRight, Native.MonitorAt(0, 0));
        }
    }

    public void RestorePosition()
    {
        var (x, y) = HomePoint;
        HeadX = x;
        HeadY = y;
        _target = null;
        UpdateSides(x, y);
    }

    public void GoHome()
    {
        if (IsDragging) return;
        if (Locked)
        {
            // Kilitliyken yerinde kalır; sadece ekran söküldüyse görünür bir yere taşınır
            var m = MonitorFor(HeadX, HeadY);
            if (!m.Bounds.Contains((int)HeadX, (int)HeadY)) MoveTo(HomePoint);
            return;
        }
        MoveTo(HomePoint);
    }

    /// <summary>AI penceresinin sağ-alt köşesine uç; balon pencerenin içine doğru açılsın.</summary>
    public void Dock(Native.RECT window)
    {
        if (IsDragging || Locked) return;
        var s = MonitorFor(window.Right - 10, window.Bottom - 10).Scale * Prefs.RobotScale;
        var x = window.Right - DockOffsetX * s;
        var y = window.Bottom - DockOffsetY * s;
        x = Math.Max(x, window.Left + BaseHead / 2 * s);
        y = Math.Max(y, window.Top + BaseHead / 2 * s);
        var (rx, ry) = _target ?? (HeadX, HeadY);
        if (Math.Abs(rx - x) < 1 && Math.Abs(ry - y) < 1) return;
        _target = (x, y);
        AlignLeft = x < (window.Left + window.Right) / 2.0;
        BubbleBelow = y < (window.Top + window.Bottom) / 2.0;
    }

    private void MoveTo((double X, double Y) p)
    {
        _target = p;
        UpdateSides(p.X, p.Y);
    }

    private void UpdateSides(double x, double y)
    {
        var b = MonitorFor(x, y).Bounds;
        AlignLeft = x < (b.Left + b.Right) / 2.0;
        BubbleBelow = y < (b.Top + b.Bottom) / 2.0;
    }

    // MARK: Sürükleme (ekrandan ekrana serbest)

    public void BeginDrag()
    {
        if (Locked) return;
        IsDragging = true;
        _target = null;
        _dragStartX = HeadX;
        _dragStartY = HeadY;
        var c = Native.Cursor();
        _dragCursorX = c.X;
        _dragCursorY = c.Y;
    }

    public void Drag()
    {
        if (!IsDragging) return;
        var c = Native.Cursor();
        HeadX = _dragStartX + (c.X - _dragCursorX);
        HeadY = _dragStartY + (c.Y - _dragCursorY);
    }

    /// <summary>Bırakınca: bir köşeye yakınsa oraya yapış, değilse olduğu yerde kal.</summary>
    public void EndDrag()
    {
        if (!IsDragging) return;
        IsDragging = false;
        var m = MonitorFor(HeadX, HeadY);
        Corner? nearest = null;
        var best = double.MaxValue;
        foreach (var c in Enum.GetValues<Corner>())
        {
            var (px, py) = CornerPoint(c, m);
            var d = Math.Sqrt((px - HeadX) * (px - HeadX) + (py - HeadY) * (py - HeadY));
            if (d < best) { best = d; nearest = c; }
        }
        if (nearest != null && best < SnapDistance * m.Scale)
        {
            Prefs.AvatarCorner = nearest.Value.ToString();
            Prefs.AvatarScreen = m.Device;
        }
        else
        {
            var (x, y) = Clamp(HeadX, HeadY, m);
            Prefs.AvatarCorner = null;
            Prefs.AvatarX = x;
            Prefs.AvatarY = y;
        }
        MoveTo(HomePoint);
        UserMoved?.Invoke();
    }

    /// <summary>Yapışma ve uçma animasyonu.</summary>
    public void Step(double dt)
    {
        if (IsDragging) { Drag(); return; }
        if (_target is not { } t) return;
        var k = Math.Min(1, dt * 9);
        HeadX += (t.X - HeadX) * k;
        HeadY += (t.Y - HeadY) * k;
        if (Math.Abs(t.X - HeadX) < 0.5 && Math.Abs(t.Y - HeadY) < 0.5)
        {
            HeadX = t.X;
            HeadY = t.Y;
            _target = null;
        }
    }
}
