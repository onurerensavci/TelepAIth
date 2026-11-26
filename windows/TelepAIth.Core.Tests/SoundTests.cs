using TelepAIth.Core;

public static partial class Tests
{
    public static void SoundKindsAndNotices()
    {
        // Ayarlar: varsayılan açık, kapatılınca kapalı, sessize alınca hepsi susar
        A.Eq(8, Text.SoundKinds.Length);
        A.True(Text.SoundKinds.All(k => Prefs.Sound(k.Id) == (k.Id != "background")));   // "arkada çalışınca" baştan kapalı
        Prefs.SetSound("done", false);
        A.True(!Prefs.SoundOn("done") && Prefs.SoundOn("waiting"));
        Prefs.Muted = true;
        A.True(!Prefs.SoundOn("waiting"));
        Prefs.Muted = false;
        Prefs.SetSound("done", true);

        // Her bildirim kendi türünü taşır
        var m = new RobotModel("claude");
        m.Apply(new AgentEvent("claude", "s", EventKind.Prompt, RobotState.Thinking, "x"));
        A.Eq("waiting", m.Apply(new AgentEvent("claude", "s", EventKind.Waiting, RobotState.Waiting, "onay"))!.Kind);
        A.Eq("error", m.Apply(new AgentEvent("claude", "s", EventKind.Failure, RobotState.Error, "hata"))!.Kind);
        m.Apply(new AgentEvent("claude", "s", EventKind.Prompt, RobotState.Thinking, "x"));
        A.Eq("done", m.Apply(new AgentEvent("claude", "s", EventKind.Stop, RobotState.Done, "bitti") { ForceNotify = true })!.Kind);
        A.Eq("alert", m.Apply(new AgentEvent("claude", "s", EventKind.Insight, text: "Takıldı"))!.Kind);
        A.Eq("usage", m.Apply(new AgentEvent("claude", "usage", EventKind.Insight, text: "%80"))!.Kind);
        A.Eq("usage", m.Apply(new AgentEvent("claude", "q", EventKind.Quota, RobotState.Error, "Kota bitti") { ForceNotify = true })!.Kind);
    }
}
