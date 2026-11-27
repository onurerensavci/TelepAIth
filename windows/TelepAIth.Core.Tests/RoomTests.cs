using TelepAIth.Core;

public static partial class Tests
{
    public static void OutfitsParseAndColors()
    {
        A.Eq(35, Outfits.All.Count);
        A.True(Outfits.All.All(i => Outfits.Slots.Contains(i.Slot) && i.Shapes.Count > 0 && i.Name.Length > 0));
        A.True(Outfits.All.Select(i => i.Id).Distinct().Count() == Outfits.All.Count);
        // Başarımla açılan parçaların başarımı var
        A.True(Outfits.All.Where(i => i.Achievement != null).All(i => Achievements.Find(i.Achievement!) != null));
        var (c, a) = Outfits.Color("#FF8FB180", new Rgb(0, 0, 0));
        A.True(c == new Rgb(0xFF, 0x8F, 0xB1) && Math.Abs(a - 0x80 / 255.0) < 0.001);
        A.True(Outfits.Color("theme", new Rgb(10, 20, 30)).Color == new Rgb(10, 20, 30));
        A.True(Outfits.Color("theme-dark", new Rgb(100, 100, 100)).Color == new Rgb(72, 72, 72));
        // Işık geçişleri (3B görünüm) okunuyor
        A.True(Outfits.Find("beanie")!.Shapes.Any(sh => sh.Fill?.Radial is { Length: 3 } && sh.Fill.Stops.Count >= 2));
        A.True(Outfits.Find("crown")!.Shapes.Any(sh => sh.Fill?.Linear is { Length: 4 }));
        // Hareketler: ponpon sallanır, buhar yükselip söner
        var sway = Outfits.Find("beanie")!.Shapes.First(sh => sh.Anim != null).Anim!;
        A.Eq("sway", sway.Kind);
        A.True(Math.Abs(sway.At(0.25 / sway.Speed).Rotate - sway.Amount) < 0.001);
        var rise = Outfits.Find("gramophone")!.Shapes.First(sh => sh.Anim?.Kind == "rise").Anim!;
        A.True(Math.Abs(rise.At(0.5 / rise.Speed).Dy + rise.Amount / 2) < 0.001 && Math.Abs(rise.At(0.5 / rise.Speed).Opacity - 1) < 0.001);
        var twinkle = new OutfitAnim("twinkle", 1, 1, 0, null);
        A.True(twinkle.At(0.1).Opacity > 0.99 && twinkle.At(0.5).Opacity == 0);
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
        var cap = Outfits.Find("beanie")!;
        A.True(!Outfits.Unlocked(cap, new ProgressData()));
        A.True(Outfits.Unlocked(cap, new ProgressData { Turns = 30 }));   // 300 XP = seviye 3
        A.True(Outfits.UnlockHint(Outfits.Find("scarf")!).Contains("Erkenci"));
    }

    public static void OutfitTypesAndNews()
    {
        // 7 tip × 5 parça: her yuvadan bir tane; ilk altısında biri gizli ödül, Teknolog'da gizli ödül yok
        A.Eq(7, Outfits.Types.Length);
        foreach (var t in Outfits.Types)
        {
            var items = Outfits.ItemsOf(t.Id);
            A.True(items.Select(i => i.Slot).OrderBy(x => x).SequenceEqual(Outfits.Slots.OrderBy(x => x)), t.Id);
            if (t.Id == "techie") { A.Eq(0, items.Count(i => i.Legendary)); A.True(items.All(i => i.Achievement == null && i.Level > 0), "teknolog seviyeyle"); continue; }
            A.Eq(1, items.Count(i => i.Legendary));
            A.True(items.First(i => i.Legendary).Achievement == null, t.Id);   // gizli ödül seviyeyle açılır
        }
        var p = new ProgressData();
        A.Eq("Gizli ödül", Outfits.DisplayName(Outfits.Find("crown")!, p));
        A.True(!Outfits.TypeComplete("coder", p));
        // Yeni açılanlar: ilk seferde sessizce kaydedilir, sonra yeni açılanlar bir kez söylenir
        var file = Path.Combine(Path.GetTempPath(), "tp-progress-" + Guid.NewGuid() + ".json");
        var pr = new Progress(file);
        A.True(pr.TakeOutfitNews().Items.Count == 0);
        for (var i = 0; i < 30; i++) pr.Turn("claude", 60, 1, 1, DateTime.Now, 1);
        var news = pr.TakeOutfitNews();
        A.True(news.Items.Any(i => i.Id == "beanie") && news.Items.Any(i => i.Id == "lanyard"));
        A.True(pr.TakeOutfitNews().Items.Count == 0);
        File.Delete(file);
        var lines = Outfits.NewsLines(news.Items, new List<OutfitType> { Outfits.FindType("king")! });
        A.True(lines[0].StartsWith("🎉 Gardıropta açıldı: "));
        A.True(lines[^1].Contains("Kral tipi tamamlandı"));
        A.True(Outfits.NewsLines(new List<OutfitItem> { Outfits.Find("crown")! }, new()).First().Contains("Gizli ödül açıldı: Taç"));
        p = new ProgressData { Turns = 5000, Edits = 5000, CiPassed = 30, EarlyTurns = 10, MaxParallel = 3, Sources = new() { "claude", "gpt" } };
        A.True(Outfits.TypeComplete("coder", p));
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
        // Tüm zamanlar: ilk kayıtlı günden (40 gün önce) bugüne
        var all = st.Effort(today, 0);
        A.Eq(41, all.Days.Count);
        A.Eq(3, all.Projects.Count);
        A.True(all.Headline(0).StartsWith("Şimdiye kadar"), all.Headline(0));
        File.Delete(file);
    }
}

