import Foundation
import SwiftUI

// Robotun odası (Windows'ta TelepAIth.Core/Room.cs, aynı kurallar): gardırop, seviye ve başarımlar, emek, kullanım.

/// Boya: düz renk ("#RRGGBB(AA)" ya da "theme…") veya ışık geçişi: doğrusal [x1,y1,x2,y2] / dairesel [cx,cy,r],
/// duraklar (konum 0…1, renk). Koordinatlar 100×100 kafa alanında; parçalara hacim (3B görünüm) verir.
struct OutfitPaint {
    let color: String?
    let linear: [Double]?
    let radial: [Double]?
    let stops: [(offset: Double, color: String)]

    static func from(_ any: Any?) -> OutfitPaint? {
        if let s = any as? String { return OutfitPaint(color: s, linear: nil, radial: nil, stops: []) }
        guard let o = any as? [String: Any] else { return nil }
        let stops: [(offset: Double, color: String)] = (o["stops"] as? [[Any]] ?? []).compactMap { a in
            guard a.count == 2, let off = (a[0] as? NSNumber)?.doubleValue, let c = a[1] as? String else { return nil }
            return (off, c)
        }
        return OutfitPaint(color: nil, linear: (o["lin"] as? [NSNumber])?.map(\.doubleValue),
                           radial: (o["rad"] as? [NSNumber])?.map(\.doubleValue), stops: stops)
    }
}

/// Şeklin hareketi (Windows'ta OutfitAnim, aynı formüller): sway (pivot etrafında ±amount derece), bob (±amount nokta
/// yukarı-aşağı), beat (1±amount ölçek), rise (amount nokta yükselip söner), twinkle (arada bir parlayıp söner),
/// slide (±amount nokta kayan parlama). speed: saniyedeki tur, offset: faz (0…1).
struct OutfitAnim {
    let kind: String
    let amount: Double
    let speed: Double
    let offset: Double
    let pivot: [Double]?

    static func from(_ any: Any?) -> OutfitAnim? {
        guard let o = any as? [String: Any] else { return nil }
        return OutfitAnim(kind: o["k"] as? String ?? "", amount: (o["a"] as? NSNumber)?.doubleValue ?? 0,
                          speed: (o["s"] as? NSNumber)?.doubleValue ?? 1, offset: (o["o"] as? NSNumber)?.doubleValue ?? 0,
                          pivot: (o["p"] as? [NSNumber])?.map(\.doubleValue))
    }

    /// t anındaki kayma, dönme (derece), ölçek ve saydamlık
    func at(_ t: Double) -> (dx: Double, dy: Double, rotate: Double, scale: Double, opacity: Double) {
        let ph = speed * t + offset
        let f = ph - floor(ph)
        switch kind {
        case "sway": return (0, 0, amount * sin(2 * .pi * ph), 1, 1)
        case "bob": return (0, amount * sin(2 * .pi * ph), 0, 1, 1)
        case "beat": return (0, 0, 0, 1 + amount * pow(Swift.max(0, sin(2 * .pi * ph)), 2), 1)
        case "rise": return (0, -amount * f, 0, 1, sin(.pi * f))
        case "twinkle":
            let op = f < 0.2 ? sin(.pi * f / 0.2) : 0
            return (0, 0, 0, 0.5 + 0.5 * op, op)
        case "slide":
            let op = f < 0.35 ? sin(.pi * f / 0.35) : 0
            return (-amount + 2 * amount * Swift.min(1, f / 0.35), 0, 0, 1, op)
        default: return (0, 0, 0, 1, 1)
        }
    }
}

/// Gardırop parçasının bir şekli: SVG yolu, elips [cx,cy,rx,ry] ya da dikdörtgen [x,y,w,h,r]; 100×100 kafa alanında.
struct OutfitShape {
    let path: String?
    let ellipse: [Double]?
    let rect: [Double]?
    let fill: OutfitPaint?
    let stroke: OutfitPaint?
    let width: Double
    var anim: OutfitAnim? = nil
}

/// Gardırop parçası; type: hangi tipin (polis, kral…), legendary: tipin parıltılı gizli ödülü.
struct OutfitItem: Identifiable {
    let id: String
    let slot: String
    let nameTr: String
    let nameEn: String
    let level: Int
    let achievement: String?
    let shapes: [OutfitShape]
    var type = ""
    var legendary = false
    var name: String { loc(nameTr, nameEn) }
}

