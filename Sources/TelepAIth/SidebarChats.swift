import Foundation

/// Yan menüde görülen bir öğe: ad, ipucu/açıklama (ör. "running"), bağlantı adresi, seçili (açık) sohbet mi
struct SidebarItem: Equatable {
    var name: String
    var help: String
    var url: String?
    var rect: CGRect
    var current = false
}

/// Arkada çalışan sohbetler: Claude uygulaması yan menüde her sohbetin yanında bir durum noktası gösterir
/// (üstüne gelince "running"; cevap beklerken "awaiting…"). Açık olmayan sohbetler bundan izlenir:
/// çalışırken minik kafa olur, nokta sönünce "bitti" bildirimi gelir. (Windows'taki SidebarChats'in aynısı.)
final class SidebarChats {
    struct Row: Equatable {
        let key: String
        let title: String
        let url: String?
        let state: RobotState
    }

    private struct Chat {
        var title: String
        var url: String?
        var state: RobotState
        var since: TimeInterval
        var lastBeat: TimeInterval
    }

    private static let waitingWords = [
        "awaiting answer", "awaiting your answer", "awaiting response", "awaiting your response", "awaiting input",
        "awaiting reply", "awaiting approval", "needs input", "needs your input", "needs attention", "needs approval",
        "needs your approval", "waiting for you", "waiting for your answer", "waiting for input", "waiting for approval",
        "cevap bekliyor", "cevabını bekliyor", "yanıt bekliyor", "yanıtını bekliyor", "onay bekliyor", "seni bekliyor",
    ]

    private static let workingWords = [
        "running", "working", "responding", "generating", "in progress", "streaming",
        "çalışıyor", "yanıt veriyor", "yanıtlıyor", "devam ediyor",
    ]

    private static let separators = [", ", " · ", " - ", " — ", " – ", ": ", " | "]

    /// Uzun süre yanıp sönen (takılı kalmış) nokta sonsuza kadar "çalışıyor" saymasın
    static let maxRunSeconds: TimeInterval = 30 * 60

    let source: String
    let pid: pid_t
    private var chats: [String: Chat] = [:]
    /// Bitmiş ya da açılmış olsa da görülen sohbetler (oturum → ad, adres): listeden tıklayınca açabilmek için
    private var known: [String: (title: String, url: String?)] = [:]

    init(source: String, pid: pid_t) {
        self.source = source
        self.pid = pid
    }

    var count: Int { chats.count }

    private static func normalized(_ text: String) -> String {
        var l = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = l.last, last == "." || last == "…" || last == " " { l.removeLast() }
        return l
    }

    private static func matches(_ l: String, _ w: String) -> Bool {
        l == w || l.hasSuffix("(" + w + ")")
            || separators.contains { l.hasSuffix($0 + w) || l.hasPrefix(w + $0) }
    }

    /// Durum yazısı mı? Tam eşleşme ya da "Başlık, running" / "Başlık · running" / "Başlık (running)" gibi sonek,
    /// ya da Claude'un biçimi: "Başlık Running" (sonda işaret olabilir: "Başlık Running Includes an artifact")
    static func statusOf(_ text: String?) -> RobotState? {
        guard let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let l = normalized(stripDecorations(text))
        if waitingWords.contains(where: { matches(l, $0) }) { return .waiting }
        if workingWords.contains(where: { matches(l, $0) }) { return .running }
        return spacedStatus(text)?.state
    }

    /// Claude'un biçimi: durum adın sonuna sadece bir boşlukla ve büyük harfle eklenir ("SCAM OR LEGIT video konsepti Running").
    /// Yanlış alarm olmasın diye yalnızca büyük harfle başlayan durum sayılır ("marathon running" sayılmaz). (Windows'ta SpacedStatus)
    static func spacedStatus(_ name: String) -> (state: RobotState, title: String)? {
        var t = stripDecorations(name)
        while let last = t.last, last == "." || last == "…" || last == " " { t.removeLast() }
        let l = t.lowercased()
        guard l.count == t.count else { return nil }
        for (words, state) in [(waitingWords, RobotState.waiting), (workingWords, RobotState.running)] {
            for w in words where l.hasSuffix(" " + w) && l.count > w.count + 1 {
                guard t[t.index(t.endIndex, offsetBy: -w.count)].isUppercase else { continue }
                let title = String(t.prefix(t.count - w.count - 1)).trimmingCharacters(in: .whitespaces)
                if title.count >= 2 { return (state, title) }
            }
        }
        return nil
    }

