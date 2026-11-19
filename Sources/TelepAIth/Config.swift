import AppKit

/// Uygulamanın adı ve sabitleri.
enum AppInfo {
    static let name = "TelepAIth"
    static let supportDirName = ".telepaith"
    static let hookMarker = "__telepaith_hook"
    static let defaultPort: UInt16 = 19850 // ClaudeBar 19847 kullanıyor, çakışmasın

    static var supportDir: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(supportDirName, isDirectory: true)
    }
    static var portFile: URL { supportDir.appendingPathComponent("port") }
    static var configFile: URL { supportDir.appendingPathComponent("config.json") }
    static var skinsDir: URL { supportDir.appendingPathComponent("skins", isDirectory: true) }
}

enum Layout {
    static let windowSize = CGSize(width: 280, height: 250)
    static let headSize = CGSize(width: 100, height: 100)
    static let margin: CGFloat = 16      // pencere kenarı ile kafa arası
    static let edgeInset: CGFloat = 14   // ekran köşesi ile kafa arası
}

enum Language: String, CaseIterable {
    case tr, en

    var displayName: String {
        switch self {
        case .tr: return "Türkçe"
        case .en: return "English"
        }
    }

    /// Kullanıcı seçmediyse sistem dili: Türkçe ise Türkçe, değilse İngilizce.
    static var current: Language {
        if let raw = UserDefaults.standard.string(forKey: "language"), let lang = Language(rawValue: raw) {
            return lang
        }
        return (Locale.preferredLanguages.first ?? "en").lowercased().hasPrefix("tr") ? .tr : .en
    }

    static func set(_ lang: Language) {
        UserDefaults.standard.set(lang.rawValue, forKey: "language")
    }
}

/// İki dilli metin: loc("Bitti!", "Done!")
func loc(_ tr: String, _ en: String) -> String {
    Language.current == .tr ? tr : en
}

enum Preferences {
    private static let defaults = UserDefaults.standard

