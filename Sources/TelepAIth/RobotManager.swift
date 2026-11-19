import AppKit
import QuartzCore

/// Kaynak başına bir robot: oluşturur, olayları dağıtır, saniyede 30 kez hareket ettirir.
final class RobotManager {
    private var controllers: [String: RobotWindowController] = [:]
    private var order: [String] = []
    private var timer: Timer?
    private var lastTick = CACurrentMediaTime()

    var onChange: (() -> Void)?

    var visible: Bool = Preferences.robotsVisible {
        didSet {
            Preferences.robotsVisible = visible
            for c in controllers.values {
                if visible { c.show() } else { c.hide() }
            }
        }
    }

    var models: [RobotModel] {
        order.compactMap { controllers[$0]?.model }
    }

    func start() {
        for source in Preferences.knownSources {
            controller(for: source)
        }
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.layoutBounds()
        }
    }

    func handle(_ event: AgentEvent) {
        let c = controller(for: event.source)
        if let notice = c.model.apply(event) {
            Notifier.shared.notify(title: notice.title, body: notice.body)
        }
        onChange?()
    }

    func reloadAppearance() {
        SkinStore.shared.reload()
        for c in controllers.values { c.model.reloadTheme() }
    }

    func showHistory(source: String) {
        controllers[source]?.model.showHistory()
    }

    @discardableResult
    func controller(for source: String) -> RobotWindowController {
        if let existing = controllers[source] { return existing }

        let model = RobotModel(source: source)
        let c = RobotWindowController(model: model)
        c.onHide = { [weak self] in self?.remove(source) }
        model.onStateChange = { [weak self] in self?.onChange?() }
        controllers[source] = c
        order.append(source)
        if !Preferences.knownSources.contains(source) {
            Preferences.knownSources.append(source)
        }

        layoutBounds()
        let frame = screenFrame()
        let slot = CGFloat(order.count - 1)
        model.x = frame.midX - Layout.windowSize.width / 2 - 130 + slot * 260
        model.setBounds(minX: model.minX, maxX: model.maxX, groundY: model.groundY) // konumu sınırla
        model.y = model.groundY

        if visible { c.show() }
        return c
    }

    private func remove(_ source: String) {
        controllers[source]?.hide()
        controllers[source] = nil
        order.removeAll { $0 == source }
        Preferences.knownSources.removeAll { $0 == source }
        onChange?()
    }

    private func screenFrame() -> NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func layoutBounds() {
        let f = screenFrame()
        for c in controllers.values {
            c.model.setBounds(minX: f.minX - 40,
                              maxX: f.maxX - Layout.windowSize.width + 40,
                              groundY: f.minY)
        }
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(Swift.min(0.1, now - lastTick))
        lastTick = now
        let date = Date()
        for c in controllers.values {
            c.model.tick(dt: dt, now: date)
            if visible { c.syncFrame() }
        }
    }
}