/// Tip: aynı temanın 5 parçası (her yuvadan bir tane, biri gizli ödül); hepsi açılınca o tip olursun.
struct OutfitType: Identifiable {
    let id: String
    let emoji: String
    let nameTr: String
    let nameEn: String
    let descTr: String
    let descEn: String
    var name: String { loc(nameTr, nameEn) }
    var description: String { loc(descTr, descEn) }
}

enum Outfits {
    static let slots = ["head", "eyes", "face", "neck", "side"]

    static func slotName(_ slot: String) -> String {
        switch slot {
        case "head": return loc("Baş", "Head")
        case "eyes": return loc("Gözlük", "Glasses")
        case "face": return loc("Yüz", "Face")
        case "neck": return loc("Boyun", "Neck")
        default: return loc("Yanında", "Beside")
        }
    }

    /// Tipler (kolaydan zora): her birinin 5 parçası var, sonuncusu gizli ödül.
    static let types: [OutfitType] = [
        OutfitType(id: "coder", emoji: "💻", nameTr: "Kodcu", nameEn: "Coder",
                   descTr: "Kulaklığı takar, ördeğiyle hata ayıklar", descEn: "Headphones on, debugging with a duck"),
        OutfitType(id: "hipster", emoji: "☕", nameTr: "Hipster", nameEn: "Hipster",
                   descTr: "Bere, bıyık ve plak sesi", descEn: "Beanie, mustache and vinyl crackle"),
        OutfitType(id: "police", emoji: "🚓", nameTr: "Polis", nameEn: "Police",
                   descTr: "Kodun düzenini korur", descEn: "Keeps the code in order"),
        OutfitType(id: "marketing", emoji: "📣", nameTr: "Pazarlamacı", nameEn: "Marketer",
                   descTr: "Fikir bulur, duyurur, uçurur", descEn: "Finds the idea, shouts it, launches it"),
        OutfitType(id: "artist", emoji: "🎨", nameTr: "Sanatçı", nameEn: "Artist",
                   descTr: "Her satırı bir tuval gibi görür", descEn: "Sees every line as a canvas"),
        OutfitType(id: "king", emoji: "👑", nameTr: "Kral", nameEn: "King",
                   descTr: "Robotların en yücesi", descEn: "The highest of all robots"),
    ]

    static func findType(_ id: String?) -> OutfitType? { types.first { $0.id == id } }

    static func items(of type: String) -> [OutfitItem] { all.filter { $0.type == type } }

    /// Tipin 5 parçasının hepsi açık mı?
    static func typeComplete(_ type: String, _ p: ProgressData) -> Bool {
        let list = items(of: type)
        return !list.isEmpty && list.allSatisfy { unlocked($0, p) }
    }

    static func completedTypes(_ p: ProgressData) -> [OutfitType] { types.filter { typeComplete($0.id, p) } }

    /// Tipin açık parçalarının hepsini giy
    static func wearType(_ type: String, _ p: ProgressData) {
        for i in items(of: type) where unlocked(i, p) { Preferences.setOutfit(i.slot, i.id) }
    }

    /// "Açıldı: Bere, Bıyık", "✨ Gizli ödül açıldı: Taç!", "👑 Kral tipi tamamlandı!" (Windows'ta Outfits.NewsLines, aynı metinler)
    static func newsLines(_ items: [OutfitItem], _ types: [OutfitType]) -> [String] {
        var lines: [String] = []
        let normal = items.filter { !$0.legendary }
        if !normal.isEmpty {
            var names = normal.prefix(3).map(\.name).joined(separator: ", ")
            if normal.count > 3 { names += loc(" ve \(normal.count - 3) parça daha", " and \(normal.count - 3) more") }
            lines.append("🎉 " + loc("Gardıropta açıldı: ", "Unlocked in the wardrobe: ") + names)
        }
        for item in items where item.legendary {
            lines.append("✨ " + loc("Gizli ödül açıldı: ", "Secret reward unlocked: ") + item.name + "!")
        }
        for t in types {
            lines.append(t.emoji + " " + loc("\(t.name) tipi tamamlandı! Odadan hepsini birden giyebilirsin.",
                                             "\(t.name) set complete! Wear it all from the room."))
        }
        return lines
    }

