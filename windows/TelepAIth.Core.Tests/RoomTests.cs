using TelepAIth.Core;

public static partial class Tests
{
    public static void OutfitsParseAndColors()
    {
        A.Eq(17, Outfits.All.Count);
        A.True(Outfits.All.All(i => Outfits.Slots.Contains(i.Slot) && i.Shapes.Count > 0 && i.Name.Length > 0));
        A.True(Outfits.All.Select(i => i.Id).Distinct().Count() == Outfits.All.Count);
        // Başarımla açılan parçaların başarımı var
        A.True(Outfits.All.Where(i => i.Achievement != null).All(i => Achievements.Find(i.Achievement!) != null));
        var (c, a) = Outfits.Color("#FF8FB180", new Rgb(0, 0, 0));
        A.True(c == new Rgb(0xFF, 0x8F, 0xB1) && Math.Abs(a - 0x80 / 255.0) < 0.001);
        A.True(Outfits.Color("theme", new Rgb(10, 20, 30)).Color == new Rgb(10, 20, 30));
        A.True(Outfits.Color("theme-dark", new Rgb(100, 100, 100)).Color == new Rgb(72, 72, 72));
    }

    public static void LevelsGrow()
    {
        A.Eq(1, Levels.Level(0));
        A.Eq(1, Levels.Level(99));
        A.Eq(2, Levels.Level(100));
        A.Eq(3, Levels.Level(300));
        A.Eq(10, Levels.Level(4500));
        A.Eq(9, Levels.Level(4499));
        var p = new ProgressData { Turns = 20 };   // 200 XP: seviye 2, sonrakine 100
        A.Eq(2, Levels.Level(p));
        A.Eq(100L, Levels.Next(p).Left);
        A.Eq(0.5, Levels.Next(p).Fraction);
    }

    public static void ProgressStreaksAndNews()
    {
        var file = Path.Combine(Path.GetTempPath(), "tp-progress-" + Guid.NewGuid() + ".json");
        var pr = new Progress(file);
        var day = new DateTime(2026, 11, 20, 1, 30, 0);
        pr.Turn("claude", 120, 5, 2, day, 1);
        pr.Turn("gpt", 30, 0, 0, day.AddHours(1), 2);
        pr.Turn("claude", 60, 1, 1, day.AddDays(1).AddHours(10), 1);
        pr.Turn("claude", 60, 1, 1, day.AddDays(3).AddHours(10), 1);   // seri bozuldu
        pr.Parallel(3);
        pr.Parallel(2);
        var d = pr.Snapshot();
        A.Eq(4, d.Turns);
        A.Eq(3, d.ActiveDays);
        A.Eq(1, d.Streak);
        A.Eq(2, d.BestStreak);
        A.Eq(2, d.NightTurns);
        A.Eq(3, d.MaxParallel);
        A.Eq(2, d.Sources.Count);
        var news = pr.TakeNews();
        A.True(news.Achievements.Any(a => a.Id == "hello") && news.Achievements.Any(a => a.Id == "lead") && news.Achievements.Any(a => a.Id == "polyglot"));
        A.True(pr.TakeNews().Achievements.Count == 0);   // bir kez
        // Kayıttan geri okunur
        A.Eq(4, new Progress(file).Snapshot().Turns);
        File.Delete(file);
        // Parça açılması
        var cap = Outfits.Find("cap")!;
        A.True(!Outfits.Unlocked(cap, new ProgressData()));
        A.True(Outfits.Unlocked(cap, new ProgressData { Turns = 30 }));   // 300 XP = seviye 3
        A.True(Outfits.UnlockHint(Outfits.Find("party")!).Contains("Büyük gün"));
    }

    public static void EffortByProject()
    {
        var file = Path.Combine(Path.GetTempPath(), "tp-stats-" + Guid.NewGuid() + ".json");
        var st = new DailyStats(file);
        var today = new DateTime(2026, 11, 26, 12, 0, 0);
        st.RecordTurn("claude", 3600, 3, 2, today, "shop");
        st.RecordTurn("claude", 1800, 3, 2, today.AddDays(-1), "api");
        st.RecordTurn("gpt", 1800, 0, 0, today.AddDays(-2), null);
        st.RecordTurn("claude", 999, 0, 0, today.AddDays(-40), "old");
        var e = new DailyStats(file).Effort(today, 30);   // kayıttan okununca projeler kalır
        A.Eq(30, e.Days.Count);
        A.Eq("2026-11-26", e.Days[^1].Day);
        A.Eq(7200.0, e.TotalSeconds);
        A.Eq(3, e.TotalTurns);
        A.Eq("shop", e.Projects[0].Name);
        A.Eq(2, e.Projects.Count);
        A.True(Math.Abs(e.Projects[0].Share - 2.0 / 3) < 0.001);
        A.True(e.Headline(30).Contains("2 sa"), e.Headline(30));
        A.True(e.TopLine!.Contains("shop"));
        A.Eq(5400.0, e.BySource["claude"]);
        File.Delete(file);
    }
}
