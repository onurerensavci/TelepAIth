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
    // %100 boyuttaki ölçüler; robot bunlarla çizilip Preferences.robotScale kadar büyütülür/küçültülür
    /// Robotun penceresi: kafa ve balon (sohbet listesinde 6 satır sığsın diye 340 yüksek; boş kısmı tıklamaları geçirir)
    static let baseWindowSize = CGSize(width: 280, height: 340)
    static let baseHeadSize = CGSize(width: 100, height: 100)
    static let baseMargin: CGFloat = 16  // pencere kenarı ile kafa arası
    static let edgeInset: CGFloat = 14   // ekran köşesi ile kafa arası

    static var scale: CGFloat { CGFloat(Preferences.robotScale) }
    static var windowSize: CGSize { CGSize(width: baseWindowSize.width * scale, height: baseWindowSize.height * scale) }
    static var headSize: CGSize { CGSize(width: baseHeadSize.width * scale, height: baseHeadSize.height * scale) }
    static var margin: CGFloat { baseMargin * scale }

    /// Ayarlardaki boyut seçenekleri
    static let scaleOptions: [(Double, String, String)] = [(0.75, "Küçük", "Small"), (1.0, "Orta", "Medium"),
                                                           (1.3, "Büyük", "Large"), (1.6, "Çok büyük", "Extra large")]
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

    /// Kalkan: Claude Code'da tehlikeli görünen komutlarda Claude Code senden onay istesin.
    static var shield: Bool {
        get { defaults.object(forKey: "shield") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "shield") }
    }

    /// Akıllı uyarılar: takıldı, iki sohbet aynı dosyada, push sonrası CI, commit'lenmemiş iş, kullanım sınırları
    static var insights: Bool {
        get { defaults.object(forKey: "insights") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "insights") }
    }

    /// "Mac açılınca başlasın" için kullanıcı bir seçim yaptı mı (yapmadıysa ilk açılışta açılır)
    static var launchAtLoginChosen: Bool {
        get { defaults.bool(forKey: "launchAtLoginChosen") }
        set { defaults.set(newValue, forKey: "launchAtLoginChosen") }
    }

    /// Mevsimlik kostüm: "auto" (Aralık – 6 Ocak kış), "winter" (hep), "off"
    static var costume: String {
        get { defaults.string(forKey: "costume") ?? "auto" }
        set { defaults.set(newValue, forKey: "costume") }
    }

    /// Gardırop: yuvaya (head, eyes, face, side) takılı parça; yoksa nil
    static func outfit(_ slot: String) -> String? {
        let v = defaults.string(forKey: "outfit." + slot) ?? ""
        return v.isEmpty ? nil : v
    }

    static func setOutfit(_ slot: String, _ id: String?) { defaults.set(id ?? "", forKey: "outfit." + slot) }

    /// Kış kostümü şu an takılı mı?
    static var winterActive: Bool { Effects.winterCostume() }

    /// Claude Code izin isteyince robotun balonunda İzin ver / Reddet düğmeleri
    static var approveFromRobot: Bool {
        get { defaults.object(forKey: "approveFromRobot") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "approveFromRobot") }
    }

    /// Önemli anlarda (bitti, seni bekliyor, güncelleme) robot sesli söylesin.
    static var speak: Bool {
        get { defaults.object(forKey: "speak") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "speak") }
    }

    /// Sessize al (robota sağ tık): bildirim sesi, kısa sesler ve sesli söyleme susar; bildirimler sessiz gelir.
    static var muted: Bool {
        get { defaults.bool(forKey: "muted") }
        set { defaults.set(newValue, forKey: "muted") }
    }

    /// Ses sekmesi: bu tür (done, waiting, reminder, error, usage, alert, summary) ses çıkarsın mı (bildirim sesi, kısa ses, sesli söyleme)
    static func sound(_ kind: String) -> Bool { defaults.object(forKey: "sound." + kind) as? Bool ?? (kind != "background") }
    static func setSound(_ kind: String, _ on: Bool) { defaults.set(on, forKey: "sound." + kind) }
    /// Sessize alınmadıysa ve bu türün sesi açıksa
    static func soundOn(_ kind: String) -> Bool { !muted && sound(kind) }

    /// Ses sekmesindeki türler: kimlik, başlık, açıklama
    struct SoundKind: Identifiable {
        let id: String
        let title: String
        let detail: String
    }

    static var soundKinds: [SoundKind] {
        [
            SoundKind(id: "done", title: loc("İş bitince", "When a task finishes"), detail: loc("Bir sohbet işini bitirdiğinde", "A chat finished its work")),
            SoundKind(id: "waiting", title: loc("Seni bekleyince", "When it needs you"), detail: loc("Onay ya da cevap beklerken", "Waiting for an approval or an answer")),
            SoundKind(id: "reminder", title: loc("Hatırlatma", "Reminders"), detail: loc("Bir süredir hâlâ seni bekliyorsa", "Still waiting for you after a while")),
            SoundKind(id: "background", title: loc("Arkada çalışınca", "Working in the background"), detail: loc("Yan menüdeki bir sohbet arkada çalışmaya başlayınca", "A chat in the sidebar starts working in the background")),
            SoundKind(id: "error", title: loc("Hata verince", "On errors"), detail: loc("Bir sohbet hata verdiğinde", "A chat hit an error")),
            SoundKind(id: "usage", title: loc("Kullanım sınırı", "Usage limits"), detail: loc("%80, %95 ve limit yenilenince", "At 80%, 95% and when the limit resets")),
            SoundKind(id: "alert", title: loc("Akıllı uyarılar", "Smart alerts"), detail: loc("Takıldı, aynı dosya, CI sonucu, commit hatırlatması", "Stuck, same file, CI result, commit reminder")),
            SoundKind(id: "summary", title: loc("Günün özeti ve diğerleri", "Daily summary and others"), detail: loc("Günün özeti, güncelleme, kutlamalar", "Daily summary, updates, celebrations")),
        ]
    }

    /// Robotun kısa sesleri (bitti, bekliyor, hata…); hangi anlarda çalacağını Ses sekmesindeki türler seçer.
    static var sounds: Bool {
        get { defaults.object(forKey: "sounds") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "sounds") }
    }

    /// Claude, ChatGPT ve Codex masaüstü uygulamalarını Erişilebilirlik ile izle.
    static var watchApps: Bool {
        get { defaults.object(forKey: "watchApps") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "watchApps") }
    }

    /// Her zaman üstte: robot diğer pencerelerin üstünde durur. Kapalıyken normal bir pencere gibi arkada kalabilir.
    static var alwaysOnTop: Bool {
        get { defaults.object(forKey: "alwaysOnTop") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "alwaysOnTop") }
    }

    /// Kilitli: robot olduğu yerde ve olduğu masaüstünde kalır, sürüklenmez, AI pencerelerine uçmaz.
    static var robotLocked: Bool {
        get { defaults.object(forKey: "robotLocked") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "robotLocked") }
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
        get { defaults.object(forKey: "systemNotifications") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "systemNotifications") }
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

    /// Kullanıcı o AI uygulamasına bakarken de bildirim gelsin (normalde gelmez, zaten görüyorsun).
    static var notifyWhenFrontmost: Bool {
        get { defaults.object(forKey: "notifyWhenFrontmost") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "notifyWhenFrontmost") }
    }

    /// AI uzun süre onay beklerse robot ısrar etsin (sallansın, 2 dakikada bir hatırlatsın).
    /// Güncellemeleri otomatik kur: yeni sürüm hazır olunca, hiçbir sohbet çalışmıyor/beklemiyorken (2 dk sakin)
    /// kendini günceller. Varsayılan kapalı: isteyen açar. (Windows'ta Prefs.AutoUpdate)
    static var autoUpdate: Bool {
        get { defaults.bool(forKey: "autoUpdate") }
        set { defaults.set(newValue, forKey: "autoUpdate") }
    }

    static var waitReminders: Bool {
        get { defaults.object(forKey: "waitReminders") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "waitReminders") }
    }

    /// Aynı anda çalışan diğer oturumlar robotun yanında minik kafalar olarak görünsün.
    static var miniHeads: Bool {
        get { defaults.object(forKey: "miniHeads") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "miniHeads") }
    }

    /// Odak modu elle açıldıysa bitiş zamanı (0: kapalı, sonsuz: kapatılana kadar).
    static var focusUntil: Double {
        get { defaults.object(forKey: "focusUntil") as? Double ?? 0 }
        set { defaults.set(newValue, forKey: "focusUntil") }
    }

    /// Zoom, Teams, Webex, FaceTime gibi toplantı uygulamaları öndeyken odak modu kendiliğinden açılsın.
    static var autoFocusInMeetings: Bool {
        get { defaults.object(forKey: "autoFocusInMeetings") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "autoFocusInMeetings") }
    }

    /// Akşam günün özetini söylesin.
    static var dailySummary: Bool {
        get { defaults.object(forKey: "dailySummary") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "dailySummary") }
    }

    /// Günlük özetin saati (0-23).
    static var dailySummaryHour: Int {
        get { defaults.object(forKey: "dailySummaryHour") as? Int ?? 18 }
        set { defaults.set(newValue, forKey: "dailySummaryHour") }
    }

    /// Robotun boyutu (1 = %100)
    static var robotScale: Double {
        get { Swift.max(0.6, Swift.min(1.8, defaults.object(forKey: "robotScale") as? Double ?? 1.0)) }
        set { defaults.set(newValue, forKey: "robotScale") }
    }

    /// İlk açılış sihirbazı tamamlandı mı?
    /// Son söylenen mevsim (otomatik efekt geçişi) ve en son çalışan sürüm (güncellemeden sonra yeniliği söylemek için)
    static var lastSeason: String? {
        get { defaults.string(forKey: "lastSeason") }
        set { defaults.set(newValue, forKey: "lastSeason") }
    }

    static var lastRunVersion: String? {
        get { defaults.string(forKey: "lastRunVersion") }
        set { defaults.set(newValue, forKey: "lastRunVersion") }
    }

    static var onboardingDone: Bool {
        get { defaults.object(forKey: "onboardingDone") as? Bool ?? false }
        set { defaults.set(newValue, forKey: "onboardingDone") }
    }

    /// Açılışta ekrana konacak robotlar.
    static var knownSources: [String] {
        get { defaults.stringArray(forKey: "knownSources") ?? ["claude"] }
        set { defaults.set(newValue, forKey: "knownSources") }
    }
}