    static func takeOffAll() { for s in slots { Preferences.setOutfit(s, nil) } }

    /// Gizli ödülün adı açılana kadar görünmez
    static func displayName(_ item: OutfitItem, _ p: ProgressData) -> String {
        item.legendary && !unlocked(item, p) ? loc("Gizli ödül", "Secret reward") : item.name
    }

    static let all: [OutfitItem] = parse(OutfitData.json)

    static func find(_ id: String?) -> OutfitItem? { id.flatMap { id in all.first { $0.id == id } } }

    static func parse(_ json: String) -> [OutfitItem] {
        guard let items = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return [] }
        return items.map { node in
            let shapes = (node["shapes"] as? [[String: Any]] ?? []).map { s in
                OutfitShape(path: s["d"] as? String,
                            ellipse: (s["ellipse"] as? [NSNumber])?.map(\.doubleValue),
                            rect: (s["rect"] as? [NSNumber])?.map(\.doubleValue),
                            fill: OutfitPaint.from(s["fill"]), stroke: OutfitPaint.from(s["stroke"]),
                            width: (s["w"] as? NSNumber)?.doubleValue ?? 1, anim: OutfitAnim.from(s["anim"]))
            }
            return OutfitItem(id: node["id"] as? String ?? "", slot: node["slot"] as? String ?? "head",
                              nameTr: node["tr"] as? String ?? "", nameEn: node["en"] as? String ?? "",
                              level: (node["level"] as? NSNumber)?.intValue ?? 0, achievement: node["achievement"] as? String,
                              shapes: shapes, type: node["type"] as? String ?? "", legendary: node["legendary"] as? Bool ?? false)
        }
    }

    /// Renk: "#RRGGBB", "#RRGGBBAA" ya da AI rengi ("theme", "theme-dark", "theme-light"). (r, g, b 0…1, saydamlık)
    static func color(_ token: String, theme: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double, a: Double) {
        switch token {
        case "theme": return (theme.r, theme.g, theme.b, 1)
        case "theme-dark": return (floor(theme.r * 255 * 0.72) / 255, floor(theme.g * 255 * 0.72) / 255, floor(theme.b * 255 * 0.72) / 255, 1)
        case "theme-light": return (theme.r + (1 - theme.r) * 0.35, theme.g + (1 - theme.g) * 0.35, theme.b + (1 - theme.b) * 0.35, 1)
        default: break
        }
        let hex = token.hasPrefix("#") ? String(token.dropFirst()) : token
        guard hex.count == 6 || hex.count == 8, let v = UInt32(hex, radix: 16) else { return (1, 1, 1, 1) }
        if hex.count == 6 {
            return (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255, 1)
        }
        return (Double((v >> 24) & 0xFF) / 255, Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
    }

    /// Takılı ve açık parçalar (çizim sırası: yanında, boyun, yüz, gözlük, baş)
    static func worn(_ p: ProgressData) -> [OutfitItem] {
        ["side", "neck", "face", "eyes", "head"].compactMap { find(Preferences.outfit($0)) }.filter { unlocked($0, p) }
    }

    /// Parça açık mı (seviyeyle ya da başarımla)?
    static func unlocked(_ item: OutfitItem, _ p: ProgressData) -> Bool {
        if let a = item.achievement { return Achievements.isDone(a, p) }
        return Levels.level(p) >= item.level
    }

    /// Kilitliyse ne zaman açılır: "Seviye 10" ya da "Başarım: Büyük gün"
    static func unlockHint(_ item: OutfitItem) -> String {
        if let a = item.achievement { return loc("Başarım: ", "Achievement: ") + (Achievements.find(a)?.title ?? a) }
        return loc("Seviye \(item.level)", "Level \(item.level)")
    }
}