    /// Bitti, bekliyor, hata gibi anlarda kısa sesler.
    static var sounds: Bool {
        get { defaults.object(forKey: "sounds") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "sounds") }
    }

    /// Claude, ChatGPT ve Codex masaüstü uygulamalarını Erişilebilirlik ile izle.
    static var watchApps: Bool {
        get { defaults.object(forKey: "watchApps") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watchApps") }
    }

    /// Claude/ChatGPT/Codex'e geçince robot o pencerenin köşesine gitsin.
    static var followAppWindow: Bool {
        get { defaults.object(forKey: "followAppWindow") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "followAppWindow") }
    }

    /// Boştayken ara sıra laf atsın.
    static var idleChatter: Bool {
        get { defaults.object(forKey: "idleChatter") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "idleChatter") }
    }

    /// Balonda ve bildirimlerde eyleme göre emoji.
    static var emojiEnabled: Bool {
        get { defaults.object(forKey: "emojiEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "emojiEnabled") }
    }

    static var notificationsEnabled: Bool {
        get { defaults.object(forKey: "notificationsEnabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "notificationsEnabled") }
    }

    static var robotsVisible: Bool {
        get { defaults.object(forKey: "robotsVisible") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "robotsVisible") }
    }

    /// Bu kadar saniyeden uzun süren görevler bitince bildirim gelir.
    static var longTurnSeconds: Double {
        get { defaults.object(forKey: "longTurnSeconds") as? Double ?? 20 }
        set { defaults.set(newValue, forKey: "longTurnSeconds") }
    }

    /// Açılışta ekrana konacak robotlar.
    static var knownSources: [String] {
        get { defaults.stringArray(forKey: "knownSources") ?? ["claude"] }
        set { defaults.set(newValue, forKey: "knownSources") }
    }
}

struct SourceTheme: Equatable {
    let id: String
    let displayName: String
    let color: NSColor
}

/// Kaynak (AI) başına isim ve renk. ~/.telepaith/config.json ile değiştirilebilir.
final class Themes {
    static let shared = Themes()

    private static let aliases: [String: String] = [
        "claude": "claude", "claude-code": "claude", "claudecode": "claude", "anthropic": "claude",
        "gpt": "gpt", "codex": "gpt", "openai": "gpt", "chatgpt": "gpt",
        "gemini": "gemini", "google": "gemini",
    ]

    private static let builtIn: [String: (name: String, hex: String)] = [
        "claude": ("Claude", "#D97757"),
        "gpt": ("GPT", "#3B82F6"),
        "gemini": ("Gemini", "#8B5CF6"),
    ]

    private var custom: [String: (name: String?, hex: String?)] = [:]
    private var appSources: [String: String] = [:]   // bundle id (küçük harf) → kaynak

    /// config.json'daki "apps" eşlemesi: {"com.todesktop.230313mzl4w4u92": "claude"}
    func appSource(bundleID: String) -> String? {
        appSources[bundleID.lowercased()]
    }

    static func canonical(_ raw: String) -> String {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if key.isEmpty { return "custom" }
        return aliases[key] ?? key
    }

    func theme(for source: String) -> SourceTheme {
        let base = Themes.builtIn[source]
        let user = custom[source]
        let name = user?.name ?? base?.name ?? source.capitalized
        let hex = user?.hex ?? base?.hex ?? "#8E8E93"
        return SourceTheme(id: source, displayName: name, color: NSColor(hex: hex) ?? .systemGray)
    }

    func reload() {
        custom = [:]
        appSources = [:]
        guard let data = try? Data(contentsOf: AppInfo.configFile),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let seconds = (root["longTurnSeconds"] as? NSNumber)?.doubleValue {
            Preferences.longTurnSeconds = seconds
        }
        if let apps = root["apps"] as? [String: String] {
            for (bundleID, source) in apps {
                appSources[bundleID.lowercased()] = Themes.canonical(source)
            }
        }
        guard let sources = root["sources"] as? [String: Any] else { return }
        for (key, value) in sources {
            guard let dict = value as? [String: Any] else { continue }
            custom[Themes.canonical(key)] = (dict["name"] as? String, dict["color"] as? String)
        }
    }

    /// İlk açılışta örnek bir config.json yazar.
    static func writeExampleConfigIfMissing() {
        let url = AppInfo.configFile
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        let example = """
        {
          "longTurnSeconds": 20,
          "sources": {
            "claude": { "name": "Claude", "color": "#D97757" },
            "gpt":    { "name": "GPT",    "color": "#3B82F6" },
            "gemini": { "name": "Gemini", "color": "#8B5CF6" }
          }
        }

        """
        try? example.write(to: url, atomically: true, encoding: .utf8)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
                  green: CGFloat((v >> 8) & 0xFF) / 255,
                  blue: CGFloat(v & 0xFF) / 255,
                  alpha: 1)
    }

    func mix(_ other: NSColor, _ fraction: CGFloat) -> NSColor {
        blended(withFraction: fraction, of: other) ?? self
    }
}

/// Metni tek satıra indirip kısaltır.
func clip(_ s: String, _ max: Int) -> String {
    let flat = s.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    if flat.count <= max { return flat }
    return String(flat.prefix(Swift.max(1, max - 1))) + "…"
}

/// 75 → "1 dk 15 sn" / "1 min 15 s"
func formatDuration(_ seconds: TimeInterval) -> String {
    let s = loc("sn", "s")
    let m = loc("dk", "min")
    let h = loc("sa", "h")
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) \(s)" }
    let minutes = total / 60
    if minutes < 60 {
        let sec = total % 60
        return sec == 0 ? "\(minutes) \(m)" : "\(minutes) \(m) \(sec) \(s)"
    }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) \(h)" : "\(hours) \(h) \(rest) \(m)"
}

/// Emoji açıksa metnin başına ekler.
func withEmoji(_ emoji: String?, _ text: String) -> String {
    guard Preferences.emojiEnabled, let emoji = emoji, !emoji.isEmpty else { return text }
    return "\(emoji) \(text)"
}