/// Odak modu: toplantıda ya da elle açılınca robot susar, sadece seni bekleyen şeyleri söyler.
enum FocusMode {
    /// Toplantı uygulaması öndeyken RobotManager doldurur.
    static var meetingActive = false

    static var manualActive: Bool { Preferences.focusUntil > Date().timeIntervalSince1970 }

    static var isActive: Bool { manualActive || (Preferences.autoFocusInMeetings && meetingActive) }

    static func turnOn(for seconds: TimeInterval?) {
        Preferences.focusUntil = seconds.map { Date().timeIntervalSince1970 + $0 } ?? Double.greatestFiniteMagnitude
    }

    static func turnOff() { Preferences.focusUntil = 0 }

    /// Toplantı uygulamaları (bundle id başı)
    static let meetingApps = ["us.zoom.xos", "com.microsoft.teams", "com.microsoft.teams2", "com.cisco.webexmeetingsapp",
                              "com.webex.meetingmanager", "com.apple.FaceTime", "com.hnc.Discord", "com.tinyspeck.slackmacgap.huddle"]

    static func isMeetingApp(_ bundleID: String?) -> Bool {
        guard let id = bundleID?.lowercased() else { return false }
        return meetingApps.contains { id.hasPrefix($0.lowercased()) }
    }

