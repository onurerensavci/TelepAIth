using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

/// <summary>
/// Efektler (Mac'te Effects.swift, aynı kurallar): robotun çevresinde kar, güneş, gökkuşağı…
/// Robot ses çıkaran bir an yaşayınca (bitti, seni bekliyor, hata, kutlama) efekt canlanır; çalışırken hafifçe atar.
/// Otomatik mod: mevsime ve özel güne göre seçer, sohbette bir duygu geçerse (aşk, kutlama…) ona göre tepki verir;
/// robot bir şey yaparken görünür, boşta kalınca yavaşça söner (sakin çizim bozulmasın).
/// </summary>
public static class Effects
{
    public static readonly (string Id, Func<string> Name)[] All =
    {
        ("winter", () => L("Kış (kar ve bere)", "Winter (snow and beanie)")),
        ("sun", () => L("Güneş", "Sun")),
        ("rainbow", () => L("Gökkuşağı", "Rainbow")),
        ("aurora", () => L("Kuzey ışıkları", "Northern lights")),
        ("stars", () => L("Yıldızlar", "Stars")),
        ("hearts", () => L("Kalpler", "Hearts")),
        ("bubbles", () => L("Baloncuklar", "Bubbles")),
        ("fireflies", () => L("Ateş böcekleri", "Fireflies")),
        ("rain", () => L("Yağmur", "Rain")),
        ("leaves", () => L("Sonbahar yaprakları", "Autumn leaves")),
        ("confetti", () => L("Konfeti", "Confetti")),
    };

    public static string Name(string id) => All.FirstOrDefault(e => e.Id == id).Name?.Invoke() ?? id;

    /// <summary>Arkada çizilenler (robotun arkasında parlar); diğerleri önünde uçuşur.</summary>
    public static bool IsBackground(string id) => id is "sun" or "rainbow" or "aurora";

    public static bool IsAuto => Prefs.Costume is "auto" or "";

    // MARK: Mevsim ve özel günler

    /// <summary>Mevsim: winter, spring, summer, autumn</summary>
    public static string SeasonKey(DateTime now) => now.Month switch
    {
        12 or 1 or 2 => "winter",
        3 or 4 or 5 => "spring",
        6 or 7 or 8 => "summer",
        _ => "autumn",
    };

    /// <summary>Otomatik modda günün efekti: yılbaşı konfeti, sevgililer günü kalp, yoksa mevsimi (kar, gökkuşağı, güneş, yaprak)</summary>
    public static string Season(DateTime now) => now switch
    {
        { Month: 12, Day: 31 } or { Month: 1, Day: 1 } => "confetti",
        { Month: 2, Day: 14 } => "hearts",
        _ => SeasonKey(now) switch { "winter" => "winter", "spring" => "rainbow", "summer" => "sun", _ => "leaves" },
    };

    /// <summary>Mevsim geçişinde robotun söylediği</summary>
    public static string SeasonGreeting(string key) => key switch
    {
        "winter" => "❄️ " + L("Kış geldi! Kar yağdırıyorum.", "Winter is here! Let it snow."),
        "spring" => "🌈 " + L("Bahar geldi! Gökkuşağı çıktı.", "Spring is here! Rainbow's out."),
        "summer" => "☀️ " + L("Yaz geldi! Güneş açtı.", "Summer is here! The sun is out."),
        _ => "🍂 " + L("Sonbahar geldi! Yapraklar dökülüyor.", "Autumn is here! Leaves are falling."),
    };

    /// <summary>Kış beresi: elle "Kış" seçildiyse ya da otomatikte kış mevsimiyse (şapka takılı değilken)</summary>
    public static bool WinterCostume(DateTime now) => Prefs.Costume == "winter" || (IsAuto && SeasonKey(now) == "winter");

    // MARK: Duygular (otomatik mod)

