using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32;

namespace TelepAIth;

/// <summary>Windows sistem çağrıları: pencereler, ekranlar, DPI, sanal masaüstleri, süreç ağacı, mikrofon.</summary>
internal static class Native
{
    [StructLayout(LayoutKind.Sequential)]
    public struct POINT { public int X, Y; }

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT
    {
        public int Left, Top, Right, Bottom;
        public int Width => Right - Left;
        public int Height => Bottom - Top;
        public bool Contains(int x, int y) => x >= Left && x < Right && y >= Top && y < Bottom;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
    }

    public const int GWL_EXSTYLE = -20;
    public const int WS_EX_TRANSPARENT = 0x20;
    public const int WS_EX_TOOLWINDOW = 0x80;
    public const int WS_EX_NOACTIVATE = 0x08000000;
    public const int WS_EX_LAYERED = 0x80000;
    public const uint SWP_NOSIZE = 0x1, SWP_NOMOVE = 0x2, SWP_NOZORDER = 0x4, SWP_NOACTIVATE = 0x10;
    public static readonly IntPtr HWND_TOPMOST = new(-1);
    public static readonly IntPtr HWND_NOTOPMOST = new(-2);
    public const int SW_RESTORE = 9;
    public const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    public const int DWMWA_CLOAKED = 14;

    [DllImport("user32.dll")] public static extern bool GetCursorPos(out POINT p);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hwnd, out RECT r);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hwnd, int cmd);
    [DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int pid);
    [DllImport("user32.dll", SetLastError = true)] public static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] public static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] public static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromPoint(POINT p, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
    [DllImport("user32.dll")] public static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnum callback, IntPtr data);
    public delegate bool MonitorEnum(IntPtr monitor, IntPtr hdc, ref RECT rect, IntPtr data);
    [DllImport("shcore.dll")] public static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT value, int size);
    [DllImport("dwmapi.dll")] public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);
    [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);

    public const uint MONITOR_DEFAULTTONEAREST = 2;

    public static POINT Cursor()
    {
        GetCursorPos(out var p);
        return p;
    }

    public static int WindowPid(IntPtr hwnd)
    {
        GetWindowThreadProcessId(hwnd, out var pid);
        return (int)pid;
    }

    public static string WindowTitle(IntPtr hwnd)
    {
        var sb = new StringBuilder(512);
        GetWindowText(hwnd, sb, sb.Capacity);
        return sb.ToString();
    }

    /// <summary>Pencerenin görünen çerçevesi (gölgesiz), fiziksel piksel.</summary>
    public static RECT? WindowFrame(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero || !IsWindowVisible(hwnd) || IsIconic(hwnd)) return null;
        if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out int cloaked, sizeof(int)) == 0 && cloaked != 0) return null;
        if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out RECT r, Marshal.SizeOf<RECT>()) == 0) return r;
        return GetWindowRect(hwnd, out r) ? r : null;
    }

    public sealed record Monitor(IntPtr Handle, RECT Bounds, RECT Work, string Device, double Scale);

    public static List<Monitor> Monitors()
    {
        var list = new List<Monitor>();
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr m, IntPtr hdc, ref RECT rect, IntPtr data) =>
        {
            var info = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
            if (GetMonitorInfo(m, ref info)) list.Add(new Monitor(m, info.rcMonitor, info.rcWork, info.szDevice, ScaleOf(m)));
            return true;
        }, IntPtr.Zero);
        return list;
    }

    public static Monitor MonitorAt(int x, int y)
    {
        var handle = MonitorFromPoint(new POINT { X = x, Y = y }, MONITOR_DEFAULTTONEAREST);
        var info = new MONITORINFOEX { cbSize = Marshal.SizeOf<MONITORINFOEX>() };
        GetMonitorInfo(handle, ref info);
        return new Monitor(handle, info.rcMonitor, info.rcWork, info.szDevice, ScaleOf(handle));
    }

    public static double ScaleOf(IntPtr monitor)
    {
        try
        {
            if (GetDpiForMonitor(monitor, 0, out var dx, out _) == 0 && dx > 0) return dx / 96.0;
        }
        catch { }
        return 1.0;
    }

    public static void SetClickThrough(IntPtr hwnd, bool through)
    {
        var ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        var want = through ? ex | WS_EX_TRANSPARENT : ex & ~WS_EX_TRANSPARENT;
        if (want != ex) SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(want));
    }

    public static void MakeToolWindow(IntPtr hwnd)
    {
        var ex = GetWindowLongPtr(hwnd, GWL_EXSTYLE).ToInt64();
        SetWindowLongPtr(hwnd, GWL_EXSTYLE, new IntPtr(ex | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE));
    }

    /// <summary>Bir pencereyi öne getirir (simge durumundaysa açar).</summary>
    public static void Activate(IntPtr hwnd)
    {
        if (hwnd == IntPtr.Zero) return;
        if (IsIconic(hwnd)) ShowWindow(hwnd, SW_RESTORE);
        SetForegroundWindow(hwnd);
    }

    // MARK: Süreç ağacı (hook'u çalıştıran terminalin penceresini bulmak için)

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct PROCESSENTRY32W
    {
        public uint dwSize, cntUsage, th32ProcessID;
        public IntPtr th32DefaultHeapID;
        public uint th32ModuleID, cntThreads, th32ParentProcessID;
        public int pcPriClassBase;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
    }

    [DllImport("kernel32.dll", SetLastError = true)] private static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool Process32FirstW(IntPtr snap, ref PROCESSENTRY32W e);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] private static extern bool Process32NextW(IntPtr snap, ref PROCESSENTRY32W e);
    [DllImport("kernel32.dll")] private static extern bool CloseHandle(IntPtr h);

    public static Dictionary<int, (int Parent, string Exe)> ProcessTable()
    {
        var map = new Dictionary<int, (int, string)>();
        var snap = CreateToolhelp32Snapshot(0x2, 0);
        if (snap == IntPtr.Zero || snap == new IntPtr(-1)) return map;
        try
        {
            var e = new PROCESSENTRY32W { dwSize = (uint)Marshal.SizeOf<PROCESSENTRY32W>() };
            if (Process32FirstW(snap, ref e))
            {
                do { map[(int)e.th32ProcessID] = ((int)e.th32ParentProcessID, e.szExeFile); }
                while (Process32NextW(snap, ref e));
            }
        }
        finally { CloseHandle(snap); }
        return map;
    }

    /// <summary>Verilen süreçten yukarı doğru çıkıp ilk görünür penceresi olan atayı bulur (terminal, VS Code…).</summary>
    public static int? WindowedAncestor(int pid)
    {
        var table = ProcessTable();
        var seen = new HashSet<int>();
        var current = pid;
        for (var i = 0; i < 12 && current > 4 && seen.Add(current); i++)
        {
            try
            {
                using var p = Process.GetProcessById(current);
                if (p.MainWindowHandle != IntPtr.Zero) return current;
            }
            catch { }
            if (!table.TryGetValue(current, out var entry)) break;
            current = entry.Parent;
        }
        return null;
    }

    // MARK: Mikrofon kullanımda mı? (görüşmedeyiz demek; izin gerektirmez)

    public static bool MicrophoneInUse(Func<string, bool> ignore)
    {
        try
        {
            using var root = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\microphone");
            if (root == null) return false;
            return InUse(root, ignore);
        }
        catch { return false; }
    }

    private static bool InUse(RegistryKey key, Func<string, bool> ignore)
    {
        foreach (var name in key.GetSubKeyNames())
        {
            using var sub = key.OpenSubKey(name);
            if (sub == null) continue;
            if (name == "NonPackaged")
            {
                if (InUse(sub, ignore)) return true;
                continue;
            }
            var start = sub.GetValue("LastUsedTimeStart") as long? ?? 0;
            var stop = sub.GetValue("LastUsedTimeStop") as long? ?? -1;
            if (start > 0 && stop == 0 && !ignore(name)) return true;
        }
        return false;
    }
}