    /// Menü/ayarlar için kısa açıklama
    static var statusText: String {
        if manualActive {
            if Preferences.focusUntil > 4e9 { return loc("açık (kapatana kadar)", "on (until you turn it off)") }
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return loc("açık, \(f.string(from: Date(timeIntervalSince1970: Preferences.focusUntil)))'e kadar",
                       "on until \(f.string(from: Date(timeIntervalSince1970: Preferences.focusUntil)))")
        }
        if Preferences.autoFocusInMeetings && meetingActive { return loc("açık (toplantıdasın)", "on (you're in a meeting)") }
        return loc("kapalı", "off")
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

/// Kısa süre: 40 → "40 sn", 200 → "3 dk", 4000 → "1 sa 6 dk"
private let smallWords: Set<String> = ["ve", "ile", "ya", "da", "de", "ki", "mi",
                                       "a", "an", "the", "and", "or", "of", "to", "in", "on", "at", "for", "by", "with", "from"]

/// Menü başlığı: her kelime büyük harfle ("Robotun Odası", "Güncellemeleri Denetle"), bağlaçlar küçük, içinde büyük
/// harf olan kelime (macOS, GPT) olduğu gibi, sondaki üç nokta yok. (Windows'ta Text.MenuTitle, aynı kural)
func menuTitle(_ text: String) -> String {
    let t = text.replacingOccurrences(of: "…", with: "").replacingOccurrences(of: "...", with: "")
        .trimmingCharacters(in: .whitespaces)
    let locale = Locale(identifier: Language.current == .tr ? "tr_TR" : "en_US")
    var words = t.components(separatedBy: " ")
    for i in words.indices {
        let w = words[i]
        guard let idx = w.firstIndex(where: { $0.isLetter }), w[idx].isLowercase, !w.contains(where: { $0.isUppercase }) else { continue }
        let core = String(w.filter { $0.isLetter })
        if i > 0 && smallWords.contains(core) { continue }
        words[i] = String(w[..<idx]) + String(w[idx]).uppercased(with: locale) + String(w[w.index(after: idx)...])
    }
    return words.joined(separator: " ")
}

/// Menüdeki tüm başlıkları (alt menüler dahil) menü kuralına göre yazar; durum satırları (renkli, devre dışı) dokunulmaz.
func applyMenuTitles(_ menu: NSMenu) {
    for item in menu.items where !item.isSeparatorItem {
        if item.attributedTitle == nil && item.isEnabled { item.title = menuTitle(item.title) }
        if let sub = item.submenu {
            item.title = menuTitle(item.title)
            applyMenuTitles(sub)
        }
    }
}

func shortDuration(_ seconds: TimeInterval) -> String {
    let total = Swift.max(0, Int(seconds))
    if total < 60 { return "\(total) \(loc("sn", "s"))" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes) \(loc("dk", "min"))" }
    let rest = minutes % 60
    return rest == 0 ? "\(minutes / 60) \(loc("sa", "h"))" : "\(minutes / 60) \(loc("sa", "h")) \(rest) \(loc("dk", "min"))"
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
