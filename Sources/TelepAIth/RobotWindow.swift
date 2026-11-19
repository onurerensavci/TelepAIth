import AppKit
import SwiftUI

enum Corner: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight
}

/// Alındaki ışık: yeşil her şey yolunda, turuncu güncelleme var, kırmızı bir şey çalışmıyor.
enum Health: Equatable {
    case ok
    case update(String)
    case broken(String)
}

/// Ekrandaki tek robot: hangi AI'ı gösterdiği, nerede durduğu, köşelere yapışma,
/// AI uygulamasının penceresine uçma.
final class RobotAvatar: ObservableObject {
    @Published private(set) var current: RobotModel
    @Published private(set) var alignLeft = false     // kafa pencerenin solunda, balon sağa uzar
    @Published private(set) var bubbleBelow = false   // ekranın üst yarısında: balon kafanın altında
    @Published private(set) var health: Health = .ok

    /// Kafanın merkezi (ekran koordinatı, ana ekranın sol-alt köşesi köken)
    private(set) var head: CGPoint = .zero
    private(set) var isDragging = false
    private var dragStartHead: CGPoint = .zero
    private var target: CGPoint?

    /// Kullanıcı robotu elle taşıyınca (pencere takibini bırakmak için)
    var onUserMoved: (() -> Void)?

