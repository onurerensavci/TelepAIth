import AppKit
import SwiftUI

enum Corner: String, CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight
}

/// Ekrandaki tek robot: hangi AI'ı gösterdiği, nerede durduğu, köşelere yapışma.
final class RobotAvatar: ObservableObject {
    @Published private(set) var current: RobotModel
    @Published private(set) var alignLeft = false     // kafa pencerenin solunda, balon sağa uzar
    @Published private(set) var bubbleBelow = false   // ekranın üst yarısında: balon kafanın altında

    /// Kafanın merkezi (ekran koordinatı, sol-alt köken)
    private(set) var head: CGPoint = .zero
    private(set) var isDragging = false
    private var dragStartHead: CGPoint = .zero
    private var target: CGPoint?
    private var screen = NSRect(x: 0, y: 0, width: 1440, height: 900)

    private static let snapDistance: CGFloat = 260

    init(model: RobotModel) {
        current = model
    }

    /// Gösterilen AI'ı değiştirir (küçük bir "puf" animasyonuyla).
    func show(_ model: RobotModel) {
        guard model !== current else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            current = model
        }
    }

    // MARK: Konum

    func setScreen(_ frame: NSRect) {
        screen = frame
        if let raw = UserDefaults.standard.string(forKey: "avatarCorner"), let corner = Corner(rawValue: raw) {
            head = point(for: corner)
        } else {
            head = clamp(head)
        }
        target = nil
        updateSides(for: head)
    }

    func restorePosition() {
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "avatarCorner"), let corner = Corner(rawValue: raw) {
            head = point(for: corner)
        } else if let x = defaults.object(forKey: "avatarX") as? Double, let y = defaults.object(forKey: "avatarY") as? Double {
            head = clamp(CGPoint(x: x, y: y))
        } else {
            head = point(for: .bottomRight)
        }
        updateSides(for: head)
    }

    private func point(for corner: Corner) -> CGPoint {
        let hw = Layout.headSize.width / 2 + Layout.edgeInset
        let hh = Layout.headSize.height / 2 + Layout.edgeInset
        switch corner {
        case .bottomLeft: return CGPoint(x: screen.minX + hw, y: screen.minY + hh)
        case .bottomRight: return CGPoint(x: screen.maxX - hw, y: screen.minY + hh)
        case .topLeft: return CGPoint(x: screen.minX + hw, y: screen.maxY - hh)
        case .topRight: return CGPoint(x: screen.maxX - hw, y: screen.maxY - hh)
        }
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        let hw = Layout.headSize.width / 2 + Layout.edgeInset
        let hh = Layout.headSize.height / 2 + Layout.edgeInset
        let x = Swift.min(Swift.max(p.x, screen.minX + hw), screen.maxX - hw)
        let y = Swift.min(Swift.max(p.y, screen.minY + hh), screen.maxY - hh)
        return CGPoint(x: x, y: y)
    }

    private func updateSides(for p: CGPoint) {
        let left = p.x < screen.midX
        let below = p.y > screen.midY
        if alignLeft != left { alignLeft = left }
        if bubbleBelow != below { bubbleBelow = below }
    }

    // MARK: Sürükleme

    func beginDrag() {
        isDragging = true
        target = nil
        dragStartHead = head
    }

    func drag(dx: CGFloat, dy: CGFloat) {
        head = CGPoint(x: dragStartHead.x + dx, y: dragStartHead.y + dy)
    }

    /// Bırakınca en yakın köşeye yapışır; köşeden uzaksa olduğu yerde kalır.
    func endDrag() {
        isDragging = false
        let defaults = UserDefaults.standard
        var nearest: (corner: Corner, distance: CGFloat)?
        for corner in Corner.allCases {
            let p = point(for: corner)
            let d = hypot(p.x - head.x, p.y - head.y)
            if nearest == nil || d < nearest!.distance { nearest = (corner: corner, distance: d) }
        }
        let destination: CGPoint
        if let n = nearest, n.distance < RobotAvatar.snapDistance {
            destination = point(for: n.corner)
            defaults.set(n.corner.rawValue, forKey: "avatarCorner")
        } else {
            destination = clamp(head)
            defaults.removeObject(forKey: "avatarCorner")
            defaults.set(Double(destination.x), forKey: "avatarX")
            defaults.set(Double(destination.y), forKey: "avatarY")
        }
        target = destination
        updateSides(for: destination)
    }

    /// Yapışma animasyonu (saniyede 30 kez).
    func step(dt: CGFloat) {
        guard !isDragging, let t = target else { return }
        let k = Swift.min(1, dt * 14)
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
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.ignoresMouseEvents = true

        let host = AvatarHostingView(rootView: AvatarView(avatar: avatar))
        host.frame = NSRect(origin: .zero, size: Layout.windowSize)
        panel.contentView = host

        self.panel = panel
        self.host = host
        super.init()

        host.onClick = { [weak self] in self?.avatar.current.showHistory() }
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
