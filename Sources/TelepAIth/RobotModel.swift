import AppKit
import Combine

/// Bir AI'ın (kaynağın) durumu: oturumları takip eder, robotun ne söyleyeceğini hesaplar.
/// Ekrandaki tek robot, o an gösterilen kaynağın modelini çizer.
final class RobotModel: ObservableObject {
    struct Session {
        var state: RobotState
        var text: String?
        var emoji: String?
        var project: String?
        var updated: Date
        var turnStart: Date?
        var lastWaitNotice: Date?
        var tools = 0
        var edits = 0
        var errors = 0
        var errorRun = 0
        var target: AppTarget?
        var waitingSince: Date?
        var reminded = false
    }

    struct Notice {
        let title: String
        let body: String
        /// Odak modunda da gösterilsin mi (seni bekliyor, hata, kota bitti)
        var important = false
        var target: AppTarget?
    }

    /// Robotun yanındaki minik kafalar: aynı anda çalışan diğer oturumlar.
    struct MiniSession: Equatable, Identifiable {
        let id: String
        let source: String
        let state: RobotState
        let label: String
    }

    let source: String
    @Published private(set) var theme: SourceTheme
    @Published private(set) var state: RobotState = .idle
    @Published private(set) var bubbleText: String?
    @Published private(set) var bubbleSubtitle: String?
    @Published private(set) var celebrateStart: Date?
    @Published private(set) var errorStart: Date?
    @Published private(set) var mood: Mood?
    /// Balona tıklayınca gidilecek yer (gösterilen oturumun uygulaması)
    @Published private(set) var target: AppTarget?
    /// Gösterilen oturum ne zamandan beri seni bekliyor
    @Published private(set) var waitingSince: Date?
    /// ClaudeBar'dan son bilinen kalan kota (%)
    @Published private(set) var quotaLeft: Int?
    private var quotaAt: Date?
    /// Balondaki yazı robotun kendi söylediği bir şey mi (güncelleme, kilit, odak…)? Odak modunda da gösterilir.
    @Published private(set) var bubbleIsExplicit = false
    private var explicitUntil: Date?
    private var moodUntil: Date?
    private(set) var bestSessionID: String?
    /// Zamanlayıcıdan gelen bildirimler (bekleme hatırlatması); RobotManager boşaltır
    var pendingNotices: [Notice] = []

    var onStateChange: (() -> Void)?

    /// Bu kaynaktan gelen son gerçek olay (kimi göstereceğimize karar verirken kullanılır).
    private(set) var lastRealEvent: Date?
    private(set) var history: [String] = []
    private var sessions: [String: Session] = [:]
    private var lastEventAt = Date()
    private var lastCleanup = Date()
    private var overrideText: String?
    private var overrideUntil: Date?
    private var nextIdleThought = Date().addingTimeInterval(Double.random(in: 60...120))

    private static let clock: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    init(source: String) {
        self.source = source
        self.theme = Themes.shared.theme(for: source)
    }

    func reloadTheme() {
        theme = Themes.shared.theme(for: source)
    }

    var statusLine: String {
        clip(bubbleText ?? withEmoji(state.emoji, state.label), 48)
    }

    // MARK: - Konuşma

    private static func donePhrase() -> String {
        let phrases = Language.current == .tr
            ? ["Bitti!", "Tamamdır!", "Hallettim!", "İş bitti!"]
            : ["Done!", "All set!", "Finished!", "Nailed it!"]
        return phrases.randomElement() ?? phrases[0]
    }

    private static func doneEmoji() -> String {
        ["🎉", "✨", "✅", "🪄"].randomElement() ?? "🎉"
    }

    private func setMood(_ mood: Mood, for seconds: Double, now: Date) {
        self.mood = mood
        moodUntil = now.addingTimeInterval(seconds)
    }

