using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

namespace TelepAIth.Core;

public static class AppInfo
{
    public const string Name = "TelepAIth";
    public const string HookMarker = "__telepaith_hook";
    public const int DefaultPort = 19850;
    public const string Repo = "onurerensavci/TelepAIth";

    /// <summary>Kullanıcıya açık klasör: config.json, port, kostümler, algılama günlüğü (Mac ile aynı: ~/.telepaith)</summary>
    public static string SupportDir
    {
        get
        {
            var dir = Environment.GetEnvironmentVariable("TELEPAITH_HOME")
                      ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), ".telepaith");
            Directory.CreateDirectory(dir);
            return dir;
        }
    }

    public static string PortFile => Path.Combine(SupportDir, "port");
    public static string ConfigFile => Path.Combine(SupportDir, "config.json");
    public static string SkinsDir => Path.Combine(SupportDir, "skins");
    public static string DebugFile => Path.Combine(SupportDir, "watch-debug.txt");

    /// <summary>Uygulamanın iç ayarları ve sayaçları</summary>
    public static string PrefsFile => Path.Combine(SupportDir, "settings.json");
    public static string StatsFile => Path.Combine(SupportDir, "daily-stats.json");

    public static string Version
    {
        get
        {
            var v = typeof(AppInfo).Assembly.GetName().Version;
            return v == null ? "0.0.0" : $"{v.Major}.{v.Minor}.{v.Build}";
        }
    }
}

public enum Language { Tr, En }

public static class Lang
{
    public static Language Current
    {
        get
        {
            var raw = Prefs.GetString("language");
            if (raw == "tr") return Language.Tr;
            if (raw == "en") return Language.En;
            return CultureInfo.CurrentUICulture.TwoLetterISOLanguageName.Equals("tr", StringComparison.OrdinalIgnoreCase)
                ? Language.Tr : Language.En;
        }
    }

    public static void Set(Language lang) => Prefs.Set("language", lang == Language.Tr ? "tr" : "en");

    public static string DisplayName(Language l) => l == Language.Tr ? "Türkçe" : "English";
}

public static class Text
{
    /// <summary>İki dilli metin: L("Bitti!", "Done!")</summary>
    public static string L(string tr, string en) => Lang.Current == Language.Tr ? tr : en;

    /// <summary>Metni tek satıra indirip kısaltır.</summary>
    public static string Clip(string s, int max)
    {
        var flat = s.Replace("\r", "").Replace("\n", " ").Trim();
        var info = new StringInfo(flat);
        if (info.LengthInTextElements <= max) return flat;
        return info.SubstringByTextElements(0, Math.Max(1, max - 1)) + "…";
    }

    /// <summary>Kısa süre: 40 → "40 sn", 200 → "3 dk", 4000 → "1 sa 6 dk"</summary>
    public static string ShortDuration(double seconds)
    {
        var total = Math.Max(0, (int)seconds);
        if (total < 60) return $"{total} {L("sn", "s")}";
        var minutes = total / 60;
        if (minutes < 60) return $"{minutes} {L("dk", "min")}";
        var rest = minutes % 60;
        return rest == 0 ? $"{minutes / 60} {L("sa", "h")}" : $"{minutes / 60} {L("sa", "h")} {rest} {L("dk", "min")}";
    }

    /// <summary>75 → "1 dk 15 sn" / "1 min 15 s"</summary>
    public static string FormatDuration(double seconds)
    {
        var s = L("sn", "s");
        var m = L("dk", "min");
        var h = L("sa", "h");
        var total = (int)Math.Round(seconds);
        if (total < 60) return $"{total} {s}";
        var minutes = total / 60;
        if (minutes < 60)
        {
            var sec = total % 60;
            return sec == 0 ? $"{minutes} {m}" : $"{minutes} {m} {sec} {s}";
        }
        var hours = minutes / 60;
        var rest = minutes % 60;
        return rest == 0 ? $"{hours} {h}" : $"{hours} {h} {rest} {m}";
    }

    /// <summary>Emoji açıksa metnin başına ekler.</summary>
    public static string WithEmoji(string? emoji, string text)
    {
        if (!Prefs.EmojiEnabled || string.IsNullOrEmpty(emoji)) return text;
        return emoji + " " + text;
    }

    public static string LastPathComponent(string path)
    {
        var trimmed = path.TrimEnd('/', '\\');
        var i = trimmed.LastIndexOfAny(new[] { '/', '\\' });
        return i >= 0 ? trimmed[(i + 1)..] : trimmed;
    }
}

/// <summary>Kalıcı ayarlar (~/.telepaith/settings.json). Anahtarlar Mac sürümündekilerle aynı.</summary>
public static class Prefs
{
    private static readonly object Gate = new();
    private static JsonObject? _data;
    private static string? _pathOverride;