    /// Yan menü satırındaki simge ve düğme yazıları sohbet adı değildir ("Includes an artifact", "More options")
    private static let noiseLabels: Set<String> = [
        "includes an artifact", "contains an artifact", "has an artifact", "artifact", "starred", "pinned", "more options",
        "options", "chat options", "open menu", "menu", "rename", "delete", "archive", "share", "new chat",
        "yıldızlı", "sabitlendi", "sabitlenmiş", "seçenekler", "daha fazla seçenek", "sohbet seçenekleri", "yeni sohbet",
        "artifact içerir", "yeniden adlandır", "sil", "arşivle", "paylaş",
        "sidebar", "kenar çubuğu", "copy", "retry", "edit", "kopyala", "yeniden dene", "düzenle",
    ]

    static func isNoise(_ text: String) -> Bool {
        let l = normalized(text)
        return noiseLabels.contains(l) || noisePrefixes.contains { l.hasPrefix($0) } || l.contains("\n")
    }

    /// Sohbetin içinden gelen yazılar (mesajlar, mesaj düğmeleri, kenar çubuğu düğmesi) sohbet adı değildir
    private static let noisePrefixes = ["includes ", "you said:", "claude said:", "chatgpt said:", "show message actions", "message actions for",
                                        "open sidebar", "close sidebar", "toggle sidebar", "collapse sidebar", "expand sidebar",
                                        "scroll to bottom", "skip to content", "şunu dedin:"]

    /// Claude'un yan menüde adın sonuna eklediği işaretler ("TelepAIth Includes an artifact")
    private static let decorations = ["includes an artifact", "contains an artifact", "has an artifact", "artifact içerir",
                                      "starred", "pinned", "yıldızlı", "sabitlendi", "sabitlenmiş"]

    /// Adın sonundaki işaretleri at: "TelepAIth Includes an artifact" → "TelepAIth" (Windows'ta StripDecorations)
    static func stripDecorations(_ name: String) -> String {
        var t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var changed = true
        while changed {
            changed = false
            let l = t.lowercased()
            outer: for d in decorations {
                for sep in [", ", " · ", " - ", " — ", " | ", " "] where l.hasSuffix(sep + d) && l.count > d.count + sep.count {
                    t = String(t.prefix(t.count - d.count - sep.count)).trimmingCharacters(in: .whitespaces)
                    changed = true
                    break outer
                }
            }
        }
        return t
    }

    /// Addaki durum ekini ve işaretleri at: "Tarif, running" → "Tarif", "Kod Includes an artifact" → "Kod"
    static func stripStatus(_ name: String) -> String {
        stripDecorations(stripStatusOnly(stripDecorations(name)))
    }

    private static func stripStatusOnly(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if isNoise(t) { return "" }
        let l = normalized(t)
        // Küçük harfe çevirmek uzunluğu değiştirebilir (Türkçe İ); karakter sayısıyla kes
        func dropLast(_ n: Int) -> String { String(t.prefix(Swift.max(0, l.count - n))).trimmingCharacters(in: .whitespaces) }
        for w in waitingWords + workingWords {
            if l == w { return "" }
            if l.hasSuffix("(" + w + ")") { return dropLast(w.count + 2) }
            for sep in separators {
                if l.hasSuffix(sep + w) { return dropLast(w.count + sep.count) }
                if l.hasPrefix(w + sep) { return String(t.dropFirst(w.count + sep.count)).trimmingCharacters(in: .whitespaces) }
            }
        }
        if let s = spacedStatus(t) { return s.title }
        return t
    }

