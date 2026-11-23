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

    /// <summary>Minik kafalar: gösterilen kafanın dışında çalışan/bekleyen tüm oturumlar (gösterilen oturum hariç)</summary>
    public static List<RobotModel.MiniSession> Minis(IEnumerable<RobotModel> models, RobotModel current, DateTime now)
    {
        var minis = new List<RobotModel.MiniSession>();
        foreach (var m in models)
            minis.AddRange(m.MiniSessions(ReferenceEquals(m, current) ? m.BestSessionId : null, now));
        return minis;
    }
}
