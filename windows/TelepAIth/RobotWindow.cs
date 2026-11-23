using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using TelepAIth.Core;

namespace TelepAIth;

/// <summary>
/// Robotun saydam, her zaman üstte, odak çalmayan penceresi. Konumu ve boyutu fiziksel piksel olarak
/// <see cref="RobotAvatar"/>'dan gelir; boş alanlar tıklamayı alttaki pencereye geçirir.
/// </summary>
internal sealed class RobotWindow : Window
{
    private readonly RobotAvatar _avatar;
    private readonly RobotView _view;
    private IntPtr _hwnd;
    private (int X, int Y, int W, int H) _lastRect;
    private bool _menuOpen;

    // Fare
    private Point? _pressAt;
    private bool _dragging;

    public event Action? Clicked;
    public event Action? DoubleClicked;
    /// <summary>Kafaya art arda hızlıca (1,5 sn'de 4 kez) tıklandı</summary>
    public event Action? RapidClicked;
    private readonly List<DateTime> _presses = new();
    public event Action? BubbleClicked;
    public event Action<ApprovalChoice>? ApprovalClicked;
    public Func<ContextMenu>? BuildMenu;

    public IntPtr Handle => _hwnd;

    public RobotWindow(RobotAvatar avatar)
    {
        _avatar = avatar;
        _view = new RobotView(avatar);
        Title = "TelepAIth";
        WindowStyle = WindowStyle.None;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        ShowActivated = false;
        Focusable = false;
        Topmost = Prefs.AlwaysOnTop;
        Content = _view;
        Width = RobotAvatar.BaseWindowW;
        Height = RobotAvatar.BaseWindowH;
        Left = -10000;
        Top = -10000;

        SourceInitialized += (_, _) =>
        {
            _hwnd = new WindowInteropHelper(this).Handle;
            Native.MakeToolWindow(_hwnd);
            HwndSource.FromHwnd(_hwnd)?.AddHook(WndProc);
            ApplyRect(force: true);
        };

        _view.MouseLeftButtonDown += OnDown;
        _view.MouseMove += OnMove;
        _view.MouseLeftButtonUp += OnUp;
        _view.MouseRightButtonUp += OnRightUp;
    }

    private const int WM_MOUSEACTIVATE = 0x0021, MA_NOACTIVATE = 3, WM_DPICHANGED = 0x02E0;

