using System.Text.Json.Nodes;
using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

// Robotun odası (Mac'te Room.swift, aynı kurallar): gardırop, seviye ve başarımlar, emek, kullanım.

/// <summary>
/// Boya: düz renk ("#RRGGBB(AA)" ya da "theme…") veya ışık geçişi: doğrusal [x1,y1,x2,y2] / dairesel [cx,cy,r],
/// duraklar (konum 0…1, renk). Koordinatlar 100×100 kafa alanında; parçalara hacim (3B görünüm) verir.
/// </summary>
public sealed record OutfitPaint(string? Color, double[]? Linear, double[]? Radial, IReadOnlyList<(double Offset, string Color)> Stops)
{
    public static OutfitPaint? From(JsonNode? node)
    {
        if (node is JsonValue v && v.TryGetValue<string>(out var s)) return new OutfitPaint(s, null, null, Array.Empty<(double, string)>());
        if (node is not JsonObject o) return null;
        var stops = (o["stops"] as JsonArray ?? new JsonArray()).OfType<JsonArray>()
            .Select(a => (a[0]!.GetValue<double>(), a[1]!.GetValue<string>())).ToList();
        static double[]? Nums(JsonNode? n) => (n as JsonArray)?.Select(x => x!.GetValue<double>()).ToArray();
        return new OutfitPaint(null, Nums(o["lin"]), Nums(o["rad"]), stops);
    }
}

/// <summary>
/// Şeklin hareketi (Mac'te OutfitAnim, aynı formüller): sway (Pivot etrafında ±Amount derece), bob (±Amount nokta
/// yukarı-aşağı), beat (1±Amount ölçek), rise (Amount nokta yükselip söner), twinkle (arada bir parlayıp söner),
/// slide (±Amount nokta kayan parlama). Speed: saniyedeki tur, Offset: faz (0…1).
/// </summary>
public sealed record OutfitAnim(string Kind, double Amount, double Speed, double Offset, double[]? Pivot)
{
    public static OutfitAnim? From(JsonNode? node) =>
        node is JsonObject o
            ? new OutfitAnim(o.Str("k") ?? "", o.Num("a") ?? 0, o.Num("s") ?? 1, o.Num("o") ?? 0,
                             (o["p"] as JsonArray)?.Select(x => x!.GetValue<double>()).ToArray())
            : null;

    /// <summary>t anındaki kayma, dönme (derece), ölçek ve saydamlık</summary>
    public (double Dx, double Dy, double Rotate, double Scale, double Opacity) At(double t)
    {
        var ph = Speed * t + Offset;
        var f = ph - Math.Floor(ph);
        switch (Kind)
        {
            case "sway": return (0, 0, Amount * Math.Sin(2 * Math.PI * ph), 1, 1);
            case "bob": return (0, Amount * Math.Sin(2 * Math.PI * ph), 0, 1, 1);
            case "beat": return (0, 0, 0, 1 + Amount * Math.Pow(Math.Max(0, Math.Sin(2 * Math.PI * ph)), 2), 1);
            case "rise": return (0, -Amount * f, 0, 1, Math.Sin(Math.PI * f));
            case "twinkle":
            {
                var op = f < 0.2 ? Math.Sin(Math.PI * f / 0.2) : 0;
                return (0, 0, 0, 0.5 + 0.5 * op, op);
            }
            case "slide":
            {
                var op = f < 0.35 ? Math.Sin(Math.PI * f / 0.35) : 0;
                return (-Amount + 2 * Amount * Math.Min(1, f / 0.35), 0, 0, 1, op);
            }
            default: return (0, 0, 0, 1, 1);
        }
    }
}

/// <summary>Gardırop parçasının bir şekli: SVG yolu, elips [cx,cy,rx,ry] ya da dikdörtgen [x,y,w,h,r]; 100×100 kafa alanında.</summary>
public sealed record OutfitShape(string? Path, double[]? Ellipse, double[]? Rect, OutfitPaint? Fill, OutfitPaint? Stroke, double Width,
                                 OutfitAnim? Anim = null);

public sealed record OutfitItem(string Id, string Slot, string NameTr, string NameEn, int Level, string? Achievement, IReadOnlyList<OutfitShape> Shapes)
{
    public string Name => L(NameTr, NameEn);
}

