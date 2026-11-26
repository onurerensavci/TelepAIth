using TelepAIth.Core;

public static partial class Tests
{
    public static void EffectsPickAndReact()
    {
        A.Eq(11, Effects.All.Length);
        A.True(Effects.All.Select(e => e.Id).Distinct().Count() == Effects.All.Length);
        // Otomatik: mevsim ve özel günler
        A.Eq("winter", Effects.Season(new DateTime(2026, 12, 10)));
        A.Eq("rainbow", Effects.Season(new DateTime(2027, 4, 2)));
        A.Eq("sun", Effects.Season(new DateTime(2027, 7, 1)));
        A.Eq("leaves", Effects.Season(new DateTime(2026, 11, 26)));
        A.Eq("confetti", Effects.Season(new DateTime(2026, 12, 31)));
        A.Eq("hearts", Effects.Season(new DateTime(2027, 2, 14)));
        A.True(Effects.IsBackground("sun") && !Effects.IsBackground("hearts"));
        // Duygular
        A.Eq("hearts", Effects.Feeling("Sevgilime bir aşk mektubu yaz"));
        A.Eq("confetti", Effects.Feeling("Tebrikler, başardık!"));
        A.Eq("rain", Effects.Feeling("bugün moralim bozuk"));
        A.True(Effects.Feeling("README'yi düzelt") == null);

        var t0 = new DateTime(2027, 7, 1, 12, 0, 0);
        Effects.Reset();
        // Seçilen efekt her zaman görünür; kapalı hiç
        Prefs.Costume = "rainbow";
        A.Eq("rainbow", Effects.Visible(t0, false)!.Value.Id);
        Prefs.Costume = "off";
        A.True(Effects.Visible(t0, true) == null);
        A.True(Effects.Hear("seni seviyorum", t0) == null);   // otomatik değilken dinlemez
        // Otomatik: boştayken görünmez, bir şey olunca mevsimin efekti, boşta kalınca söner
        Prefs.Costume = "auto";
        A.True(Effects.Visible(t0, false) == null);
        A.Eq("sun", Effects.Visible(t0, true)!.Value.Id);
        A.Eq(1.0, Effects.Visible(t0.AddSeconds(20), false)!.Value.Alpha);
        A.True(Effects.Visible(t0.AddSeconds(30), false)!.Value.Alpha is > 0.4 and < 0.6);
        A.True(Effects.Visible(t0.AddSeconds(40), false) == null);
        // Sohbette aşk geçti: 30 sn kalpler
        A.Eq("hearts", Effects.Hear("Sevgilim için şiir", t0.AddSeconds(100))!);
        A.Eq("hearts", Effects.Visible(t0.AddSeconds(110), false)!.Value.Id);
        A.Eq("sun", Effects.Visible(t0.AddSeconds(131), false)!.Value.Id);
        A.True(Effects.WinterCostume(new DateTime(2027, 1, 10)) && !Effects.WinterCostume(new DateTime(2027, 7, 1)));
        // Ses çıkaran an: efekt canlanır, sonra söner
        Effects.Reset();
        Effects.Kick(1, t0);
        A.True(Effects.Energy(t0, false) > 0.99);
        A.True(Effects.Energy(t0.AddSeconds(1), false) is > 0.1 and < 0.3);
        A.True(Effects.Energy(t0.AddSeconds(5), false) < 0.01);
        A.True(Effects.Energy(t0.AddSeconds(60), true) is >= 0.1 and <= 0.34);
        A.Eq(1.0, Effects.Strength("Glass"));
        Effects.Reset();
    }
}
