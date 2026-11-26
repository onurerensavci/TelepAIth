using TelepAIth.Core;

public static partial class Tests
{
    public static void EffectsPickAndReact()
    {
        A.Eq(11, Effects.All.Length);
        A.True(Effects.All.Select(e => e.Id).Distinct().Count() == Effects.All.Length);
        // Otomatik: Aralık – 6 Ocak kış, sonrasında yok; seçilen efekt her zaman
        Prefs.Costume = "auto";
        A.Eq("winter", Effects.Current(new DateTime(2026, 12, 10)));
        A.Eq("winter", Effects.Current(new DateTime(2027, 1, 6)));
        A.True(Effects.Current(new DateTime(2027, 1, 7)) == null);
        Prefs.Costume = "rainbow";
        A.Eq("rainbow", Effects.Current(new DateTime(2027, 7, 1)));
        Prefs.Costume = "off";
        A.True(Effects.Current(new DateTime(2026, 12, 10)) == null);
        Prefs.Costume = "bilinmeyen";
        A.True(Effects.Current(new DateTime(2027, 7, 1)) == null);
        Prefs.Costume = "auto";
        A.True(Effects.IsBackground("sun") && !Effects.IsBackground("hearts"));
        // Ses çıkaran an: efekt canlanır, sonra söner
        var t0 = new DateTime(2027, 3, 1, 12, 0, 0);
        Effects.Kick(1, t0);
        A.True(Effects.Energy(t0, false) > 0.99);
        A.True(Effects.Energy(t0.AddSeconds(1), false) is > 0.1 and < 0.3);
        A.True(Effects.Energy(t0.AddSeconds(5), false) < 0.01);
        // Çalışırken hafif nabız
        A.True(Effects.Energy(t0.AddSeconds(60), true) is >= 0.1 and <= 0.34);
        A.Eq(1.0, Effects.Strength("Glass"));
    }
}