public static partial class Tests
{
    public static void MenuTitlesCapitalized()
    {
        Lang.Set(Language.Tr);
        A.Eq("Robotun Odası", Text.MenuTitle("Robotun odası…"));
        A.Eq("Güncellemeleri Denetle", Text.MenuTitle("Güncellemeleri denetle…"));
        A.Eq("Robotu Bu Masaüstüne Getir", Text.MenuTitle("Robotu bu masaüstüne getir"));
        A.Eq("İzni Sıfırla ve Yeniden İste", Text.MenuTitle("İzni sıfırla ve yeniden iste"));
        A.Eq("Renkleri ve Kostümleri Yeniden Yükle", Text.MenuTitle("Renkleri ve kostümleri yeniden yükle"));
        A.Eq("⚠︎ Bildirimler macOS'ta Kapalı — Aç", Text.MenuTitle("⚠︎ Bildirimler macOS'ta kapalı — aç…"));
        A.Eq("Claude: İzin İstesin (İzin Ver / Reddet)", Text.MenuTitle("Claude: izin istesin (İzin ver / Reddet)"));
        A.Eq("1 Saat", Text.MenuTitle("1 saat"));
        Lang.Set(Language.En);
        A.Eq("Bring Robot to This Desktop", Text.MenuTitle("Bring robot to this desktop"));
        A.Eq("Robot's Room", Text.MenuTitle("Robot's room…"));
        Lang.Set(Language.Tr);
        // Yan menüdeki simge yazıları sohbet adı sayılmaz
        A.Eq("", SidebarChats.StripStatus("Includes an artifact"));
        A.Eq("Tarif", SidebarChats.StripStatus("Tarif, running"));
        var rows = SidebarChats.Parse(new[]
        {
            new SidebarItem("", "running", null, new RectD(0, 100, 8, 8)),
            new SidebarItem("Includes an artifact", "", null, new RectD(150, 100, 12, 12)),
            new SidebarItem("UGC video akışı", "", "https://claude.ai/chat/u1", new RectD(20, 96, 120, 16)),
        });
        A.Eq("UGC video akışı", rows[0].Row.Title);
        // Sohbetin içindeki yazılar (mesaj, mesaj düğmesi, kenar çubuğu düğmesi) sohbet sayılmaz: sadece bağlantısı olan satırlar
        var junk = SidebarChats.Parse(new[]
        {
            new SidebarItem("", "running", null, new RectD(300, 200, 8, 8)),
            new SidebarItem("You said: /Volumes/LaCie/spark", "", null, new RectD(320, 196, 300, 20)),
            new SidebarItem("", "running", null, new RectD(300, 260, 8, 8)),
            new SidebarItem("Show message actions for Claude", "", null, new RectD(320, 256, 30, 20)),
            new SidebarItem("", "running", null, new RectD(10, 10, 8, 8)),
            new SidebarItem("Sidebar", "", null, new RectD(30, 6, 30, 20)),
        });
        A.Eq(0, junk.Count);
        A.Eq("", SidebarChats.StripStatus("You said: merhaba"));
        A.Eq("Copywriting fikirleri", SidebarChats.StripStatus("Copywriting fikirleri"));
        // Otomatik güncelleme: sohbet çalışırken değil, 2 dakikadır sakinken
        var um = new RobotModel("claude");
        var ut = DateTime.Now;
        A.True(DisplayPicker.QuietForUpdate(new[] { um }, ut), "hiç sohbet yok: sakin");
        um.Apply(new AgentEvent("claude", "term-9", EventKind.Tool, RobotState.Running, "npm test"));
        um.Refresh(ut);
        A.True(!DisplayPicker.QuietForUpdate(new[] { um }, ut), "çalışırken güncelleme yok");
        A.True(DisplayPicker.QuietForUpdate(new[] { um }, ut.AddSeconds(121)), "2 dk sakin: güncellenebilir");
        // Çenedeki noktalar: en fazla 4, fazlası varsa 4. noktada "+"
        A.Eq((0, false), DisplayPicker.ExtrasDots(0));
        A.Eq((3, false), DisplayPicker.ExtrasDots(3));
        A.Eq((4, false), DisplayPicker.ExtrasDots(4));
        A.Eq((4, true), DisplayPicker.ExtrasDots(7));
        // Claude'un biçimi: durum sadece boşlukla, büyük harfle eklenir (kullanıcının günlüğündeki gerçek adlar)
        A.Eq(RobotState.Running, SidebarChats.StatusOf("SCAM OR LEGIT video konsepti Running"));
        A.Eq(RobotState.Running, SidebarChats.StatusOf("TelepAIth Running Includes an artifact"));
        A.Eq(RobotState.Waiting, SidebarChats.StatusOf("Spark Win Cash video Needs input"));
        A.True(SidebarChats.StatusOf("marathon running") == null, "küçük harf: adın parçası");
        A.True(SidebarChats.StatusOf("SCAM OR LEGIT video konsepti") == null);
        A.Eq("SCAM OR LEGIT video konsepti", SidebarChats.StripStatus("SCAM OR LEGIT video konsepti Running"));
        A.Eq("TelepAIth", SidebarChats.StripStatus("TelepAIth Running Includes an artifact"));
        A.Eq("marathon running", SidebarChats.StripStatus("marathon running"));
        var claudeRows = SidebarChats.Parse(new[]
        {
            new SidebarItem("SCAM OR LEGIT video konsepti Running", "", null, new RectD(10, 100, 240, 28)),
            new SidebarItem("Spark Win Cash video", "", null, new RectD(10, 130, 240, 28)),
            new SidebarItem("TelepAIth Running Includes an artifact", "", null, new RectD(10, 160, 240, 28)),
        });
        A.Eq(2, claudeRows.Count);
        A.True(claudeRows.Any(r => r.Row.Title == "SCAM OR LEGIT video konsepti" && r.Row.State == RobotState.Running));
        A.True(claudeRows.Any(r => r.Row.Title == "TelepAIth" && r.Row.State == RobotState.Running));
        // Claude'un adın sonuna eklediği işaretler temizlenir
        A.Eq("TelepAIth", SidebarChats.StripStatus("TelepAIth Includes an artifact"));
        A.Eq("Tarif", SidebarChats.StripStatus("Tarif, Starred · running"));
        A.Eq("Includes an artifact", SidebarChats.StripDecorations("Includes an artifact"));   // tek başına: ad değil, dokunma (gürültü filtresi eler)
        // Claude sohbetleri resmî bağlantıyla açılır
        A.Eq("claude://claude.ai/chat/0b6a5e2c-1d2f-4c3b-9a8e-123456789abc", SidebarChats.DeepLink("https://claude.ai/chat/0b6a5e2c-1d2f-4c3b-9a8e-123456789abc?x=1"));
        A.True(SidebarChats.DeepLink("https://claude.ai/recents") == null);
        A.True(SidebarChats.DeepLink("https://chatgpt.com/c/0b6a5e2c-1d2f") == null);
        A.True(SidebarChats.DeepLink(null) == null);
        // Açık sohbetin adı: adresi eşleşen bağlantı; yoksa seçili bağlantı; yoksa seçili satır (sekmeler sayılmaz)
        var side = new[]
        {
            new SidebarItem("Chats", "", "https://claude.ai/recents", new RectD(0, 0, 100, 20), true),
            new SidebarItem("Code", "", null, new RectD(0, 30, 100, 20), true),
            new SidebarItem("Video kurgusu", "", "https://claude.ai/chat/aaa", new RectD(0, 60, 100, 20)),
        };
        A.Eq("Video kurgusu", SidebarChats.CurrentTitle(side, "https://claude.ai/chat/aaa"));
        A.True(SidebarChats.CurrentTitle(side, null) == null);
        // Gerçek hata (günlükten): Claude'un "…bekliyor" diye biten cevabı sohbet satırı sanılıyordu
        var reply = new SidebarItem("içinde üç versiyonu kurdum: bir T, iki Spark. Hepsi 1080×1920, 30 fps, tam 60 sn. Render almadım, onay bekliyor", "", null, new RectD(300, 400, 500, 20));
        A.Eq(0, SidebarChats.Parse(new[] { reply }).Count);   // uzun metin: mesaj, sohbet adı değil
        var navRow = new SidebarItem("Spark videoları · running", "", null, new RectD(10, 100, 200, 20));
        var picked = SidebarChats.PickSidebar(new[] { (navRow, true, false), (reply, false, true), (new SidebarItem("Sidebar", "", null, new RectD(0, 0, 10, 10)), false, false) });
        A.True(picked.ViaNav && picked.Items.Count == 1 && picked.Items[0].Name == navRow.Name);
        var noNav = SidebarChats.PickSidebar(new[] { (navRow, false, false), (reply, false, true) });
        A.True(!noNav.ViaNav && noNav.Items.Count == 1);   // gezinme bölümü yoksa sohbet içeriği yine sayılmaz
        A.True(SidebarChats.IsNavigation("AXLandmarkNavigation", "") && SidebarChats.IsNavigation("navigation", "") && SidebarChats.IsNavigation("", "Sidebar"));
        A.True(!SidebarChats.IsNavigation("group", "Mesajlar") && SidebarChats.IsMainContent("AXLandmarkMain") && SidebarChats.IsMainContent("main"));
        var code = new[] { new SidebarItem("Klasördeki üç versiyonu karşılaştır", "", null, new RectD(0, 0, 200, 20), true) };
        A.Eq("Klasördeki üç versiyonu karşılaştır", SidebarChats.CurrentTitle(code, null));
    }
}