    /// Adres: sorgu ve son eğik çizgi olmadan (aynı sohbetin adresleri eşleşsin)
    static func normalizeURL(_ url: String?) -> String? {
        guard let url = url, let u = URL(string: url), let host = u.host else { return nil }
        var path = u.path
        while path.hasSuffix("/") { path.removeLast() }
        return (host + path).lowercased()
    }

    /// Claude masaüstünün resmî bağlantısı: claude.ai/chat/<id> → claude://claude.ai/chat/<id>.
    /// Uygulama bu bağlantıyla o sohbeti doğrudan açar (yan menüde aramaya gerek kalmaz). (Windows'ta DeepLink)
    static func deepLink(_ url: String?) -> URL? {
        guard let url = url, let u = URL(string: url), let host = u.host?.lowercased(),
              host == "claude.ai" || host.hasSuffix(".claude.ai") else { return nil }
        let parts = u.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, ["chat", "project"].contains(parts[0].lowercased()) else { return nil }
        let id = parts[1]
        guard id.count >= 8, id.allSatisfy({ $0.isHexDigit || $0 == "-" }) else { return nil }
        return URL(string: "claude://claude.ai/\(parts[0].lowercased())/\(id)")
    }

    // MARK: Yan menüyü yapısından tanıma

    /// Gezinme bölümü mü? (sayfadaki <nav>: Mac'te alt rolü AXLandmarkNavigation, Windows'ta yerel türü "navigation";
    /// ya da adı "Sidebar" olan grup). Yan menü budur; sohbet içeriği burada değildir. (Windows'ta IsNavigation)
    static func isNavigation(kind: String, name: String) -> Bool {
        let k = kind.lowercased()
        if ["axlandmarknavigation", "navigation", "gezinti", "gezinme"].contains(k) { return true }
        return ["sidebar", "kenar çubuğu", "yan menü", "yan çubuk"].contains(normalized(name))
    }

    /// Ana içerik bölümü mü? (<main>: sohbetin kendisi; buradaki yazılar asla sohbet listesi sayılmaz)
    static func isMainContent(kind: String) -> Bool {
        ["axlandmarkmain", "main", "ana", "ana içerik"].contains(kind.lowercased())
    }

    /// Taranan öğelerden yan menüdekiler: gezinme bölümü bulunduysa yalnızca onun içindekiler,
    /// bulunamadıysa ana içerik dışındakiler. viaNav: gezinme bölümü bulundu mu (teşhis için)
    static func pickSidebar(_ entries: [(item: SidebarItem, inNav: Bool, inMain: Bool)]) -> (items: [SidebarItem], viaNav: Bool) {
        if entries.contains(where: { $0.inNav }) { return (entries.filter { $0.inNav }.map(\.item), true) }
        return (entries.filter { !$0.inMain }.map(\.item), false)
    }

    /// Yan menüdeki gezinme sekmeleri (seçili olsalar da sohbet adı değildir)
    private static let navWords: Set<String> = [
        "chat", "chats", "code", "cowork", "projects", "artifacts", "recents", "home", "search", "new chat", "settings",
        "sohbet", "sohbetler", "kod", "projeler", "son kullanılanlar", "ana sayfa", "ara", "yeni sohbet", "ayarlar",
    ]

    private static func key(url: String?, title: String) -> String {
        normalizeURL(url) ?? "t:" + title.lowercased()
    }

