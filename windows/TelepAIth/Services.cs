using System;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json.Nodes;
using System.Threading.Tasks;
using Microsoft.Win32;
using TelepAIth.Core;
using static TelepAIth.Core.Text;
using WinForms = System.Windows.Forms;

namespace TelepAIth;

/// <summary>Bildirimler: tepsi simgesinin balonu (Windows 10/11'de bildirim olarak görünür). Tıklayınca ilgili pencereye gider.</summary>
internal static class Notifier
{
    public static WinForms.NotifyIcon? Icon;
    public static Action<AppTarget>? OnClick;
    private static AppTarget? _lastTarget;
    private static Action? _lastAction;

    public static void Attach(WinForms.NotifyIcon icon)
    {
        Icon = icon;
        icon.BalloonTipClicked += (_, _) =>
        {
            if (_lastAction != null) _lastAction();
            else if (_lastTarget is { IsEmpty: false } t) OnClick?.Invoke(t);
        };
    }

    public static void Notify(string title, string body, AppTarget? target = null, Action? onClick = null)
    {
        if (!Prefs.NotificationsEnabled || Icon == null) return;
        var dispatcher = System.Windows.Application.Current?.Dispatcher;
        if (dispatcher != null && !dispatcher.CheckAccess())
        {
            dispatcher.BeginInvoke(() => Notify(title, body, target, onClick));
            return;
        }
        _lastTarget = target;
        _lastAction = onClick;
        try
        {
            if (Prefs.Muted)
            {
                // Sessize alındı: bildirimi Windows'un sessiz seçeneğiyle göster; olmazsa hiç gösterme (robot balonda söyler)
                SilentBalloon(Clip(title, 60), Clip(string.IsNullOrWhiteSpace(body) ? " " : body, 250));
                return;
            }
            Icon.BalloonTipTitle = Clip(title, 60);
            Icon.BalloonTipText = Clip(string.IsNullOrWhiteSpace(body) ? " " : body, 250);
            Icon.BalloonTipIcon = WinForms.ToolTipIcon.None;
            Icon.ShowBalloonTip(6000);
        }
        catch { }
    }

    [System.Runtime.InteropServices.StructLayout(System.Runtime.InteropServices.LayoutKind.Sequential, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private struct NotifyIconData
    {
        public int Size;
        public IntPtr Window;
        public int Id;
        public int Flags;
        public int CallbackMessage;
        public IntPtr IconHandle;
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 128)] public string Tip;
        public int State;
        public int StateMask;
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 256)] public string Info;
        public int TimeoutOrVersion;
        [System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.ByValTStr, SizeConst = 64)] public string InfoTitle;
        public int InfoFlags;
        public Guid Item;
        public IntPtr BalloonIcon;
    }

    [System.Runtime.InteropServices.DllImport("shell32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    private static extern bool Shell_NotifyIcon(int message, ref NotifyIconData data);

    /// <summary>Sessiz bildirim balonu (NIIF_NOSOUND). Tepsi simgesinin penceresi ve kimliği bulunamazsa balon gösterilmez.</summary>
    private static void SilentBalloon(string title, string body)
    {
        if (Icon == null) return;
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var type = typeof(WinForms.NotifyIcon);
        var window = (type.GetField("_window", flags) ?? type.GetField("window", flags))?.GetValue(Icon) as WinForms.NativeWindow;
        var idValue = (type.GetField("_id", flags) ?? type.GetField("id", flags))?.GetValue(Icon);
        if (window == null || window.Handle == IntPtr.Zero || idValue == null) return;
        var data = new NotifyIconData
        {
            Size = System.Runtime.InteropServices.Marshal.SizeOf<NotifyIconData>(),
            Window = window.Handle,
            Id = Convert.ToInt32(idValue),
            Flags = 0x10,                // NIF_INFO
            Tip = "",
            Info = body,
            InfoTitle = title,
            TimeoutOrVersion = 6000,
            InfoFlags = 0x10,            // NIIF_NOSOUND (simgesiz)
        };
        Shell_NotifyIcon(1, ref data);   // NIM_MODIFY
    }

    /// <summary>Windows'ta uygulama bildirimleri kapalı mı? (Ayarlar → Sistem → Bildirimler)</summary>
    public static bool SystemDisabled
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\PushNotifications");
                return k?.GetValue("ToastEnabled") is int v && v == 0;
            }
            catch { return false; }
        }
    }

    public static void OpenSystemSettings() => Shell.Open("ms-settings:notifications");
}

