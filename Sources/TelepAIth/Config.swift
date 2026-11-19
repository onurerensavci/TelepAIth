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
    static let windowSize = CGSize(width: 240, height: 260)
    static let robotSize = CGSize(width: 90, height: 124)
}

enum Preferences {
    private static let defaults = UserDefaults.standard

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
        guard let data = try? Data(contentsOf: AppInfo.configFile),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return }
        if let seconds = (root["longTurnSeconds"] as? NSNumber)?.doubleValue {
            Preferences.longTurnSeconds = seconds
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

/// 75 → "1 dk 15 sn"
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) sn" }
    let minutes = total / 60
    if minutes < 60 {
        let sec = total % 60
        return sec == 0 ? "\(minutes) dk" : "\(minutes) dk \(sec) sn"
    }
    let hours = minutes / 60
    let rest = minutes % 60
    return rest == 0 ? "\(hours) sa" : "\(hours) sa \(rest) dk"
}
