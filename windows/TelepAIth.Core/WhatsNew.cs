using System.Text.Json.Nodes;
using static TelepAIth.Core.Text;

namespace TelepAIth.Core;

/// <summary>
/// Yenilikler (Mac'te WhatsNew.swift, aynı kurallar): assets/whatsnew.json'dan gömülü liste ve GitHub sürüm notları.
/// Güncellemeye basınca kısaca ne geldiğini, güncellemeden sonra da yeni bir özelliği robot söyler.
/// </summary>
public static class WhatsNew
{
    public sealed record Entry(string Version, IReadOnlyList<string> Tr, IReadOnlyList<string> En)
    {
        public IReadOnlyList<string> Items => Lang.Current == Language.Tr ? Tr : En;
    }

    private static List<Entry>? _all;

    public static IReadOnlyList<Entry> All => _all ??= Parse(WhatsNewData.Json);

    public static List<Entry> Parse(string json)
    {
        var list = new List<Entry>();
        if (JsonNode.Parse(json) is not JsonArray arr) return list;
        foreach (var n in arr.OfType<JsonObject>())
        {
            static List<string> Items(JsonNode? a) => (a as JsonArray)?.Select(x => x?.GetValue<string>() ?? "").Where(s => s.Length > 0).ToList() ?? new();
            list.Add(new Entry(n.Str("version") ?? "", Items(n["tr"]), Items(n["en"])));
        }
        return list;
    }

    public static Entry? For(string version) => All.FirstOrDefault(e => e.Version == version.TrimStart('v'));

    /// <summary>
    /// Sürümün kısa özeti: GitHub notlarındaki "&lt;!-- tr --&gt;" / "&lt;!-- en --&gt;" bölümü, yoksa gömülü liste,
    /// o da yoksa notlardaki "- " maddeleri ("Full Changelog" gibi satırlar atlanır).
    /// </summary>
    public static List<string> Summary(string version, string? notes, int max = 4)
    {
        var lines = (notes ?? "").Replace("\r", "").Split('\n').Select(l => l.Trim()).ToList();
        var marker = Lang.Current == Language.Tr ? "<!-- tr -->" : "<!-- en -->";
        var start = lines.IndexOf(marker);
        var items = new List<string>();
        if (start >= 0)
            items = lines.Skip(start + 1).TakeWhile(l => !l.StartsWith("<!--")).Where(l => l.StartsWith("- ")).Select(l => l[2..].Trim()).ToList();
        if (items.Count == 0 && For(version) is { } e) items = e.Items.ToList();
        if (items.Count == 0)
            items = lines.Where(l => l.StartsWith("- ") || l.StartsWith("* ")).Select(l => l[2..].Trim())
                .Where(l => !l.Contains("http") && !l.Contains("@")).ToList();
        return items.Take(max).ToList();
    }

    /// <summary>Güncellemeye basınca balonda: "⬆️ 0.23.0'da neler var: • …"</summary>
    public static string Bubble(string version, IReadOnlyList<string> items) =>
        "⬆️ " + L($"{version}'da neler var:", $"What's new in {version}:") + (items.Count == 0 ? "" : "\n• " + string.Join("\n• ", items));

    /// <summary>Güncellemeden sonra robotun söylediği (ilk madde)</summary>
    public static string? AfterUpdate(string version) =>
        For(version) is { Items.Count: > 0 } e
            ? "🎁 " + L($"{version} geldi! Şuna bakabilirsin: ", $"{version} is here! Check this out: ") + e.Items[0]
            : null;
}