/// Basit SVG yolu okuyucu (M, L, C, Q, Z; mutlak koordinatlar). Gardırop verisi bunlarla yazılır.
enum SVGPath {
    static func parse(_ d: String) -> Path {
        var path = Path()
        var tokens: [String] = []
        var current = ""
        for ch in d {
            if ch.isLetter {
                if !current.isEmpty { tokens.append(current); current = "" }
                tokens.append(String(ch))
            } else if ch == " " || ch == "," {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else if ch == "-" && !current.isEmpty && !current.hasSuffix("e") {
                tokens.append(current); current = "-"
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { tokens.append(current) }
        var i = 0
        var command = "M"
        func num() -> CGFloat? {
            guard i < tokens.count, let v = Double(tokens[i]) else { return nil }
            i += 1
            return CGFloat(v)
        }
        func point() -> CGPoint? {
            guard let x = num(), let y = num() else { return nil }
            return CGPoint(x: x, y: y)
        }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter { command = String(c).uppercased(); i += 1 }
            switch command {
            case "M":
                guard let p = point() else { return path }
                path.move(to: p)
                command = "L"   // M'den sonraki noktalar çizgidir
            case "L":
                guard let p = point() else { return path }
                path.addLine(to: p)
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
            case "Q":
                guard let c = point(), let p = point() else { return path }
                path.addQuadCurve(to: p, control: c)
            case "Z":
                path.closeSubpath()
            default:
                i += 1
            }
        }
        return path
    }
}

/// Ömür boyu sayaçlar: seviye ve başarımlar bunlardan hesaplanır.
struct ProgressData: Codable, Equatable {
    var turns = 0
    var seconds: Double = 0
    var edits = 0
    var tools = 0
    var waits = 0
    var activeDays = 0
    var lastDay = ""
    var streak = 0
    var bestStreak = 0
    var maxParallel = 0
    var nightTurns = 0
    var earlyTurns = 0
    var bigDay = 0
    var longestTurn: Double = 0
    var ciPassed = 0
    var sources: [String] = []
    var unlocked: [String] = []   // söylenmiş başarımlar
    var toldLevel = 1
    /// Açıldığı söylenmiş gardırop parçaları (nil: ilk açılış, sessizce doldurulur)
    var seenItems: [String]?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        turns = try c.decodeIfPresent(Int.self, forKey: .turns) ?? 0
        seconds = try c.decodeIfPresent(Double.self, forKey: .seconds) ?? 0
        edits = try c.decodeIfPresent(Int.self, forKey: .edits) ?? 0
        tools = try c.decodeIfPresent(Int.self, forKey: .tools) ?? 0
        waits = try c.decodeIfPresent(Int.self, forKey: .waits) ?? 0
        activeDays = try c.decodeIfPresent(Int.self, forKey: .activeDays) ?? 0
        lastDay = try c.decodeIfPresent(String.self, forKey: .lastDay) ?? ""
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        bestStreak = try c.decodeIfPresent(Int.self, forKey: .bestStreak) ?? 0
        maxParallel = try c.decodeIfPresent(Int.self, forKey: .maxParallel) ?? 0
        nightTurns = try c.decodeIfPresent(Int.self, forKey: .nightTurns) ?? 0
        earlyTurns = try c.decodeIfPresent(Int.self, forKey: .earlyTurns) ?? 0
        bigDay = try c.decodeIfPresent(Int.self, forKey: .bigDay) ?? 0
        longestTurn = try c.decodeIfPresent(Double.self, forKey: .longestTurn) ?? 0
        ciPassed = try c.decodeIfPresent(Int.self, forKey: .ciPassed) ?? 0
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        unlocked = try c.decodeIfPresent([String].self, forKey: .unlocked) ?? []
        toldLevel = try c.decodeIfPresent(Int.self, forKey: .toldLevel) ?? 1
        seenItems = try c.decodeIfPresent([String].self, forKey: .seenItems)
    }
}

/// Sayaçları tutar ve kaydeder; yeni başarımları/seviyeyi bir kez söylemek için sıraya koyar.
final class Progress {
    static let shared = Progress(defaultsKey: "progress")

    private let key: String?
    private let lock = NSLock()
    private var data: ProgressData

    init(defaultsKey: String?) {
        key = defaultsKey
        if let key = defaultsKey, let raw = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode(ProgressData.self, from: raw) {
            data = decoded
        } else {
            data = ProgressData()
        }
    }

