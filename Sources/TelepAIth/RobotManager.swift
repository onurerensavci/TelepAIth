import AppKit
import QuartzCore

/// Uygulama → AI eşlemesi: öndeki uygulama Claude ise turuncu, Codex/ChatGPT ise mavi robot.
enum AppMatcher {
    static func source(for app: NSRunningApplication) -> String? {
        let bundleID = (app.bundleIdentifier ?? "").lowercased()
        let name = (app.localizedName ?? "").lowercased()
        if let custom = Themes.shared.appSource(bundleID: bundleID) { return custom }
        if bundleID.hasPrefix("com.anthropic.") || name == "claude" { return "claude" }
        if bundleID.hasPrefix("com.openai.") || name.contains("codex") || name.contains("chatgpt") { return "gpt" }
        if bundleID.contains("gemini") || name.contains("gemini") { return "gemini" }
        return nil
    }
}

/// AI başına durum modeli tutar, ekrandaki tek robotun hangisini göstereceğine karar verir.
final class RobotManager {
    private var models: [String: RobotModel] = [:]
    private var order: [String] = []
    private var avatar: RobotAvatar?
    private var window: AvatarWindowController?
    private var pinnedSource: String?
    private var dockPID: pid_t?            // robotun peşinden gittiği AI uygulaması
    private var lastDockCheck = CACurrentMediaTime()
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()
    private let watcher = AppWatcher()
    /// Menü için: izlenen masaüstü uygulamalarında ne görüyorum
    private(set) var watcherStatus: [String: String] = [:]
    private var lastTrustCheck = CACurrentMediaTime()
    private var wasTrusted = AppWatcher.isTrusted
    private var lastUpdateAnnounce: CFTimeInterval = 0

    var onChange: (() -> Void)?

    var visible: Bool = Preferences.robotsVisible {
        didSet {
            Preferences.robotsVisible = visible
            if visible { window?.show() } else { window?.hide() }
        }
    }

    /// Menüde listelenen tüm AI'lar
    var allModels: [RobotModel] {
        order.compactMap { models[$0] }
    }

    func start() {
        let sources = Preferences.knownSources.isEmpty ? ["claude"] : Preferences.knownSources
        for source in sources { model(for: source) }

        let first = models[sources[0]] ?? model(for: "claude")
        let avatar = RobotAvatar(model: first)
        avatar.restorePosition()
        avatar.onUserMoved = { [weak self] in self?.dockPID = nil }
        self.avatar = avatar

        let window = AvatarWindowController(avatar: avatar)
        window.onHide = { [weak self] in
            self?.visible = false
            self?.onChange?()
        }
        window.onClick = { [weak self] in self?.robotClicked() }
        self.window = window

        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            if self.dockPID != nil { self.refreshDock() } else { self.avatar?.goHome() }
        }