    private static let snapDistance: CGFloat = 260
    /// AI penceresinin sağ-alt köşesinden kafa merkezine uzaklık
    private static let dockOffset = CGPoint(x: 95, y: 100)
    private static let fallbackFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)

    init(model: RobotModel) {
        current = model
    }

    func setHealth(_ value: Health) {
        if health != value { health = value }
    }

    /// Gösterilen AI'ı değiştirir (küçük bir "puf" animasyonuyla).
    func show(_ model: RobotModel) {
        guard model !== current else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            current = model
        }
    }

    // MARK: Ekranlar

    private static func screen(containing p: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.frame.contains(p) }) { return s }
        return screens.min { distance(p, $0.frame) < distance(p, $1.frame) }
    }

    private static func distance(_ p: CGPoint, _ r: NSRect) -> CGFloat {
        let dx = Swift.max(r.minX - p.x, 0, p.x - r.maxX)
        let dy = Swift.max(r.minY - p.y, 0, p.y - r.maxY)
        return hypot(dx, dy)
    }

    private static func displayID(of screen: NSScreen) -> Int {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    private static func screen(withID id: Int) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == id }
    }

    private static func cornerPoint(_ corner: Corner, in frame: NSRect) -> CGPoint {
        let hw = Layout.headSize.width / 2 + Layout.edgeInset
        let hh = Layout.headSize.height / 2 + Layout.edgeInset
        switch corner {
        case .bottomLeft: return CGPoint(x: frame.minX + hw, y: frame.minY + hh)
        case .bottomRight: return CGPoint(x: frame.maxX - hw, y: frame.minY + hh)
        case .topLeft: return CGPoint(x: frame.minX + hw, y: frame.maxY - hh)
        case .topRight: return CGPoint(x: frame.maxX - hw, y: frame.maxY - hh)
        }
    }

    private static func clamp(_ p: CGPoint, to frame: NSRect) -> CGPoint {
        let hw = Layout.headSize.width / 2 + Layout.edgeInset
        let hh = Layout.headSize.height / 2 + Layout.edgeInset
        let x = Swift.min(Swift.max(p.x, frame.minX + hw), frame.maxX - hw)
        let y = Swift.min(Swift.max(p.y, frame.minY + hh), frame.maxY - hh)
        return CGPoint(x: x, y: y)
    }

    // MARK: Ev konumu (kullanıcının bıraktığı köşe ya da nokta, hangi ekranda olursa)

    private var homePoint: CGPoint {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "avatarCorner"), let corner = Corner(rawValue: raw) {
            let screen = RobotAvatar.screen(withID: defaults.integer(forKey: "avatarScreen")) ?? NSScreen.main ?? NSScreen.screens.first
            return RobotAvatar.cornerPoint(corner, in: screen?.visibleFrame ?? RobotAvatar.fallbackFrame)
        }
        if let x = defaults.object(forKey: "avatarX") as? Double, let y = defaults.object(forKey: "avatarY") as? Double {
            let p = CGPoint(x: x, y: y)
            return RobotAvatar.clamp(p, to: RobotAvatar.screen(containing: p)?.visibleFrame ?? RobotAvatar.fallbackFrame)
        }
        let frame = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame ?? RobotAvatar.fallbackFrame
        return RobotAvatar.cornerPoint(.bottomRight, in: frame)
    }

    func restorePosition() {
        head = homePoint
        target = nil
        updateSides(for: head)
    }

    func goHome() {
        guard !isDragging else { return }
        moveTo(homePoint)
    }

    /// AI uygulamasının penceresinin sağ-alt köşesine uç (pencere taşınırsa tekrar çağrılır).
    func dock(to window: NSRect) {
        guard !isDragging else { return }
        var p = CGPoint(x: window.maxX - RobotAvatar.dockOffset.x, y: window.minY + RobotAvatar.dockOffset.y)
        p.x = Swift.max(p.x, window.minX + Layout.headSize.width / 2)
        p.y = Swift.min(p.y, window.maxY - Layout.headSize.height / 2)
        let reference = target ?? head
        if hypot(reference.x - p.x, reference.y - p.y) < 1 { return }
        target = p
        // Balon pencerenin içine doğru açılsın (sağ-alt köşede: yukarı ve sola)
        let left = p.x < window.midX
        let below = p.y > window.midY
        if alignLeft != left { alignLeft = left }
        if bubbleBelow != below { bubbleBelow = below }
    }

    private func moveTo(_ p: CGPoint) {
        target = p
        updateSides(for: p)
    }

    private func updateSides(for p: CGPoint) {
        let frame = RobotAvatar.screen(containing: p)?.frame ?? RobotAvatar.fallbackFrame
        let left = p.x < frame.midX
        let below = p.y > frame.midY
        if alignLeft != left { alignLeft = left }
        if bubbleBelow != below { bubbleBelow = below }
    }

    // MARK: Sürükleme (ekrandan ekrana serbest)

    func beginDrag() {
        isDragging = true
        target = nil
        dragStartHead = head
    }

    func drag(dx: CGFloat, dy: CGFloat) {
        head = CGPoint(x: dragStartHead.x + dx, y: dragStartHead.y + dy)
    }

    /// Bırakıldığı ekranda en yakın köşeye yapışır; köşeden uzaksa olduğu yerde kalır.
    func endDrag() {
        isDragging = false
        let defaults = UserDefaults.standard
        let screen = RobotAvatar.screen(containing: head)
        let frame = screen?.visibleFrame ?? RobotAvatar.fallbackFrame

        var nearest: (corner: Corner, distance: CGFloat)?
        for corner in Corner.allCases {
            let p = RobotAvatar.cornerPoint(corner, in: frame)
            let d = hypot(p.x - head.x, p.y - head.y)
            if nearest == nil || d < nearest!.distance { nearest = (corner: corner, distance: d) }
        }
        if let n = nearest, n.distance < RobotAvatar.snapDistance {
            defaults.set(n.corner.rawValue, forKey: "avatarCorner")
            defaults.set(screen.map { RobotAvatar.displayID(of: $0) } ?? 0, forKey: "avatarScreen")
        } else {
            let p = RobotAvatar.clamp(head, to: frame)
            defaults.removeObject(forKey: "avatarCorner")
            defaults.set(Double(p.x), forKey: "avatarX")
            defaults.set(Double(p.y), forKey: "avatarY")
        }
        moveTo(homePoint)
        onUserMoved?()
    }

    /// Yapışma ve uçma animasyonu (saniyede 30 kez).
    func step(dt: CGFloat) {
        guard !isDragging, let t = target else { return }
        let k = Swift.min(1, dt * 9)
        head = CGPoint(x: head.x + (t.x - head.x) * k, y: head.y + (t.y - head.y) * k)
        if hypot(t.x - head.x, t.y - head.y) < 0.5 {
            head = t
            target = nil
        }
    }

    /// Pencerenin sol-alt köşesi: kafa pencerenin hangi köşesindeyse ona göre.
    var windowOrigin: CGPoint {
        let size = Layout.windowSize
        let localX = alignLeft
            ? Layout.margin + Layout.headSize.width / 2
            : size.width - Layout.margin - Layout.headSize.width / 2
        let localY = bubbleBelow
            ? size.height - Layout.margin - Layout.headSize.height / 2
            : Layout.margin + Layout.headSize.height / 2
        return CGPoint(x: head.x - localX, y: head.y - localY)
    }

    var headRect: NSRect {
        NSRect(x: head.x - Layout.headSize.width / 2,
               y: head.y - Layout.headSize.height / 2,
               width: Layout.headSize.width,
               height: Layout.headSize.height)
    }
}

