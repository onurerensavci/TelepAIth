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
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

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
        avatar.setScreen(screenFrame())
        avatar.restorePosition()
        self.avatar = avatar

        let window = AvatarWindowController(avatar: avatar)
        window.onHide = { [weak self] in
            self?.visible = false
            self?.onChange?()
        }
        self.window = window

        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            self.avatar?.setScreen(self.screenFrame())
        }

        // Öndeki uygulama değişince robot o AI'a dönüşsün
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostChanged(app)
        }
        frontmostChanged(NSWorkspace.shared.frontmostApplication)

        if visible { window.show() }
    }

    func handle(_ event: AgentEvent) {
        let m = model(for: event.source)
        if let notice = m.apply(event) {
            Notifier.shared.notify(title: notice.title, body: notice.body)
        }
        chooseDisplay()
        onChange?()
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

    // MARK: - Hangi AI gösterilsin?

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app = app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        pinnedSource = AppMatcher.source(for: app)
        if let source = pinnedSource { model(for: source) }
        chooseDisplay()
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

    private func screenFrame() -> NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(Swift.min(0.1, now - lastTick))
        lastTick = now
        let date = Date()
        for m in models.values { m.refresh(now: date) }
        if visible { window?.tick(dt: dt) }
    }
}