        // Öndeki uygulama değişince robot o AI'a dönüşsün
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostChanged(app)
        }
        // Masaüstü (Space) değişince: öndeki uygulama Claude/GPT ise robot o masaüstüne gelsin,
        // değilse olduğu masaüstünde kalsın.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            guard let self = self, self.pinnedSource != nil, self.visible else { return }
            self.window?.bringToActiveSpace()
        }

        frontmostChanged(NSWorkspace.shared.frontmostApplication)

        watcher.onEvent = { [weak self] event in self?.handle(event) }
        watcher.onStatus = { [weak self] status in
            guard let self = self, self.watcherStatus != status else { return }
            self.watcherStatus = status
            self.onChange?()
        }
        if Preferences.watchApps {
            if !AppWatcher.isTrusted { AppWatcher.requestTrust() }
            watcher.start()
        }

        if visible { window.show() }
    }

    /// Claude/ChatGPT/Codex masaüstü uygulamalarını izlemeyi aç/kapat.
    func setWatchApps(_ on: Bool) {
        Preferences.watchApps = on
        if on {
            if !AppWatcher.isTrusted { AppWatcher.requestTrust() }
            watcher.start()
        } else {
            watcher.stop()
        }
    }

    func handle(_ event: AgentEvent) {
        let m = model(for: event.source)
        if let notice = m.apply(event) {
            let lookingAtIt = event.quietIfFrontmostPID != nil
                && NSWorkspace.shared.frontmostApplication?.processIdentifier == event.quietIfFrontmostPID
            if !lookingAtIt {
                Notifier.shared.notify(title: notice.title, body: notice.body)
            }
        }
        chooseDisplay()
        onChange?()
    }

    /// Menüden: robotu şu anki masaüstüne getir.
    func bringRobotHere() {
        if !visible { visible = true }
        window?.bringToActiveSpace()
    }

    func reloadAppearance() {
        SkinStore.shared.reload()
        for m in models.values { m.reloadTheme() }
    }

    func showHistory(source: String) {
        guard let m = models[source] else { return }
        avatar?.show(m)
        m.showHistory()
    }

    @discardableResult
    func model(for source: String) -> RobotModel {
        if let existing = models[source] { return existing }
        let m = RobotModel(source: source)
        m.onStateChange = { [weak self] in
            self?.chooseDisplay()
            self?.onChange?()
        }
        models[source] = m
        order.append(source)
        if !Preferences.knownSources.contains(source) {
            Preferences.knownSources.append(source)
        }
        return m
    }

    // MARK: - Sağlık ışığı ve güncelleme haberi

    func setHealth(_ health: Health) {
        guard let avatar = avatar, avatar.health != health else { return }
        let wasUpdate: Bool
        if case .update = avatar.health { wasUpdate = true } else { wasUpdate = false }
        avatar.setHealth(health)
        if case .update(let version) = health, !wasUpdate {
            announceUpdate(version)
        }
    }

    private func announceUpdate(_ version: String) {
        lastUpdateAnnounce = CACurrentMediaTime()
        avatar?.current.say(withEmoji("⬆️", loc("Güncelleme var: \(version)! Bana tıkla, kurayım.",
                                                  "Update available: \(version)! Click me to install.")), for: 10)
    }

    /// Robota tıklayınca: güncelleme varsa kur, bir sorun varsa söyle, yoksa son olayları göster.
    private func robotClicked() {
        guard let avatar = avatar else { return }
        switch avatar.health {
        case .update:
            Updater.shared.promptInstall()
        case .broken(let reason):
            avatar.current.say(withEmoji("🔴", reason), for: 8)
            if Preferences.watchApps && !AppWatcher.isTrusted { AppWatcher.resetAndRequestTrust() }
        case .ok:
            avatar.current.showHistory()
        }
    }

    // MARK: - Hangi AI gösterilsin?

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app = app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        pinnedSource = AppMatcher.source(for: app)
        if let source = pinnedSource { model(for: source) }
        chooseDisplay()

        // Sadece AI uygulamasına geçince robot o pencerenin sağ-alt köşesine uçsun.
        // Başka bir uygulamaya geçince olduğu yerde kalsın (pencereyi takip etmeyi bırakır).
        if pinnedSource != nil && Preferences.followAppWindow {
            dockPID = app.processIdentifier
            refreshDock()
        } else {
            dockPID = nil
        }
        // Claude/GPT başka bir masaüstündeyse robot da oraya geçsin (masaüstü geçiş animasyonundan sonra)
        if pinnedSource != nil && visible {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self = self, self.pinnedSource != nil else { return }
                self.window?.bringToActiveSpace()
            }
        }
    }

    func followSettingChanged() {
        if Preferences.followAppWindow {
            frontmostChanged(NSWorkspace.shared.frontmostApplication)
        } else {
            dockPID = nil
            avatar?.goHome()
        }
    }

    private func refreshDock() {
        guard let pid = dockPID, let avatar = avatar else { return }
        if let frame = RobotManager.frontWindowFrame(pid: pid) {
            avatar.dock(to: frame)
        } else {
            avatar.goHome()   // pencere küçültülmüş ya da kapalı
        }
    }

    /// Uygulamanın en öndeki normal penceresi (Cocoa koordinatında). İzin gerektirmez.
    private static func frontWindowFrame(pid: pid_t) -> NSRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] else { return nil }
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        for info in list {   // önden arkaya sıralı
            guard let owner = info[kCGWindowOwnerPID as String] as? Int32, owner == pid,
                  let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let boundsDict = info[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else { continue }
            if bounds.width < 320 || bounds.height < 240 { continue }   // küçük açılır pencereleri atla
            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha < 0.1 { continue }
            return NSRect(x: bounds.minX, y: primaryHeight - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return nil
    }

    /// Öndeki uygulama bir AI'sa onu göster. Değilse en acil olanı (seni bekleyen > çalışan),
    /// eşitlikte en son hareket edeni. Hepsi boştaysa olduğu gibi kalsın.
    private func chooseDisplay() {
        guard let avatar = avatar else { return }
        if let pinned = pinnedSource, let m = models[pinned] {
            avatar.show(m)
            return
        }
        let current = avatar.current
        var best: RobotModel?
        for m in allModels {
            guard let last = m.lastRealEvent else { continue }
            if let b = best, let bLast = b.lastRealEvent {
                if (m.state.priority, last) > (b.state.priority, bLast) { best = m }
            } else {
                best = m
            }
        }
        guard let candidate = best, candidate !== current else { return }
        let higher = candidate.state.priority > current.state.priority
        let sameButNewer = candidate.state.priority == current.state.priority
            && candidate.state.priority >= RobotState.thinking.priority
            && (candidate.lastRealEvent ?? .distantPast) > (current.lastRealEvent ?? .distantPast)
        if higher || sameButNewer { avatar.show(candidate) }
    }

    // MARK: - Döngü

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(Swift.min(0.1, now - lastTick))
        lastTick = now
        let date = Date()
        for m in models.values { m.refresh(now: date) }
        // Takip edilen pencere taşındı mı? (saniyede 5 kez bak)
        if dockPID != nil && now - lastDockCheck > 0.2 {
            lastDockCheck = now
            refreshDock()
        }
        // Erişilebilirlik izni verildi/alındı mı? (menüdeki uyarıyı güncelle)
        if Preferences.watchApps && now - lastTrustCheck > 2 {
            lastTrustCheck = now
            let trusted = AppWatcher.isTrusted
            if trusted != wasTrusted {
                wasTrusted = trusted
                if trusted {
                    Notifier.shared.notify(title: withEmoji("👀", AppInfo.name),
                                           body: loc("Artık Claude ve ChatGPT uygulamalarını da görebiliyorum.",
                                                     "I can now see the Claude and ChatGPT apps too."))
                }
                onChange?()
            }
        }
        // Güncelleme hâlâ bekliyorsa, robot boştayken arada bir hatırlatsın
        if let avatar = avatar, case .update(let version) = avatar.health,
           now - lastUpdateAnnounce > 45 * 60, avatar.current.state == .idle {
            announceUpdate(version)
        }
        if visible { window?.tick(dt: dt) }
    }
}
