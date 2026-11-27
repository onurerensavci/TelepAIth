using TelepAIth.Core;

public static partial class Tests
{
    public static void WhatsNewSummaries()
    {
        A.True(WhatsNew.For("0.23.0") != null && WhatsNew.For("v0.23.0") != null);
        var notes = "## Yenilikler\n<!-- tr -->\n- Bir\n- İki\n\n## What's new\n<!-- en -->\n- One\n<!-- end -->\n\n**Full Changelog**: https://x";
        var s = WhatsNew.Summary("9.9.9", notes);
        A.Eq(2, s.Count);
        A.Eq("Bir", s[0]);
        // Notlarda bölüm yoksa gömülü liste; o da yoksa boş
        A.Eq(WhatsNew.For("0.23.0")!.Tr[0], WhatsNew.Summary("0.23.0", "**Full Changelog**: https://x")[0]);
        A.True(WhatsNew.Summary("9.9.9", "**Full Changelog**: https://x").Count == 0);
        A.Eq("\n• A\n• B", WhatsNew.Bullets(new[] { "A", "B" }));
        A.Eq("", WhatsNew.Bullets(Array.Empty<string>()));
        A.True(WhatsNew.AfterUpdate("0.23.0")!.StartsWith("🎁 0.23.0 geldi! Neler var:\n• "));
        A.True(WhatsNew.AfterUpdate("0.0.1") == null);
    }
}
