import AppKit
import Combine

/// Bir AI'ın (kaynağın) robotu: oturumları takip eder, durumu ve balonu hesaplar, ekranda yürütür.
final class RobotModel: ObservableObject {
    struct Session {
        var state: RobotState
        var text: String?
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
    @Published private(set) var facing: CGFloat = 1   // 1 sağa, -1 sola
    @Published private(set) var isWalking = false
    @Published private(set) var celebrateStart: Date?

    // Konum: pencerenin sol-alt köşesi (ekran koordinatı)
    var x: CGFloat = 0
    var y: CGFloat = 0
    private(set) var minX: CGFloat = 0
    private(set) var maxX: CGFloat = 800
    private(set) var groundY: CGFloat = 0
    private var vy: CGFloat = 0
    private(set) var isDragging = false

    var onStateChange: (() -> Void)?

    private(set) var history: [String] = []
    private var sessions: [String: Session] = [:]
    private var lastEventAt = Date()
    private var lastCleanup = Date()
    private var overrideText: String?
    private var overrideUntil: Date?
    private var targetX: CGFloat?
    private var pauseUntil = Date()

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
        clip(bubbleText ?? state.label, 48)
    }

    // MARK: - Olaylar

    func apply(_ e: AgentEvent, now: Date = Date()) -> Notice? {
        lastEventAt = now
        if let t = e.text, !t.isEmpty { remember(t, now: now) }
        var notice: Notice?

        switch e.kind {
        case .quota:
            let text = e.text ?? ""
            showOverride(text, for: 10, now: now)
            if e.forceNotify { notice = Notice(title: "\(theme.displayName) kota", body: text) }

        case .heartbeat:
            sessions[e.sessionID]?.updated = now

        case .toolDone:
            if var s = sessions[e.sessionID] {
                if s.state == .waiting {
                    s.state = .thinking
                    s.text = "Devam ediyor…"
                }
                s.updated = now
                sessions[e.sessionID] = s
            }

        case .sessionEnd:
            sessions.removeValue(forKey: e.sessionID)

        default:
            var s = sessions[e.sessionID]
                ?? Session(state: .idle, text: nil, project: e.project, updated: now, turnStart: nil, lastWaitNotice: nil)
            if let st = e.state { s.state = st }
            if let t = e.text { s.text = t }
            if let p = e.project { s.project = p }
            s.updated = now
            if e.kind == .prompt { s.turnStart = now }
            if s.state.isWorking && s.turnStart == nil { s.turnStart = now }
            let place = s.project.map { " · \($0)" } ?? ""

            switch e.kind {
            case .stop:
                let duration = s.turnStart.map { now.timeIntervalSince($0) } ?? 0
                s.text = e.text ?? (duration >= 1 ? "Bitti! (\(formatDuration(duration)))" : "Bitti!")
                s.turnStart = nil
                celebrateStart = now
                if e.forceNotify || duration >= Preferences.longTurnSeconds {
                    var body = (s.project ?? "Görev") + " — \(formatDuration(duration)) sürdü"
                    if let m = e.lastMessage, !m.isEmpty { body += "\n" + clip(m, 140) }
                    notice = Notice(title: "\(theme.displayName) bitirdi", body: body)
                }
            case .waiting:
                let canNotify = s.lastWaitNotice.map { now.timeIntervalSince($0) > 20 } ?? true
                if canNotify {
                    s.lastWaitNotice = now
                    notice = Notice(title: "\(theme.displayName) seni bekliyor\(place)", body: s.text ?? "Cevabını bekliyor")
                }
            case .failure:
                notice = Notice(title: "\(theme.displayName) hata verdi\(place)", body: s.text ?? "")
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
        showOverride(lines.isEmpty ? "Henüz bir şey olmadı" : lines.joined(separator: "\n"), for: 6, now: Date())
        refresh(now: Date())
    }

    private func remember(_ text: String, now: Date) {
        let line = "\(RobotModel.clock.string(from: now))  \(clip(text, 60))"
        if let last = history.last, last.hasSuffix(clip(text, 60)) { return }
        history.append(line)
        if history.count > 30 { history.removeFirst(history.count - 30) }
    }

    private func showOverride(_ text: String, for seconds: TimeInterval, now: Date) {
        overrideText = text
        overrideUntil = now.addingTimeInterval(seconds)
    }

    // MARK: - Durum hesaplama

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

        var text: String?
        var subtitle: String?
        if let until = overrideUntil, until > now, let o = overrideText {
            text = o
        } else {
            overrideText = nil
            overrideUntil = nil
            if let b = bestSession, newState != .idle, newState != .sleeping {
                text = b.text ?? newState.label
                subtitle = b.project
                if newState == .done && now.timeIntervalSince(b.updated) > 15 {
                    text = nil
                    subtitle = nil
                }
            }
        }

        if newState != state {
            state = newState
            targetX = nil
            pauseUntil = now
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

    // MARK: - Hareket

    private var speed: CGFloat {
        switch state {
        case .idle: return 28
        case .thinking: return 16
        case .reading: return 34
        case .searching: return 52
        case .running: return 90
        case .delegating: return 60
        case .editing, .waiting, .done, .error, .sleeping: return 0
        }
    }

    private func randomPause() -> TimeInterval {
        switch state {
        case .idle: return Double.random(in: 3...9)
        case .thinking: return Double.random(in: 0.8...2.0)
        default: return Double.random(in: 0.2...1.2)
        }
    }

    private func pickTarget() -> CGFloat {
        let range: CGFloat
        switch state {
        case .idle:
            return CGFloat.random(in: minX...Swift.max(minX + 1, maxX))
        case .thinking:
            range = 70
        default:
            range = 240
        }
        let lo = Swift.max(minX, x - range)
        let hi = Swift.min(maxX, x + range)
        return lo < hi ? CGFloat.random(in: lo...hi) : x
    }

    func setBounds(minX: CGFloat, maxX: CGFloat, groundY: CGFloat) {
        self.minX = minX
        self.maxX = Swift.max(minX, maxX)
        self.groundY = groundY
        x = Swift.min(Swift.max(x, self.minX), self.maxX)
        if y < groundY { y = groundY }
        targetX = nil
    }

    func tick(dt: CGFloat, now: Date) {
        refresh(now: now)
        guard !isDragging else { return }

        // Yerçekimi: sürükleyip havada bırakınca düşer
        if y > groundY + 0.5 || vy != 0 {
            vy -= 2200 * dt
            y += vy * dt
            if y <= groundY {
                y = groundY
                vy = abs(vy) > 300 ? abs(vy) * 0.3 : 0
            }
            setWalking(false)
            return
        }
        y = groundY

        let v = speed
        if v == 0 || now < pauseUntil {
            setWalking(false)
            return
        }
        let target = targetX ?? pickTarget()
        targetX = target
        let dir: CGFloat = target >= x ? 1 : -1
        if facing != dir { facing = dir }
        let step = v * dt
        if abs(target - x) <= step {
            x = target
            targetX = nil
            pauseUntil = now.addingTimeInterval(randomPause())
            setWalking(false)
        } else {
            x += dir * step
            setWalking(true)
        }
    }

    private func setWalking(_ walking: Bool) {
        if isWalking != walking { isWalking = walking }
    }

    func beginDrag() {
        isDragging = true
        vy = 0
        setWalking(false)
    }

    func drag(to origin: CGPoint) {
        x = Swift.min(Swift.max(origin.x, minX), maxX)
        y = Swift.max(origin.y, groundY)
    }

    func endDrag() {
        isDragging = false
        vy = 0
        targetX = nil
        pauseUntil = Date().addingTimeInterval(1.5)
    }
}