    /// <summary>Testler için: ayar dosyasını başka bir yere yönlendir</summary>
    public static void UseFile(string? path)
    {
        lock (Gate)
        {
            _pathOverride = path;
            _data = null;
        }
    }

    private static string FilePath => _pathOverride ?? AppInfo.PrefsFile;

    private static JsonObject Data
    {
        get
        {
            if (_data != null) return _data;
            try
            {
                if (File.Exists(FilePath) && JsonNode.Parse(File.ReadAllText(FilePath)) is JsonObject o)
                {
                    _data = o;
                    return o;
                }
            }
            catch { /* bozuk dosya: baştan başla */ }
            _data = new JsonObject();
            return _data;
        }
    }

    private static void Save()
    {
        try
        {
            var dir = Path.GetDirectoryName(FilePath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            var tmp = FilePath + ".tmp";
            File.WriteAllText(tmp, Data.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
            File.Move(tmp, FilePath, true);
        }
        catch { /* ayar yazılamadı: bellekte kalsın */ }
    }

    public static bool GetBool(string key, bool fallback)
    {
        lock (Gate)
        {
            return Data[key] is JsonValue v && v.TryGetValue<bool>(out var b) ? b : fallback;
        }
    }

    public static double GetDouble(string key, double fallback)
    {
        lock (Gate)
        {
            if (Data[key] is JsonValue v)
            {
                if (v.TryGetValue<double>(out var d)) return d;
                if (v.TryGetValue<int>(out var i)) return i;
                if (v.TryGetValue<long>(out var l)) return l;
            }
            return fallback;
        }
    }

    public static string? GetString(string key)
    {
        lock (Gate)
        {
            return Data[key] is JsonValue v && v.TryGetValue<string>(out var s) ? s : null;
        }
    }

    public static void Set(string key, bool value) { lock (Gate) { Data[key] = value; Save(); } }
    public static void Set(string key, double value) { lock (Gate) { Data[key] = value; Save(); } }
    public static void Set(string key, string? value) { lock (Gate) { Data[key] = value; Save(); } }

    // Mac sürümüyle aynı ayarlar
    public static bool NotificationsEnabled { get => GetBool("notificationsEnabled", true); set => Set("notificationsEnabled", value); }
    public static bool EmojiEnabled { get => GetBool("emojiEnabled", true); set => Set("emojiEnabled", value); }
    public static bool RobotsVisible { get => GetBool("robotsVisible", true); set => Set("robotsVisible", value); }
    public static double LongTurnSeconds { get => GetDouble("longTurnSeconds", 20); set => Set("longTurnSeconds", value); }
    public static bool IdleChatter { get => GetBool("idleChatter", true); set => Set("idleChatter", value); }
    public static bool Shield { get => GetBool("shield", true); set => Set("shield", value); }
    /// <summary>Mevsimlik kostüm: "auto" (Aralık – 6 Ocak kış), "winter" (hep), "off"</summary>
    public static string Costume { get => GetString("costume") ?? "auto"; set => Set("costume", value); }
    /// <summary>Claude Code izin isteyince robotun balonunda İzin ver / Reddet düğmeleri</summary>
    public static bool ApproveFromRobot { get => GetBool("approveFromRobot", true); set => Set("approveFromRobot", value); }
    public static bool Speak { get => GetBool("speak", false); set => Set("speak", value); }
    public static bool Sounds { get => GetBool("sounds", false); set => Set("sounds", value); }
    /// <summary>Sessize al (robota sağ tık): bildirim sesi, kısa sesler ve sesli söyleme susar; bildirimler sessiz gelir</summary>
    public static bool Muted { get => GetBool("muted", false); set => Set("muted", value); }
    public static bool WatchApps { get => GetBool("watchApps", true); set => Set("watchApps", value); }
    public static bool AlwaysOnTop { get => GetBool("alwaysOnTop", true); set => Set("alwaysOnTop", value); }
    public static bool RobotLocked { get => GetBool("robotLocked", false); set => Set("robotLocked", value); }
    public static bool FollowAppWindow { get => GetBool("followAppWindow", true); set => Set("followAppWindow", value); }
    public static bool NotifyWhenFrontmost { get => GetBool("notifyWhenFrontmost", false); set => Set("notifyWhenFrontmost", value); }
    public static bool WaitReminders { get => GetBool("waitReminders", true); set => Set("waitReminders", value); }
    public static bool MiniHeads { get => GetBool("miniHeads", true); set => Set("miniHeads", value); }
    public static double FocusUntil { get => GetDouble("focusUntil", 0); set => Set("focusUntil", value); }
    public static bool AutoFocusInMeetings { get => GetBool("autoFocusInMeetings", true); set => Set("autoFocusInMeetings", value); }
    public static bool DailySummary { get => GetBool("dailySummary", true); set => Set("dailySummary", value); }
    public static int DailySummaryHour { get => (int)GetDouble("dailySummaryHour", 18); set => Set("dailySummaryHour", value); }
    public static bool OnboardingDone { get => GetBool("onboardingDone", false); set => Set("onboardingDone", value); }
    public static bool StartWithWindows { get => GetBool("startWithWindows", true); set => Set("startWithWindows", value); }

    public static double RobotScale
    {
        get => Math.Clamp(GetDouble("robotScale", 1.0), 0.6, 1.8);
        set => Set("robotScale", value);
    }

    // Robotun yeri
    public static string? AvatarCorner { get => GetString("avatarCorner"); set => Set("avatarCorner", value); }
    public static string? AvatarScreen { get => GetString("avatarScreen"); set => Set("avatarScreen", value); }
    public static double AvatarX { get => GetDouble("avatarX", double.NaN); set => Set("avatarX", value); }
    public static double AvatarY { get => GetDouble("avatarY", double.NaN); set => Set("avatarY", value); }
}

/// <summary>Odak modu: toplantıda ya da elle açılınca robot susar, sadece seni bekleyen şeyleri söyler.</summary>
public static class FocusMode
{
    /// <summary>Toplantı uygulaması öndeyken ya da mikrofon açıkken uygulama doldurur.</summary>
    public static bool MeetingActive { get; set; }

    public static double Now => DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() / 1000.0;

    public static bool ManualActive => Prefs.FocusUntil > Now;

    public static bool IsActive => ManualActive || (Prefs.AutoFocusInMeetings && MeetingActive);

    public static void TurnOn(double? seconds) => Prefs.FocusUntil = seconds.HasValue ? Now + seconds.Value : 9e15;

    public static void TurnOff() => Prefs.FocusUntil = 0;

    /// <summary>Toplantı uygulamaları (süreç adı, küçük harf, .exe'siz)</summary>
    public static readonly string[] MeetingProcesses =
    {
        "zoom", "ms-teams", "teams", "msteams", "webex", "ciscocollabhost", "webexmta", "discord", "slack_huddle", "skype",
    };

    public static bool IsMeetingProcess(string? processName)
    {
        if (string.IsNullOrEmpty(processName)) return false;
        var p = processName.ToLowerInvariant().Replace(".exe", "");
        return MeetingProcesses.Contains(p);
    }

    public static string StatusText
    {
        get
        {
            if (ManualActive)
            {
                if (Prefs.FocusUntil > 4e9) return Text.L("açık (kapatana kadar)", "on (until you turn it off)");
                var until = DateTimeOffset.FromUnixTimeMilliseconds((long)(Prefs.FocusUntil * 1000)).ToLocalTime();
                return Text.L($"açık, {until:HH:mm}'e kadar", $"on until {until:HH:mm}");
            }
            if (Prefs.AutoFocusInMeetings && MeetingActive) return Text.L("açık (toplantıdasın)", "on (you're in a meeting)");
            return Text.L("kapalı", "off");
        }
    }
}

/// <summary>Sürüm karşılaştırma: "0.10.1" > "0.9.12"</summary>
public static class VersionCompare
{
    public static bool IsNewer(string candidate, string current)
    {
        static int[] Parts(string v) => v.TrimStart('v', 'V').Split('.', '-')
            .Select(p => int.TryParse(p, out var n) ? n : 0).ToArray();
        var a = Parts(candidate);
        var b = Parts(current);
        for (var i = 0; i < Math.Max(a.Length, b.Length); i++)
        {
            var x = i < a.Length ? a[i] : 0;
            var y = i < b.Length ? b[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }
}

/// <summary>
/// Windows güncellemesi: .NET çalışma zamanı değişmediyse sadece uygulama dosyalarını (küçük paket) indir,
/// değiştiyse ya da bilinmiyorsa tam paketi.
/// </summary>
public static class UpdatePlan
{
    public const string FullAsset = "Windows-TelepAIth-x64.zip";
    public const string SmallAsset = "Windows-TelepAIth-x64-update.zip";
    public const string RuntimeAsset = "Windows-TelepAIth-runtime.txt";
    public const string RuntimeFile = "runtime.txt";

    public static bool UseSmall(string? localRuntime, string? remoteRuntime, bool smallAvailable) =>
        smallAvailable && !string.IsNullOrWhiteSpace(localRuntime) && !string.IsNullOrWhiteSpace(remoteRuntime)
        && string.Equals(localRuntime.Trim(), remoteRuntime.Trim(), StringComparison.Ordinal);

    /// <summary>"12.3 / 61.8 MB" gibi</summary>
    public static string Progress(long done, long? total) =>
        total is > 0 ? $"{done / 1048576.0:0.0} / {total.Value / 1048576.0:0.0} MB" : $"{done / 1048576.0:0.0} MB";
}