    private static func play(_ name: String) {
        guard Preferences.sounds, !FocusMode.isActive else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    private static func idleThought() -> String {
        let thoughts: [(String, String, String)] = [
            ("🪄", "Bir büyü yapalım mı?", "Shall we cast a spell?"),
            ("✨", "Hazırım, ne yapıyoruz?", "Ready when you are."),
            ("🔮", "Kristal küreme bakıyorum…", "Gazing into my crystal ball…"),
            ("🙂", "Buradayım.", "I'm right here."),
            ("📚", "Yeni bir şey öğrenmek isterdim.", "I'd love to learn something new."),
            ("☕️", "Kahve molası mı?", "Coffee break?"),
            ("👀", "Noktalarım parlıyor mu?", "Are my dots glowing?"),
        ]
        let pick = thoughts.randomElement() ?? thoughts[0]
        return withEmoji(pick.0, loc(pick.1, pick.2))
    }

    // MARK: - Olaylar

    func apply(_ e: AgentEvent, now: Date = Date()) -> Notice? {
        lastEventAt = now
        if e.kind != .heartbeat && e.kind != .toolDone { lastRealEvent = now }
        if let t = e.text, !t.isEmpty { remember(withEmoji(e.emoji, t), now: now) }
        if let m = e.mood { setMood(m, for: e.moodSeconds, now: now) }
        var notice: Notice?

        switch e.kind {
        case .quota:
            let text = withEmoji(e.emoji, e.text ?? "")
            showOverride(text, for: 10, now: now)
            if e.state == .error { errorStart = now }
            if let left = e.quotaLeft {
                quotaLeft = max(0, min(100, left))
                quotaAt = now
            } else if e.state == .error {
                quotaLeft = 0
                quotaAt = now
            }
            if e.forceNotify {
                notice = Notice(title: theme.displayName + loc(" kota", " quota"), body: text,
                                important: e.state == .error || (e.quotaLeft ?? 100) <= 10)
            }

        case .heartbeat:
            sessions[e.sessionID]?.updated = now

        case .say:
            showOverride(withEmoji(e.emoji, e.text ?? ""), for: 4, now: now)

        case .toolDone:
            if var s = sessions[e.sessionID] {
                if s.state == .waiting {
                    s.state = .thinking
                    s.text = loc("Devam ediyor…", "Back to work…")
                    s.emoji = "🔮"
                    s.waitingSince = nil
                    s.reminded = false
                }
                if e.state == .error {
                    s.errors += 1
                    s.errorRun += 1
                    if s.errorRun >= 3 {
                        setMood(.dizzy, for: 6, now: now)
                        showOverride(withEmoji("😵‍💫", loc("Üst üste \(s.errorRun) hata", "\(s.errorRun) errors in a row")), for: 5, now: now)
                        RobotModel.play("Basso")
                    }
                } else {
                    s.errorRun = 0
                }
                s.updated = now
                sessions[e.sessionID] = s
            }
            if let t = e.text, !(e.state == .error && (sessions[e.sessionID]?.errorRun ?? 0) >= 3) {
                showOverride(withEmoji(e.emoji, t), for: 4, now: now)
                if e.mood == .party { RobotModel.play("Hero") }
            }

        case .sessionEnd:
            sessions.removeValue(forKey: e.sessionID)

        default:
            var s = sessions[e.sessionID]
                ?? Session(state: .idle, text: nil, emoji: nil, project: e.project, updated: now, turnStart: nil, lastWaitNotice: nil)
            if let st = e.state { s.state = st }
            if let t = e.text {
                s.text = t
                s.emoji = e.emoji ?? s.state.emoji
            }
            if let p = e.project { s.project = p }
            if let pid = e.appPID ?? e.quietIfFrontmostPID {
                s.target = AppTarget(pid: pid, bundleID: nil)
            } else if let id = e.appBundleID {
                s.target = AppTarget(pid: nil, bundleID: id)
            }
            if s.state == .waiting {
                if s.waitingSince == nil { s.waitingSince = now }
            } else {
                s.waitingSince = nil
                s.reminded = false
            }
            s.updated = now
            if e.kind == .prompt {
                s.turnStart = now
                s.tools = 0
                s.edits = 0
                s.errors = 0
                s.errorRun = 0
            }
            if s.state.isWorking && s.turnStart == nil { s.turnStart = now }
            if e.kind == .tool {
                s.tools += 1
                if s.state == .editing { s.edits += 1 }
            }
            let place = s.project.map { " · \($0)" } ?? ""

            switch e.kind {
            case .stop:
                let duration = s.turnStart.map { now.timeIntervalSince($0) } ?? 0
                // Mochi gibi tur özeti: süre, araç ve düzenleme sayısı
                var parts = [RobotModel.donePhrase()]
                if duration >= 1 { parts.append(formatDuration(duration)) }
                if s.tools > 0 { parts.append(loc("\(s.tools) araç", "\(s.tools) tools")) }
                if s.edits > 0 { parts.append(loc("\(s.edits) düzenleme", "\(s.edits) edits")) }
                var text = e.text ?? parts.joined(separator: " · ")
                if let m = e.lastMessage, !m.isEmpty { text += "\n" + clip(m, 110) }
                s.text = text
                if duration > 180 || s.tools > 25 {
                    s.emoji = e.emoji ?? "😮‍💨"
                    setMood(.tired, for: 6, now: now)
                } else if s.edits > 0 && s.errors == 0 {
                    s.emoji = e.emoji ?? RobotModel.doneEmoji()
                    setMood(.proud, for: 6, now: now)
                } else {
                    s.emoji = e.emoji ?? RobotModel.doneEmoji()
                }
                if duration >= 1 || s.tools > 0 {
                    DailyStats.shared.recordTurn(source: source, seconds: duration, tools: s.tools, edits: s.edits, at: now)
                }
                s.turnStart = nil
                celebrateStart = now
                RobotModel.play("Glass")
                remember(withEmoji(s.emoji, text), now: now)
                // Anlatıcının "bitti"si bildirim atmaz (izleyici ya da hook zaten haber veriyor)
                if e.sessionID != "mcp" && (e.forceNotify || duration >= Preferences.longTurnSeconds) {
                    var body = (s.project ?? loc("Görev", "Task")) + " — " + formatDuration(duration)
                    if let m = e.lastMessage, !m.isEmpty { body += "\n" + clip(m, 140) }
                    notice = Notice(title: withEmoji(s.emoji, theme.displayName + loc(" bitirdi", " is done")), body: body,
                                    target: s.target)
                }
            case .waiting:
                let canNotify = s.lastWaitNotice.map { now.timeIntervalSince($0) > 20 } ?? true
                if canNotify {
                    s.lastWaitNotice = now
                    DailyStats.shared.recordWait(source: source, at: now)
                    RobotModel.play("Ping")
                    notice = Notice(title: withEmoji(s.emoji, theme.displayName + loc(" seni bekliyor", " needs you") + place),
                                    body: s.text ?? loc("Cevabını bekliyor", "Waiting for your reply"),
                                    important: true, target: s.target)
                }
            case .failure:
                errorStart = now
                RobotModel.play("Basso")
                notice = Notice(title: withEmoji(s.emoji, theme.displayName + loc(" hata verdi", " hit an error") + place),
                                body: s.text ?? "", important: true, target: s.target)
            case .interrupt:
                s.turnStart = nil
            default:
                break
            }
            sessions[e.sessionID] = s
            // Uygulama işi bitirdiyse anlatıcının son cümlesi ekranda asılı kalmasın
            if e.kind == .stop && e.sessionID != "mcp" { sessions.removeValue(forKey: "mcp") }
        }

        refresh(now: now)
        return notice
    }

    /// Robotun balonda bir şey söylemesi (güncelleme haberi, uyarı…)
    func say(_ text: String, for seconds: TimeInterval = 8) {
        let now = Date()
        showOverride(text, for: seconds, now: now)
        explicitUntil = now.addingTimeInterval(seconds)
        refresh(now: now)
    }

    /// Uyuyorsa uyandır (AI uygulaması açıldı, öne geldi ya da robota tıklandı).
    /// greet: kısa bir balon; always değilse sadece uyuyorduysa gösterilir.
    func wake(greet: String? = nil, always: Bool = false) {
        let now = Date()
        let wasSleeping = state == .sleeping
        lastEventAt = now
        if wasSleeping || always, let greet = greet { showOverride(greet, for: 3, now: now) }
        refresh(now: now)
    }

    /// Balondaki geçici yazıyı kaldır (yeni bir soru geldiğinde eski "izin verdim" onu örtmesin)
    func clearSay() {
        overrideUntil = nil
        explicitUntil = nil
        refresh(now: Date())
    }

    func showHistory() {
        let lines = history.suffix(5)
        showOverride(lines.isEmpty ? loc("Henüz bir şey olmadı", "Nothing has happened yet") : lines.joined(separator: "\n"),
                     for: 6, now: Date())
        refresh(now: Date())
    }

    private func remember(_ text: String, now: Date) {
        let short = clip(text, 60)
        if let last = history.last, last.hasSuffix(short) { return }
        history.append("\(RobotModel.clock.string(from: now))  \(short)")
        if history.count > 30 { history.removeFirst(history.count - 30) }
    }

    private func showOverride(_ text: String, for seconds: TimeInterval, now: Date) {
        overrideText = text
        overrideUntil = now.addingTimeInterval(seconds)
        explicitUntil = nil
    }

    // MARK: - Durum hesaplama (saniyede 30 kez çağrılır)

    func refresh(now: Date) {
        if let until = moodUntil, until <= now {
            moodUntil = nil
            mood = nil
        }
        if now.timeIntervalSince(lastCleanup) > 5 {
            lastCleanup = now
            sessions = sessions.filter { now.timeIntervalSince($0.value.updated) < 3600 }
            // Kota bilgisi 6 saatte eskir
            if let at = quotaAt, now.timeIntervalSince(at) > 6 * 3600 {
                quotaAt = nil
                quotaLeft = nil
            }
            // Uzun süre onay bekleyen oturum: 2 dakika sonra bir kez daha hatırlat
            if Preferences.waitReminders {
                for (id, s) in sessions where s.state == .waiting && !s.reminded {
                    guard let since = s.waitingSince, now.timeIntervalSince(since) >= 120 else { continue }
                    sessions[id]?.reminded = true
                    let place = s.project.map { " · \($0)" } ?? ""
                    pendingNotices.append(Notice(title: withEmoji("⏰", theme.displayName + loc(" hâlâ seni bekliyor", " is still waiting for you") + place),
                                                 body: s.text ?? loc("Cevabını bekliyor", "Waiting for your reply"),
                                                 important: true, target: s.target))
                    showOverride(withEmoji("⏰", loc("Hâlâ onayını bekliyorum!", "Still waiting for your OK!")), for: 6, now: now)
                }
            }
        }

        var bestSession: Session?
        var bestID: String?
        var bestState: RobotState = .idle
        for (id, s) in sessions {
            let st = effectiveState(s, id: id, now: now)
            if let b = bestSession {
                if st.priority > bestState.priority || (st.priority == bestState.priority && s.updated > b.updated) {
                    bestSession = s
                    bestID = id
                    bestState = st
                }
            } else {
                bestSession = s
                bestID = id
                bestState = st
            }
        }
        bestSessionID = bestID
        let newTarget = bestSession?.target
        if newTarget != target { target = newTarget }
        let newWaiting = bestState == .waiting ? bestSession?.waitingSince : nil
        if newWaiting != waitingSince { waitingSince = newWaiting }

        var newState = bestSession == nil ? RobotState.idle : bestState
        if newState == .idle && now.timeIntervalSince(lastEventAt) > 600 { newState = .sleeping }

        // Boştayken ara sıra laf at
        if newState == .idle && Preferences.idleChatter && !FocusMode.isActive && overrideUntil == nil && now >= nextIdleThought {
            showOverride(RobotModel.idleThought(), for: 5, now: now)
            nextIdleThought = now.addingTimeInterval(Double.random(in: 150...360))
        }

        var text: String?
        var subtitle: String?
        if let until = overrideUntil, until > now, let o = overrideText {
            text = o
        } else {
            overrideText = nil
            overrideUntil = nil
            if let b = bestSession, newState != .idle, newState != .sleeping {
                text = b.text.map { withEmoji(b.emoji, $0) } ?? withEmoji(newState.emoji, newState.label)
                subtitle = b.project
                if newState == .done && now.timeIntervalSince(b.updated) > 15 {
                    text = nil
                    subtitle = nil
                }
            }
        }

        if newState != state {
            state = newState
            onStateChange?()
        }
        let explicit = (explicitUntil.map { $0 > now } ?? false) && text != nil
        if explicit != bubbleIsExplicit { bubbleIsExplicit = explicit }
        if text != bubbleText { bubbleText = text }
        if subtitle != bubbleSubtitle { bubbleSubtitle = subtitle }
        // Yüz değiştiyse (durum ya da ruh hâli) çizim eskisinden yenisine yumuşakça geçsin
        if state != visualState || mood != visualMood {
            previousState = visualState
            previousMood = visualMood
            visualChangedAt = now
            visualState = state
            visualMood = mood
        }
    }

    private var visualState: RobotState = .idle
    private var visualMood: Mood?
    /// Bir önceki yüz (durum + ruh hâli) ve değiştiği an: çizim aradaki geçişi yumuşatır
    private(set) var previousState: RobotState = .idle
    private(set) var previousMood: Mood?
    private(set) var visualChangedAt: Date = .distantPast

    /// Bu AI'ın, ekranda gösterilen dışında kalan çalışan/bekleyen oturumları.
    /// Masaüstü uygulamasından izlenen sohbet ("app-…") ile Anlatıcı'nın ("mcp") anlattığı aynı sohbettir:
    /// ikisi ayrı minik kafa olmasın.
    static func sessionGroup(_ id: String) -> String { id == "mcp" || id.hasPrefix("app-") ? "desktop" : id }

    func miniSessions(excluding excluded: String?, now: Date = Date()) -> [MiniSession] {
        let excludedGroup = excluded.map(RobotModel.sessionGroup)
        var best: [String: (id: String, s: Session, st: RobotState)] = [:]
        for (id, s) in sessions {
            let group = RobotModel.sessionGroup(id)
            guard group != excludedGroup else { continue }
            let st = effectiveState(s, id: id, now: now)
            guard st.isWorking || st == .waiting else { continue }
            if let b = best[group], b.st.priority > st.priority || (b.st.priority == st.priority && b.s.updated >= s.updated) { continue }
            best[group] = (id, s, st)
        }
        return best.values.map { x in
            let label = [theme.displayName, x.s.project, x.s.text.map { clip($0, 40) }].compactMap { $0 }.joined(separator: " · ")
            return MiniSession(id: source + "/" + x.id, source: source, state: x.st, label: label)
        }
        .sorted { $0.id < $1.id }
    }

    private func effectiveState(_ s: Session, id: String, now: Date) -> RobotState {
        let age = now.timeIntervalSince(s.updated)
        if id == "mcp" && s.state.isWorking && age > 90 { return .idle }   // anlatıcı sustuysa
        if s.state == .done && age > 90 { return .idle }
        if s.state == .error && age > 60 { return .idle }
        if s.state.isWorking && age > 300 { return .idle } // takılı kalan oturum
        return s.state
    }
}