/// <summary>Windows'un sanal masaüstü arayüzü (resmî, belgelenmiş kısmı).</summary>
[ComImport, Guid("a5cd92ff-29be-454c-8d04-d82879fb3f1b"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IVirtualDesktopManager
{
    [PreserveSig] int IsWindowOnCurrentVirtualDesktop(IntPtr topLevelWindow, out bool onCurrentDesktop);
    [PreserveSig] int GetWindowDesktopId(IntPtr topLevelWindow, out Guid desktopId);
    [PreserveSig] int MoveWindowToDesktop(IntPtr topLevelWindow, ref Guid desktopId);
}

internal static class VirtualDesktops
{
    private static IVirtualDesktopManager? _manager;

    private static IVirtualDesktopManager? Manager
    {
        get
        {
            if (_manager != null) return _manager;
            try
            {
                var type = Type.GetTypeFromCLSID(new Guid("aa509086-5ca9-4c25-8f95-589d3c07b48a"));
                if (type != null) _manager = (IVirtualDesktopManager?)Activator.CreateInstance(type);
            }
            catch { _manager = null; }
            return _manager;
        }
    }

    public static bool IsOnCurrent(IntPtr hwnd)
    {
        try { return Manager == null || (Manager.IsWindowOnCurrentVirtualDesktop(hwnd, out var on) != 0 || on); }
        catch { return true; }
    }

    /// <summary>Kendi penceremizi başka bir pencerenin masaüstüne taşır.</summary>
    public static void MoveTo(IntPtr ours, IntPtr other)
    {
        try
        {
            if (Manager == null || other == IntPtr.Zero) return;
            if (Manager.GetWindowDesktopId(other, out var id) != 0 || id == Guid.Empty) return;
            if (Manager.GetWindowDesktopId(ours, out var current) == 0 && current == id) return;
            Manager.MoveWindowToDesktop(ours, ref id);
        }
        catch { }
    }
}
