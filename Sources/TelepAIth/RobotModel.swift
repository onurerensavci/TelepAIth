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
    }

    struct Notice {
        let title: String
        let body: String
    }

    let source: String
    @Published private(set) var theme: SourceTheme
    @Published private(set) var state: RobotState = .idle
    @Published private(set) var bubbleText: String?
    @Published private(set) var bubbleSubtitle: String?
    @Published private(set) var celebrateStart: Date?
    @Published private(set) var errorStart: Date?

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

    private static func idleThought() -> String {
        let thoughts: [(String, String, String)] = [
            ("🪄", "Bir büyü yapalım mı?", "Shall we cast a spell?"),
            ("✨", "Hazırım, ne yapıyoruz?", "Ready when you are."),
            ("🔮", "Kristal küreme bakıyorum…", "Gazing into my crystal ball…"),
            ("🙂", "Buradayım.", "I'm right here."),
            ("📚", "Yeni bir şey öğrenmek isterdim.", "I'd love to learn something new."),
            ("☕️", "Kahve molası mı?", "Coffee break?"),
            ("🧙", "Şapkam yerinde mi?", "Is my hat on straight?"),
        ]
        let pick = thoughts.randomElement() ?? thoughts[0]
        return withEmoji(pick.0, loc(pick.1, pick.2))
    }

    // MARK: - Olaylar

    func apply(_ e: AgentEvent, now: Date = Date()) -> Notice? {
        lastEventAt = now
        if e.kind != .heartbeat && e.kind != .toolDone { lastRealEvent = now }
        if let t = e.text, !t.isEmpty { remember(withEmoji(e.emoji, t), now: now) }
        var notice: Notice?

        switch e.kind {
        case .quota:
            let text = withEmoji(e.emoji, e.text ?? "")
            showOverride(text, for: 10, now: now)
            if e.state == .error { errorStart = now }
            if e.forceNotify { notice = Notice(title: theme.displayName + loc(" kota", " quota"), body: text) }

        case .heartbeat:
            sessions[e.sessionID]?.updated = now

        case .toolDone:
            if var s = sessions[e.sessionID] {
                if s.state == .waiting {
                    s.state = .thinking
                    s.text = loc("Devam ediyor…", "Back to work…")
                    s.emoji = "🔮"
                }
                s.updated = now
                sessions[e.sessionID] = s
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
            s.updated = now
            if e.kind == .prompt { s.turnStart = now }
            if s.state.isWorking && s.turnStart == nil { s.turnStart = now }
            let place = s.project.map { " · \($0)" } ?? ""

            switch e.kind {
            case .stop:
                let duration = s.turnStart.map { now.timeIntervalSince($0) } ?? 0
                let phrase = RobotModel.donePhrase()
                var text = e.text ?? (duration >= 1 ? "\(phrase) (\(formatDuration(duration)))" : phrase)
                if let m = e.lastMessage, !m.isEmpty { text += "\n" + clip(m, 110) }
                s.text = text
                s.emoji = e.emoji ?? RobotModel.doneEmoji()
                s.turnStart = nil
                celebrateStart = now
                remember(withEmoji(s.emoji, text), now: now)
                if e.forceNotify || duration >= Preferences.longTurnSeconds {
                    var body = (s.project ?? loc("Görev", "Task")) + " — " + formatDuration(duration)
                    if let m = e.lastMessage, !m.isEmpty { body += "\n" + clip(m, 140) }
                    notice = Notice(title: withEmoji(s.emoji, theme.displayName + loc(" bitirdi", " is done")), body: body)
                }
            case .waiting:
                let canNotify = s.lastWaitNotice.map { now.timeIntervalSince($0) > 20 } ?? true
                if canNotify {
                    s.lastWaitNotice = now
                    notice = Notice(title: withEmoji(s.emoji, theme.displayName + loc(" seni bekliyor", " needs you") + place),
                                    body: s.text ?? loc("Cevabını bekliyor", "Waiting for your reply"))
                }
            case .failure:
                errorStart = now
                notice = Notice(title: withEmoji(s.emoji, theme.displayName + loc(" hata verdi", " hit an error") + place),
                                body: s.text ?? "")
            case .interrupt:
                s.turnStart = nil
            default:
                break
            }
            sessions[e.sessionID] = s
        }

        refresh(now: now)
        return notice
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
    }

    // MARK: - Durum hesaplama (saniyede 30 kez çağrılır)

    func refresh(now: Date) {
        if now.timeIntervalSince(lastCleanup) > 5 {
            lastCleanup = now
            sessions = sessions.filter { now.timeIntervalSince($0.value.updated) < 3600 }
        }

        var bestSession: Session?
        var bestState: RobotState = .idle
        for (_, s) in sessions {
            let st = effectiveState(s, now: now)
            if let b = bestSession {
                if st.priority > bestState.priority || (st.priority == bestState.priority && s.updated > b.updated) {
                    bestSession = s
                    bestState = st
                }
            } else {
                bestSession = s
                bestState = st
            }
        }

        var newState = bestSession == nil ? RobotState.idle : bestState
        if newState == .idle && now.timeIntervalSince(lastEventAt) > 600 { newState = .sleeping }

        // Boştayken ara sıra laf at
        if newState == .idle && Preferences.idleChatter && overrideUntil == nil && now >= nextIdleThought {
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
        if text != bubbleText { bubbleText = text }
        if subtitle != bubbleSubtitle { bubbleSubtitle = subtitle }
    }

    private func effectiveState(_ s: Session, now: Date) -> RobotState {
        let age = now.timeIntervalSince(s.updated)
        if s.state == .done && age > 90 { return .idle }
        if s.state == .error && age > 60 { return .idle }
        if s.state.isWorking && age > 300 { return .idle } // takılı kalan oturum
        return s.state
    }
}