/// Odak almayan, şeffaf, her masaüstünde görünen panel.
final class RobotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Robotun üstüne tıklama ve sürükleme.
final class AvatarHostingView: NSHostingView<AvatarView> {
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var mouseStart: NSPoint = .zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseStart = NSEvent.mouseLocation
        dragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        let p = NSEvent.mouseLocation
        let dx = p.x - mouseStart.x
        let dy = p.y - mouseStart.y
        if !dragging {
            guard hypot(dx, dy) >= 3 else { return }
            dragging = true
            onDragStart?()
        }
        onDrag?(dx, dy)
    }

    override func mouseUp(with event: NSEvent) {
        if dragging {
            dragging = false
            onDragEnd?()
        } else {
            onClick?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onRightClick?(event)
    }
}

final class AvatarWindowController: NSObject {
    let avatar: RobotAvatar
    var onHide: (() -> Void)?
    var onClick: (() -> Void)?

    private let panel: RobotPanel
    private let host: AvatarHostingView

    init(avatar: RobotAvatar) {
        self.avatar = avatar

        let panel = RobotPanel(contentRect: NSRect(origin: .zero, size: Layout.windowSize),
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered,
                               defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        // Her masaüstünde değil: Claude/GPT hangi masaüstündeyse orada kalır.
        // Öne getirildiğinde o anki masaüstüne taşınır (moveToActiveSpace).
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let host = AvatarHostingView(rootView: AvatarView(avatar: avatar))
        host.frame = NSRect(origin: .zero, size: Layout.windowSize)
        panel.contentView = host

        self.panel = panel
        self.host = host
        super.init()

        host.onClick = { [weak self] in
            guard let self = self else { return }
            if let handler = self.onClick { handler() } else { self.avatar.current.showHistory() }
        }
        host.onDragStart = { [weak self] in self?.avatar.beginDrag() }
        host.onDrag = { [weak self] dx, dy in
            guard let self = self else { return }
            self.avatar.drag(dx: dx, dy: dy)
            self.syncFrame()
        }
        host.onDragEnd = { [weak self] in self?.avatar.endDrag() }
        host.onRightClick = { [weak self] event in self?.showMenu(event) }
    }

    func show() {
        syncFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Robotu şu an açık olan masaüstüne taşır.
    func bringToActiveSpace() {
        panel.orderFrontRegardless()
    }

    func tick(dt: CGFloat) {
        avatar.step(dt: dt)
        syncFrame()
    }

    private func syncFrame() {
        let origin = avatar.windowOrigin
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        // Fare kafanın üstünde değilse tıklamalar arkadaki pencerelere geçsin (balon dahil)
        let over = avatar.isDragging || avatar.headRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let history = NSMenuItem(title: loc("Son olayları göster", "Show recent events"), action: #selector(historyAction), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: loc("Robotu gizle", "Hide robot"), action: #selector(hideAction), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        NSMenu.popUpContextMenu(menu, with: event, for: host)
    }

    @objc private func historyAction() {
        avatar.current.showHistory()
    }

    @objc private func hideAction() {
        onHide?()
    }
}