/// <summary>Sesli okuma (Windows'un kendi sesleri, SAPI)</summary>
internal static class Speech
{
    private static dynamic? _voice;
    private static Language? _voiceLang;

    public static void Say(string text)
    {
        if (!Prefs.Speak || Prefs.Muted || FocusMode.IsActive) return;
        var clean = new string(text.Where(c => !char.IsSurrogate(c) && c != '️').ToArray()).Trim();
        if (clean.Length == 0) return;
        Task.Run(() =>
        {
            try
            {
                lock (typeof(Speech))
                {
                    if (_voice == null || _voiceLang != Lang.Current)
                    {
                        var type = Type.GetTypeFromProgID("SAPI.SpVoice");
                        if (type == null) return;
                        _voice = Activator.CreateInstance(type);
                        _voiceLang = Lang.Current;
                        // Dile uygun ses varsa onu seç (Türkçe: 41F, İngilizce: 409)
                        var voices = _voice!.GetVoices(Lang.Current == Language.Tr ? "Language=41F" : "Language=409", "");
                        if (voices.Count > 0) _voice.Voice = voices.Item(0);
                    }
                    _voice!.Speak(clean, 1 | 2);   // eşzamansız, öncekini kes
                }
            }
            catch { _voice = null; }
        });
    }
}

internal static class Sounds
{
    public static void Play(string name)
    {
        try
        {
            switch (name)
            {
                case "Basso": System.Media.SystemSounds.Hand.Play(); break;
                case "Ping": System.Media.SystemSounds.Exclamation.Play(); break;
                case "Hero": System.Media.SystemSounds.Asterisk.Play(); break;
                default: System.Media.SystemSounds.Asterisk.Play(); break;
            }
        }
        catch { }
    }
}

internal static class Shell
{
    public static void Open(string target)
    {
        try { Process.Start(new ProcessStartInfo(target) { UseShellExecute = true }); } catch { }
    }
}

