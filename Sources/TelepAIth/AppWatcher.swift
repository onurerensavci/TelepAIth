import AppKit
import ApplicationServices

/// Claude, ChatGPT ve Codex masaüstü uygulamalarını Erişilebilirlik API'siyle izler.
/// Bu uygulamaların hook'u yok; pencerenin alt kısmında "Durdur" düğmesi görünüyorsa AI çalışıyordur,
/// "İzin ver" düğmesi varsa onay bekliyordur, "Durdur" kaybolunca iş bitmiştir.
/// Çalışırken yazı kutusunun hemen üstündeki son satırı (ör. "Mapping the dot grid…") okuyup söyler.
final class AppWatcher {
    var onEvent: ((AgentEvent) -> Void)?
    /// Bir AI uygulaması açıldı (izleme başladıktan sonra): kaynak, uygulama adı
    var onAppOpened: ((String, String) -> Void)?
    private var knownPIDs: Set<pid_t> = []
    private var firstTick = true
    /// Menü için: uygulama adı → ne görüyorum
    var onStatus: (([String: String]) -> Void)?
    /// Teşhis paneli için ayrıntılar
    var onDiagnostics: (([AppDiagnostics]) -> Void)?

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
        var lastTail: String?         // en alttaki mesaj metni (akış algılama için)
        var growthPolls = 0
        var lastGrowthAt: TimeInterval = 0
        var lastActiveAt: TimeInterval = 0   // en son "Durdur" görüldüğü ya da metnin aktığı an
        var chatKey: String?          // hangi sohbet açık (sayfa adresi ya da pencere başlığı)
        var chatCounter = 0
        func session(_ pid: pid_t) -> String { "app-\(pid)-\(chatCounter)" }
        var lastFullScan: TimeInterval = 0
        var lastDebugDump: TimeInterval = 0
        var lastAXRequest: TimeInterval = -100
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
        var urls: [String] = []
        var composer: CGRect?          // en alttaki yazılabilir metin alanı (yazı kutusu)
        var roles: [String: Int] = [:]
        var sampleTexts: [String] = []
        var windowsInfo = ""
        var composerTop: CGFloat? { [stop, send, composer].compactMap { $0?.minY }.min() }
    }

    private let queue = DispatchQueue(label: "telepaith.appwatcher")
    private var timer: Timer?
    private var busy = false
    private var states: [pid_t: AppState] = [:]   // yalnızca queue içinde

    // Değişiklik bildirimleri (AXObserver): ekranda bir şey değişince hemen tara, yoklamayı seyrekleştir.
    private var observers: [pid_t: AXObserver] = [:]   // yalnızca ana iş parçacığında
    private var kickPending = false
    private var rescanWhenDone = false
    private var lastScanAt: TimeInterval = 0
    private var anyGenerating = false
    /// Teşhis için: kaç uygulamayı anlık izleyebiliyoruz
    private(set) var observedCount = 0

    private static let axCallback: AXObserverCallback = { _, _, _, refcon in
        guard let refcon = refcon else { return }
        Unmanaged<AppWatcher>.fromOpaque(refcon).takeUnretainedValue().kick()
    }

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
        let t = Timer(timeInterval: 0.4, repeats: true) { [weak self] _ in self?.tick(force: false) }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        for pid in Array(observers.keys) { unobserve(pid) }
        knownPIDs = []
        firstTick = true
        queue.async { self.states = [:] }
        onStatus?([:])
    }

    /// Ekranda bir şey değişti: kısa bir beklemeden sonra tara (art arda gelen bildirimleri birleştirir).
    fileprivate func kick() {
        guard timer != nil, !kickPending else { return }
        kickPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self = self else { return }
            self.kickPending = false
            self.tick(force: true)
        }
    }

    // Ana iş parçacığında: hangi uygulamalar açık?
    private func tick(force: Bool) {
        guard AppWatcher.isTrusted else { return }
        if busy {
            if force { rescanWhenDone = true }
            return
        }
        let now = ProcessInfo.processInfo.systemUptime
        // Bildirimler çalışıyorsa boştayken 2 sn'de bir bakmak yeter; çalışırken ya da bildirim yoksa 0,8 sn
        let interval: TimeInterval = (anyGenerating || observers.isEmpty) ? 0.8 : 2.0
        if force {
            if now - lastScanAt < 0.3 { return }
        } else if now - lastScanAt < interval {
            return
        }
        lastScanAt = now
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let targets: [Target] = NSWorkspace.shared.runningApplications.compactMap { app in
            guard app.processIdentifier != ownPID, app.activationPolicy == .regular,
                  let source = AppMatcher.source(for: app) else { return nil }
            return Target(pid: app.processIdentifier, source: source, name: app.localizedName ?? source)
        }
        let alive = Set(targets.map { $0.pid })
        // Yeni açılan AI uygulamaları (ilk taramada zaten açık olanlar sayılmaz)
        for target in targets where !knownPIDs.contains(target.pid) && !firstTick {
            onAppOpened?(target.source, target.name)
        }
        knownPIDs = alive
        firstTick = false
        for pid in Array(observers.keys) where !alive.contains(pid) { unobserve(pid) }
        for target in targets { observe(target.pid) }
        busy = true
        queue.async {
            let (status, diagnostics) = self.scan(targets)
            let generating = self.states.values.contains { $0.generating }
            DispatchQueue.main.async {
                self.busy = false
                self.anyGenerating = generating
                self.onStatus?(status)
                self.onDiagnostics?(diagnostics)
                if self.rescanWhenDone {
                    self.rescanWhenDone = false
                    self.kick()
                }
            }
        }
    }

    private func observe(_ pid: pid_t) {
        guard observers[pid] == nil else { return }
        var created: AXObserver?
        guard AXObserverCreate(pid, AppWatcher.axCallback, &created) == .success, let observer = created else { return }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let names = [kAXValueChangedNotification, kAXCreatedNotification, kAXUIElementDestroyedNotification,
                     kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification,
                     kAXTitleChangedNotification, "AXLayoutChanged"]
        var added = 0
        for name in names where AXObserverAddNotification(observer, app, name as CFString, refcon) == .success {
            added += 1
        }
        guard added > 0 else { return }   // uygulama bildirim göndermiyor: yoklamaya devam
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observers[pid] = observer
        observedCount = observers.count
    }

    private func unobserve(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        observedCount = observers.count
    }

    // MARK: - Tarama (arka planda)

    private func scan(_ targets: [Target]) -> ([String: String], [AppDiagnostics]) {
        let now = ProcessInfo.processInfo.systemUptime
        let alive = Set(targets.map { $0.pid })
        for pid in states.keys where !alive.contains(pid) {
            if let st = states[pid], st.generating { emit(stop: pid, state: st) }
            states.removeValue(forKey: pid)
        }

        var status: [String: String] = [:]
        var diagnostics: [AppDiagnostics] = []
        for target in targets {
            var st = states[target.pid] ?? AppState(source: target.source, name: target.name)
            let app = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(app, 0.5)
            // Electron uygulamaları (Claude) erişilebilirlik ağacını ancak istenince kurar. Uygulama yeni açıldıysa
            // ilk istek boşa gidebilir: yazı kutusu görülene kadar 3 sn'de bir, sonra 30 sn'de bir yeniden iste.
            if now - st.lastAXRequest > (st.sawComposer ? 30 : 3) {
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                st.lastAXRequest = now
            }

            var found = Found()
            var windowTitle: String?
            let windows = AppWatcher.windows(of: app)
            found.windowsInfo = windows.compactMap { w -> String? in
                guard let f = AppWatcher.frame(w) else { return nil }
                return "\(AppWatcher.string(w, kAXTitleAttribute) ?? "?") \(Int(f.width))x\(Int(f.height))"
            }.joined(separator: ", ")
            for window in windows {
                if windowTitle == nil { windowTitle = AppWatcher.string(window, kAXTitleAttribute) }
                guard let windowFrame = AppWatcher.frame(window), windowFrame.height > 100 else { continue }
                // Sadece pencerenin alt %50'si: yazı kutusu, son mesaj, izin düğmeleri burada.
                let zone = CGRect(x: windowFrame.minX, y: windowFrame.minY + windowFrame.height * 0.5,
                                  width: windowFrame.width, height: windowFrame.height * 0.5)
                walk(window, zone: zone, budget: 3000, found: &found)
            }
            // Alt kısımda yazı kutusu bulunamadıysa ara sıra tüm pencereye bak
            if found.stop == nil && found.send == nil && found.composer == nil && now - st.lastFullScan > 6 {
                st.lastFullScan = now
                for window in AppWatcher.windows(of: app) {
                    walk(window, zone: nil, budget: 8000, found: &found)
                }
                if found.stop == nil && found.send == nil && found.composer == nil && now - st.lastDebugDump > 60 {
                    st.lastDebugDump = now
                    dumpDebug(target: target, found: found)
                }
            }

            // Yazı kutusu ağaçta tanınmadıysa: uygulamanın odaktaki metin alanına bak (ChatGPT gibi yerli uygulamalar)
            if found.composer == nil, let focused = AppWatcher.value(app, kAXFocusedUIElementAttribute) {
                let element = focused as! AXUIElement
                let role = AppWatcher.string(element, kAXRoleAttribute) ?? ""
                if role == kAXTextAreaRole || role == kAXTextFieldRole || role == "AXComboBox",
                   let f = AppWatcher.frame(element), f.width > 80 {
                    found.composer = f
                }
            }

            if found.stop != nil || found.send != nil || found.composer != nil { st.sawComposer = true }

            // Başka sohbete geçildi mi? Geçildiyse eski sohbet için "bitti" deme, tıklanan sohbete geç.
            let chatKey = found.urls.first(where: { $0.contains("/chat") }) ?? found.urls.last ?? windowTitle
            if let key = chatKey, !key.isEmpty {
                if let old = st.chatKey, old != key {
                    if st.generating || st.approving {
                        emitMain(AgentEvent(source: st.source, sessionID: st.session(target.pid), kind: .sessionEnd))
                    }
                    st.generating = false
                    st.approving = false
                    st.quietPolls = 0
                    st.phase = nil
                    st.chatCounter += 1
                    var text = loc("Bu sohbete geçtim", "Switched to this chat")
                    if let title = windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty, title.lowercased() != target.name.lowercased() {
                        text += ": " + clip(title, 40)
                    }
                    emitMain(AgentEvent(source: st.source, sessionID: st.session(target.pid), kind: .say, text: text, emoji: "💬"))
                }
                st.chatKey = key
            }

            // İkinci yol: son mesaj büyümeye devam ediyorsa cevap akıyordur (düğme adı bilinmese de çalışır)
            // Zamana bağlı: tarama sıklığı değişse de (bildirimle anlık tarama) aynı sonucu verir
            let tail = AppWatcher.tailText(found)
            if let t = tail, let prev = st.lastTail, t != prev {
                if t.count > prev.count && t.hasPrefix(String(prev.prefix(12))) {
                    st.growthPolls = now - st.lastGrowthAt < 3 ? st.growthPolls + 1 : 1
                    st.lastGrowthAt = now
                } else {
                    st.growthPolls = 0      // başka bir mesaj ya da kaydırma
                }
            }
            st.lastTail = tail
            let streaming = st.growthPolls >= 2 && now - st.lastGrowthAt < 2.5

            let generatingNow = found.stop != nil || streaming
            update(&st, pid: target.pid, found: found, generatingNow: generatingNow, streaming: streaming, now: now)

            if !st.sawComposer {
                status[target.name] = loc("yazı kutusu bulunamadı", "can't find the input box")
            } else if st.approving {
                status[target.name] = loc("onay bekliyor", "waiting for approval")
            } else if st.generating {
                status[target.name] = loc("çalışıyor", "working")
            } else {
                status[target.name] = loc("izleniyor", "watching")
            }
            diagnostics.append(AppDiagnostics(
                name: target.name,
                windows: found.windowsInfo.isEmpty ? "—" : found.windowsInfo,
                composer: found.composer != nil,
                stopButton: found.stop != nil,
                sendButton: found.send != nil,
                approveButton: found.approve,
                streaming: streaming,
                generating: st.generating,
                phase: st.phase?.phrase ?? "—",
                chat: st.chatKey.map { clip($0, 70) } ?? "—",
                buttons: Array(found.buttonLabels.prefix(25)),
                roles: found.roles.sorted { $0.value > $1.value }.prefix(10).map { "\($0.key)=\($0.value)" }.joined(separator: ", "),
                texts: Array(found.sampleTexts.prefix(6))))
            states[target.pid] = st
        }
        return (status, diagnostics)
    }

    private func update(_ st: inout AppState, pid: pid_t, found: Found, generatingNow: Bool, streaming: Bool, now: TimeInterval) {
        let session = st.session(pid)
        if generatingNow {
            st.quietPolls = 0
            st.lastActiveAt = now
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
                let p = AppWatcher.phase(found, elapsed: now - st.startedAt, streaming: streaming)
                if p != st.phase && now - st.lastPhaseAt > 1.5 {
                    st.phase = p
                    st.lastPhaseAt = now
                    emitMain(AgentEvent(source: st.source, sessionID: session, kind: .status, state: p.robotState,
                                        text: p.phrase, emoji: p.emoji))
                }
            }
        } else if st.generating {
            st.quietPolls += 1
            if st.quietPolls >= 2 && now - st.lastActiveAt >= 1.6 {   // 1,6 sn boyunca "Durdur" yoksa (ve metin akmıyorsa) bitti say
                st.generating = false
                st.approving = false
                if now - st.startedAt >= 4 {
                    emit(stop: pid, state: st)
                } else {
                    // Çok kısa sürdüyse (kaydırma vb. yanlış alarm) sessizce kapat
                    emitMain(AgentEvent(source: st.source, sessionID: st.session(pid), kind: .sessionEnd))
                }
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
    private static func phase(_ found: Found, elapsed: TimeInterval, streaming: Bool) -> WorkPhase {
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
        if streaming { return .writing }
        if elapsed < 8 { return .understanding }
        if elapsed < 30 { return .thinking }
        return .solving
    }

    /// En alttaki (en yeni) mesaj metni: yazı kutusunun üstünde, ipucu olmayan, en alttaki metin.
    private static func tailText(_ found: Found) -> String? {
        let limit = found.composerTop ?? .greatestFiniteMagnitude
        let hints = ["press tab", "escape", "focus", "keyboard", "screen reader", "available to open",
                     "can make mistakes", "reply", "message claude", "ask anything"]
        let candidates = found.texts.filter { item in
            let low = item.0.lowercased()
            // Kısa arayüz yazılarını (model adı, düğmeler) değil, mesaj gövdesini izle
            return item.1.maxY <= limit - 2 && item.0.count >= 25 && !hints.contains { low.contains($0) }
        }
        return candidates.max(by: { $0.1.maxY < $1.1.maxY })?.0
    }

    private func emit(stop pid: pid_t, state st: AppState) {
        var e = AgentEvent(source: st.source, sessionID: st.session(pid), kind: .stop, state: .done)
        e.quietIfFrontmostPID = pid
        emitMain(e)
    }

    private func emitMain(_ event: AgentEvent) {
        var e = event
        // Oturum adı "app-<pid>-<n>": balona tıklayınca bu uygulamayı öne getirmek için
        if e.appPID == nil, e.sessionID.hasPrefix("app-") {
            let parts = e.sessionID.split(separator: "-")
            if parts.count >= 2, let pid = Int32(parts[1]) { e.appPID = pid }
        }
        DispatchQueue.main.async { self.onEvent?(e) }
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
            found.roles[role, default: 0] += 1

            // Metin alanları: yazılabilir olan yazı kutusudur, değilse mesaj metnidir
            if role == kAXTextAreaRole || role == kAXTextFieldRole {
                var settable: DarwinBoolean = false
                AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
                // Yazılabilir ya da "Bir şey sor…" gibi yer tutucusu olan alan yazı kutusudur
                let placeholder = AppWatcher.string(element, "AXPlaceholderValue") ?? ""
                if (settable.boolValue || !placeholder.isEmpty), let f = elementFrame, f.width > 80 {
                    if found.composer == nil || f.maxY > found.composer!.maxY { found.composer = f }
                } else if let f = elementFrame, let text = AppWatcher.string(element, kAXValueAttribute), !text.isEmpty {
                    found.texts.append((text, f))
                    if found.sampleTexts.count < 12 { found.sampleTexts.append("[\(role)] " + clip(text, 60)) }
                }
                continue
            }

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
                    if found.sampleTexts.count < 12 { found.sampleTexts.append("[\(role)] " + clip(text, 60)) }
                }
                continue
            }
            if role == kAXImageRole { continue }
            if role == "AXWebArea", let url = AppWatcher.value(element, "AXURL") as? URL {
                found.urls.append(url.absoluteString)
            }
            guard depth < 70, let children = AppWatcher.children(element) else { continue }
            for child in children { stack.append((child, depth + 1)) }
        }
    }

    /// Algılama tutmazsa düğme adlarını dosyaya yazar (düzeltmek için).
    private func dumpDebug(target: Target, found: Found) {
        let roles = found.roles.sorted { $0.value > $1.value }.prefix(20).map { "\($0.key)=\($0.value)" }
        let lines = ["\(Date()) \(target.name) (pid \(target.pid))",
                     "Pencereler / windows: \(found.windowsInfo)",
                     "Roller / roles: " + roles.joined(separator: ", "),
                     "Düğmeler / buttons: " + found.buttonLabels.prefix(120).joined(separator: " | "),
                     "Metinler / texts: " + found.sampleTexts.joined(separator: " | "),
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

    /// Uygulamanın en büyük görünen 2 penceresi (küçük hızlı-sohbet panellerini atlar).
    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        var all: [AXUIElement] = []
        if let main = value(app, kAXMainWindowAttribute) { all.append(main as! AXUIElement) }
        if let focused = value(app, kAXFocusedWindowAttribute) { all.append(focused as! AXUIElement) }
        all += (value(app, kAXWindowsAttribute) as? [AXUIElement] ?? [])
        var unique: [(AXUIElement, CGFloat)] = []
        for w in all where !unique.contains(where: { CFEqual($0.0, w) }) {
            guard let f = frame(w), f.width >= 300, f.height >= 300 else { continue }
            if (value(w, kAXMinimizedAttribute) as? Bool) == true { continue }
            unique.append((w, f.width * f.height))
        }
        return unique.sorted { $0.1 > $1.1 }.prefix(2).map { $0.0 }
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
