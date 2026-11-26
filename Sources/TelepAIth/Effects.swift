import Foundation

/// Efektler (Windows'ta TelepAIth.Core/Effects.cs, aynı kurallar): robotun çevresinde kar, güneş, gökkuşağı…
/// Robot ses çıkaran bir an yaşayınca (bitti, seni bekliyor, hata, kutlama) efekt canlanır; çalışırken hafifçe atar.
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

    /// Arkada çizilenler (robotun arkasında parlar); diğerleri önünde uçuşur.
    static func isBackground(_ id: String) -> Bool { ["sun", "rainbow", "aurora"].contains(id) }

    /// Şu an çizilecek efekt: "auto" Aralık – 6 Ocak arası kış, değilse yok; "off" yok.
    static func current(_ now: Date = Date()) -> String? {
        switch Preferences.costume {
        case "off": return nil
        case "auto", "":
            let c = Calendar.current.dateComponents([.month, .day], from: now)
            return c.month == 12 || (c.month == 1 && (c.day ?? 99) <= 6) ? "winter" : nil
        case let id: return all.contains { $0.id == id } ? id : nil
        }
    }

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