    /// Yan menü öğelerinden durumu belli sohbetler (aynı sohbet bir kez; açık olan da dahil, current işaretiyle)
    static func parse(_ items: [SidebarItem]) -> [(row: Row, current: Bool)] {
        var rows: [String: (row: Row, current: Bool)] = [:]
        var order: [String] = []
        for item in items {
            guard let st = statusOf(item.help) ?? statusOf(item.name) else { continue }
            var title = stripStatus(item.name)
            var url = item.url
            var current = item.current
            if title.count < 2 || url == nil {
                // Nokta tek başına bir öğe: aynı satırdaki sohbet bağlantısını bul
                let cy = item.rect.midY
                var row: SidebarItem?
                for o in items where o != item {
                    let oTitle = stripStatus(o.name)
                    if statusOf(o.name) != nil && oTitle.count < 2 { continue }
                    if o.url == nil || oTitle.count < 2 { continue }   // sadece sohbet bağlantıları
                    if abs(o.rect.midY - cy) > Swift.max(o.rect.height / 2, 12) { continue }
                    if let r = row {
                        let better = (o.url != nil && r.url == nil)
                            || ((o.url != nil) == (r.url != nil) && abs(o.rect.midY - cy) < abs(r.rect.midY - cy))
                        if better { row = o }
                    } else {
                        row = o
                    }
                }
                if let r = row {
                    if title.count < 2 { title = stripStatus(r.name) }
                    if url == nil { url = r.url }
                    current = current || r.current
                }
            }
            // Sohbet satırı bir bağlantıdır: adresi olmayan (sohbetin içindeki mesaj, düğme…) satır sayılmaz.
            // Tek istisna: durumu kendi adında taşıyan satır ("Tarif · running")
            // (Bir sohbet adı kısadır: uzun metin bir mesajdır, sohbet satırı değil)
            let ownName = statusOf(item.name) != nil && (2...80).contains(stripStatus(item.name).count)
            guard title.count >= 2, url != nil || ownName else { continue }
            let k = key(url: url, title: title)
            if let old = rows[k], old.row.state.priority >= st.priority { continue }
            if rows[k] == nil { order.append(k) }
            rows[k] = (Row(key: k, title: title, url: url, state: st), current)
        }
        return order.compactMap { rows[$0] }
    }

    func sessionID(for key: String) -> String {
        var h: UInt32 = 2166136261
        for c in key.utf16 { h = (h ^ UInt32(c)) &* 16777619 }
        return "bg-\(pid)-" + String(format: "%08x", h)
    }

    /// Bir taramanın yan menü öğelerini işler; robota gönderilecek olayları döner.
    /// currentChat: açık sohbetin adresi (o zaten büyük kafada izleniyor, burada sayılmaz).
    func update(_ items: [SidebarItem], currentChat: String?, now: TimeInterval) -> [AgentEvent] {
        var events: [AgentEvent] = []
        let currentKey = SidebarChats.normalizeURL(currentChat)

        var rows: [String: Row] = [:]
        var rowOrder: [String] = []
        var currentRows = Set<String>()
        for (row, cur) in SidebarChats.parse(items) {
            if cur || (currentKey != nil && row.key == currentKey) {
                currentRows.insert(row.key)
            } else {
                rows[row.key] = row
                rowOrder.append(row.key)
            }
        }
        // Ekranda görünen (noktası sönmüş olsa da) sohbetler: "bitti" demek için satırın hâlâ görünmesi gerekir
        var visible = Set<String>()
        for it in items {
            let title = SidebarChats.stripStatus(it.name)
            if it.url != nil { visible.insert(SidebarChats.key(url: it.url, title: title)) }
            if title.count >= 2 { visible.insert("t:" + title.lowercased()) }
            if it.current && (it.url != nil || title.count >= 2) { currentRows.insert(SidebarChats.key(url: it.url, title: title)) }
        }
        if let k = currentKey { currentRows.insert(k) }

        let working = loc("Arkada çalışıyor", "Working in the background")
        let waiting = loc("Cevabını bekliyor", "Waiting for your reply")
        for k in rowOrder {
            guard let row = rows[k] else { continue }
            let id = sessionID(for: k)
            if known.count > 300 { known.removeAll() }
            known[id] = (row.title, row.url)
            guard var chat = chats[k] else {
                chats[k] = Chat(title: row.title, url: row.url, state: row.state, since: now, lastBeat: now)
                events.append(row.state == .waiting
                    ? ev(id, row.title, .waiting, .waiting, waiting, "✋")
                    : ev(id, row.title, .prompt, .thinking, working, "🔄"))
                continue
            }
            chat.title = row.title
            if chat.url == nil { chat.url = row.url }
            if row.state != chat.state {
                chat.state = row.state
                chat.lastBeat = now
                events.append(row.state == .waiting
                    ? ev(id, row.title, .waiting, .waiting, waiting, "✋")
                    : ev(id, row.title, .status, .thinking, working, "🔄"))
            } else if now - chat.lastBeat > 20 && now - chat.since < SidebarChats.maxRunSeconds {
                chat.lastBeat = now
                events.append(ev(id, row.title, .heartbeat))
            }
            chats[k] = chat
        }

        for k in chats.keys.sorted() where rows[k] == nil {
            guard let chat = chats.removeValue(forKey: k) else { continue }
            let id = sessionID(for: k)
            // Satır görünüyor ve noktası söndüyse iş bitti; açıldıysa, kaydırıldıysa ya da menü kapandıysa sessizce bırak
            let finished = visible.contains(k) && !currentRows.contains(k) && chat.state != .waiting
            if finished && now - chat.since >= 4 {
                var stop = ev(id, chat.title, .stop, .done)
                stop.forceNotify = true
                events.append(stop)
            } else {
                events.append(ev(id, chat.title, .sessionEnd))
            }
        }
        return events
    }

