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
    @Published private(set) var locked = Preferences.robotLocked
    /// Aynı anda çalışan diğer oturumlar (minik kafalar)
    @Published private(set) var minis: [RobotModel.MiniSession] = []
    /// Kafadaki küçük ışıklar: kafalarda görünmeyen diğer çalışan/bekleyen sohbetler (bekleyenler önce)
    @Published private(set) var extras: [RobotState] = []
    /// Yeni sohbet ışığı eklendiği an (nokta zıplayarak belirsin)
    private(set) var extrasPoppedAt: Date = .distantPast
    /// Odak modu: robot soluk durur, sadece seni bekleyen şeyleri söyler
    @Published private(set) var focus = FocusMode.isActive
    /// Balonun pencere içindeki yeri (SwiftUI, sol-üst köken, %100 boyuttaki ölçüyle). Tıklamayı yakalamak için.
    var bubbleFrame: CGRect = .zero
    /// Gösterilen AI'ın cevap bekleyen izin sorusu varsa balonda İzin ver / Reddet düğmeleri
    @Published private(set) var approval: ApprovalPrompt?
    /// Düğmelerin pencere içindeki yeri (bubbleFrame gibi)
    var approvalFrames: [ApprovalChoice: CGRect] = [:]

    func setApproval(_ value: ApprovalPrompt?) {
        if approval != value { approval = value }
        if value == nil { approvalFrames = [:] }
    }

    var miniFrames: [String: CGRect] = [:]

    /// Kafaya tıklayınca açılan sohbet listesi (nil: kapalı) ve ne zamana kadar açık kalacağı
    @Published private(set) var chatList: [RobotModel.ChatRow]?
    var chatListUntil: Date = .distantPast
    var chatRowFrames: [Int: CGRect] = [:]

    func setChatList(_ rows: [RobotModel.ChatRow]?) {
        if chatList != rows { chatList = rows }
        if rows == nil { chatRowFrames = [:] }
    }

    /// Ekrandaki bu noktada sohbet listesinin bir satırı var mı?
    func chatRow(at point: NSPoint) -> RobotModel.ChatRow? {
        guard let list = chatList, let index = chatRowIndex(at: point), index < list.count else { return nil }
        return list[index]
    }

    /// Bu noktadaki satırın sırası (fare üstündeyken koyulaşması için)
    func chatRowIndex(at point: NSPoint) -> Int? {
        guard let list = chatList else { return nil }
        let origin = windowOrigin
        let s = Layout.scale
        for (index, f) in chatRowFrames where index < list.count {
            let r = NSRect(x: origin.x + f.minX * s, y: origin.y + Layout.windowSize.height - f.maxY * s,
                           width: f.width * s, height: f.height * s)
            if r.contains(point) { return index }
        }
        return nil
    }

    /// Ekrandaki bu noktada bir minik kafa var mı? (hangi AI'ın)
    func miniSource(at point: NSPoint) -> String? {
        guard Preferences.miniHeads, !minis.isEmpty else { return nil }
        let origin = windowOrigin
        let s = Layout.scale
        for (source, f) in miniFrames where minis.contains(where: { $0.source == source }) {
            let r = NSRect(x: origin.x + f.minX * s, y: origin.y + Layout.windowSize.height - f.maxY * s,
                           width: f.width * s, height: f.height * s)
            if r.contains(point) { return source }
        }
        return nil
    }

    /// Ekrandaki bu noktada bir onay düğmesi var mı?
    func approvalChoice(at point: NSPoint) -> ApprovalChoice? {
        guard approval != nil else { return nil }
        let origin = windowOrigin
        let s = Layout.scale
        for (choice, f) in approvalFrames {
            let r = NSRect(x: origin.x + f.minX * s, y: origin.y + Layout.windowSize.height - f.maxY * s,
                           width: f.width * s, height: f.height * s)
            if r.contains(point) { return choice }
        }
        return nil
    }
    /// Robotun boyutu (ayarlardan)
    @Published private(set) var scale = Layout.scale

    func setScale(_ value: CGFloat) {
        if scale != value { scale = value }
    }

    /// Kafanın merkezi (ekran koordinatı, ana ekranın sol-alt köşesi köken)
    private(set) var head: CGPoint = .zero
    /// Gözler imleci izleyebilir mi (hiçbir sohbet çalışmıyor ve son iş biteli 20 sn oldu)
    var gazeAllowed = false
    /// Boştayken gözlerin imleci izlemesi için
    lazy var pointer: PointerTracker = {
        let p = PointerTracker()
        p.avatar = self
        return p
    }()
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

    func setMinis(_ value: [RobotModel.MiniSession]) {
        if minis != value { minis = value }
    }

    func setExtras(_ value: [RobotState]) {
        if value.count > extras.count { extrasPoppedAt = Date() }
        if extras != value { extras = value }
    }

    func setFocus(_ value: Bool) {
        if focus != value { focus = value }
    }

    /// Balonun ekrandaki yeri (görünüyorsa)
    var bubbleScreenRect: NSRect? {
        guard bubbleFrame.width > 0, bubbleFrame.height > 0 else { return nil }
        let origin = windowOrigin
        let s = Layout.scale
        return NSRect(x: origin.x + bubbleFrame.minX * s,
                      y: origin.y + Layout.windowSize.height - bubbleFrame.maxY * s,
                      width: bubbleFrame.width * s, height: bubbleFrame.height * s)
    }

    func setLocked(_ value: Bool) {
        Preferences.robotLocked = value
        if locked != value { locked = value }
        if value { target = nil }
    }

    /// Gösterilen AI'ı değiştirir (küçük bir "puf" animasyonuyla).
    func show(_ model: RobotModel) {
        guard model !== current else { return }
        currentSince = Date()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
            current = model
        }
    }

    /// Gösterilen AI'ın değiştiği an (geçiş animasyonu bitmeden sakin çizime geçilmez)
    private(set) var currentSince = Date()
    /// Kullanım sınırları (Claude Code durum satırı): kafanın altında iki küçük halka
    @Published private(set) var usage: [UsageWindow] = []
    /// Sakin çizim: hiçbir şey olmuyorken kafa yeniden çizilmez (paused); calm süzülmenin yumuşakça durmasını taşır
    @Published private(set) var paused = false
    @Published private(set) var calm = CalmState()
    /// Kafa uçuyor ya da sürükleniyor mu
    var isMoving: Bool { isDragging || target != nil }

    func setUsage(_ value: [UsageWindow]) { if usage != value { usage = value } }
    /// Gardırop: takılı parçalar (kafada çizilir)
    @Published private(set) var outfit: [OutfitItem] = []
    func setOutfit(_ value: [OutfitItem]) { if outfit.map(\.id) != value.map(\.id) { outfit = value } }
    func setPaused(_ value: Bool) { if paused != value { paused = value } }
    func setCalm(_ value: CalmState) { if calm != value { calm = value } }

    // MARK: Ekranlar

    private static func screen(containing p: CGPoint) -> NSScreen? {
        let screens = NSScreen.screens
        if let s = screens.first(where: { $0.frame.contains(p) }) { return s }
        return screens.min { distance(p, $0.frame) < distance(p, $1.frame) }
    }

    /// Kafanın kenara uzaklığı: robotun penceresi de ekranın dışına (komşu ekrana) taşmasın
    private static var inset: CGFloat { Swift.max(Layout.edgeInset, Layout.margin) }

    /// Bir dikdörtgenin en çok üstünde durduğu ekran (iki ekrana yayılan pencere için)
    private static func screen(for rect: NSRect) -> NSScreen? {
        NSScreen.screens.max { a, b in
            let ia = a.frame.intersection(rect), ib = b.frame.intersection(rect)
            return ia.width * ia.height < ib.width * ib.height
        } ?? screen(containing: CGPoint(x: rect.midX, y: rect.midY))
    }

    /// Balon tarafı ekranın dışına taşacaksa öbür yöne aç (Cocoa: y yukarı doğru)
    private static func fitSides(_ p: CGPoint, left: Bool, below: Bool, in frame: NSRect) -> (Bool, Bool) {
        let size = Layout.windowSize
        let near = Layout.margin + Layout.headSize.width / 2
        var left = left, below = below
        if left && p.x - near + size.width > frame.maxX { left = false }
        else if !left && p.x + near - size.width < frame.minX { left = true }
        if below && p.y + near - size.height < frame.minY { below = false }
        else if !below && p.y - near + size.height > frame.maxY { below = true }
        return (left, below)
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
        let hw = Layout.headSize.width / 2 + inset
        let hh = Layout.headSize.height / 2 + inset
        switch corner {
        case .bottomLeft: return CGPoint(x: frame.minX + hw, y: frame.minY + hh)
        case .bottomRight: return CGPoint(x: frame.maxX - hw, y: frame.minY + hh)
        case .topLeft: return CGPoint(x: frame.minX + hw, y: frame.maxY - hh)
        case .topRight: return CGPoint(x: frame.maxX - hw, y: frame.maxY - hh)
        }
    }

    private static func clamp(_ p: CGPoint, to frame: NSRect) -> CGPoint {
        let hw = Layout.headSize.width / 2 + inset
        let hh = Layout.headSize.height / 2 + inset
        let x = Swift.min(Swift.max(p.x, frame.minX + hw), frame.maxX - hw)
        let y = Swift.min(Swift.max(p.y, frame.minY + hh), frame.maxY - hh)
        return CGPoint(x: x, y: y)
    }

    /// Serbest konum: üstte menü çubuğunun üstüne de çıkabilir (kafanın tepesi ekranın tepesine kadar)
    private static func clampFree(_ p: CGPoint, on screen: NSScreen?) -> CGPoint {
        let visible = screen?.visibleFrame ?? fallbackFrame
        var q = clamp(p, to: visible)
        if p.y > q.y {
            let top = (screen?.frame ?? visible).maxY - Layout.headSize.height / 2 - 2
            q.y = Swift.max(q.y, Swift.min(p.y, top))
        }
        return q
    }

    /// Kafa menü çubuğunun üstüne çıktı mı? (pencere menü çubuğunun da üstünde çizilmeli)
    var overMenuBar: Bool {
        guard let screen = RobotAvatar.screen(containing: head) else { return false }
        return head.y + Layout.headSize.height / 2 > screen.visibleFrame.maxY + 1
    }

    // MARK: Ev konumu (kullanıcının bıraktığı köşe ya da nokta, hangi ekranda olursa)

    /// Ekranın altına itildi: sadece kafasının üstü görünür; tıklayınca ya da haber gelince geri çıkar
    private(set) var peeking = false
    private var peekPoint = CGPoint.zero

    /// Saklanmaktan çık, eski yerine dön
    func unpeek() {
        guard peeking else { return }
        peeking = false
        moveTo(homePoint)
    }

    private var homePoint: CGPoint {
        if peeking { return peekPoint }
        let defaults = UserDefaults.standard
        if let raw = defaults.string(forKey: "avatarCorner"), let corner = Corner(rawValue: raw) {
            let screen = RobotAvatar.screen(withID: defaults.integer(forKey: "avatarScreen")) ?? NSScreen.main ?? NSScreen.screens.first
            return RobotAvatar.cornerPoint(corner, in: screen?.visibleFrame ?? RobotAvatar.fallbackFrame)
        }
        if let x = defaults.object(forKey: "avatarX") as? Double, let y = defaults.object(forKey: "avatarY") as? Double {
            let p = CGPoint(x: x, y: y)
            return RobotAvatar.clampFree(p, on: RobotAvatar.screen(containing: p))
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
        if locked {
            // Kilitliyken yerinde kalır; sadece ekran söküldüyse görünür bir yere taşınır, iki ekrana taşıyorsa içeri alınır
            if !NSScreen.screens.contains(where: { $0.frame.contains(head) }) { moveTo(homePoint); return }
            let p = RobotAvatar.clampFree(head, on: RobotAvatar.screen(containing: head))
            if hypot(p.x - head.x, p.y - head.y) > 0.5 { moveTo(p) }
            return
        }
        moveTo(homePoint)
    }

    /// AI uygulamasının penceresinin sağ-alt köşesine uç (pencere taşınırsa tekrar çağrılır).
    func dock(to window: NSRect) {
        guard !isDragging, !locked, !peeking else { return }
        var p = CGPoint(x: window.maxX - RobotAvatar.dockOffset.x, y: window.minY + RobotAvatar.dockOffset.y)
        p.x = Swift.max(p.x, window.minX + Layout.headSize.width / 2)
        p.y = Swift.min(p.y, window.maxY - Layout.headSize.height / 2)
        // Pencere iki ekrana yayılmışsa çoğunun durduğu ekran; robot hep o ekranın içinde kalır
        let frame = RobotAvatar.screen(for: window)?.visibleFrame ?? RobotAvatar.fallbackFrame
        p = RobotAvatar.clamp(p, to: frame)
        // Balon pencerenin içine doğru açılsın (sağ-alt köşede: yukarı ve sola); ekrandan taşacaksa öbür yöne
        let (left, below) = RobotAvatar.fitSides(p, left: p.x < window.midX, below: p.y > window.midY, in: frame)
        let reference = target ?? head
        if hypot(reference.x - p.x, reference.y - p.y) < 1 && left == alignLeft && below == bubbleBelow { return }
        target = p
        if alignLeft != left { alignLeft = left }
        if bubbleBelow != below { bubbleBelow = below }
    }

    private func moveTo(_ p: CGPoint) {
        target = p
        updateSides(for: p)
    }

    private func updateSides(for p: CGPoint) {
        let screen = RobotAvatar.screen(containing: p)
        let frame = screen?.frame ?? RobotAvatar.fallbackFrame
        let (left, below) = RobotAvatar.fitSides(p, left: p.x < frame.midX, below: p.y > frame.midY,
                                                 in: screen?.visibleFrame ?? RobotAvatar.fallbackFrame)
        if alignLeft != left { alignLeft = left }
        if bubbleBelow != below { bubbleBelow = below }
    }

    // MARK: Sürükleme (ekrandan ekrana serbest)

    func beginDrag() {
        guard !locked else { return }
        isDragging = true
        peeking = false
        target = nil
        dragStartHead = head
    }

    func drag(dx: CGFloat, dy: CGFloat) {
        guard isDragging else { return }
        head = CGPoint(x: dragStartHead.x + dx, y: dragStartHead.y + dy)
    }

    /// Bırakıldığı ekranda en yakın köşeye yapışır; köşeden uzaksa olduğu yerde kalır.
    func endDrag() {
        guard isDragging else { return }
        isDragging = false
        let defaults = UserDefaults.standard
        let screen = RobotAvatar.screen(containing: head)
            ?? NSScreen.screens.first { $0.frame.minX <= head.x && head.x < $0.frame.maxX }
        let frame = screen?.visibleFrame ?? RobotAvatar.fallbackFrame
        // Ekranın altına itildiyse saklan: sadece kafasının üstü görünsün (kayıtlı yeri değişmez)
        if head.y < frame.minY + Layout.headSize.height * 0.1 {
            peeking = true
            peekPoint = CGPoint(x: RobotAvatar.clamp(head, to: frame).x, y: frame.minY - Layout.headSize.height * 0.2)
            moveTo(peekPoint)
            onUserMoved?()
            return
        }

        // Menü çubuğunun üstüne bırakıldıysa köşeye yapışmaz, orada kalır
        let intoMenuBar = head.y + Layout.headSize.height / 2 > frame.maxY
        var nearest: (corner: Corner, distance: CGFloat)?
        for corner in Corner.allCases where !intoMenuBar {
            let p = RobotAvatar.cornerPoint(corner, in: frame)
            let d = hypot(p.x - head.x, p.y - head.y)
            if nearest == nil || d < nearest!.distance { nearest = (corner: corner, distance: d) }
        }
        if let n = nearest, n.distance < RobotAvatar.snapDistance {
            defaults.set(n.corner.rawValue, forKey: "avatarCorner")
            defaults.set(screen.map { RobotAvatar.displayID(of: $0) } ?? 0, forKey: "avatarScreen")
        } else {
            let p = RobotAvatar.clampFree(head, on: screen)
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
    /// macOS pencereyi menü çubuğunun altına itmesin: robot menü çubuğunun üstüne de çıkabilir
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

/// Robotun üstüne tıklama ve sürükleme.
final class AvatarHostingView: NSHostingView<AvatarView> {
    var onClick: (() -> Void)?
    var onDragStart: (() -> Void)?
    var onDrag: ((CGFloat, CGFloat) -> Void)?
    var onDragEnd: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDoubleClick: (() -> Void)?
    /// Kafaya art arda hızlıca (1,5 sn'de 4 kez) tıklandı
    var onRapidClick: (() -> Void)?
    var onBubbleClick: (() -> Void)?
    var onApproval: ((ApprovalChoice) -> Void)?
    /// Tıklanan nokta balonun üstünde mi (kafanın değil)?
    var isOverBubble: ((NSPoint) -> Bool)?
    /// Tıklanan noktada onay düğmesi var mı?
    var approvalAt: ((NSPoint) -> ApprovalChoice?)?
    /// Bu noktada minik kafa var mı (hangi AI'ın)?
    var miniAt: ((NSPoint) -> String?)?
    var onMiniClick: ((String) -> Void)?
    /// Bu noktada sohbet listesinin bir satırı var mı?
    var chatRowAt: ((NSPoint) -> RobotModel.ChatRow?)?
    var onChatRow: ((RobotModel.ChatRow) -> Void)?

    private var mouseStart: NSPoint = .zero
    private var dragging = false
    private var presses: [Date] = []
    private var swallowUp = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseStart = NSEvent.mouseLocation
        dragging = false
        swallowUp = false
        guard approvalAt?(mouseStart) == nil, isOverBubble?(mouseStart) != true, miniAt?(mouseStart) == nil,
              chatRowAt?(mouseStart) == nil else { return }
        let now = Date()
        presses.append(now)
        presses.removeAll { now.timeIntervalSince($0) > 1.5 }
        if presses.count >= 4 {
            presses.removeAll()
            swallowUp = true
            onRapidClick?()
        }
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
        if swallowUp {
            swallowUp = false
            return
        }
        if dragging {
            dragging = false
            onDragEnd?()
        } else if let choice = approvalAt?(NSEvent.mouseLocation) {
            onApproval?(choice)
        } else if let source = miniAt?(NSEvent.mouseLocation) {
            onMiniClick?(source)
        } else if let row = chatRowAt?(NSEvent.mouseLocation) {
            onChatRow?(row)
        } else if isOverBubble?(NSEvent.mouseLocation) == true {
            onBubbleClick?()
        } else if event.clickCount == 2 {
            onDoubleClick?()
        } else if event.clickCount == 1 {
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
    var onDoubleClick: (() -> Void)?
    var onRapidClick: (() -> Void)?
    /// Minik kafaya tıklandı: o AI'a geç
    var onMiniClick: ((String) -> Void)?
    /// Sohbet listesinde bir satıra tıklandı: o sohbete git
    var onChatRow: ((RobotModel.ChatRow) -> Void)?
    var onLockChanged: ((Bool) -> Void)?
    var onAlwaysOnTopChanged: ((Bool) -> Void)?
    var onBubbleClick: (() -> Void)?
    var onApproval: ((ApprovalChoice) -> Void)?
    var onFocusChanged: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenRoom: (() -> Void)?
    var onShowSummary: (() -> Void)?
    var onReportBug: (() -> Void)?
    /// Hazır güncellemenin sürümü (yoksa nil); menüden güncelle / denetle
    var updateVersion: (() -> String?)?
    var onUpdate: (() -> Void)?
    var onCheckUpdates: (() -> Void)?

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
        panel.level = Preferences.alwaysOnTop ? .statusBar : .normal
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
        host.onRapidClick = { [weak self] in self?.onRapidClick?() }
        host.onDragStart = { [weak self] in self?.avatar.beginDrag() }
        host.onDrag = { [weak self] dx, dy in
            guard let self = self else { return }
            self.avatar.drag(dx: dx, dy: dy)
            self.syncFrame()
        }
        host.onDragEnd = { [weak self] in self?.avatar.endDrag() }
        host.onRightClick = { [weak self] event in self?.showMenu(event) }
        host.onDoubleClick = { [weak self] in self?.onDoubleClick?() }
        host.onBubbleClick = { [weak self] in self?.onBubbleClick?() }
        host.onApproval = { [weak self] choice in self?.onApproval?(choice) }
        host.approvalAt = { [weak self] point in self?.avatar.approvalChoice(at: point) }
        host.miniAt = { [weak self] point in self?.avatar.miniSource(at: point) }
        host.onMiniClick = { [weak self] source in self?.onMiniClick?(source) }
        host.chatRowAt = { [weak self] point in self?.avatar.chatRow(at: point) }
        host.onChatRow = { [weak self] row in self?.onChatRow?(row) }
        host.isOverBubble = { [weak self] point in
            guard let self = self, !self.avatar.headRect.contains(point) else { return false }
            return self.avatar.bubbleScreenRect?.contains(point) ?? false
        }
    }

    func show() {
        syncFrame()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Her zaman üstte açık/kapalı
    func setAlwaysOnTop(_ value: Bool) {
        Preferences.alwaysOnTop = value
        panel.level = value ? .statusBar : .normal
        if panel.isVisible { panel.orderFrontRegardless() }
    }

    /// Robotu şu an açık olan masaüstüne taşır.
    func bringToActiveSpace() {
        panel.orderFrontRegardless()
    }

    func tick(dt: CGFloat) {
        avatar.step(dt: dt)
        syncFrame()
    }

    /// Ayarlardan boyut değişince: pencereyi yeni boyuta getir, kafa yerinde kalsın.
    func applyScale() {
        let size = Layout.windowSize
        avatar.setScale(Layout.scale)
        host.frame = NSRect(origin: .zero, size: size)
        panel.setFrame(NSRect(origin: avatar.windowOrigin, size: size), display: true)
    }

    private func syncFrame() {
        let origin = avatar.windowOrigin
        if panel.frame.origin != origin { panel.setFrameOrigin(origin) }
        // Menü çubuğunun üstündeyken onun da üstünde çizilsin
        let level: NSWindow.Level = Preferences.alwaysOnTop || avatar.overMenuBar ? .statusBar : .normal
        if panel.level != level { panel.level = level }
        // Fare kafanın ya da balonun üstünde değilse tıklamalar arkadaki pencerelere geçsin
        let mouse = NSEvent.mouseLocation
        let over = avatar.isDragging || avatar.headRect.contains(mouse) || (avatar.bubbleScreenRect?.contains(mouse) ?? false)
            || avatar.miniSource(at: mouse) != nil
        if panel.ignoresMouseEvents == over { panel.ignoresMouseEvents = !over }
    }

    private func showMenu(_ event: NSEvent) {
        // Sık kullanılanlar üstte, açılıp kapananlar işaretli, gerisi "Diğer" altında
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, on: Bool? = nil, to target: NSMenu? = nil) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            if let on = on { item.state = on ? .on : .off }
            (target ?? menu).addItem(item)
        }
        // Güncelleme varsa en üstte; tıklayınca robot kısaca ne geldiğini söyler, sonra kurulumu sorar
        if let version = updateVersion?() {
            add("⬆️ " + loc("Güncelle: \(version) hazır", "Update: \(version) is ready"), #selector(updateAction))
            menu.addItem(.separator())
        }
        add(loc("Son olaylar", "Recent events"), #selector(historyAction))
        add(loc("Robotun odası", "Robot's room"), #selector(roomAction))
        add(loc("Bugünün özeti", "Today's summary"), #selector(summaryAction))
        menu.addItem(.separator())
        add(loc("Kilitle", "Lock"), #selector(lockAction), on: avatar.locked)
        add(loc("Sessize al", "Mute"), #selector(muteAction), on: Preferences.muted)
        add(loc("Odak modu (1 saat)", "Focus mode (1 hour)"), #selector(focusAction), on: FocusMode.manualActive)
        menu.addItem(.separator())
        add(loc("Ayarlar", "Settings"), #selector(settingsAction))
        if updateVersion?() == nil { add(loc("Güncellemeleri denetle", "Check for updates"), #selector(checkUpdatesAction)) }
        let more = NSMenu()
        add(loc("Her zaman üstte", "Always on top"), #selector(alwaysOnTopAction), on: Preferences.alwaysOnTop, to: more)
        add(loc("Teşhis", "Diagnostics"), #selector(diagnosticsAction), to: more)
        add(loc("Hata bildir", "Report a problem"), #selector(bugAction), to: more)
        more.addItem(.separator())
        add(loc("Robotu gizle", "Hide robot"), #selector(hideAction), to: more)
        let moreItem = NSMenuItem(title: loc("Diğer", "More"), action: nil, keyEquivalent: "")
        moreItem.submenu = more
        menu.addItem(moreItem)
        applyMenuTitles(menu)
        NSMenu.popUpContextMenu(menu, with: event, for: host)
    }

    @objc private func updateAction() { onUpdate?() }
    @objc private func checkUpdatesAction() { onCheckUpdates?() }

    @objc private func historyAction() {
        avatar.current.showHistory()
    }

    @objc private func alwaysOnTopAction() {
        let value = !Preferences.alwaysOnTop
        setAlwaysOnTop(value)
        avatar.current.say(value
            ? withEmoji("📌", loc("Her zaman en üstteyim.", "I'll stay on top of everything."))
            : withEmoji("🪟", loc("Artık diğer pencerelerin arkasında kalabilirim.", "Other windows can cover me now.")),
            for: 4)
        onAlwaysOnTopChanged?(value)
    }

    @objc private func lockAction() {
        let value = !avatar.locked
        avatar.setLocked(value)
        avatar.current.say(value
            ? withEmoji("🔒", loc("Kilitlendim, yerimden kıpırdamıyorum.", "Locked. I'm staying right here."))
            : withEmoji("🔓", loc("Kilidim açıldı, yine Claude ve GPT'nin peşinden gelirim.", "Unlocked. I'll follow Claude and GPT again.")),
            for: 4)
        onLockChanged?(value)
    }

    @objc private func muteAction() {
        Preferences.muted.toggle()
        avatar.current.say(Preferences.muted
            ? withEmoji("🔇", loc("Sessizim: bildirimler sessiz gelir, ses çıkarmam.", "Muted: notifications come silently, no sounds."))
            : withEmoji("🔊", loc("Sesim geri geldi.", "Sound is back.")),
            for: 4)
    }

    @objc private func focusAction() {
        if FocusMode.manualActive {
            FocusMode.turnOff()
            avatar.current.say(withEmoji("☀️", loc("Odak modu kapandı, yine konuşuyorum.", "Focus mode off, I'm chatty again.")), for: 4)
        } else {
            FocusMode.turnOn(for: 3600)
            avatar.current.say(withEmoji("🌙", loc("Bir saat sessizim; sadece seni bekleyen şeyleri söylerim.", "Quiet for an hour; I'll only tell you what needs you.")), for: 4)
        }
        onFocusChanged?()
    }

    @objc private func summaryAction() { onShowSummary?() }
    @objc private func settingsAction() { onOpenSettings?() }
    @objc private func roomAction() { onOpenRoom?() }
    @objc private func bugAction() { onReportBug?() }

    @objc private func diagnosticsAction() {
        DiagnosticsWindow.shared.show()
    }

    @objc private func hideAction() {
        onHide?()
    }
}