    func snapshot() -> ProgressData {
        lock.lock(); defer { lock.unlock() }
        return data
    }

    /// Bir tur bitti. todayTurns: bugün (bu dahil) kaç tur.
    func turn(source: String, seconds: Double, tools: Int, edits: Int, at: Date, todayTurns: Int) {
        lock.lock(); defer { lock.unlock() }
        data.turns += 1
        data.seconds += Swift.max(0, seconds)
        data.tools += tools
        data.edits += edits
        data.longestTurn = Swift.max(data.longestTurn, seconds)
        data.bigDay = Swift.max(data.bigDay, todayTurns)
        let hour = Calendar.current.component(.hour, from: at)
        if hour < 5 { data.nightTurns += 1 } else if hour < 8 { data.earlyTurns += 1 }
        let src = Themes.canonical(source)
        if !data.sources.contains(src) { data.sources.append(src) }
        let day = DailyStats.dayKey(at)
        if data.lastDay != day {
            data.activeDays += 1
            let yesterday = DailyStats.dayKey(Calendar.current.date(byAdding: .day, value: -1, to: at) ?? at)
            data.streak = data.lastDay == yesterday ? data.streak + 1 : 1
            data.bestStreak = Swift.max(data.bestStreak, data.streak)
            data.lastDay = day
        }
        save()
    }

    func wait() { lock.lock(); data.waits += 1; save(); lock.unlock() }
    func ci() { lock.lock(); data.ciPassed += 1; save(); lock.unlock() }

    func parallel(_ working: Int) {
        lock.lock(); defer { lock.unlock() }
        guard working > data.maxParallel else { return }
        data.maxParallel = working
        save()
    }

    /// Yeni açılan gardırop parçaları ve tamamlanan tipler (bir kez döner). İlk açılışta sessizce kaydeder.
    func takeOutfitNews() -> (items: [OutfitItem], types: [OutfitType]) {
        lock.lock(); defer { lock.unlock() }
        let open = Outfits.all.filter { Outfits.unlocked($0, data) }.map(\.id)
        guard let seen = data.seenItems else {
            data.seenItems = open
            save()
            return ([], [])
        }
        let fresh = Outfits.all.filter { open.contains($0.id) && !seen.contains($0.id) }
        guard !fresh.isEmpty else { return ([], []) }
        data.seenItems = seen + fresh.map(\.id)
        save()
        let types = Outfits.types.filter { t in fresh.contains { $0.type == t.id } && Outfits.typeComplete(t.id, data) }
        return (fresh, types)
    }

    /// Henüz söylenmemiş yeni başarımlar ve seviye (bir kez döner).
    func takeNews() -> (achievements: [Achievement], level: Int?) {
        lock.lock(); defer { lock.unlock() }
        let fresh = Achievements.all.filter { $0.done(data) && !data.unlocked.contains($0.id) }
        data.unlocked += fresh.map(\.id)
        let level = Levels.level(data)
        var up: Int?
        if level > data.toldLevel { up = level; data.toldLevel = level }
        if !fresh.isEmpty || up != nil { save() }
        return (fresh, up)
    }

    private func save() {
        guard let key = key, let raw = try? JSONEncoder().encode(data) else { return }
        UserDefaults.standard.set(raw, forKey: key)
    }
}

enum Levels {
    /// XP: tur 10, düzenleme 2, çalışılan dakika 1, aktif gün 25, geçen CI 15.
    static func xp(_ p: ProgressData) -> Int {
        p.turns * 10 + p.edits * 2 + Int(p.seconds / 60) + p.activeDays * 25 + p.ciPassed * 15
    }

    /// n. seviyeye çıkmak için gereken toplam XP: 50·n·(n−1) (2: 100, 3: 300, 10: 4500).
    static func need(_ level: Int) -> Int { 50 * level * (level - 1) }

    static func level(xp: Int) -> Int {
        var n = Int(floor((1 + (1 + 8.0 * Double(xp) / 100).squareRoot()) / 2))
        while need(n + 1) <= xp { n += 1 }
        while n > 1 && need(n) > xp { n -= 1 }
        return Swift.max(1, n)
    }

    static func level(_ p: ProgressData) -> Int { level(xp: xp(p)) }