    /// Bu oturum hangi sohbet? (yan menüde bulup açmak için: ad ve adres)
    func find(_ sessionID: String) -> (title: String, url: String?)? {
        for (k, chat) in chats where self.sessionID(for: k) == sessionID { return (chat.title, chat.url) }
        return known[sessionID]
    }

    /// Yan menüde açık sohbetin adı: önce adresi açık sohbetinkiyle aynı olan bağlantı, sonra seçili bağlantı,
    /// en son seçili satır (Code oturumları gibi bağlantısız listeler). Gezinme sekmeleri ("Chats", "Code") sayılmaz.
    static func currentTitle(_ items: [SidebarItem], currentChat: String?) -> String? {
        let key = normalizeURL(currentChat)
        // Sohbet adresi (claude.ai/chat/…, chatgpt.com/c/…) taşıyan bağlantının adı, "Kod" gibi sekme adlarına benzese de sohbet adıdır
        func isChatLink(_ url: String?) -> Bool {
            guard let u = normalizeURL(url) else { return false }
            return u.contains("/chat/") || u.contains("/c/")
        }
        func usable(_ it: SidebarItem, min: Int) -> String? {
            let title = stripStatus(it.name)
            guard title.count >= min, isChatLink(it.url) || !navWords.contains(normalized(title)) else { return nil }
            return title
        }
        if let key = key {
            for it in items where it.url != nil && normalizeURL(it.url) == key {
                let title = stripStatus(it.name)
                if title.count >= 2 { return title }
            }
        }
        for it in items where it.current && it.url != nil { if let t = usable(it, min: 2) { return t } }
        for it in items where it.current && it.url == nil { if let t = usable(it, min: 4) { return t } }
        return nil
    }

    /// Uygulama kapandı: arkadaki sohbetleri kapat
    func closed() -> [AgentEvent] {
        let events = chats.keys.sorted().map { ev(sessionID(for: $0), chats[$0]!.title, .sessionEnd) }
        chats.removeAll()
        return events
    }

    private func ev(_ id: String, _ title: String, _ kind: EventKind, _ state: RobotState? = nil,
                    _ text: String? = nil, _ emoji: String? = nil) -> AgentEvent {
        var e = AgentEvent(source: source, sessionID: id, kind: kind, state: state, text: text)
        e.project = clip(title, 40)
        e.emoji = emoji
        e.appPID = pid
        e.quietIfFrontmostPID = pid   // uygulama öndeyken arkadaki sohbetin bildirimi/sesi gelmez (robot balonda söyler)
        return e
    }
}
