import Foundation

/// Efektler (Windows'ta TelepAIth.Core/Effects.cs, aynı kurallar): robotun çevresinde kar, güneş, gökkuşağı…
/// Robot ses çıkaran bir an yaşayınca (bitti, seni bekliyor, hata, kutlama) efekt canlanır; çalışırken hafifçe atar.
/// Otomatik mod: mevsime ve özel güne göre seçer, sohbette bir duygu geçerse (aşk, kutlama…) ona göre tepki verir;
/// robot bir şey yaparken görünür, boşta kalınca yavaşça söner (sakin çizim bozulmasın).
enum Effects {
    struct Effect: Identifiable {
        let id: String
        let name: String
    }

    static var all: [Effect] {
        [
            Effect(id: "winter", name: loc("Kış (kar ve bere)", "Winter (snow and beanie)")),
            Effect(id: "sun", name: loc("Güneş", "Sun")),
            Effect(id: "rainbow", name: loc("Gökkuşağı", "Rainbow")),
            Effect(id: "aurora", name: loc("Kuzey ışıkları", "Northern lights")),
            Effect(id: "stars", name: loc("Yıldızlar", "Stars")),
            Effect(id: "hearts", name: loc("Kalpler", "Hearts")),
            Effect(id: "bubbles", name: loc("Baloncuklar", "Bubbles")),
            Effect(id: "fireflies", name: loc("Ateş böcekleri", "Fireflies")),
            Effect(id: "rain", name: loc("Yağmur", "Rain")),
            Effect(id: "leaves", name: loc("Sonbahar yaprakları", "Autumn leaves")),
            Effect(id: "confetti", name: loc("Konfeti", "Confetti")),
        ]
    }

    static func name(_ id: String) -> String { all.first { $0.id == id }?.name ?? id }

    /// Arkada çizilenler (robotun arkasında parlar); diğerleri önünde uçuşur.
    static func isBackground(_ id: String) -> Bool { ["sun", "rainbow", "aurora"].contains(id) }

    static var isAuto: Bool { ["auto", ""].contains(Preferences.costume) }

    // MARK: Mevsim ve özel günler

    /// Mevsim: winter, spring, summer, autumn
    static func seasonKey(_ now: Date) -> String {
        switch Calendar.current.component(.month, from: now) {
        case 12, 1, 2: return "winter"
        case 3, 4, 5: return "spring"
        case 6, 7, 8: return "summer"
        default: return "autumn"
        }
    }