    /// Bu seviyenin içinde ne kadar ilerledi (0…1) ve sonrakine kaç XP kaldı.
    static func next(_ p: ProgressData) -> (fraction: Double, left: Int) {
        let x = xp(p)
        let l = level(xp: x)
        let from = need(l), to = need(l + 1)
        return (Double(x - from) / Double(to - from), to - x)
    }
}

struct Achievement: Identifiable {
    let id: String
    let category: String
    let tier: Int
    let titleTr: String
    let titleEn: String
    let descTr: String
    let descEn: String
    let value: (ProgressData) -> Double
    let target: Double

    var title: String { loc(titleTr, titleEn) }
    var description: String { loc(descTr, descEn) }
    func done(_ p: ProgressData) -> Bool { value(p) >= target }
    func fraction(_ p: ProgressData) -> Double { Swift.min(1, Swift.max(0, value(p) / target)) }
}

enum Achievements {
    static let categories = ["chat", "code", "time", "team"]

    static func categoryName(_ c: String) -> String {
        switch c {
        case "chat": return loc("Sohbet", "Chat")
        case "code": return loc("Kod", "Code")
        case "time": return loc("Zaman", "Time")
        default: return loc("Ekip", "Team")
        }
    }

    /// 0 Kolay, 1 Orta, 2 Zor, 3 İmkânsız
    static func tierName(_ tier: Int) -> String {
        switch tier {
        case 0: return loc("Kolay", "Easy")
        case 1: return loc("Orta", "Medium")
        case 2: return loc("Zor", "Hard")
        default: return loc("İmkânsız", "Impossible")
        }
    }

    private static func a(_ id: String, _ cat: String, _ tier: Int, _ tr: String, _ en: String, _ dtr: String, _ den: String,
                          _ v: @escaping (ProgressData) -> Double, _ target: Double) -> Achievement {
        Achievement(id: id, category: cat, tier: tier, titleTr: tr, titleEn: en, descTr: dtr, descEn: den, value: v, target: target)
    }