public static class Outfits
{
    public static readonly string[] Slots = { "head", "eyes", "face", "side" };

    public static string SlotName(string slot) => slot switch
    {
        "head" => L("Baş", "Head"),
        "eyes" => L("Gözlük", "Glasses"),
        "face" => L("Yüz", "Face"),
        _ => L("Yanında", "Beside"),
    };

    private static IReadOnlyList<OutfitItem>? _all;
    public static IReadOnlyList<OutfitItem> All => _all ??= Parse(OutfitData.Json);

    public static OutfitItem? Find(string? id) => id == null ? null : All.FirstOrDefault(i => i.Id == id);

    public static List<OutfitItem> Parse(string json)
    {
        var list = new List<OutfitItem>();
        if (JsonNode.Parse(json) is not JsonArray items) return list;
        foreach (var node in items.OfType<JsonObject>())
        {
            var shapes = new List<OutfitShape>();
            foreach (var s in (node["shapes"] as JsonArray ?? new JsonArray()).OfType<JsonObject>())
            {
                static double[]? Nums(JsonNode? n) => (n as JsonArray)?.Select(x => x!.GetValue<double>()).ToArray();
                shapes.Add(new OutfitShape(s.Str("d"), Nums(s["ellipse"]), Nums(s["rect"]), OutfitPaint.From(s["fill"]), OutfitPaint.From(s["stroke"]), s.Num("w") ?? 1,
                    OutfitAnim.From(s["anim"])));
            }
            list.Add(new OutfitItem(node.Str("id") ?? "", node.Str("slot") ?? "head", node.Str("tr") ?? "", node.Str("en") ?? "",
                (int)(node.Num("level") ?? 0), node.Str("achievement"), shapes));
        }
        return list;
    }

    /// <summary>Renk: "#RRGGBB", "#RRGGBBAA" ya da AI rengi ("theme", "theme-dark", "theme-light"). (renk, saydamlık)</summary>
    public static (Rgb Color, double Alpha) Color(string token, Rgb theme)
    {
        switch (token)
        {
            case "theme": return (theme, 1);
            case "theme-dark": return (new Rgb((byte)(theme.R * 0.72), (byte)(theme.G * 0.72), (byte)(theme.B * 0.72)), 1);
            case "theme-light": return (theme.Mix(Rgb.White, 0.35), 1);
        }
        var hex = token.TrimStart('#');
        if (hex.Length is not (6 or 8)) return (Rgb.White, 1);
        var v = Convert.ToUInt32(hex, 16);
        return hex.Length == 6
            ? (new Rgb((byte)(v >> 16), (byte)(v >> 8), (byte)v), 1)
            : (new Rgb((byte)(v >> 24), (byte)(v >> 16), (byte)(v >> 8)), (v & 0xFF) / 255.0);
    }

    /// <summary>Takılı ve açık parçalar (çizim sırası: yanında, yüz, gözlük, baş)</summary>
    public static List<OutfitItem> Worn(ProgressData p) =>
        new[] { "side", "face", "eyes", "head" }
            .Select(slot => Find(Prefs.Outfit(slot)))
            .Where(i => i != null && Unlocked(i, p))
            .Select(i => i!).ToList();

    /// <summary>Parça açık mı (seviyeyle ya da başarımla)?</summary>
    public static bool Unlocked(OutfitItem item, ProgressData p) =>
        item.Achievement is { } a ? Achievements.IsDone(a, p) : Levels.Level(p) >= item.Level;

    /// <summary>Kilitliyse ne zaman açılır: "Seviye 10" ya da "Başarım: Büyük gün"</summary>
    public static string UnlockHint(OutfitItem item) =>
        item.Achievement is { } a
            ? L("Başarım: ", "Achievement: ") + (Achievements.Find(a)?.Title ?? a)
            : L($"Seviye {item.Level}", $"Level {item.Level}");
}

