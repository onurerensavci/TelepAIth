using System.Text.Json.Nodes;

namespace TelepAIth.Core;

public readonly record struct Rgb(byte R, byte G, byte B)
{
    public static Rgb? Parse(string hex)
    {
        var s = hex.Trim().TrimStart('#');
        if (s.Length != 6 || !uint.TryParse(s, System.Globalization.NumberStyles.HexNumber, null, out var v)) return null;
        return new Rgb((byte)((v >> 16) & 0xFF), (byte)((v >> 8) & 0xFF), (byte)(v & 0xFF));
    }

    /// <summary>Başka bir renge doğru karıştır (0: bu renk, 1: diğeri)</summary>
    public Rgb Mix(Rgb other, double t) => new(
        (byte)Math.Round(R + (other.R - R) * t),
        (byte)Math.Round(G + (other.G - G) * t),
        (byte)Math.Round(B + (other.B - B) * t));

    public static readonly Rgb White = new(255, 255, 255);
}

public sealed record SourceTheme(string Id, string DisplayName, Rgb Color);

/// <summary>Kaynak (AI) başına isim ve renk. ~/.telepaith/config.json ile değiştirilebilir.</summary>
public sealed class Themes
{
    public static Themes Shared { get; } = new();

    private static readonly Dictionary<string, string> Aliases = new()
    {
        ["claude"] = "claude", ["claude-code"] = "claude", ["claudecode"] = "claude", ["anthropic"] = "claude",
        ["gpt"] = "gpt", ["codex"] = "gpt", ["openai"] = "gpt", ["chatgpt"] = "gpt",
        ["gemini"] = "gemini", ["google"] = "gemini",
    };

    private static readonly Dictionary<string, (string Name, string Hex)> BuiltIn = new()
    {
        ["claude"] = ("Claude", "#D97757"),
        ["gpt"] = ("GPT", "#3B82F6"),
        ["gemini"] = ("Gemini", "#8B5CF6"),
    };

    private Dictionary<string, (string? Name, string? Hex)> _custom = new();
    private Dictionary<string, string> _appSources = new();   // süreç adı (küçük harf) → kaynak

    public static string Canonical(string raw)
    {
        var key = raw.Trim().ToLowerInvariant();
        if (key.Length == 0) return "custom";
        return Aliases.TryGetValue(key, out var v) ? v : key;
    }

    /// <summary>config.json'daki "apps" eşlemesi: {"cursor": "claude"} (süreç adı)</summary>
    public string? AppSource(string processName)
    {
        var key = processName.ToLowerInvariant().Replace(".exe", "");
        return _appSources.TryGetValue(key, out var v) ? v : null;
    }

    public SourceTheme Theme(string source)
    {
        BuiltIn.TryGetValue(source, out var b);
        _custom.TryGetValue(source, out var u);
        var name = u.Name ?? b.Name ?? (source.Length > 0 ? char.ToUpperInvariant(source[0]) + source[1..] : source);
        var hex = u.Hex ?? b.Hex ?? "#8E8E93";
        return new SourceTheme(source, name, Rgb.Parse(hex) ?? new Rgb(142, 142, 147));
    }

    public void Reload()
    {
        _custom = new();
        _appSources = new();
        try
        {
            if (!File.Exists(AppInfo.ConfigFile)) return;
            if (JsonNode.Parse(File.ReadAllText(AppInfo.ConfigFile)) is not JsonObject root) return;
            if (root["longTurnSeconds"] is JsonValue lv && lv.TryGetValue<double>(out var seconds)) Prefs.LongTurnSeconds = seconds;
            if (root["apps"] is JsonObject apps)
            {
                foreach (var (process, value) in apps)
                    if (value is JsonValue v && v.TryGetValue<string>(out var s))
                        _appSources[process.ToLowerInvariant().Replace(".exe", "")] = Canonical(s);
            }
            if (root["sources"] is JsonObject sources)
            {
                foreach (var (key, value) in sources)
                {
                    if (value is not JsonObject d) continue;
                    _custom[Canonical(key)] = (d["name"]?.GetValue<string>(), d["color"]?.GetValue<string>());
                }
            }
        }
        catch { /* bozuk config: varsayılanlar */ }
    }

    /// <summary>İlk açılışta örnek bir config.json yazar.</summary>
    public static void WriteExampleConfigIfMissing()
    {
        if (File.Exists(AppInfo.ConfigFile)) return;
        File.WriteAllText(AppInfo.ConfigFile, """
        {
          "longTurnSeconds": 20,
          "sources": {
            "claude": { "name": "Claude", "color": "#D97757" },
            "gpt":    { "name": "GPT",    "color": "#3B82F6" },
            "gemini": { "name": "Gemini", "color": "#8B5CF6" }
          }
        }

        """);
    }
}