    static let all: [Achievement] = [
        a("hello", "chat", 0, "Merhaba", "Hello", "1 tur", "1 turn", { Double($0.turns) }, 1),
        a("chatty", "chat", 0, "Geveze", "Chatty", "10 tur", "10 turns", { Double($0.turns) }, 10),
        a("talker", "chat", 1, "Konuşkan", "Talker", "250 tur", "250 turns", { Double($0.turns) }, 250),
        a("storyteller", "chat", 1, "Hikâyeci", "Storyteller", "1.000 tur", "1,000 turns", { Double($0.turns) }, 1000),
        a("orator", "chat", 2, "Hatip", "Orator", "5.000 tur", "5,000 turns", { Double($0.turns) }, 5000),
        a("legend", "chat", 3, "Efsane", "Legend", "25.000 tur", "25,000 turns", { Double($0.turns) }, 25000),
        a("bigday", "chat", 1, "Büyük gün", "Big day", "bir günde 50 tur", "50 turns in a day", { Double($0.bigDay) }, 50),
        a("crazyday", "chat", 2, "Çılgın gün", "Wild day", "bir günde 200 tur", "200 turns in a day", { Double($0.bigDay) }, 200),
        a("patient", "chat", 1, "Sabırlı", "Patient", "AI 100 kez seni bekledi", "the AI waited for you 100 times", { Double($0.waits) }, 100),

        a("firsttouch", "code", 0, "İlk dokunuş", "First touch", "1 düzenleme", "1 edit", { Double($0.edits) }, 1),
        a("handy", "code", 0, "Eli çabuk", "Handy", "50 araç çağrısı", "50 tool calls", { Double($0.tools) }, 50),
        a("builder", "code", 1, "Usta", "Builder", "500 düzenleme", "500 edits", { Double($0.edits) }, 500),
        a("architect", "code", 2, "Mimar", "Architect", "5.000 düzenleme", "5,000 edits", { Double($0.edits) }, 5000),
        a("toolbox", "code", 2, "Alet çantası", "Toolbox", "10.000 araç çağrısı", "10,000 tool calls", { Double($0.tools) }, 10000),
        a("green", "code", 0, "İlk yeşil", "First green", "push'tan sonra geçen bir CI", "a CI run that passed after a push", { Double($0.ciPassed) }, 1),
        a("greenstreak", "code", 1, "Yemyeşil", "All green", "25 geçen CI", "25 passing CI runs", { Double($0.ciPassed) }, 25),

        a("hour", "time", 0, "İlk saat", "First hour", "toplam 1 saat çalışma", "1 hour of work in total", { $0.seconds / 3600 }, 1),
        a("tenhours", "time", 1, "On saat", "Ten hours", "toplam 10 saat", "10 hours in total", { $0.seconds / 3600 }, 10),
        a("hundred", "time", 2, "Yüz saat", "Hundred hours", "toplam 100 saat", "100 hours in total", { $0.seconds / 3600 }, 100),
        a("thousand", "time", 3, "Bin saat", "Thousand hours", "toplam 1.000 saat", "1,000 hours in total", { $0.seconds / 3600 }, 1000),
        a("marathon", "time", 1, "Maraton", "Marathon", "tek turda 30 dakika", "30 minutes in one turn", { $0.longestTurn / 60 }, 30),
        a("night", "time", 1, "Gece kuşu", "Night owl", "gece yarısından sonra 10 tur", "10 turns after midnight", { Double($0.nightTurns) }, 10),
        a("early", "time", 1, "Erkenci", "Early bird", "sabah 5–8 arası 10 tur", "10 turns between 5 and 8 am", { Double($0.earlyTurns) }, 10),
        a("streak7", "time", 1, "Bir hafta", "One week", "7 gün üst üste", "7 days in a row", { Double($0.bestStreak) }, 7),
        a("streak30", "time", 2, "Bir ay", "One month", "30 gün üst üste", "30 days in a row", { Double($0.bestStreak) }, 30),
        a("days100", "time", 2, "Yüz gün", "Hundred days", "100 aktif gün", "100 active days", { Double($0.activeDays) }, 100),

        a("team", "team", 0, "İkili", "Duo", "aynı anda 2 sohbet çalışıyor", "2 chats working at once", { Double($0.maxParallel) }, 2),
        a("lead", "team", 1, "Takım lideri", "Team lead", "aynı anda 3 sohbet", "3 chats at once", { Double($0.maxParallel) }, 3),
        a("orchestra", "team", 2, "Orkestra", "Orchestra", "aynı anda 6 sohbet", "6 chats at once", { Double($0.maxParallel) }, 6),
        a("polyglot", "team", 0, "Çok dilli", "Polyglot", "2 farklı AI", "2 different AIs", { Double($0.sources.count) }, 2),
        a("zoo", "team", 2, "Hayvanat bahçesi", "Zoo", "4 farklı AI", "4 different AIs", { Double($0.sources.count) }, 4),
    ]

    static func find(_ id: String) -> Achievement? { all.first { $0.id == id } }
    static func isDone(_ id: String, _ p: ProgressData) -> Bool { find(id)?.done(p) ?? false }
}

/// Emek sekmesi: son N günde hangi AI ve hangi projede ne kadar çalışıldı.
struct EffortDay: Identifiable {
    let day: String
    let secondsBySource: [String: Double]
    var id: String { day }
}

struct EffortProject: Identifiable {
    let name: String
    let seconds: Double
    let turns: Int
    let share: Double
    var id: String { name }
}

struct Effort {
    let days: [EffortDay]
    let projects: [EffortProject]
    let bySource: [String: Double]
    let totalSeconds: Double
    let totalTurns: Int
    let totalEdits: Int

    /// "Son 30 günde AI'ların 48 sa çalıştı."
    func headline(_ days: Int) -> String {
        totalSeconds < 60
            ? loc("Son \(days) günde henüz iş yok.", "No work in the last \(days) days yet.")
            : loc("Son \(days) günde AI'ların \(shortDuration(totalSeconds)) çalıştı.",
                  "Your AIs worked \(shortDuration(totalSeconds)) in the last \(days) days.")
    }

    var topLine: String? {
        guard let top = projects.first, totalSeconds >= 60 else { return nil }
        let pct = Int((top.share * 100).rounded())
        return loc("En büyük pay \(top.name) projesinin: %\(pct).", "\(top.name) took the biggest share: \(pct)%.")
    }
}