    private static readonly (string Effect, string[] Words)[] Feelings =
    {
        ("hearts", new[] { "aşk", "aşık", "seviyorum", "sevgilim", "sevgilime", "romantik", "evlilik teklifi", "❤", "💕", "💖", "😍", "🥰",
                           "i love you", "love you", "my love", "valentine", "sweetheart", "romantic", "girlfriend", "boyfriend" }),
        ("confetti", new[] { "tebrik", "kutlu olsun", "doğum günü", "yaşasın", "başardık", "başardım", "yayına aldık", "🎉", "🥳",
                             "congrat", "birthday", "hooray", "we did it", "celebrat", "we shipped", "launched" }),
        ("rain", new[] { "üzgünüm", "çok üzgün", "üzüldüm", "ağlıyorum", "moralim bozuk", "kötü hissediyorum", "😢", "😭",
                         "i'm sad", "so sad", "crying", "heartbroken", "depressed" }),
        ("stars", new[] { "harika", "muhteşem", "mükemmel", "efsane", "şahane", "bravo", "✨", "🤩",
                          "amazing", "awesome", "wonderful", "brilliant", "fantastic" }),
        ("fireflies", new[] { "iyi geceler", "tatlı rüyalar", "good night", "sweet dreams" }),
    };

    /// <summary>Metinde bir duygu geçiyor mu? (aşk → kalpler, kutlama → konfeti, üzüntü → yağmur, övgü → yıldızlar)</summary>
    public static string? Feeling(string? text)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        var low = text.ToLowerInvariant();
        foreach (var (effect, words) in Feelings)
            if (words.Any(low.Contains)) return effect;
        return null;
    }

    private const double ReactSeconds = 30, StaySeconds = 25, FadeSeconds = 10;
    private static string? _reaction;
    private static DateTime _reactionAt = DateTime.MinValue;
    private static DateTime _lastActive = DateTime.MinValue;

    /// <summary>Sohbette geçen metni dinle (sadece otomatik modda): bir duygu varsa 30 sn o efekt</summary>
    public static string? Hear(string? text, DateTime now)
    {
        if (!IsAuto || Feeling(text) is not { } feeling) return null;
        _reaction = feeling;
        _reactionAt = now;
        Kick(1, now);
        return feeling;
    }

    /// <summary>Şu an çizilecek efekt ve görünürlüğü (0…1). working: robot çalışıyor (otomatik modda efekt açık kalır).</summary>
    public static (string Id, double Alpha)? Visible(DateTime now, bool working)
    {
        var mode = Prefs.Costume;
        if (mode == "off") return null;
        if (!IsAuto) return All.Any(e => e.Id == mode) ? (mode, 1) : null;
        if (working) _lastActive = now;
        if ((now - _reactionAt).TotalSeconds is >= 0 and < ReactSeconds && _reaction != null) return (_reaction, 1);
        var last = new[] { _lastActive, _kickAt, _reactionAt }.Max();
        if (last == DateTime.MinValue) return null;
        var idle = (now - last).TotalSeconds;
        var alpha = Math.Clamp(1 - (idle - StaySeconds) / FadeSeconds, 0, 1);
        return alpha <= 0 ? null : (Season(now), alpha);
    }

    public static (string Id, double Alpha)? Visible(bool working) => Visible(DateTime.Now, working);

    /// <summary>Test için: tepki ve etkinlik geçmişini sil</summary>
    public static void Reset()
    {
        _reaction = null;
        _reactionAt = _lastActive = _kickAt = DateTime.MinValue;
        _kickStrength = 0;
    }

    // MARK: Canlılık

    private static DateTime _kickAt = DateTime.MinValue;
    private static double _kickStrength;

    /// <summary>Robot ses çıkaran bir an yaşadı (ses kapalı olsa da): efekt bir an canlansın.</summary>
    public static void Kick(double strength, DateTime now)
    {
        if (strength >= Energy(now, false)) { _kickAt = now; _kickStrength = Math.Clamp(strength, 0, 1); }
    }

    public static void Kick(double strength) => Kick(strength, DateTime.Now);

    /// <summary>Efektin canlılığı 0…1: son andan beri sönen vuruş; çalışırken hafif nabız.</summary>
    public static double Energy(DateTime now, bool working)
    {
        var age = (now - _kickAt).TotalSeconds;
        var pulse = age < 0 || _kickAt == DateTime.MinValue ? 0 : _kickStrength * Math.Exp(-age * 1.6);
        var beat = working ? 0.22 + 0.12 * Math.Sin((now - DateTime.UnixEpoch).TotalSeconds * 5) : 0;
        return Math.Clamp(Math.Max(pulse, beat), 0, 1);
    }

    /// <summary>Sesin adına göre vuruş gücü (Glass bitti, Hero kutlama, Ping bekliyor, Basso hata).</summary>
    public static double Strength(string sound) => sound switch
    {
        "Glass" or "Hero" => 1,
        "Ping" => 0.8,
        _ => 0.6,
    };
}