    private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        // Tıklayınca öne gelip başka pencerenin odağını çalmasın
        if (msg == WM_MOUSEACTIVATE)
        {
            handled = true;
            return new IntPtr(MA_NOACTIVATE);
        }
        if (msg == WM_DPICHANGED) _lastRect = default;   // yeni ekranın ölçüsüyle yeniden yerleştir
        return IntPtr.Zero;
    }

    public void SetAlwaysOnTop(bool on)
    {
        Prefs.AlwaysOnTop = on;
        Topmost = on;
        ApplyRect(force: true);
    }

    // MARK: Kare (yönetici saniyede 30 kez çağırır)

    public void Frame(double dt)
    {
        if (!IsVisible) return;
        _avatar.Step(dt);
        ApplyRect(force: false);
        _view.InvalidateVisual();
        UpdateClickThrough();
    }

    private void ApplyRect(bool force)
    {
        if (_hwnd == IntPtr.Zero) return;
        var r = _avatar.WindowRect;
        if (!force && r == _lastRect) return;
        _lastRect = r;
        const uint SWP_NOACTIVATE = 0x0010, SWP_NOOWNERZORDER = 0x0200;
        var after = Prefs.AlwaysOnTop ? Native.HWND_TOPMOST : Native.HWND_NOTOPMOST;
        Native.SetWindowPos(_hwnd, after, r.X, r.Y, r.W, r.H, SWP_NOACTIVATE | SWP_NOOWNERZORDER);
    }

    /// <summary>İmleç kafanın ya da balonun üstünde değilse tıklamalar alttaki pencereye geçsin.</summary>
    private void UpdateClickThrough()
    {
        if (_hwnd == IntPtr.Zero) return;
        if (_dragging || _menuOpen || _pressAt != null)
        {
            Native.SetClickThrough(_hwnd, false);
            return;
        }
        var c = Native.Cursor();
        var r = _lastRect;
        var dpi = VisualTreeHelper.GetDpi(this).DpiScaleX;
        var local = new Point((c.X - r.X) / dpi, (c.Y - r.Y) / dpi);
        var over = Contains(_view.HeadRect, local) || Contains(_view.BubbleRect, local);
        Native.SetClickThrough(_hwnd, !over);
    }

    private static bool Contains(Rect r, Point p) => !r.IsEmpty && r.Contains(p);

    // MARK: Fare

    private void OnDown(object sender, MouseButtonEventArgs e)
    {
        if (Contains(_view.HeadRect, e.GetPosition(_view)))
        {
            var now = DateTime.Now;
            _presses.Add(now);
            _presses.RemoveAll(t => (now - t).TotalSeconds > 1.5);
            if (_presses.Count >= 4)
            {
                _presses.Clear();
                _pressAt = null;
                RapidClicked?.Invoke();
                return;
            }
        }
        if (e.ClickCount >= 3) { _pressAt = null; return; }
        if (e.ClickCount == 2)
        {
            _pressAt = null;
            if (Contains(_view.HeadRect, e.GetPosition(_view))) DoubleClicked?.Invoke();
            return;
        }
        _pressAt = e.GetPosition(_view);
        _dragging = false;
        _view.CaptureMouse();
    }

    private void OnMove(object sender, MouseEventArgs e)
    {
        if (_pressAt is not { } start || e.LeftButton != MouseButtonState.Pressed) return;
        var p = e.GetPosition(_view);
        if (!_dragging && (Math.Abs(p.X - start.X) > 4 || Math.Abs(p.Y - start.Y) > 4) && !_avatar.Locked)
        {
            _dragging = true;
            _avatar.BeginDrag();
        }
    }

    private void OnUp(object sender, MouseButtonEventArgs e)
    {
        _view.ReleaseMouseCapture();
        if (_pressAt is not { } start) return;
        _pressAt = null;
        if (_dragging)
        {
            _dragging = false;
            _avatar.EndDrag();
            return;
        }
        if (_view.ButtonAt(start) is { } choice) ApprovalClicked?.Invoke(choice);
        else if (Contains(_view.BubbleRect, start)) BubbleClicked?.Invoke();
        else if (Contains(_view.HeadRect, start)) Clicked?.Invoke();
    }

    private void OnRightUp(object sender, MouseButtonEventArgs e)
    {
        if (BuildMenu == null) return;
        var menu = BuildMenu();
        menu.PlacementTarget = _view;
        menu.Placement = System.Windows.Controls.Primitives.PlacementMode.MousePoint;
        _menuOpen = true;
        menu.Closed += (_, _) => _menuOpen = false;
        menu.IsOpen = true;
        e.Handled = true;
    }

    /// <summary>Test için: düğmelerin ekrandaki yeri (fiziksel piksel)</summary>
    public System.Text.Json.Nodes.JsonObject ApprovalButtonsJson()
    {
        var o = new System.Text.Json.Nodes.JsonObject();
        var dpi = _hwnd == IntPtr.Zero ? 1 : VisualTreeHelper.GetDpi(this).DpiScaleX;
        foreach (var (choice, r) in _view.ButtonRects)
            o[choice.ToString().ToLowerInvariant()] = new System.Text.Json.Nodes.JsonArray(
                (int)(_lastRect.X + (r.X + r.Width / 2) * dpi), (int)(_lastRect.Y + (r.Y + r.Height / 2) * dpi));
        return o;
    }

    /// <summary>Robotu şu anki sanal masaüstüne getir (verilen pencerenin masaüstüne).</summary>
    public void MoveToDesktopOf(IntPtr other)
    {
        if (_hwnd != IntPtr.Zero) VirtualDesktops.MoveTo(_hwnd, other);
    }

    public bool IsOnCurrentDesktop => _hwnd == IntPtr.Zero || VirtualDesktops.IsOnCurrent(_hwnd);
}
