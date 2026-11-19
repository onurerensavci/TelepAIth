import AppKit
import ApplicationServices

/// Claude, ChatGPT ve Codex masaüstü uygulamalarını Erişilebilirlik API'siyle izler.
/// Bu uygulamaların hook'u yok; pencerenin alt kısmında "Durdur" düğmesi görünüyorsa AI çalışıyordur,
/// "İzin ver" düğmesi varsa onay bekliyordur, "Durdur" kaybolunca iş bitmiştir.
/// Çalışırken yazı kutusunun hemen üstündeki son satırı (ör. "Mapping the dot grid…") okuyup söyler.
final class AppWatcher {
    var onEvent: ((AgentEvent) -> Void)?
    /// Menü için: uygulama adı → ne görüyorum
    var onStatus: (([String: String]) -> Void)?

    private struct Target {
        let pid: pid_t
        let source: String
        let name: String
    }

    private struct AppState {
        var source: String
        var name: String
        var generating = false
        var approving = false
        var quietPolls = 0
        var lastHeartbeat: TimeInterval = 0
        var phase: WorkPhase?
        var lastPhaseAt: TimeInterval = 0
        var startedAt: TimeInterval = 0
        var lastFullScan: TimeInterval = 0
        var lastDebugDump: TimeInterval = 0
        var enabledElectronAX = false
        var sawComposer = false
    }

    private enum ButtonKind {
        case stop, send, approve
    }

    /// AI'ın o an hangi aşamada olduğu (kısa, insanca bir cümleyle söylenir).
    enum WorkPhase: Equatable {
        case understanding, thinking, solving, looking, reading, writing, fixing, running, testing, finishing

        var phrase: String {
            switch self {
            case .understanding: return loc("İşi anlamaya çalışıyor…", "Getting the gist…")
            case .thinking: return loc("Düşünüyor…", "Thinking…")
            case .solving: return loc("Çözüyor…", "Working it out…")
            case .looking: return loc("Bakıyor, araştırıyor…", "Looking around…")
            case .reading: return loc("İnceliyor…", "Reading through…")
            case .writing: return loc("Yazıyor…", "Writing…")
            case .fixing: return loc("Düzeltiyor…", "Fixing things…")
            case .running: return loc("Komut çalıştırıyor…", "Running commands…")
            case .testing: return loc("Test ediyor…", "Testing…")
            case .finishing: return loc("Bitiriyor…", "Wrapping up…")
            }
        }

        var emoji: String {
            switch self {
            case .understanding: return "🤔"
            case .thinking: return "🧠"
            case .solving: return "🛠️"
            case .looking: return "🔍"
            case .reading: return "📖"
            case .writing: return "✍️"
            case .fixing: return "🔧"
            case .running: return "💻"
            case .testing: return "🧪"
            case .finishing: return "📦"
            }
        }

        var robotState: RobotState {
            switch self {
            case .understanding, .thinking, .solving, .finishing: return .thinking
            case .looking: return .searching
            case .reading: return .reading
            case .writing, .fixing: return .editing
            case .running, .testing: return .running
            }
        }

