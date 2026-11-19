import AppKit
import SwiftUI

/// Odak almayan, şeffaf, her masaüstünde görünen panel.
final class RobotPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Robotun üstüne tıklama ve sürükleme.
final class RobotHostingView: NSHostingView<RobotContainerView> {
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDrag: ((CGPoint) -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?

    private var mouseStart: NSPoint = .zero
    private var originStart: NSPoint = .zero
    private var dragging = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseStart = NSEvent.mouseLocation
        originStart = window?.frame.origin ?? .zero
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
        onDrag?(CGPoint(x: originStart.x + dx, y: originStart.y + dy))
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

final class RobotWindowController: NSObject {
    let model: RobotModel
    var onHide: (() -> Void)?

    private let panel: RobotPanel
    private let host: RobotHostingView

    init(model: RobotModel) {
        self.model = model

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

        let host = RobotHostingView(rootView: RobotContainerView(model: model))
        host.frame = NSRect(origin: .zero, size: Layout.windowSize)
        panel.contentView = host

        self.panel = panel
        self.host = host
        super.init()

        host.onClick = { [weak self] in self?.model.showHistory() }
        host.onDragStart = { [weak self] in self?.model.beginDrag() }
        host.onDrag = { [weak self] point in
            guard let self = self else { return }
            self.model.drag(to: point)
            self.syncFrame()
        }
        host.onDragEnd = { [weak self] in self?.model.endDrag() }
        host.onRightClick = { [weak self] event in self?.showMenu(event) }
    }

    func show() {
        syncFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Her karede çağrılır: pencereyi modelin konumuna taşır.
    func syncFrame() {
        let origin = NSPoint(x: model.x, y: model.y)
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        updateMousePassThrough()
    }

    /// Fare robotun üstünde değilse tıklamalar arkadaki pencerelere geçsin (balon dahil).
    private func updateMousePassThrough() {
        let frame = panel.frame
        let robotRect = NSRect(x: frame.minX + (frame.width - Layout.robotSize.width) / 2,
                               y: frame.minY,
                               width: Layout.robotSize.width,
                               height: Layout.robotSize.height)
        let over = model.isDragging || robotRect.contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        let history = NSMenuItem(title: "Son olayları göster", action: #selector(historyAction), keyEquivalent: "")
        history.target = self
        menu.addItem(history)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Bu robotu gizle", action: #selector(hideAction), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        NSMenu.popUpContextMenu(menu, with: event, for: host)
    }

    @objc private func historyAction() {
        model.showHistory()
    }

    @objc private func hideAction() {
        onHide?()
    }
}
