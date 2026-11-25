import AppKit
import CoreAudio
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
    private var lastMiniCheck: CFTimeInterval = 0
    private var lastApprovalCheck: CFTimeInterval = 0
    private var lastSlowCheck: CFTimeInterval = 0
    private var wasFocused = FocusMode.isActive
    /// Takıldı, çakışma, CI, commit hatırlatması ve kullanım sınırları
    let insights = Insights()
    // Sakin çizim
    private var pointerMovedAt = 0.0
    private var lastMouse = CGPoint.zero

    var onChange: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onReportBug: (() -> Void)?

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
        // Art arda hızlı tıklanınca başı döner
        window.onRapidClick = { [weak self] in
            self?.avatar?.current.react(.dizzy, for: 2.5, say: withEmoji("😵‍💫", loc("Başım döndü!", "I'm dizzy!")))
        }
        window.onDoubleClick = { [weak self] in self?.openCurrentApp() }
        // Minik kafaya tıklayınca o AI büyük kafaya geçer ve uygulaması öne gelir
        window.onMiniClick = { [weak self] source in self?.miniClicked(source) }
        window.onChatRow = { [weak self] row in self?.openChat(row) }
        window.onAlwaysOnTopChanged = { [weak self] _ in self?.onChange?() }
        window.onBubbleClick = { [weak self] in self?.bubbleClicked() }
        window.onApproval = { [weak self] choice in self?.choose(choice) }
        window.onFocusChanged = { [weak self] in self?.focusChanged() }
        window.onOpenSettings = { [weak self] in self?.onOpenSettings?() }
        window.onShowSummary = { [weak self] in self?.showSummary() }
        window.onReportBug = { [weak self] in self?.onReportBug?() }
        window.onLockChanged = { [weak self] locked in
            guard let self = self else { return }
            if locked { self.dockPID = nil } else { self.frontmostChanged(NSWorkspace.shared.frontmostApplication) }
            self.onChange?()
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
            guard let self = self, self.pinnedSource != nil, self.visible, !Preferences.robotLocked else { return }
            self.window?.bringToActiveSpace()
        }

        frontmostChanged(NSWorkspace.shared.frontmostApplication)
        Notifier.shared.onClick = { target in RobotManager.activate(target) }

        watcher.onEvent = { [weak self] event in self?.handle(event) }
        // Claude/ChatGPT (yeniden) açıldı: robot uyansın ve söylesin
        watcher.onAppOpened = { [weak self] source, name in
            guard let self = self else { return }
            let m = self.model(for: source)
            m.wake(greet: withEmoji("👋", loc("\(name) açıldı, buradayım!", "\(name) is open, I'm here!")), always: true)
            self.chooseDisplay()
        }
        watcher.onDiagnostics = { diagnostics in
            if Diagnostics.shared.apps != diagnostics { Diagnostics.shared.apps = diagnostics }
        }
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

    // MARK: - Robottan onay

    private var approvals: [PendingApproval] = []

    /// Claude Code izin istiyor: robot bekliyor durumuna geçer, balonda düğmeler çıkar
    func onPermission(_ p: PendingApproval) {
        model(for: p.event.source).clearSay()   // önceki "izin verdim" yeni soruyu örtmesin
        handle(p.event)   // bekliyor durumu ve bildirim
        // Ayar kapalıysa ya da zaten terminale bakıyorsan soru terminalde çıksın
        if !Preferences.approveFromRobot || terminalInFront(p) {
            p.release()
            return
        }
        approvals.append(p)
        approvalsChanged()
    }

    private func terminalInFront(_ p: PendingApproval) -> Bool {
        guard let front = NSWorkspace.shared.frontmostApplication else { return false }
        if let pid = p.event.appPID, front.processIdentifier == pid { return true }
        if let bundle = p.event.appBundleID, !bundle.isEmpty, front.bundleIdentifier == bundle { return true }
        return false
    }

    /// Ekrandaki robotun cevaplayabileceği soru (gösterilen AI'ın en yeni sorusu)
    private var currentApproval: PendingApproval? {
        guard let avatar = avatar else { return nil }
        let mine = approvals.filter { !$0.finished && $0.event.source == avatar.current.source }
        return mine.first(where: { $0.event.sessionID == avatar.current.bestSessionID }) ?? mine.last
    }

    func approvalsChanged() {
        approvals.removeAll { $0.finished }
        avatar?.setApproval(currentApproval.map { ApprovalPrompt(id: $0.id, hasAlways: $0.suggestions != nil, canAllow: $0.canAllow) })
    }

    /// Balondaki düğme: kararı Claude Code'a gönder
    func choose(_ choice: ApprovalChoice) {
        guard let p = currentApproval else { return }
        if choice != .deny && !p.canAllow { return }   // balonda tamamı görünmeyen şeye izin verilmez
        p.answer(Approval.decision(choice, suggestions: p.suggestions))
        let m = model(for: p.event.source)
        switch choice {
        case .deny: m.say(withEmoji("🚫", loc("Reddettim.", "Declined.")), for: 2.5)
        case .always: m.say(withEmoji("✅", loc("İzin verdim, bundan sonra sormayacak.", "Allowed; it won't ask again.")), for: 2.5)
        case .allow: m.say(withEmoji("✅", loc("İzin verdim.", "Allowed.")), for: 2.5)
        }
        approvalsChanged()
        onChange?()
    }

    /// Bekleyen sorular: terminale geçtiysen, ayar kapandıysa ya da çok beklediyse bırak
    private func checkApprovals() {
        for p in approvals where !p.finished {
            if terminalInFront(p) || Date().timeIntervalSince(p.created) > 580 || !Preferences.approveFromRobot { p.release() }
        }
        approvalsChanged()
    }

    func handle(_ event: AgentEvent) {
        // Claude devam etti (izin verildi, reddedildi, yeni istek…): o oturumun bekleyen sorusunu bırak
        if event.kind != .waiting && event.kind != .insight {
            for p in approvals where p.event.source == event.source && p.event.sessionID == event.sessionID { p.release() }
        }
        let m = model(for: event.source)
        if let notice = m.apply(event) {
            deliver(notice, quietPID: event.quietIfFrontmostPID)
        }
        chooseDisplay()
        onChange?()
    }

    /// Ham istek: hook olayından ya da durum satırından çıkan uyarılar; işler (CI, commit) arka planda.
    func handleRaw(path: String, query: [String: String], body: Data) {
        let (events, jobs) = insights.handle(path: path, query: query, body: body, now: Date())
        guard Preferences.insights else { return }
        for e in events { handle(e) }
        for job in jobs {
            InsightJobs.run(job, insights: insights) { [weak self] e in self?.handle(e) }
        }
    }

    /// Bildirimi gönderir: odak modunda sadece önemliler, kullanıcı o uygulamaya bakıyorsa hiç (ayara göre).
    private func deliver(_ notice: RobotModel.Notice, quietPID: Int32?) {
        if FocusMode.isActive && !notice.important { return }
        if !Preferences.notifyWhenFrontmost, let pid = quietPID,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == pid {
            return
        }
        Notifier.shared.notify(title: notice.title, body: notice.body, target: notice.target)
        if !FocusMode.isActive { Speech.say(notice.title) }
    }

    /// Bir uygulamayı öne getirir (süreç kimliğiyle ya da bundle id ile; kapalıysa açar).
    static func activate(_ target: AppTarget) {
        if let pid = target.pid, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
            app.activate(options: [.activateAllWindows])
            return
        }
        guard let id = target.bundleID, !id.isEmpty else { return }
        if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
            app.activate(options: [.activateAllWindows])
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Balona tıklayınca: o oturumun penceresine/terminaline git; bilinmiyorsa AI uygulamasını aç.
    private func bubbleClicked() {
        guard let avatar = avatar else { return }
        if let target = avatar.current.target, !target.isEmpty {
            RobotManager.activate(target)
        } else {
            openCurrentApp()
        }
    }

    // MARK: - Odak modu ve günlük özet

    func focusChanged() {
        let on = FocusMode.isActive
        avatar?.setFocus(on)
        if on != wasFocused {
            wasFocused = on
            onChange?()
        }
    }

    /// Mikrofon başka bir uygulama tarafından kullanılıyor mu? (görüşmedeyiz demek; izin gerektirmez)
    static func microphoneInUse() -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal,
                                                 mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr,
              deviceID != 0 else { return false }
        var running: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &running) == noErr else { return false }
        return running != 0
    }

    /// Toplantıda mıyız: toplantı uygulaması öndeyse ya da mikrofon açıkken (AI uygulaması dışında bir yerde).
    private func updateMeeting() {
        let front = NSWorkspace.shared.frontmostApplication
        let frontIsAI = front.map { AppMatcher.source(for: $0) != nil } ?? false
        let meeting = FocusMode.isMeetingApp(front?.bundleIdentifier) || (!frontIsAI && RobotManager.microphoneInUse())
        if meeting != FocusMode.meetingActive {
            FocusMode.meetingActive = meeting
        }
        focusChanged()
    }

    func todaySummaryText() -> String? {
        DailyStats.shared.summary(names: { [weak self] source in
            self?.models[source]?.theme.displayName ?? Themes.shared.theme(for: source).displayName
        })
    }

    /// Robota bir şey söylet (güncelleme ilerlemesi gibi)
    func say(_ text: String, for seconds: TimeInterval) {
        avatar?.current.say(text, for: seconds)
    }

    /// Bugünün özetini robota söylet (menüden ya da akşam kendiliğinden).
    func showSummary() {
        guard let avatar = avatar else { return }
        if !visible { visible = true }
        if let text = todaySummaryText() {
            avatar.current.say(withEmoji("📊", loc("Bugün:\n", "Today:\n") + text), for: 14)
        } else {
            avatar.current.say(withEmoji("📊", loc("Bugün henüz bitmiş bir iş yok.", "No finished tasks yet today.")), for: 5)
        }
    }

    private func checkDailySummary() {
        guard Preferences.dailySummary, !DailyStats.shared.shownToday, !FocusMode.isActive,
              Calendar.current.component(.hour, from: Date()) >= Preferences.dailySummaryHour,
              let text = todaySummaryText() else { return }
        DailyStats.shared.shownToday = true
        avatar?.current.say(withEmoji("📊", loc("Günün özeti:\n", "Your day:\n") + text), for: 14)
        Notifier.shared.notify(title: withEmoji("📊", loc("TelepAIth · günün özeti", "TelepAIth · your day")), body: text)
    }

    var isLocked: Bool { Preferences.robotLocked }

    /// Menüden her zaman üstte aç/kapat
    /// Ayarlardan robot boyutu değişti
    func setRobotScale(_ value: Double) {
        Preferences.robotScale = value
        window?.applyScale()
        // Köşeye yapışıksa yeni boyutla yine köşeye otursun
        if let avatar = avatar, !avatar.isDragging { avatar.goHome() }
        onChange?()
    }

    func setAlwaysOnTop(_ value: Bool) {
        window?.setAlwaysOnTop(value)
        onChange?()
    }

    /// Menüden kilitle/aç
    func setLocked(_ value: Bool) {
        avatar?.setLocked(value)
        if value { dockPID = nil } else { frontmostChanged(NSWorkspace.shared.frontmostApplication) }
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
        show(m)
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
        let text = loc("Güncelleme var: \(version)! Bana tıkla, kurayım.", "Update available: \(version)! Click me to install.")
        avatar?.current.say(withEmoji("⬆️", text), for: 10)
        Speech.say(text)
    }

    /// Robota çift tıklayınca o an gösterdiği AI'ın uygulamasını öne getir (açık değilse aç).
    private func miniClicked(_ source: String) {
        guard let m = models[source] else { return }
        pinnedSource = source
        show(m)
        m.wake()
        openCurrentApp()
    }

    private func openCurrentApp() {
        guard let source = avatar?.current.source else { return }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.processIdentifier != ownPID && $0.activationPolicy == .regular && AppMatcher.source(for: $0) == source
        }) {
            app.activate(options: [.activateAllWindows])
            return
        }
        let bundleIDs: [String: String] = ["claude": "com.anthropic.claudefordesktop", "gpt": "com.openai.chat"]
        if let id = bundleIDs[source], let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Robota tıklayınca: güncelleme varsa kur, bir sorun varsa söyle, yoksa son olayları göster.
    private func robotClicked() {
        // Ekranın altında saklanıyorsa önce geri çıksın
        if let avatar = avatar, avatar.peeking { avatar.unpeek(); return }
        guard let avatar = avatar else { return }
        switch avatar.health {
        case .update:
            Updater.shared.promptInstall()
        case .broken(let reason):
            avatar.current.say(withEmoji("🔴", reason), for: 8)
            if Preferences.watchApps && !AppWatcher.isTrusted { AppWatcher.resetAndRequestTrust() }
        case .ok:
            avatar.current.wake()
            // Sohbet listesi: açıksa kapat; çalışan/bekleyen/yeni biten sohbet varsa aç, yoksa son olaylar
            if avatar.chatList != nil {
                avatar.setChatList(nil)
                return
            }
            let rows = RobotModel.chatRows(allModels)
            if rows.isEmpty {
                avatar.current.showHistory()
            } else {
                avatar.chatListUntil = Date().addingTimeInterval(10)
                avatar.setChatList(rows)
            }
        }
    }

    /// Listeden bir sohbet seçildi: o AI'a geç ve sohbeti aç
    private func openChat(_ row: RobotModel.ChatRow) {
        avatar?.setChatList(nil)
        if let m = models[row.source] {
            pinnedSource = row.source
            show(m)
        }
        // Masaüstü uygulamasındaki sohbet (açık, önceden açılmış ya da arkadaki): uygulamayı öne getir, yan menüde o sohbete bas
        if watcher.openChat(row.sessionID) { return }
        // Claude Code: çalıştığı terminal; uygulama sohbeti: uygulamanın penceresi
        if let target = row.target, !target.isEmpty {
            RobotManager.activate(target)
            return
        }
        openCurrentApp()
    }

    // MARK: - Hangi AI gösterilsin?

    private func frontmostChanged(_ app: NSRunningApplication?) {
        guard let app = app, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
        pinnedSource = AppMatcher.source(for: app)
        // AI uygulamasına geçince robot uyuyorsa uyansın
        if let source = pinnedSource { model(for: source).wake(greet: withEmoji("👋", loc("Uyandım!", "I'm up!"))) }
        chooseDisplay()

        // Sadece AI uygulamasına geçince robot o pencerenin sağ-alt köşesine uçsun.
        // Başka bir uygulamaya geçince olduğu yerde kalsın (pencereyi takip etmeyi bırakır).
        // Kilitliyse hiçbir yere gitmez (ne pencereye ne başka masaüstüne)
        if pinnedSource != nil && Preferences.followAppWindow && !Preferences.robotLocked {
            dockPID = app.processIdentifier
            refreshDock()
        } else {
            dockPID = nil
        }
        // Claude/GPT başka bir masaüstündeyse robot da oraya geçsin (masaüstü geçiş animasyonundan sonra)
        if pinnedSource != nil && visible && !Preferences.robotLocked {
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
        // Öndeki AI uygulaması (tıkladığın) her zaman büyük kafada; öteki çalışıyorsa yanında minik kafa olur
        if let pinned = pinnedSource, let m = models[pinned] {
            show(m)
            return
        }
        if let next = RobotModel.pickDisplay(allModels, current: avatar.current) { show(next) }
    }

    /// Büyük kafayı değiştir ve minik kafaları hemen yenile (aynı AI hem büyük hem minik görünmesin)
    private func show(_ model: RobotModel) {
        guard let avatar = avatar, model !== avatar.current else { return }
        avatar.show(model)
        avatar.setMinis(RobotModel.minis(allModels, current: model))
        avatar.setExtras(RobotModel.extras(current: model))
    }

    // MARK: - Döngü

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = CGFloat(Swift.min(0.1, now - lastTick))
        lastTick = now
        let date = Date()
        for m in models.values { m.refresh(now: date) }
        avatar?.gazeAllowed = RobotModel.canGaze(allModels, now: date)
        // Bekleyen izin soruları (terminale geçildi mi?)
        if (!approvals.isEmpty || avatar?.approval != nil) && now - lastApprovalCheck > 0.15 {
            lastApprovalCheck = now
            checkApprovals()
        }
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
        // Bekleme hatırlatmaları gibi zamanlayıcı bildirimleri
        for m in models.values where !m.pendingNotices.isEmpty {
            let notices = m.pendingNotices
            m.pendingNotices = []
            for n in notices { deliver(n, quietPID: n.target?.pid) }
        }
        // Minik kafalar: gösterilenin dışında çalışan/bekleyen tüm oturumlar
        if now - lastMiniCheck > 0.5, let avatar = avatar {
            lastMiniCheck = now
            chooseDisplay()   // bitiş kutlaması bitince sıradaki çalışana geç
            // Gösterilen AI'ın kendisi zaten büyük kafada; başka AI'ların tek oturumu da minik kafa olur
            avatar.setMinis(RobotModel.minis(allModels, current: avatar.current, now: date))
            // Açık sohbet listesi canlı kalsın (süreler ilerler), süresi dolunca kapansın
            if avatar.chatList != nil {
                let rows = RobotModel.chatRows(allModels, now: date)
                avatar.setChatList(date > avatar.chatListUntil || rows.isEmpty ? nil : rows)
            }
            avatar.setExtras(RobotModel.extras(current: avatar.current, now: date))
            // Kullanım sınırları: halkalar, gözdeki "%", yenilenme bildirimi
            for e in insights.usage.tick(now: date) where Preferences.insights { handle(e) }
            avatar.setUsage(insights.usage.current(now: date))
            models["claude"]?.usageLeft = insights.usage.left(now: date)
        }
        // Saklanırken haber gelirse (balon, onay, sohbet listesi) geri çıksın
        if let avatar = avatar, avatar.peeking,
           avatar.current.bubbleText != nil || avatar.approval != nil || avatar.chatList != nil || avatar.current.state == .waiting {
            avatar.unpeek()
        }
        updateCalm(now: date)
        // Toplantı, odak süresi, günlük özet (5 sn'de bir)
        if now - lastSlowCheck > 5 {
            lastSlowCheck = now
            updateMeeting()
            checkDailySummary()
        }
        if visible { window?.tick(dt: dt) }
    }

    /// Sakin çizim: robot boşta ve hiçbir şey olmuyorken (balon, ruh hâli, sohbet, imleç hareketi yok) kafa yavaşça
    /// durur ve yeniden çizilmez; sadece göz kırpma anlarında birkaç kare çizilir. (Windows'ta UpdateCalm, aynı kural)
    private func updateCalm(now date: Date) {
        guard let avatar = avatar else { return }
        let time = date.timeIntervalSinceReferenceDate
        let mouse = NSEvent.mouseLocation
        if mouse != lastMouse {
            lastMouse = mouse
            let dx = mouse.x - avatar.head.x, dy = mouse.y - avatar.head.y
            let reach = 900 * avatar.scale
            if dx * dx + dy * dy < reach * reach { pointerMovedAt = time }
        }
        let m = avatar.current
        let restingStates: [RobotState] = [.idle, .sleeping, .done]
        var calmNow = restingStates.contains(m.state)
        calmNow = calmNow && m.mood == nil && m.bubbleText == nil && m.eyeGlyph(at: date) == nil && m.quotaLeft == nil
        if let start = m.celebrateStart, date.timeIntervalSince(start) <= 3 { calmNow = false }
        calmNow = calmNow && avatar.minis.isEmpty && avatar.chatList == nil && avatar.extras.isEmpty && avatar.approval == nil
        calmNow = calmNow && avatar.health == .ok && !avatar.isMoving && !Preferences.winterActive
        calmNow = calmNow && date.timeIntervalSince(avatar.currentSince) > 1 && time - pointerMovedAt > 1.5
        var calm = avatar.calm
        calm.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if calmNow != calm.calm {
            calm.from = calm.stillness(at: time)
            calm.calm = calmNow
            calm.since = time
        }
        avatar.setCalm(calm)
        // Uyurken gözler kapalı: kırpma için de uyanmasın
        avatar.setPaused(calmNow && time - calm.since >= Calm.settle && (m.state != .idle || !Calm.inBlink(time)))
    }
}
