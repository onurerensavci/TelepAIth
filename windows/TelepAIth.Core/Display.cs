namespace TelepAIth.Core;

/// <summary>
/// Birden fazla AI varken büyük kafada hangisinin görüneceğine karar verir (Mac'teki RobotModel.pickDisplay'in aynısı).
/// Kural: seni bekleyen > hata > çalışan > bitti > boşta. Eşitlikte bu hâle en son giren öne çıkar;
/// aşama mesajları ("bakıyor", "yazıyor"…) sırayı değiştirmez, yoksa iki AI aynı anda çalışırken kafa sürekli gidip gelir.
/// </summary>
public static class DisplayPicker
{
    /// <summary>Eşitlik bozucu: çalışıyor/bekliyorsa bu hâle giriş anı, değilse son gerçek olay</summary>
    public static DateTime Key(RobotModel m) =>
        m.State.IsWorking() || m.State is RobotState.Waiting or RobotState.Error
            ? m.ActiveSince
            : m.LastRealEvent ?? DateTime.MinValue;

    /// <summary>Gösterilmesi gereken model; değişiklik gerekmiyorsa null.</summary>
    public static RobotModel? Pick(IEnumerable<RobotModel> models, RobotModel current, DateTime now)
    {
        RobotModel? best = null;
        foreach (var m in models)
        {
            if (m.LastRealEvent == null) continue;
            if (best == null || m.State.Priority() > best.State.Priority()
                || (m.State.Priority() == best.State.Priority() && Key(m) > Key(best)))
                best = m;
        }
        if (best == null || ReferenceEquals(best, current)) return null;
        // İşini yeni bitiren başparmağını göstersin; bu arada sadece seni bekleyen bir şey öne geçebilir
        if (current.CelebrateStart is { } cs && (now - cs).TotalSeconds < 2.4 && best.State != RobotState.Waiting) return null;
        var higher = best.State.Priority() > current.State.Priority();
        var sameButNewer = best.State.Priority() == current.State.Priority()
                           && best.State.Priority() >= RobotState.Thinking.Priority()
                           && Key(best) > Key(current);
        return higher || sameButNewer ? best : null;
    }

    /// <summary>Gözler imleci izlemeye başlamadan önce, son işin üstünden geçmesi gereken süre</summary>
    public const double GazeDelay = 20;

    /// <summary>
    /// Gözler imleci izleyebilir mi? Hiçbir AI'ın hiçbir sohbeti çalışmıyor / seni beklemiyor olmalı ve
    /// son iş biteli en az 20 sn geçmiş olmalı. Çalışırken robot işine bakar.
    /// </summary>
    public static bool CanGaze(IEnumerable<RobotModel> models, DateTime now) =>
        models.All(m => (now - m.LastBusyAt).TotalSeconds >= GazeDelay);

    /// <summary>
    /// Öndeki AI uygulaması gösterilir; ama o boştayken başka bir AI çalışıyor ya da seni bekliyorsa
    /// büyük kafada çalışan görünsün (robot iş yokmuş gibi durmasın).
    /// </summary>
    public static bool PinWins(RobotModel pinned, IEnumerable<RobotModel> models) =>
        pinned.State.Priority() >= RobotState.Thinking.Priority()
        || !models.Any(m => !ReferenceEquals(m, pinned) && m.State.Priority() >= RobotState.Thinking.Priority());

    /// <summary>
    /// Kafadaki küçük ışıklar: büyük kafada ve minik kafalarda görünmeyen, çalışan ya da seni bekleyen diğer sohbetler
    /// (seni bekleyenler önce). minisShown: minik kafalar açık mı (kapalıysa öteki AI'ların sohbetleri de ışık olur).
    /// </summary>
    public static List<RobotState> Extras(IEnumerable<RobotModel> models, RobotModel current, DateTime now, bool minisShown = true)
    {
        var extras = new List<RobotState>();
        foreach (var m in models)
        {
            var all = m.MiniSessions(ReferenceEquals(m, current) ? m.BestSessionId : null, now);
            var states = all.Select(x => x.State).OrderByDescending(s => s.Priority()).ToList();
            // Öteki AI'ın en acil sohbeti zaten minik kafada
            if (!ReferenceEquals(m, current) && minisShown && states.Count > 0) states.RemoveAt(0);
            extras.AddRange(states);
        }
        return extras.OrderByDescending(s => s.Priority()).ToList();
    }

    /// <summary>
    /// Minik kafalar: büyük kafada gösterilmeyen her AI için en fazla bir tane (Claude büyükse GPT, GPT büyükse Claude).
    /// O AI'ın birden çok sohbeti çalışıyorsa en acil olanı gösterilir. Gösterilen AI'ın diğer sohbetleri
    /// ayrı kafa olmaz: büyük kafanın "çalışıyor" hâlinde ve bildirimlerde görünür.
    /// </summary>
    public static List<RobotModel.MiniSession> Minis(IEnumerable<RobotModel> models, RobotModel current, DateTime now)
    {
        var minis = new List<RobotModel.MiniSession>();
        foreach (var m in models)
        {
            if (ReferenceEquals(m, current)) continue;
            var all = m.MiniSessions(null, now);
            if (all.Count == 0) continue;
            var best = all.OrderByDescending(x => x.State.Priority()).First();
            var label = all.Count > 1 ? best.Label + Text.L($" · +{all.Count - 1} sohbet", $" · +{all.Count - 1} more") : best.Label;
            minis.Add(best with { Id = m.Source, Label = label });   // AI başına sabit kimlik: kafa yerinde kalsın
        }
        return minis;
    }
}