/// <summary>Kurulum: %LOCALAPPDATA%\Programs\TelepAIth, Başlat menüsü kısayolu, Windows'la başlat.</summary>
internal static class Installer
{
    public static string InstallDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "TelepAIth");
    public static string ExePath => Path.Combine(InstallDir, "TelepAIth.exe");
    public static string HookExe => Path.Combine(AppContext.BaseDirectory, "TelepAIthHook.exe");
    private static string ShortcutPath => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Programs), "TelepAIth.lnk");
    private const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";

    private static string CurrentExe => Environment.ProcessPath ?? Path.Combine(AppContext.BaseDirectory, "TelepAIth.exe");

    public static bool IsInstalledCopy =>
        string.Equals(Path.GetFullPath(AppContext.BaseDirectory).TrimEnd('\\'), Path.GetFullPath(InstallDir).TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);

    /// <summary>İndirilen klasörden açıldıysa kendini kurulum klasörüne kopyalar ve oradan yeniden açar. true: bu süreç kapanmalı.</summary>
    public static bool EnsureInstalled()
    {
        if (IsInstalledCopy || Environment.GetEnvironmentVariable("TELEPAITH_PORTABLE") == "1") return false;
        try
        {
            // Çalışan eski kopya varsa kapat (güncelleme gibi)
            foreach (var p in Process.GetProcessesByName("TelepAIth"))
            {
                try
                {
                    if (p.Id != Environment.ProcessId && string.Equals(p.MainModule?.FileName, ExePath, StringComparison.OrdinalIgnoreCase))
                    {
                        p.Kill();
                        p.WaitForExit(3000);
                    }
                }
                catch { }
                finally { p.Dispose(); }
            }
            Directory.CreateDirectory(InstallDir);
            var src = AppContext.BaseDirectory.TrimEnd('\\');
            foreach (var file in Directory.GetFiles(src, "*", SearchOption.AllDirectories))
            {
                if (file.EndsWith(".pdb", StringComparison.OrdinalIgnoreCase)) continue;
                var dest = Path.Combine(InstallDir, Path.GetRelativePath(src, file));
                Directory.CreateDirectory(Path.GetDirectoryName(dest)!);
                File.Copy(file, dest, true);
            }
            CreateShortcut();
            SetAutostart(Prefs.StartWithWindows);
            Process.Start(new ProcessStartInfo(ExePath) { UseShellExecute = true, WorkingDirectory = InstallDir });
            return true;
        }
        catch (Exception ex)
        {
            // Kurulamazsa olduğu yerden çalışsın
            System.Windows.MessageBox.Show(L("Kurulum klasörüne kopyalanamadı, olduğu yerden çalışacağım.\n\n", "Couldn't copy to the install folder; running from here.\n\n") + ex.Message,
                AppInfo.Name);
            return false;
        }
    }

    public static void CreateShortcut()
    {
        try
        {
            var type = Type.GetTypeFromProgID("WScript.Shell");
            if (type == null) return;
            dynamic shell = Activator.CreateInstance(type)!;
            dynamic lnk = shell.CreateShortcut(ShortcutPath);
            lnk.TargetPath = CurrentExe.StartsWith(InstallDir, StringComparison.OrdinalIgnoreCase) ? CurrentExe : ExePath;
            lnk.WorkingDirectory = InstallDir;
            lnk.Description = "TelepAIth";
            lnk.Save();
        }
        catch { }
    }

    public static bool AutostartEnabled
    {
        get
        {
            try
            {
                using var k = Registry.CurrentUser.OpenSubKey(RunKey);
                return k?.GetValue(AppInfo.Name) is string;
            }
            catch { return false; }
        }
    }

    public static void SetAutostart(bool on)
    {
        Prefs.StartWithWindows = on;
        try
        {
            using var k = Registry.CurrentUser.CreateSubKey(RunKey);
            if (on) k.SetValue(AppInfo.Name, $"\"{(IsInstalledCopy ? CurrentExe : ExePath)}\"");
            else k.DeleteValue(AppInfo.Name, false);
        }
        catch { }
    }

    /// <summary>Kaldır: kancalar, otomatik başlatma, kısayol ve program klasörü (ayarlar ~/.telepaith'te kalır).</summary>
    public static void Uninstall()
    {
        try { HookInstaller.Uninstall(HookTarget.Claude); } catch { }
        try { HookInstaller.Uninstall(HookTarget.Codex); } catch { }
        try { NarratorInstaller.Uninstall(); } catch { }
        SetAutostart(false);
        try { File.Delete(ShortcutPath); } catch { }
        if (IsInstalledCopy)
        {
            var script = Path.Combine(Path.GetTempPath(), "telepaith-uninstall.cmd");
            File.WriteAllText(script,
                "@echo off\r\n" +
                $"timeout /t 2 /nobreak >nul\r\n" +
                $"rmdir /s /q \"{InstallDir}\"\r\n" +
                "del \"%~f0\"\r\n", Encoding.ASCII);
            Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"") { CreateNoWindow = true, UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden });
        }
    }
}

/// <summary>
/// GitHub Releases üzerinden güncelleme. .NET çalışma zamanı aynıysa sadece uygulama dosyaları (birkaç MB),
/// değiştiyse tam paket iner. İndirirken robot ilerlemeyi söyler.
/// </summary>
internal sealed class Updater
{
    public static Updater Shared { get; } = new();

    public sealed record Release(string Version, string Notes, string FullUrl, string? SmallUrl, string? RuntimeUrl, long FullSize, long SmallSize, string? PageUrl);

    public Release? Available { get; private set; }
    public bool IsBusy { get; private set; }
    public event Action? Changed;
    /// <summary>İndirme durumu (UI iş parçacığında): metin</summary>
    public event Action<string>? Progress;

    private static readonly HttpClient Http = CreateClient();