        /// Kısa durum satırındaki fiillerden aşamayı bul (İngilizce ve Türkçe arayüz).
        static func match(_ line: String) -> WorkPhase? {
            let rules: [(WorkPhase, String)] = [
                (.testing, #"\btest"#),
                (.running, #"\b(ran|run|running|executing|execute|command|terminal|install|compil)|komut|çalıştır"#),
                (.fixing, #"\b(fix|debug|repair|patch)|düzelt|hata"#),
                (.writing, #"\b(writ|edit|creat|draft|updat|implement|add|generat|compos|refactor)|yaz|oluştur|ekle"#),
                (.reading, #"\b(read|review|analy|inspect|check|open|view|examin|load)|oku|incele"#),
                (.looking, #"\b(search|look|find|brows|fetch|explor|scan|gather)|ara[ıy]|bak"#),
                (.finishing, #"\b(publish|deliver|upload|final|wrap|summar|send|finish|complet)|yayınla|bitir|gönder"#),
                (.thinking, #"\b(think|reason|ponder)|düşün"#),
                (.solving, #"\b(plan|map|figur|consider|weigh|work|solv|design|decid)|çöz"#),
            ]
            for (phase, pattern) in rules where line.range(of: pattern, options: .regularExpression) != nil {
                return phase
            }
            return nil
        }
    }

    private struct Found {
        var stop: CGRect?
        var send: CGRect?
        var approve = false
        var texts: [(String, CGRect)] = []
        var buttonLabels: [String] = []
        var composerTop: CGFloat? { [stop, send].compactMap { $0?.minY }.min() }
    }

    private let queue = DispatchQueue(label: "telepaith.appwatcher")
    private var timer: Timer?
    private var busy = false
    private var states: [pid_t: AppState] = [:]   // yalnızca queue içinde

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// macOS'un "Erişilebilirlik izni ver" penceresini açar.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Eski (başka imzalı sürüme ait) izin kaydını silip yeniden ister.
    /// Ayarlar'da açık görünüp çalışmayan izni düzeltir.
    static func resetAndRequestTrust() {
        if let bundleID = Bundle.main.bundleIdentifier {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            try? process.run()
            process.waitUntilExit()
        }
        requestTrust()
        openAccessibilitySettings()
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static var debugFile: URL { AppInfo.supportDir.appendingPathComponent("watch-debug.txt") }

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.8, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        queue.async { self.states = [:] }
        onStatus?([:])
    }

    // Ana iş parçacığında: hangi uygulamalar açık?
    private func tick() {
        guard !busy, AppWatcher.isTrusted else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let targets: [Target] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ownPID, app.activationPolicy == .regular,
                  let source = AppMatcher.source(for: app) else { return nil }
            return Target(pid: app.processIdentifier, source: source, name: app.localizedName ?? source)
        }
        busy = true
        queue.async {
            let status = self.scan(targets)
            DispatchQueue.main.async {
                self.busy = false
                self.onStatus?(status)
            }
        }
    }

    // MARK: - Tarama (arka planda)

    private func scan(_ targets: [Target]) -> [String: String] {
        let now = ProcessInfo.processInfo.systemUptime
        let alive = Set(targets.map { $0.pid })
        for pid in states.keys where !alive.contains(pid) {
            if let st = states[pid], st.generating { emit(stop: pid, state: st) }
            states.removeValue(forKey: pid)
        }

        var status: [String: String] = [:]
        for target in targets {
            var st = states[target.pid] ?? AppState(source: target.source, name: target.name)
            let app = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            if !st.enabledElectronAX {
                // Electron uygulamaları (Claude) erişilebilirlik ağacını ancak istenince kurar
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                st.enabledElectronAX = true
            }

            var found = Found()
            for window in AppWatcher.windows(of: app) {
                guard let windowFrame = AppWatcher.frame(window), windowFrame.height > 100 else { continue }
                // Sadece pencerenin alt %50'si: yazı kutusu, son mesaj, izin düğmeleri burada.
                let zone = CGRect(x: windowFrame.minX, y: windowFrame.minY + windowFrame.height * 0.5,
                                  width: windowFrame.width, height: windowFrame.height * 0.5)
                walk(window, zone: zone, budget: 3000, found: &found)
            }
            // Alt kısımda yazı kutusu bulunamadıysa ara sıra tüm pencereye bak
            if found.stop == nil && found.send == nil && now - st.lastFullScan > 6 {
                st.lastFullScan = now
                for window in AppWatcher.windows(of: app) {
                    walk(window, zone: nil, budget: 8000, found: &found)
                }
                if found.stop == nil && found.send == nil && now - st.lastDebugDump > 60 {
                    st.lastDebugDump = now
                    dumpDebug(target: target, found: found)
                }
            }

            if found.stop != nil || found.send != nil { st.sawComposer = true }
            let generatingNow = found.stop != nil
            update(&st, pid: target.pid, found: found, generatingNow: generatingNow, now: now)

            if !st.sawComposer {
                status[target.name] = loc("yazı kutusu bulunamadı", "can't find the input box")
            } else if st.approving {
                status[target.name] = loc("onay bekliyor", "waiting for approval")
            } else if st.generating {
                status[target.name] = loc("çalışıyor", "working")
            } else {
                status[target.name] = loc("izleniyor", "watching")
            }
            states[target.pid] = st
        }
        return status
    }

    private func update(_ st: inout AppState, pid: pid_t, found: Found, generatingNow: Bool, now: TimeInterval) {
        let session = "app-\(pid)"
        if generatingNow {
            st.quietPolls = 0
            if !st.generating {
                st.generating = true
                st.lastHeartbeat = now
                st.startedAt = now
                st.phase = .understanding
                st.lastPhaseAt = now
                let p = WorkPhase.understanding
                emitMain(AgentEvent(source: st.source, sessionID: session, kind: .prompt, state: p.robotState,
                                    text: p.phrase, emoji: p.emoji))
            } else if now - st.lastHeartbeat > 20 {
                st.lastHeartbeat = now
                emitMain(AgentEvent(source: st.source, sessionID: session, kind: .heartbeat))
            }
            // Ne yaptığını kısa Türkçe bir aşamayla söyle (bakıyor, inceliyor, yazıyor, düzeltiyor…)
            if !found.approve {
                let p = AppWatcher.phase(found, elapsed: now - st.startedAt)
                if p != st.phase && now - st.lastPhaseAt > 1.5 {
                    st.phase = p
                    st.lastPhaseAt = now
                    emitMain(AgentEvent(source: st.source, sessionID: session, kind: .status, state: p.robotState,
                                        text: p.phrase, emoji: p.emoji))
                }
            }
        } else if st.generating {
            st.quietPolls += 1
            if st.quietPolls >= 2 {   // ~1.6 sn boyunca "Durdur" yoksa bitti say
                st.generating = false
                st.approving = false
                emit(stop: pid, state: st)
            }
        }

        if found.approve && !st.approving {
            st.approving = true
            var e = AgentEvent(source: st.source, sessionID: session, kind: .waiting, state: .waiting,
                               text: loc("Onayını bekliyor", "Needs your approval"), emoji: "✋")
            e.quietIfFrontmostPID = pid
            emitMain(e)
        } else if !found.approve && st.approving {
            st.approving = false
            if st.generating {
                emitMain(AgentEvent(source: st.source, sessionID: session, kind: .toolDone))
            }
        }
    }

    /// Ekrandaki kısa durum satırlarından (ör. "Searching the web", "Ran 3 commands") ne yaptığını çıkarır.
    /// Uzun metinler (cevabın kendisi) ve ekran okuyucu ipuçları yok sayılır. Hiçbiri tutmazsa geçen süreye
    /// göre ilerler: anlıyor → düşünüyor → çözüyor.
    private static func phase(_ found: Found, elapsed: TimeInterval) -> WorkPhase {
        if let top = found.composerTop {
            let hints = ["press tab", "escape", "focus", "keyboard", "screen reader", "available to open",
                         "double-tap", "shortcut", "can make mistakes", "reply", "message claude", "ask anything"]
            let lines = found.texts
                .filter { $0.1.maxY <= top - 2 && $0.1.maxY >= top - 500 }
                .sorted { $0.1.maxY > $1.1.maxY }   // en alttaki (en yeni) önce
                .map { $0.0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { text in text.count >= 4 && text.count <= 60 && !hints.contains { text.contains($0) } }
                .prefix(8)
            for line in lines {
                if let p = WorkPhase.match(line) { return p }
            }
        }
        if elapsed < 8 { return .understanding }
        if elapsed < 30 { return .thinking }
        return .solving
    }

    private func emit(stop pid: pid_t, state st: AppState) {
        var e = AgentEvent(source: st.source, sessionID: "app-\(pid)", kind: .stop, state: .done)
        e.quietIfFrontmostPID = pid
        emitMain(e)
    }

    private func emitMain(_ event: AgentEvent) {
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    /// Ağacı gezer; bölge verilmişse dışında kalan dalları atlar (ekran dışı eski mesajlar vb.).
    private func walk(_ root: AXUIElement, zone: CGRect?, budget: Int, found: inout Found) {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while visited < budget, let item = stack.popLast() {
            visited += 1
            let element = item.0
            let depth = item.1
            let role = AppWatcher.string(element, kAXRoleAttribute) ?? ""
            let elementFrame = AppWatcher.frame(element)
            if let zone = zone, let f = elementFrame, f.width > 0, f.height > 0, !f.intersects(zone) { continue }

            if role == kAXButtonRole {
                let label = AppWatcher.label(of: element)
                if !label.isEmpty && found.buttonLabels.count < 120 { found.buttonLabels.append(label) }
                switch AppWatcher.classify(label) {
                case .some(.stop): found.stop = elementFrame ?? found.stop ?? .zero
                case .some(.send): if found.send == nil { found.send = elementFrame ?? .zero }
                case .some(.approve): found.approve = true
                case .none: break
                }
                continue
            }
            if role == kAXStaticTextRole {
                if let f = elementFrame,
                   let text = AppWatcher.string(element, kAXValueAttribute) ?? AppWatcher.string(element, kAXTitleAttribute),
                   !text.isEmpty {
                    found.texts.append((text, f))
                }
                continue
            }
            if role == kAXImageRole { continue }
            guard depth < 70, let children = AppWatcher.children(element) else { continue }
            for child in children { stack.append((child, depth + 1)) }
        }
    }

    /// Algılama tutmazsa düğme adlarını dosyaya yazar (düzeltmek için).
    private func dumpDebug(target: Target, found: Found) {
        let lines = ["\(Date()) \(target.name) (pid \(target.pid))",
                     "Düğmeler / buttons: " + found.buttonLabels.prefix(120).joined(separator: " | "),
                     ""]
        let text = lines.joined(separator: "\n") + "\n"
        let url = AppWatcher.debugFile
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // MARK: - AX yardımcıları

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        return error == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement]? {
        value(element, kAXChildrenAttribute) as? [AXUIElement]
    }

    /// Ekran koordinatında çerçeve (sol-üst köken, AX'in kullandığı)
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let positionValue = value(element, kAXPositionAttribute),
              let sizeValue = value(element, kAXSizeAttribute) else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &point),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }
        return CGRect(origin: point, size: size)
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        if let main = value(app, kAXMainWindowAttribute) {
            return [main as! AXUIElement]
        }
        if let focused = value(app, kAXFocusedWindowAttribute) {
            return [focused as! AXUIElement]
        }
        return Array((value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).prefix(2))
    }

    private static func label(of element: AXUIElement) -> String {
        [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXIdentifier", "AXDOMIdentifier"]
            .compactMap { string(element, $0) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .lowercased()
    }

    private static func classify(_ label: String) -> ButtonKind? {
        if label.isEmpty { return nil }
        if label.range(of: #"\bstop\b|stop[-_ ]?(response|generating|streaming)|durdur|yanıtı kes|cancel response"#,
                       options: .regularExpression) != nil {
            return .stop
        }
        if label.range(of: #"^(allow|always allow|approve)\b|\ballow once\b|\ballow for\b|izin ver|onayla"#,
                       options: .regularExpression) != nil {
            return .approve
        }
        if label.range(of: #"\bsend\b|gönder|submit"#, options: .regularExpression) != nil {
            return .send
        }
        return nil
    }
}