    /// Otomatik modda günün efekti: yılbaşı konfeti, sevgililer günü kalp, yoksa mevsimi (kar, gökkuşağı, güneş, yaprak)
    static func season(_ now: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: now)
        if (c.month == 12 && c.day == 31) || (c.month == 1 && c.day == 1) { return "confetti" }
        if c.month == 2 && c.day == 14 { return "hearts" }
        switch seasonKey(now) {
        case "winter": return "winter"
        case "spring": return "rainbow"
        case "summer": return "sun"
        default: return "leaves"
        }
    }

    /// Mevsim geçişinde robotun söylediği
    static func seasonGreeting(_ key: String) -> String {
        switch key {
        case "winter": return "❄️ " + loc("Kış geldi! Kar yağdırıyorum.", "Winter is here! Let it snow.")
        case "spring": return "🌈 " + loc("Bahar geldi! Gökkuşağı çıktı.", "Spring is here! Rainbow's out.")
        case "summer": return "☀️ " + loc("Yaz geldi! Güneş açtı.", "Summer is here! The sun is out.")
        default: return "🍂 " + loc("Sonbahar geldi! Yapraklar dökülüyor.", "Autumn is here! Leaves are falling.")
        }
    }

    /// Kış beresi: elle "Kış" seçildiyse ya da otomatikte kış mevsimiyse (şapka takılı değilken)
    static func winterCostume(_ now: Date = Date()) -> Bool {
        Preferences.costume == "winter" || (isAuto && seasonKey(now) == "winter")
    }

    // MARK: Duygular (otomatik mod)

    private static let feelings: [(effect: String, words: [String])] = [
        ("hearts", ["aşk", "aşık", "seviyorum", "sevgilim", "sevgilime", "romantik", "evlilik teklifi", "❤", "💕", "💖", "😍", "🥰",
                    "i love you", "love you", "my love", "valentine", "sweetheart", "romantic", "girlfriend", "boyfriend"]),
        ("confetti", ["tebrik", "kutlu olsun", "doğum günü", "yaşasın", "başardık", "başardım", "yayına aldık", "🎉", "🥳",
                      "congrat", "birthday", "hooray", "we did it", "celebrat", "we shipped", "launched"]),
        ("rain", ["üzgünüm", "çok üzgün", "üzüldüm", "ağlıyorum", "moralim bozuk", "kötü hissediyorum", "😢", "😭",
                  "i'm sad", "so sad", "crying", "heartbroken", "depressed"]),
        ("stars", ["harika", "muhteşem", "mükemmel", "efsane", "şahane", "bravo", "✨", "🤩",
                   "amazing", "awesome", "wonderful", "brilliant", "fantastic"]),
        ("fireflies", ["iyi geceler", "tatlı rüyalar", "good night", "sweet dreams"]),
    ]

    /// Metinde bir duygu geçiyor mu? (aşk → kalpler, kutlama → konfeti, üzüntü → yağmur, övgü → yıldızlar)
    static func feeling(_ text: String?) -> String? {
        guard let text = text, !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let low = text.lowercased()
        return feelings.first { f in f.words.contains { low.contains($0) } }?.effect
    }

    private static let reactSeconds = 30.0, staySeconds = 25.0, fadeSeconds = 10.0
    private static var reaction: String?
    private static var reactionAt: Date?
    private static var lastActive: Date?

    /// Sohbette geçen metni dinle (sadece otomatik modda): bir duygu varsa 30 sn o efekt
    @discardableResult
    static func hear(_ text: String?, now: Date = Date()) -> String? {
        guard isAuto, let f = feeling(text) else { return nil }
        reaction = f
        reactionAt = now
        kick(1, now: now)
        return f
    }

    /// Şu an çizilecek efekt ve görünürlüğü (0…1). working: robot çalışıyor (otomatik modda efekt açık kalır).
    static func visible(_ now: Date = Date(), working: Bool) -> (id: String, alpha: Double)? {
        let mode = Preferences.costume
        if mode == "off" { return nil }
        if !isAuto { return all.contains { $0.id == mode } ? (mode, 1) : nil }
        if working { lastActive = now }
        if let r = reaction, let at = reactionAt, now.timeIntervalSince(at) >= 0, now.timeIntervalSince(at) < reactSeconds { return (r, 1) }
        guard let last = [lastActive, kickAt, reactionAt].compactMap({ $0 }).max() else { return nil }
        let idle = now.timeIntervalSince(last)
        let alpha = Swift.min(1, Swift.max(0, 1 - (idle - staySeconds) / fadeSeconds))
        return alpha <= 0 ? nil : (season(now), alpha)
    }

    /// Test için: tepki ve etkinlik geçmişini sil
    static func reset() {
        reaction = nil
        reactionAt = nil
        lastActive = nil
        kickAt = nil
        kickStrength = 0
    }

    // MARK: Canlılık

    private static var kickAt: Date?
    private static var kickStrength = 0.0

    /// Robot ses çıkaran bir an yaşadı (ses kapalı olsa da): efekt bir an canlansın.
    static func kick(_ strength: Double, now: Date = Date()) {
        if strength >= energy(now, working: false) {
            kickAt = now
            kickStrength = Swift.min(1, Swift.max(0, strength))
        }
    }

    /// Efektin canlılığı 0…1: son andan beri sönen vuruş; çalışırken hafif nabız.
    static func energy(_ now: Date = Date(), working: Bool) -> Double {
        var pulse = 0.0
        if let at = kickAt {
            let age = now.timeIntervalSince(at)
            if age >= 0 { pulse = kickStrength * exp(-age * 1.6) }
        }
        let beat = working ? 0.22 + 0.12 * sin(now.timeIntervalSince1970 * 5) : 0
        return Swift.min(1, Swift.max(0, Swift.max(pulse, beat)))
    }

    /// Sesin adına göre vuruş gücü (Glass bitti, Hero kutlama, Ping bekliyor, Basso hata).
    static func strength(_ sound: String) -> Double {
        switch sound {
        case "Glass", "Hero": return 1
        case "Ping": return 0.8
        default: return 0.6
        }
    }
}