/// <summary>Ömür boyu sayaçlar: seviye ve başarımlar bunlardan hesaplanır.</summary>
public sealed class ProgressData
{
    public int Turns { get; set; }
    public double Seconds { get; set; }
    public int Edits { get; set; }
    public int Tools { get; set; }
    public int Waits { get; set; }
    public int ActiveDays { get; set; }
    public string LastDay { get; set; } = "";
    public int Streak { get; set; }
    public int BestStreak { get; set; }
    public int MaxParallel { get; set; }
    public int NightTurns { get; set; }
    public int EarlyTurns { get; set; }
    public int BigDay { get; set; }
    public double LongestTurn { get; set; }
    public int CiPassed { get; set; }
    public List<string> Sources { get; set; } = new();
    public List<string> Unlocked { get; set; } = new();   // söylenmiş başarımlar
    public int ToldLevel { get; set; } = 1;
}

/// <summary>Sayaçları tutar ve kaydeder; yeni başarımları/seviyeyi bir kez söylemek için sıraya koyar.</summary>
public sealed class Progress
{
    public static Progress Shared { get; } = new(AppInfo.ProgressFile);

    private readonly string? _file;
    private readonly object _gate = new();
    public ProgressData Data { get; private set; } = new();

    public Progress(string? file)
    {
        _file = file;
        if (file == null || !File.Exists(file)) return;
        try { Data = System.Text.Json.JsonSerializer.Deserialize<ProgressData>(File.ReadAllText(file)) ?? new(); }
        catch { Data = new(); }
    }

    public ProgressData Snapshot()
    {
        lock (_gate) return System.Text.Json.JsonSerializer.Deserialize<ProgressData>(System.Text.Json.JsonSerializer.Serialize(Data))!;
    }

    /// <summary>Bir tur bitti. todayTurns: bugün (bu dahil) kaç tur.</summary>
    public void Turn(string source, double seconds, int tools, int edits, DateTime at, int todayTurns)
    {
        lock (_gate)
        {
            var d = Data;
            d.Turns++;
            d.Seconds += Math.Max(0, seconds);
            d.Tools += tools;
            d.Edits += edits;
            d.LongestTurn = Math.Max(d.LongestTurn, seconds);
            d.BigDay = Math.Max(d.BigDay, todayTurns);
            if (at.Hour < 5) d.NightTurns++;
            else if (at.Hour < 8) d.EarlyTurns++;
            var src = Themes.Canonical(source);
            if (!d.Sources.Contains(src)) d.Sources.Add(src);
            var day = DailyStats.DayKey(at);
            if (d.LastDay != day)
            {
                d.ActiveDays++;
                d.Streak = d.LastDay == DailyStats.DayKey(at.AddDays(-1)) ? d.Streak + 1 : 1;
                d.BestStreak = Math.Max(d.BestStreak, d.Streak);
                d.LastDay = day;
            }
            Save();
        }
    }

    public void Wait() { lock (_gate) { Data.Waits++; Save(); } }
    public void Ci() { lock (_gate) { Data.CiPassed++; Save(); } }

    public void Parallel(int working)
    {
        lock (_gate)
        {
            if (working <= Data.MaxParallel) return;
            Data.MaxParallel = working;
            Save();
        }
    }

    /// <summary>Henüz söylenmemiş yeni başarımlar ve seviye (bir kez döner).</summary>
    public (List<Achievement> Achievements, int? Level) TakeNews()
    {
        lock (_gate)
        {
            var fresh = Core.Achievements.All.Where(a => a.Done(Data) && !Data.Unlocked.Contains(a.Id)).ToList();
            foreach (var a in fresh) Data.Unlocked.Add(a.Id);
            var level = Levels.Level(Data);
            int? up = level > Data.ToldLevel ? level : null;
            if (up != null) Data.ToldLevel = level;
            if (fresh.Count > 0 || up != null) Save();
            return (fresh, up);
        }
    }

    private void Save()
    {
        if (_file == null) return;
        try { File.WriteAllText(_file, System.Text.Json.JsonSerializer.Serialize(Data)); }
        catch { /* yazılamadı */ }
    }
}

public static class Levels
{
    /// <summary>XP: tur 10, düzenleme 2, çalışılan dakika 1, aktif gün 25, geçen CI 15.</summary>
    public static long Xp(ProgressData p) =>
        p.Turns * 10L + p.Edits * 2L + (long)(p.Seconds / 60) + p.ActiveDays * 25L + p.CiPassed * 15L;

