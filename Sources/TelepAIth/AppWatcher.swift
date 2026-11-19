import AppKit
import ApplicationServices

/// Claude, ChatGPT ve Codex masaüstü uygulamalarını Erişilebilirlik API'siyle izler.
/// Bu uygulamaların hook'u yok; ekrandaki "Durdur" düğmesi görünüyorsa AI çalışıyordur,
/// "İzin ver" düğmesi varsa onay bekliyordur, "Durdur" kaybolunca iş bitmiştir.
final class AppWatcher {
    var onEvent: ((AgentEvent) -> Void)?

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
        var quietPolls = 0            // "Durdur" kaç taramadır yok (titremeyi önlemek için)
        var composer: AXUIElement?    // "Durdur"/"Gönder" düğmesinin bulunduğu kap
        var lastFullScan: TimeInterval = 0
        var lastHeartbeat: TimeInterval = 0
        var enabledElectronAX = false
    }

    private enum ButtonKind {
        case stop, send, approve
    }

    private struct Found {
        var stop: AXUIElement?
        var send: AXUIElement?
        var approve = false
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

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

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
            self.scan(targets)
            DispatchQueue.main.async { self.busy = false }
        }
    }

    // MARK: - Tarama (arka planda)

    private func scan(_ targets: [Target]) {
        let now = ProcessInfo.processInfo.systemUptime
        let alive = Set(targets.map { $0.pid })
        for pid in states.keys where !alive.contains(pid) {
            if let st = states[pid], st.generating { emit(stop: pid, state: st) }
            states.removeValue(forKey: pid)
        }

        for target in targets {
            var st = states[target.pid] ?? AppState(source: target.source, name: target.name)
            let app = AXUIElementCreateApplication(target.pid)
            AXUIElementSetMessagingTimeout(app, 0.4)
            if !st.enabledElectronAX {
                // Electron uygulamaları (Claude) erişilebilirlik ağacını ancak istenince kurar
                AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                st.enabledElectronAX = true
            }

            var found = Found()
            var scannedComposer = false
            if let composer = st.composer, AppWatcher.isAlive(composer) {
                walk(composer, budget: 400, found: &found)
                scannedComposer = true
            } else {
                st.composer = nil
            }

            // Tam tarama: kap bilinmiyorsa sık, biliniyorsa onay düğmeleri için ara sıra
            let fullInterval: TimeInterval = st.composer == nil ? 2.4 : 3.2
            if !scannedComposer || now - st.lastFullScan > fullInterval {
                st.lastFullScan = now
                for window in AppWatcher.windows(of: app) {
                    walk(window, budget: 6000, found: &found)
                }
                if let button = found.stop ?? found.send, let container = AppWatcher.container(of: button) {
                    st.composer = container
                }
            }

            let generatingNow = found.stop != nil
            update(&st, pid: target.pid, generatingNow: generatingNow, approvingNow: found.approve, now: now)
            states[target.pid] = st
        }
    }

    private func update(_ st: inout AppState, pid: pid_t, generatingNow: Bool, approvingNow: Bool, now: TimeInterval) {
        let session = "app-\(pid)"
        if generatingNow {
            st.quietPolls = 0
            if !st.generating {
                st.generating = true
                st.lastHeartbeat = now
                emitMain(AgentEvent(source: st.source, sessionID: session, kind: .prompt, state: .thinking,
                                    text: loc("Çalışıyor…", "Working on it…"), project: st.name, emoji: "🔮"))
            } else if now - st.lastHeartbeat > 20 {
                st.lastHeartbeat = now
                emitMain(AgentEvent(source: st.source, sessionID: session, kind: .heartbeat))
            }
        } else if st.generating {
            st.quietPolls += 1
            if st.quietPolls >= 2 {   // ~1.6 sn boyunca "Durdur" yoksa bitti say
                st.generating = false
                st.approving = false
                emit(stop: pid, state: st)
            }
        }

        if approvingNow && !st.approving {
            st.approving = true
            var e = AgentEvent(source: st.source, sessionID: session, kind: .waiting, state: .waiting,
                               text: loc("Onayını bekliyor", "Needs your approval"), project: st.name, emoji: "✋")
            e.quietIfFrontmostPID = pid
            emitMain(e)
        } else if !approvingNow && st.approving {
            st.approving = false
            if st.generating {
                emitMain(AgentEvent(source: st.source, sessionID: session, kind: .toolDone))
            }
        }
    }

    private func emit(stop pid: pid_t, state st: AppState) {
        var e = AgentEvent(source: st.source, sessionID: "app-\(pid)", kind: .stop, state: .done, project: st.name)
        e.quietIfFrontmostPID = pid
        emitMain(e)
    }

    private func emitMain(_ event: AgentEvent) {
        DispatchQueue.main.async { self.onEvent?(event) }
    }

    /// Ağacı sondan başa (ekranın altındaki yazı kutusu genelde en sonda) gezer.
    private func walk(_ root: AXUIElement, budget: Int, found: inout Found) {
        var stack: [(AXUIElement, Int)] = [(root, 0)]
        var visited = 0
        while visited < budget, let item = stack.popLast() {
            visited += 1
            let element = item.0
            let depth = item.1
            let role = AppWatcher.string(element, kAXRoleAttribute) ?? ""
            if role == kAXButtonRole {
                switch AppWatcher.classify(element) {
                case .some(.stop): found.stop = element
                case .some(.send): if found.send == nil { found.send = element }
                case .some(.approve): found.approve = true
                case .none: break
                }
                continue
            }
            if role == kAXStaticTextRole || role == kAXImageRole { continue }
            guard depth < 60, let children = AppWatcher.children(element) else { continue }
            for child in children { stack.append((child, depth + 1)) }
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

    private static func isAlive(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success
    }

    private static func windows(of app: AXUIElement) -> [AXUIElement] {
        if let main = value(app, kAXMainWindowAttribute) {
            return [main as! AXUIElement]
        }
        return Array((value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).prefix(2))
    }

    /// Düğmenin iki üst kabı: "Durdur" ile "Gönder" yer değiştirse de aynı kalır.
    private static func container(of element: AXUIElement) -> AXUIElement? {
        guard let parent = value(element, kAXParentAttribute) else { return nil }
        let p = parent as! AXUIElement
        if let grand = value(p, kAXParentAttribute) { return (grand as! AXUIElement) }
        return p
    }

    private static func classify(_ element: AXUIElement) -> ButtonKind? {
        let parts = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute, "AXIdentifier"]
            .compactMap { string(element, $0) }
        let label = parts.joined(separator: " ").lowercased()
        if label.isEmpty { return nil }
        if label.range(of: #"\bstop\b|\bstop[a-z]*(response|generating|streaming)|durdur"#, options: .regularExpression) != nil {
            return .stop
        }
        if label.range(of: #"^(allow|always allow|approve)\b|\ballow once\b|izin ver|onayla"#, options: .regularExpression) != nil {
            return .approve
        }
        if label.range(of: #"\bsend\b|gönder"#, options: .regularExpression) != nil {
            return .send
        }
        return nil
    }
}
