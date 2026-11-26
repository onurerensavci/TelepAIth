using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

/// <summary>
/// Efektler (Mac'te Effects.swift, aynı kurallar): robotun çevresinde kar, güneş, gökkuşağı…
/// Robot ses çıkaran bir an yaşayınca (bitti, seni bekliyor, hata, kutlama) efekt canlanır; çalışırken hafifçe atar.
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

    /// <summary>Arkada çizilenler (robotun arkasında parlar); diğerleri önünde uçuşur.</summary>
    public static bool IsBackground(string id) => id is "sun" or "rainbow" or "aurora";

    /// <summary>Şu an çizilecek efekt: "auto" Aralık – 6 Ocak arası kış, değilse yok; "off" yok.</summary>
    public static string? Current(DateTime now) => Prefs.Costume switch
    {
        "off" => null,
        "auto" or "" => now is { Month: 12 } or { Month: 1, Day: <= 6 } ? "winter" : null,
        var id => All.Any(e => e.Id == id) ? id : null,
    };

    public static string? Current() => Current(DateTime.Now);

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