    /// <summary>n. seviyeye çıkmak için gereken toplam XP: 50·n·(n−1) (2: 100, 3: 300, 10: 4500).</summary>
    public static long Need(int level) => 50L * level * (level - 1);

    public static int Level(long xp)
    {
        var n = (int)Math.Floor((1 + Math.Sqrt(1 + 8.0 * xp / 100)) / 2);
        while (Need(n + 1) <= xp) n++;
        while (n > 1 && Need(n) > xp) n--;
        return Math.Max(1, n);
    }

    public static int Level(ProgressData p) => Level(Xp(p));

    /// <summary>Bu seviyenin içinde ne kadar ilerledi (0…1) ve sonrakine kaç XP kaldı.</summary>
    public static (double Fraction, long Left) Next(ProgressData p)
    {
        var xp = Xp(p);
        var level = Level(xp);
        long from = Need(level), to = Need(level + 1);
        return ((double)(xp - from) / (to - from), to - xp);
    }
}

public sealed record Achievement(string Id, string Category, int Tier, string TitleTr, string TitleEn, string DescTr, string DescEn,
                                 Func<ProgressData, double> Value, double Target)
{
    public string Title => L(TitleTr, TitleEn);
    public string Description => L(DescTr, DescEn);
    public bool Done(ProgressData p) => Value(p) >= Target;
    public double Fraction(ProgressData p) => Math.Clamp(Value(p) / Target, 0, 1);
}

public static class Achievements
{
    public static readonly string[] Categories = { "chat", "code", "time", "team" };

    public static string CategoryName(string c) => c switch
    {
        "chat" => L("Sohbet", "Chat"),
        "code" => L("Kod", "Code"),
        "time" => L("Zaman", "Time"),
        _ => L("Ekip", "Team"),
    };

    /// <summary>0 Kolay, 1 Orta, 2 Zor, 3 İmkânsız</summary>
    public static string TierName(int tier) => tier switch
    {
        0 => L("Kolay", "Easy"),
        1 => L("Orta", "Medium"),
        2 => L("Zor", "Hard"),
        _ => L("İmkânsız", "Impossible"),
    };

    private static Achievement A(string id, string cat, int tier, string tr, string en, string dtr, string den, Func<ProgressData, double> v, double target) =>
        new(id, cat, tier, tr, en, dtr, den, v, target);