    private static HttpClient CreateClient()
    {
        var c = new HttpClient { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
        c.DefaultRequestHeaders.UserAgent.ParseAdd("TelepAIth-Windows/" + AppInfo.Version);
        return c;
    }

    public void StartAutomaticChecks()
    {
        Task.Run(async () =>
        {
            await Task.Delay(TimeSpan.FromSeconds(15));
            while (true)
            {
                await CheckAsync(false);
                await Task.Delay(TimeSpan.FromHours(3));
            }
        });
    }

    /// <summary>Denetler; kullanıcı istediyse sonucu metin olarak döner.</summary>
    public async Task<string?> CheckAsync(bool userInitiated)
    {
        if (IsBusy) return null;
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, $"https://api.github.com/repos/{AppInfo.Repo}/releases/latest");
            req.Headers.Accept.ParseAdd("application/vnd.github+json");
            using var res = await Http.SendAsync(req);
            res.EnsureSuccessStatusCode();
            if (JsonNode.Parse(await res.Content.ReadAsStringAsync()) is not JsonObject root) return L("GitHub'dan anlamsız cevap geldi.", "Unexpected reply from GitHub.");
            var tag = root["tag_name"]?.GetValue<string>() ?? "";
            var version = tag.TrimStart('v');
            if (!VersionCompare.IsNewer(version, AppInfo.Version))
            {
                Available = null;
                Raise();
                return userInitiated ? L($"Güncelsin ({AppInfo.Version}).", $"You're up to date ({AppInfo.Version}).") : null;
            }
            var assets = (root["assets"] as JsonArray)?.OfType<JsonObject>().ToList() ?? new();
            JsonObject? Asset(string name) => assets.FirstOrDefault(a => string.Equals(a["name"]?.GetValue<string>(), name, StringComparison.OrdinalIgnoreCase));
            var full = Asset(UpdatePlan.FullAsset);
            var small = Asset(UpdatePlan.SmallAsset);
            var runtime = Asset(UpdatePlan.RuntimeAsset);
            var url = full?["browser_download_url"]?.GetValue<string>();
            if (url == null)
                return userInitiated ? L($"{version} yayınlanmış ama Windows paketi henüz yok.", $"{version} is out but the Windows package isn't ready yet.") : null;
            var isNew = Available?.Version != version;
            Available = new Release(version, root["body"]?.GetValue<string>() ?? "", url,
                small?["browser_download_url"]?.GetValue<string>(), runtime?["browser_download_url"]?.GetValue<string>(),
                full?["size"]?.GetValue<long>() ?? 0, small?["size"]?.GetValue<long>() ?? 0, root["html_url"]?.GetValue<string>());
            Raise();
            if (!userInitiated && isNew)
                Notifier.Notify("⬆️ " + L($"TelepAIth {version} hazır", $"TelepAIth {version} is ready"),
                    L("Robota tıkla, güncelleyeyim.", "Click the robot to update."));
            return null;
        }
        catch (Exception ex)
        {
            return userInitiated ? L("Güncelleme denetlenemedi: ", "Couldn't check for updates: ") + ex.Message : null;
        }
    }

    private void Raise() => System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Changed?.Invoke());

    private void Report(string text) => System.Windows.Application.Current?.Dispatcher.BeginInvoke(() => Progress?.Invoke(text));

    public void PromptInstall()
    {
        if (Available is not { } r || IsBusy) return;
        var notes = r.Notes.Length > 600 ? r.Notes[..600] + "…" : r.Notes;
        var answer = System.Windows.MessageBox.Show(
            L($"TelepAIth {r.Version} hazır (şu an: {AppInfo.Version}).\n\n", $"TelepAIth {r.Version} is ready (current: {AppInfo.Version}).\n\n") + notes +
            L("\n\nGüncelleyip yeniden başlatayım mı?", "\n\nUpdate and restart now?"),
            AppInfo.Name, System.Windows.MessageBoxButton.YesNo, System.Windows.MessageBoxImage.Information);
        if (answer == System.Windows.MessageBoxResult.Yes) _ = InstallAsync(r);
    }

    private static string? LocalRuntime()
    {
        try
        {
            var f = Path.Combine(AppContext.BaseDirectory, UpdatePlan.RuntimeFile);
            return File.Exists(f) ? File.ReadAllText(f) : null;
        }
        catch { return null; }
    }

    private async Task InstallAsync(Release r)
    {
        IsBusy = true;
        Raise();
        try
        {
            // Çalışma zamanı aynıysa küçük paket yeter
            string? remoteRuntime = null;
            if (r.RuntimeUrl != null && r.SmallUrl != null)
            {
                try { remoteRuntime = await Http.GetStringAsync(r.RuntimeUrl); } catch { }
            }
            var small = UpdatePlan.UseSmall(LocalRuntime(), remoteRuntime, r.SmallUrl != null);
            var url = small ? r.SmallUrl! : r.FullUrl;

            var work = Path.Combine(Path.GetTempPath(), "TelepAIth-update-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(work);
            var zip = Path.Combine(work, "update.zip");
            Report("⬇️ " + L("Güncelleme indiriliyor…", "Downloading the update…"));
            using (var res = await Http.GetAsync(url, HttpCompletionOption.ResponseHeadersRead))
            {
                res.EnsureSuccessStatusCode();
                var total = res.Content.Headers.ContentLength ?? (small ? r.SmallSize : r.FullSize);
                await using var s = await res.Content.ReadAsStreamAsync();
                await using var f = File.Create(zip);
                var buffer = new byte[256 * 1024];
                long done = 0;
                var lastReport = DateTime.MinValue;
                int n;
                while ((n = await s.ReadAsync(buffer)) > 0)
                {
                    await f.WriteAsync(buffer.AsMemory(0, n));
                    done += n;
                    if ((DateTime.Now - lastReport).TotalMilliseconds > 400)
                    {
                        lastReport = DateTime.Now;
                        var pct = total > 0 ? $" %{done * 100 / total}" : "";
                        Report("⬇️ " + L("Güncelleme indiriliyor", "Downloading the update") + pct + " · " + UpdatePlan.Progress(done, total));
                    }
                }
            }
            Report("📦 " + L("Kuruluyor, birazdan dönerim…", "Installing, back in a moment…"));
            var extracted = Path.Combine(work, "new");
            ZipFile.ExtractToDirectory(zip, extracted);
            var exe = Directory.GetFiles(extracted, "TelepAIth.exe", SearchOption.AllDirectories).FirstOrDefault()
                      ?? throw new Exception(L("Paket içinde TelepAIth.exe yok.", "TelepAIth.exe not found in the package."));
            var from = Path.GetDirectoryName(exe)!;
            var to = AppContext.BaseDirectory.TrimEnd('\\');
            var script = Path.Combine(work, "update.cmd");
            // Uygulama kapanınca dosyaları değiştir ve yeniden aç
            File.WriteAllText(script,
                "@echo off\r\n" +
                $":wait\r\ntasklist /fi \"PID eq {Environment.ProcessId}\" | find \"{Environment.ProcessId}\" >nul && (timeout /t 1 /nobreak >nul & goto wait)\r\n" +
                $"robocopy \"{from}\" \"{to}\" /e /r:5 /w:1 >nul\r\n" +
                $"start \"\" \"{Path.Combine(to, "TelepAIth.exe")}\"\r\n" +
                $"rmdir /s /q \"{work}\"\r\n", Encoding.ASCII);
            Process.Start(new ProcessStartInfo("cmd.exe", $"/c \"{script}\"") { CreateNoWindow = true, UseShellExecute = false, WindowStyle = ProcessWindowStyle.Hidden });
            System.Windows.Application.Current.Dispatcher.Invoke(() => System.Windows.Application.Current.Shutdown());
        }
        catch (Exception ex)
        {
            IsBusy = false;
            Raise();
            Report("⚠️ " + L("Güncellenemedi: ", "Update failed: ") + ex.Message);
            System.Windows.Application.Current.Dispatcher.Invoke(() =>
                System.Windows.MessageBox.Show(L("Güncellenemedi: ", "Update failed: ") + ex.Message, AppInfo.Name));
        }
    }
}