    public static readonly IReadOnlyList<Achievement> All = new[]
    {
        A("hello", "chat", 0, "Merhaba", "Hello", "1 tur", "1 turn", p => p.Turns, 1),
        A("chatty", "chat", 0, "Geveze", "Chatty", "10 tur", "10 turns", p => p.Turns, 10),
        A("talker", "chat", 1, "Konuşkan", "Talker", "250 tur", "250 turns", p => p.Turns, 250),
        A("storyteller", "chat", 1, "Hikâyeci", "Storyteller", "1.000 tur", "1,000 turns", p => p.Turns, 1000),
        A("orator", "chat", 2, "Hatip", "Orator", "5.000 tur", "5,000 turns", p => p.Turns, 5000),
        A("legend", "chat", 3, "Efsane", "Legend", "25.000 tur", "25,000 turns", p => p.Turns, 25000),
        A("bigday", "chat", 1, "Büyük gün", "Big day", "bir günde 50 tur", "50 turns in a day", p => p.BigDay, 50),
        A("crazyday", "chat", 2, "Çılgın gün", "Wild day", "bir günde 200 tur", "200 turns in a day", p => p.BigDay, 200),
        A("patient", "chat", 1, "Sabırlı", "Patient", "AI 100 kez seni bekledi", "the AI waited for you 100 times", p => p.Waits, 100),

        A("firsttouch", "code", 0, "İlk dokunuş", "First touch", "1 düzenleme", "1 edit", p => p.Edits, 1),
        A("handy", "code", 0, "Eli çabuk", "Handy", "50 araç çağrısı", "50 tool calls", p => p.Tools, 50),
        A("builder", "code", 1, "Usta", "Builder", "500 düzenleme", "500 edits", p => p.Edits, 500),
        A("architect", "code", 2, "Mimar", "Architect", "5.000 düzenleme", "5,000 edits", p => p.Edits, 5000),
        A("toolbox", "code", 2, "Alet çantası", "Toolbox", "10.000 araç çağrısı", "10,000 tool calls", p => p.Tools, 10000),
        A("green", "code", 0, "İlk yeşil", "First green", "push'tan sonra geçen bir CI", "a CI run that passed after a push", p => p.CiPassed, 1),
        A("greenstreak", "code", 1, "Yemyeşil", "All green", "25 geçen CI", "25 passing CI runs", p => p.CiPassed, 25),

        A("hour", "time", 0, "İlk saat", "First hour", "toplam 1 saat çalışma", "1 hour of work in total", p => p.Seconds / 3600, 1),
        A("tenhours", "time", 1, "On saat", "Ten hours", "toplam 10 saat", "10 hours in total", p => p.Seconds / 3600, 10),
        A("hundred", "time", 2, "Yüz saat", "Hundred hours", "toplam 100 saat", "100 hours in total", p => p.Seconds / 3600, 100),
        A("thousand", "time", 3, "Bin saat", "Thousand hours", "toplam 1.000 saat", "1,000 hours in total", p => p.Seconds / 3600, 1000),
        A("marathon", "time", 1, "Maraton", "Marathon", "tek turda 30 dakika", "30 minutes in one turn", p => p.LongestTurn / 60, 30),
        A("night", "time", 1, "Gece kuşu", "Night owl", "gece yarısından sonra 10 tur", "10 turns after midnight", p => p.NightTurns, 10),
        A("early", "time", 1, "Erkenci", "Early bird", "sabah 5–8 arası 10 tur", "10 turns between 5 and 8 am", p => p.EarlyTurns, 10),
        A("streak7", "time", 1, "Bir hafta", "One week", "7 gün üst üste", "7 days in a row", p => p.BestStreak, 7),
        A("streak30", "time", 2, "Bir ay", "One month", "30 gün üst üste", "30 days in a row", p => p.BestStreak, 30),
        A("days100", "time", 2, "Yüz gün", "Hundred days", "100 aktif gün", "100 active days", p => p.ActiveDays, 100),

        A("team", "team", 0, "İkili", "Duo", "aynı anda 2 sohbet çalışıyor", "2 chats working at once", p => p.MaxParallel, 2),
        A("lead", "team", 1, "Takım lideri", "Team lead", "aynı anda 3 sohbet", "3 chats at once", p => p.MaxParallel, 3),
        A("orchestra", "team", 2, "Orkestra", "Orchestra", "aynı anda 6 sohbet", "6 chats at once", p => p.MaxParallel, 6),
        A("polyglot", "team", 0, "Çok dilli", "Polyglot", "2 farklı AI", "2 different AIs", p => p.Sources.Count, 2),
        A("zoo", "team", 2, "Hayvanat bahçesi", "Zoo", "4 farklı AI", "4 different AIs", p => p.Sources.Count, 4),
    };

    public static Achievement? Find(string id) => All.FirstOrDefault(a => a.Id == id);
    public static bool IsDone(string id, ProgressData p) => Find(id)?.Done(p) ?? false;
}

/// <summary>Emek sekmesi: son N günde hangi AI ve hangi projede ne kadar çalışıldı.</summary>
public sealed record EffortDay(string Day, IReadOnlyDictionary<string, double> SecondsBySource);
public sealed record EffortProject(string Name, double Seconds, int Turns, double Share);
public sealed record Effort(IReadOnlyList<EffortDay> Days, IReadOnlyList<EffortProject> Projects,
                            IReadOnlyDictionary<string, double> BySource, double TotalSeconds, int TotalTurns, int TotalEdits)
{
    /// <summary>"Son 30 günde AI'ların 48 sa çalıştı."</summary>
    public string Headline(int days) => TotalSeconds < 60
        ? L($"Son {days} günde henüz iş yok.", $"No work in the last {days} days yet.")
        : L($"Son {days} günde AI'ların {ShortDuration(TotalSeconds)} çalıştı.", $"Your AIs worked {ShortDuration(TotalSeconds)} in the last {days} days.");

    public string? TopLine => Projects.FirstOrDefault() is { } top && TotalSeconds >= 60
        ? L($"En büyük pay {top.Name} projesinin: %{Math.Round(top.Share * 100)}.", $"{top.Name} took the biggest share: {Math.Round(top.Share * 100)}%.")
        : null;
}
