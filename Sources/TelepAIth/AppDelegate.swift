import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: AppController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let c = AppController()
        controller = c
        c.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.stop()
    }
}

/// Menü çubuğu ikonu, sunucu ve robotları birbirine bağlar.
final class AppController: NSObject {
    private let manager = RobotManager()
    private let server = EventServer()
    private var statusItem: NSStatusItem?
    private var serverError: String?

    func start() {
        try? FileManager.default.createDirectory(at: AppInfo.skinsDir, withIntermediateDirectories: true)
        Themes.writeExampleConfigIfMissing()
        Themes.shared.reload()
        Notifier.shared.onStatusChange = { [weak self] in self?.rebuildMenu() }
        Notifier.shared.setup()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        manager.onChange = { [weak self] in self?.rebuildMenu() }
        manager.onOpenSettings = { [weak self] in self?.openSettings() }
        manager.onOpenRoom = { [weak self] in self?.openRoom() }
        manager.onReportBug = { [weak self] in self?.reportBug() }
        manager.start()

        server.onReady = { [weak self] port in
            try? "\(port)".write(to: AppInfo.portFile, atomically: true, encoding: .utf8)
            self?.serverError = nil
            self?.rebuildMenu()
        }
        server.onFailure = { [weak self] reason in
            self?.serverError = reason
            self?.rebuildMenu()
        }
        server.onRequest = { [weak self] path, query, body in
            DispatchQueue.main.async {
                guard let self = self else { return }
                // Claude Code'un durum satırı (kullanım sınırları): olay değil, sadece uyarılara gider
                if !path.hasPrefix("/statusline"), let event = EventParser.parse(path: path, query: query, body: body) {
                    self.manager.handle(event)
                }
                self.manager.handleRaw(path: path, query: query, body: body)
            }
        }
        server.onPermission = { [weak self] query, body, respond, onClosed in
            DispatchQueue.main.async {
                guard let self = self, let event = EventParser.parse(path: "/permission", query: query, body: body) else {
                    respond("")
                    return
                }
                let pending = PendingApproval(event: event, body: body) { answer in respond(answer) }
                onClosed { DispatchQueue.main.async { [weak self] in pending.closed(); self?.manager.approvalsChanged() } }
                self.manager.onPermission(pending)
            }
        }
        server.start(preferredPort: AppInfo.defaultPort)
        // İlk açılışta "Mac açılınca başlasın" açık (kullanıcı sonra kapatabilir)
        LaunchAtLogin.applyDefaultOnce()

        Updater.shared.onChange = { [weak self] in self?.rebuildMenu() }
        Updater.shared.onProgress = { [weak self] text in self?.manager.say(text, for: 30) }
        Updater.shared.startAutomaticChecks()

        // Kurulu hook'ları güncel komutla yenile (uygulama güncellenince eski komut kalmasın)
        for target in HookTarget.allCases where HookInstaller.isInstalled(target) {
            try? HookInstaller.install(target)
        }
        if UsageLine.isConnected { try? UsageLine.connect() }
        rebuildMenu()

        // İlk açılışta kurulum sihirbazı
        if !Preferences.onboardingDone {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                OnboardingWindow.shared.show(host: self)
            }
        }
    }

    func stop() {
        server.stop()
        try? FileManager.default.removeItem(at: AppInfo.portFile)
    }

    // MARK: - Menü

    private var serverLine: String {
        let version = Updater.shared.currentVersion
        if server.port > 0 { return "\(AppInfo.name) \(version)" }   // port: Teşhis'te
        if let error = serverError { return loc("Sunucu açılamadı: ", "Server failed: ") + clip(error, 40) }
        return "\(AppInfo.name) · " + loc("başlatılıyor…", "starting…")
    }

    private func updateIcon() {
        let waiting = manager.allModels.contains { $0.state == .waiting }
        if waiting {
            let image = NSImage(systemSymbolName: "exclamationmark.bubble", accessibilityDescription: AppInfo.name)
            image?.isTemplate = true
            statusItem?.button?.image = image
        } else {
            statusItem?.button?.image = BrandIcon.menuBar
        }
    }

    /// Robotun alnındaki ışık: kırmızı çalışamıyor, turuncu güncelleme var, yeşil her şey yolunda.
    private func currentHealth() -> Health {
        if let error = serverError {
            return .broken(loc("Sunucu açılamadı: ", "Server failed: ") + clip(error, 40))
        }
        if Preferences.watchApps && !AppWatcher.isTrusted {
            return .broken(loc("Claude'u göremiyorum: Erişilebilirlik izni yok ya da güncellemeyle düştü. Bana tıkla, Ayarlar'da TelepAIth'i aç (açıksa kapatıp yeniden aç).",
                               "I can't see Claude: Accessibility permission is missing or was reset by an update. Click me and turn TelepAIth on in Settings (toggle it off and on if it's already on)."))
        }
        let anyHook = HookTarget.allCases.contains { HookInstaller.isInstalled($0) }
        if !anyHook && !Preferences.watchApps {
            return .broken(loc("Hiçbir AI'a bağlı değilim. Menü → Bağlantılar'dan bağla.",
                               "I'm not connected to any AI. Connect one from the menu → Connections."))
        }
        if let release = Updater.shared.available {
            return .update(release.version)
        }
        return .ok
    }

    private func rebuildMenu() {
        updateIcon()
        let health = currentHealth()
        manager.setHealth(health)
        Diagnostics.shared.general = [
            (loc("Sürüm", "Version"), Updater.shared.currentVersion),
            ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            (loc("Sunucu", "Server"), server.port > 0 ? "127.0.0.1:\(server.port)" : (serverError ?? "—")),
            (loc("Erişilebilirlik izni", "Accessibility"), AppWatcher.isTrusted ? loc("var", "granted") : loc("yok", "missing")),
            (loc("Masaüstü izleme", "Desktop watching"), Preferences.watchApps ? loc("açık", "on") : loc("kapalı", "off")),
            (loc("Bildirim izni", "Notifications"), Notifier.shared.status.text),
            ("Claude Code", HookInstaller.isInstalled(.claude) ? loc("bağlı", "connected") : loc("bağlı değil", "not connected")),
            ("Codex", HookInstaller.isInstalled(.codex) ? loc("bağlı", "connected") : loc("bağlı değil", "not connected")),
            (loc("Anlatıcı", "Narrator"), NarratorInstaller.isInstalled() ? loc("Claude masaüstüne ekli", "added to Claude desktop") : loc("ekli değil", "not added")),
            (loc("Odak modu", "Focus mode"), FocusMode.statusText),
        ]

        let menu = NSMenu()
        menu.autoenablesItems = false

        // Başlık: "● TelepAIth 0.17.2 · Her şey yolunda" tek satır; sorun ya da güncelleme varsa ayrı satırda kalır
        let dotColor: NSColor
        let healthText: String
        switch health {
        case .ok:
            dotColor = .systemGreen
            healthText = FocusMode.isActive ? loc("Odak modu ", "Focus mode ") + FocusMode.statusText : loc("Her şey yolunda", "All good")
        case .update(let version):
            dotColor = .systemOrange
            healthText = loc("Güncelleme var: \(version)", "Update available: \(version)")
        case .broken(let reason):
            dotColor = .systemRed
            healthText = reason
        }
        let header = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        header.isEnabled = false
        let isOK: Bool
        if case .ok = health { isOK = true } else { isOK = false }
        let headerTitle = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: dotColor])
        headerTitle.append(NSAttributedString(string: isOK ? serverLine + " · " + healthText : serverLine,
                                              attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.secondaryLabelColor]))
        header.attributedTitle = headerTitle
        menu.addItem(header)
        if !isOK {
            let healthItem = NSMenuItem(title: clip(healthText, 70), action: nil, keyEquivalent: "")
            healthItem.isEnabled = false
            menu.addItem(healthItem)
        }

        if let release = Updater.shared.available {
            let title = "⬆︎ " + loc("Güncelle: \(release.version) hazır", "Update: \(release.version) is ready")
            let update = actionItem(title, #selector(installUpdate))
            update.attributedTitle = NSAttributedString(string: title,
                                                        attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            update.isEnabled = !Updater.shared.isBusy
            menu.addItem(update)
        }

        for model in manager.allModels {
            let item = NSMenuItem(title: "", action: #selector(showRobotHistory(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.source
            let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: model.theme.color])
            title.append(NSAttributedString(string: "\(model.theme.displayName) — \(model.statusLine)",
                                            attributes: [.font: NSFont.menuFont(ofSize: 0)]))
            item.attributedTitle = title
            menu.addItem(item)
        }

        // Uyarılar: sadece bir şey eksikse görünür
        if Preferences.notificationsEnabled && Notifier.shared.status == .denied {
            menu.addItem(actionItem("⚠︎ " + loc("Bildirimler macOS'ta kapalı — aç…", "Notifications are off in macOS — turn on…"),
                                    #selector(openNotificationSettings)))
        }
        if Preferences.watchApps && !AppWatcher.isTrusted {
            menu.addItem(actionItem("⚠︎ " + loc("Erişilebilirlik izni gerekli…", "Accessibility permission needed…"),
                                    #selector(openAccessibility)))
            let reset = actionItem(loc("İzni sıfırla ve yeniden iste", "Reset and request permission again"),
                                   #selector(resetAccessibility))
            reset.indentationLevel = 1
            menu.addItem(reset)
        }

        menu.addItem(.separator())
        // Güncelleme denetimi en üstte, Robotu göster'in hemen üstünde
        let checkTitle = Updater.shared.isBusy
            ? loc("Güncelleme indiriliyor…", "Downloading update…")
            : loc("Güncellemeleri denetle…", "Check for updates…")
        let check = actionItem(checkTitle, #selector(checkForUpdates))
        check.isEnabled = !Updater.shared.isBusy
        menu.addItem(check)
        menu.addItem(toggleItem(loc("Robotu göster", "Show robot"), on: manager.visible, action: #selector(toggleRobots)))

        let focus = NSMenuItem(title: loc("Odak modu", "Focus mode"), action: nil, keyEquivalent: "")
        focus.state = FocusMode.isActive ? .on : .off
        let focusMenu = NSMenu()
        let focusStatus = NSMenuItem(title: FocusMode.statusText, action: nil, keyEquivalent: "")
        focusStatus.isEnabled = false
        focusMenu.addItem(focusStatus)
        focusMenu.addItem(.separator())
        focusMenu.addItem(actionItem(loc("1 saat", "1 hour"), #selector(focusHour)))
        focusMenu.addItem(actionItem(loc("Kapatana kadar", "Until I turn it off"), #selector(focusForever)))
        let off = actionItem(loc("Kapat", "Turn off"), #selector(focusOff))
        off.isEnabled = FocusMode.manualActive
        focusMenu.addItem(off)
        focusMenu.addItem(.separator())
        focusMenu.addItem(toggleItem(loc("Toplantıda kendiliğinden aç", "Automatically in meetings"),
                                     on: Preferences.autoFocusInMeetings, action: #selector(toggleAutoFocus)))
        focus.submenu = focusMenu
        menu.addItem(focus)
        menu.addItem(actionItem(loc("Bugünün özeti", "Today's summary"), #selector(showSummaryAction)))

        menu.addItem(.separator())
        menu.addItem(actionItem(loc("Robotun odası…", "Robot's room…"), #selector(openRoom)))
        menu.addItem(actionItem(loc("Ayarlar…", "Settings…"), #selector(openSettings), key: ","))

        // Az kullanılanlar Yardım'ın altında: güncelleme, robotu buraya getir, kurulum, deneme, teşhis
        let demo = NSMenuItem(title: loc("Dene", "Try it"), action: nil, keyEquivalent: "")
        let demoMenu = NSMenu()
        demoMenu.addItem(actionItem(loc("Claude: kısa bir görev", "Claude: a short task"), #selector(demoClaude)))
        demoMenu.addItem(actionItem(loc("GPT: onay beklesin", "GPT: wait for approval"), #selector(demoGPTWaiting)))
        demoMenu.addItem(actionItem(loc("Claude: izin istesin (İzin ver / Reddet)", "Claude: ask for permission (Allow / Deny)"), #selector(demoApproval)))
        demoMenu.addItem(actionItem(loc("Claude: kota uyarısı", "Claude: quota alert"), #selector(demoQuota)))
        demoMenu.addItem(actionItem(loc("İki oturum aynı anda", "Two sessions at once"), #selector(demoParallel)))
        demoMenu.addItem(.separator())
        demoMenu.addItem(actionItem(loc("Test bildirimi gönder", "Send a test notification"), #selector(testNotification)))
        demo.submenu = demoMenu

        let help = NSMenuItem(title: loc("Yardım", "Help"), action: nil, keyEquivalent: "")
        let helpMenu = NSMenu()
        helpMenu.autoenablesItems = false
        helpMenu.addItem(actionItem(loc("Robotu bu masaüstüne getir", "Bring robot to this desktop"), #selector(bringRobotHere)))
        helpMenu.addItem(actionItem(loc("Kurulum sihirbazı…", "Setup assistant…"), #selector(openOnboarding)))
        helpMenu.addItem(demo)
        helpMenu.addItem(.separator())
        helpMenu.addItem(actionItem(loc("Hata bildir…", "Report a problem…"), #selector(reportBug)))
        helpMenu.addItem(actionItem(loc("Teşhis…", "Diagnostics…"), #selector(openDiagnostics)))
        if FileManager.default.fileExists(atPath: AppWatcher.debugFile.path) {
            helpMenu.addItem(actionItem(loc("Algılama günlüğünü aç", "Open detection log"), #selector(openDebugLog)))
        }
        helpMenu.addItem(.separator())
        helpMenu.addItem(actionItem(loc("Ayar klasörünü aç", "Open settings folder"), #selector(openSupportDir)))
        helpMenu.addItem(actionItem(loc("Renkleri ve kostümleri yeniden yükle", "Reload colors and skins"), #selector(reloadAppearance)))
        help.submenu = helpMenu
        menu.addItem(help)

        menu.addItem(.separator())
        menu.addItem(actionItem(loc("Çıkış", "Quit"), #selector(quit), key: "q"))

        applyMenuTitles(menu)
        statusItem?.menu = menu
    }

    private func actionItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func toggleItem(_ title: String, on: Bool, action: Selector) -> NSMenuItem {
        let item = actionItem(title, action)
        item.state = on ? .on : .off
        return item
    }

    // MARK: - Eylemler

    @objc private func showRobotHistory(_ sender: NSMenuItem) {
        guard let source = sender.representedObject as? String else { return }
        manager.showHistory(source: source)
    }

    @objc private func toggleLaunchAtLogin() {
        let on = !(LaunchAtLogin.isEnabled || LaunchAtLogin.needsApproval)
        if let error = LaunchAtLogin.set(on) {
            let alert = NSAlert()
            alert.messageText = loc("Ayarlanamadı", "Couldn't change it")
            alert.informativeText = error
            alert.runModal()
        } else if on && LaunchAtLogin.needsApproval {
            LaunchAtLogin.openSystemSettings()
        }
        rebuildMenu()
    }

    @objc private func toggleRobots() {
        manager.visible.toggle()
        rebuildMenu()
    }

    @objc private func toggleAlwaysOnTop() {
        manager.setAlwaysOnTop(!Preferences.alwaysOnTop)
        rebuildMenu()
    }

    @objc private func toggleLock() {
        manager.setLocked(!manager.isLocked)
        rebuildMenu()
    }

    @objc private func bringRobotHere() {
        manager.bringRobotHere()
    }

    @objc private func toggleNotifications() {
        Preferences.notificationsEnabled.toggle()
        rebuildMenu()
    }

    @objc private func toggleSpeak() {
        Preferences.speak.toggle()
        if Preferences.speak { Speech.say(loc("Merhaba, ben TelepAIth.", "Hi, I'm TelepAIth.")) }
        rebuildMenu()
    }

    // MARK: Yeni menü eylemleri

    @objc private func openNotificationSettings() {
        Notifier.openSettings()
    }

    @objc private func focusHour() {
        FocusMode.turnOn(for: 3600)
        manager.focusChanged()
        rebuildMenu()
    }

    @objc private func focusForever() {
        FocusMode.turnOn(for: nil)
        manager.focusChanged()
        rebuildMenu()
    }

    @objc private func focusOff() {
        FocusMode.turnOff()
        manager.focusChanged()
        rebuildMenu()
    }

    @objc private func toggleAutoFocus() {
        Preferences.autoFocusInMeetings.toggle()
        manager.focusChanged()
        rebuildMenu()
    }

    @objc private func showSummaryAction() {
        manager.showSummary()
    }

    @objc func openRoom() {
        RoomWindow.shared.show(host: self)
    }

    @objc func openSettings() {
        rebuildMenu()
        SettingsWindow.shared.show(host: self)
    }

    @objc private func openOnboarding() {
        OnboardingWindow.shared.show(host: self)
    }

    @objc private func testNotification() {
        Notifier.shared.sendTest()
    }

    @objc func reportBug() {
        rebuildMenu()
        BugReport.open()
    }

    @objc private func demoParallel() {
        let a = "demo-\(Int.random(in: 1000...9999))"
        let b = "demo-\(Int.random(in: 1000...9999))"
        play([
            (0, AgentEvent(source: "claude", sessionID: a, kind: .prompt, state: .thinking,
                           text: loc("Düşünüyor…", "Thinking…"), project: "api", emoji: "🔮")),
            (1, AgentEvent(source: "claude", sessionID: b, kind: .prompt, state: .thinking,
                           text: loc("Düşünüyor…", "Thinking…"), project: "web", emoji: "🔮")),
            (2, AgentEvent(source: "gpt", sessionID: b + "g", kind: .tool, state: .running,
                           text: loc("Komut: ", "Command: ") + "npm test", project: "mobile", emoji: "🧪")),
            (4, AgentEvent(source: "claude", sessionID: a, kind: .tool, state: .editing,
                           text: loc("Düzenliyor: ", "Editing ") + "server.ts", project: "api", emoji: "✍️")),
            (6, AgentEvent(source: "claude", sessionID: b, kind: .waiting, state: .waiting,
                           text: loc("Onayını bekliyor: ", "Needs your approval: ") + "rm -rf dist", project: "web", emoji: "✋")),
            (12, AgentEvent(source: "claude", sessionID: b, kind: .toolDone)),
            (13, AgentEvent(source: "gpt", sessionID: b + "g", kind: .stop, state: .done, project: "mobile")),
            (15, AgentEvent(source: "claude", sessionID: a, kind: .stop, state: .done, project: "api")),
            (16, AgentEvent(source: "claude", sessionID: b, kind: .stop, state: .done, project: "web")),
        ])
    }

    @objc private func toggleShield() {
        setShield(!Preferences.shield)
    }

    @objc private func openDiagnostics() {
        rebuildMenu()
        DiagnosticsWindow.shared.show()
    }

    @objc private func toggleNarrator() {
        setNarrator(on: !NarratorInstaller.isInstalled())
    }

    func setNarrator(on: Bool) {
        do {
            if !on {
                if NarratorInstaller.isInstalled() { try NarratorInstaller.uninstall() }
            } else if !NarratorInstaller.isInstalled() {
                try NarratorInstaller.install()
                NSApp.activate(ignoringOtherApps: true)
                let alert = NSAlert()
                alert.messageText = loc("Anlatıcı Claude masaüstüne eklendi", "Narrator added to Claude desktop")
                let trText = "1) Claude uygulamasını kapatıp yeniden aç.\n"
                    + "2) Claude'un ne zaman haber vereceğini bilmesi için bu talimatı Claude → Ayarlar → Profil'deki tercihlere ekle (aşağıdaki düğme kopyalar):\n\n"
                    + NarratorInstaller.suggestedInstruction
                    + "\n\nClaude Code için Terminal'de bir kere:\n" + NarratorInstaller.claudeCodeCommand
                let enText = "1) Quit and reopen the Claude app.\n"
                    + "2) Add this to Claude → Settings → Profile preferences so Claude knows when to report (the button copies it):\n\n"
                    + NarratorInstaller.suggestedInstruction
                    + "\n\nFor Claude Code, run once in Terminal:\n" + NarratorInstaller.claudeCodeCommand
                alert.informativeText = loc(trText, enText)
                alert.addButton(withTitle: loc("Talimatı kopyala", "Copy instruction"))
                alert.addButton(withTitle: loc("Claude Code komutunu kopyala", "Copy Claude Code command"))
                alert.addButton(withTitle: loc("Tamam", "OK"))
                let response = alert.runModal()
                if response == .alertFirstButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(NarratorInstaller.suggestedInstruction, forType: .string)
                } else if response == .alertSecondButtonReturn {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(NarratorInstaller.claudeCodeCommand, forType: .string)
                }
            }
        } catch {
            showAlert(title: loc("Anlatıcı eklenemedi", "Couldn't add the narrator"), text: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func toggleSounds() {
        Preferences.sounds.toggle()
        rebuildMenu()
    }

    @objc private func toggleWatchApps() {
        setWatchApps(!Preferences.watchApps)
    }

    func setWatchApps(_ on: Bool) {
        guard on != Preferences.watchApps else { return }
        manager.setWatchApps(on)
        if on && !AppWatcher.isTrusted {
            showAlert(title: loc("Erişilebilirlik izni", "Accessibility permission"),
                      text: loc("Claude ve ChatGPT masaüstü uygulamalarının ne zaman çalıştığını görebilmem için Sistem Ayarları → Gizlilik ve Güvenlik → Erişilebilirlik'te TelepAIth'i aç.\n\nAçık görünüp yine de çalışmıyorsa menüden \"İzni sıfırla ve yeniden iste\"yi kullan.",
                                "To see when the Claude and ChatGPT desktop apps are working, turn on TelepAIth in System Settings → Privacy & Security → Accessibility.\n\nNote: after each update you may need to turn this permission off and on again."))
            AppWatcher.openAccessibilitySettings()
        }
        rebuildMenu()
    }

    @objc private func openAccessibility() {
        AppWatcher.openAccessibilitySettings()
    }

    @objc private func resetAccessibility() {
        AppWatcher.resetAndRequestTrust()
    }

    @objc private func openDebugLog() {
        NSWorkspace.shared.open(AppWatcher.debugFile)
    }

    @objc private func toggleFollow() {
        Preferences.followAppWindow.toggle()
        manager.followSettingChanged()
        rebuildMenu()
    }

    @objc private func toggleChatter() {
        Preferences.idleChatter.toggle()
        rebuildMenu()
    }

    @objc private func toggleEmoji() {
        Preferences.emojiEnabled.toggle()
        rebuildMenu()
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let lang = Language(rawValue: raw) else { return }
        Language.set(lang)
        rebuildMenu()
    }

    @objc private func toggleHook(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let target = HookTarget(rawValue: raw) else { return }
        setHook(target, on: !HookInstaller.isInstalled(target), quiet: false)
    }

    func setHook(_ target: HookTarget, on: Bool, quiet: Bool) {
        do {
            if !on {
                if HookInstaller.isInstalled(target) { try HookInstaller.uninstall(target) }
            } else if !HookInstaller.isInstalled(target) {
                try HookInstaller.install(target)
                manager.model(for: target.source)
                if quiet {
                    rebuildMenu()
                    return
                }
                let info: String
                switch target {
                case .claude:
                    info = loc("Yeni açacağın Claude Code oturumları robota haber verecek. Açık oturumlar yeniden başlatılınca bağlanır.\n\nAyarların yedeği: ~/.claude/settings.json.telepaith-backup",
                               "New Claude Code sessions will report to the robot. Open sessions connect after a restart.\n\nBackup of your settings: ~/.claude/settings.json.telepaith-backup")
                case .codex:
                    info = loc("Codex yeni hook'lar için onay istiyor: Codex'i bir sonraki açışında /hooks yazıp TelepAIth hook'larını onayla. Sonra yeni oturumlar robota haber verecek.",
                               "Codex asks you to approve new hooks: next time you open Codex, type /hooks and approve the TelepAIth hooks. New sessions will then report to the robot.")
                }
                showAlert(title: target.displayName + loc(" bağlandı", " connected"), text: info)
            }
        } catch {
            showAlert(title: loc("Bağlanamadı", "Couldn't connect"), text: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc func showClaudeBarHelp() {
        let url = "http://localhost:\(server.port > 0 ? server.port : AppInfo.defaultPort)/claudebar"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = loc("ClaudeBar kota uyarılarını robota bağla", "Send ClaudeBar quota alerts to the robot")
        alert.informativeText = loc("""
        ClaudeBar → Settings → Sync & Alerts → Webhooks → Add Webhook:

        URL: \(url)
        Channel: JSON
        Sends: Quota alerts ve Status alerts

        Sonra "Send a test" ile dene. Kota azalınca ilgili robot uyarır.
        """, """
        ClaudeBar → Settings → Sync & Alerts → Webhooks → Add Webhook:

        URL: \(url)
        Channel: JSON
        Sends: Quota alerts and Status alerts

        Then press "Send a test". The matching robot warns you when quota runs low.
        """)
        alert.addButton(withTitle: loc("URL'yi kopyala", "Copy URL"))
        alert.addButton(withTitle: loc("Tamam", "OK"))
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }

    @objc private func demoClaude() {
        let s = "demo-\(Int.random(in: 1000...9999))"
        let p = "demo-app"
        play([
            (0, AgentEvent(source: "claude", sessionID: s, kind: .prompt, state: .thinking,
                           text: loc("Düşünüyor…", "Thinking…"), project: p, emoji: "🔮")),
            (2, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .reading,
                           text: loc("Okuyor: ", "Reading ") + "App.swift", project: p, emoji: "📖")),
            (5, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .editing,
                           text: loc("Düzenliyor: ", "Editing ") + "App.swift", project: p, emoji: "✍️")),
            (8, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .running,
                           text: loc("Komut: ", "Command: ") + "swift test", project: p, emoji: "🧪")),
            (12, AgentEvent(source: "claude", sessionID: s, kind: .stop, state: .done, project: p,
                            lastMessage: loc("Testler geçti, değişiklik hazır.", "Tests pass, the change is ready."),
                            forceNotify: true)),
        ])
    }

    @objc private func demoGPTWaiting() {
        let s = "demo-\(Int.random(in: 1000...9999))"
        let p = "web-app"
        play([
            (0, AgentEvent(source: "gpt", sessionID: s, kind: .prompt, state: .thinking,
                           text: loc("Düşünüyor…", "Thinking…"), project: p, emoji: "🔮")),
            (2, AgentEvent(source: "gpt", sessionID: s, kind: .tool, state: .searching,
                           text: loc("Arıyor: ", "Searching for ") + "useEffect", project: p, emoji: "🔍")),
            (5, AgentEvent(source: "gpt", sessionID: s, kind: .waiting, state: .waiting,
                           text: loc("Onayını bekliyor: ", "Needs your approval: ") + "Bash — npm install",
                           project: p, emoji: "✋")),
            (11, AgentEvent(source: "gpt", sessionID: s, kind: .toolDone)),
            (12, AgentEvent(source: "gpt", sessionID: s, kind: .tool, state: .running,
                            text: loc("Komut: ", "Command: ") + "npm install", project: p, emoji: "📦")),
            (15, AgentEvent(source: "gpt", sessionID: s, kind: .stop, state: .done, project: p)),
        ])
    }

    /// Robottan onayı denemek için: gerçek akışın aynısı, sadece karar Claude Code yerine bu örneğe gider
    @objc private func demoApproval() {
        let s = "demo-\(Int.random(in: 1000...9999))"
        let p = "demo-app"
        manager.handle(AgentEvent(source: "claude", sessionID: s, kind: .prompt, state: .thinking,
                                  text: loc("Düşünüyor…", "Thinking…"), project: p, emoji: "🔮"))
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            var e = AgentEvent(source: "claude", sessionID: s, kind: .waiting, state: .waiting,
                               text: loc("Onayını bekliyor: ", "Needs your approval: ") + "Bash — npm install",
                               project: p, emoji: "✋")
            e.forceNotify = false
            let body = Data(#"{"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm install"}],"behavior":"allow","destination":"localSettings"}]}"#.utf8)
            let pending = PendingApproval(event: e, body: body) { [weak self] answer in
                DispatchQueue.main.async {
                    guard let self = self, !answer.isEmpty else { return }
                    if answer.contains("\"deny\"") {
                        self.play([(2.6, AgentEvent(source: "claude", sessionID: s, kind: .stop, state: .done,
                                                    text: loc("Peki, npm install'ı atladım (demo).", "OK, skipped npm install (demo)."), project: p))])
                    } else {
                        self.play([
                            (2.6, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .running,
                                             text: loc("Komut: ", "Command: ") + "npm install", project: p, emoji: "📦")),
                            (5.5, AgentEvent(source: "claude", sessionID: s, kind: .stop, state: .done, project: p)),
                        ])
                    }
                }
            }
            self.manager.onPermission(pending)
        }
    }

    @objc private func demoQuota() {
        manager.handle(AgentEvent(source: "claude", sessionID: "claudebar", kind: .quota,
                                  text: loc("Kalan kota: %18 (demo)", "Quota left: 18% (demo)"),
                                  forceNotify: true, emoji: "🔋"))
    }

    private func play(_ steps: [(TimeInterval, AgentEvent)]) {
        for (delay, event) in steps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.manager.handle(event)
            }
        }
    }

    @objc private func openSupportDir() {
        NSWorkspace.shared.open(AppInfo.supportDir)
    }

    @objc private func reloadAppearance() {
        Themes.shared.reload()
        manager.reloadAppearance()
        rebuildMenu()
    }

    @objc private func installUpdate() {
        Updater.shared.promptInstall()
    }

    @objc private func checkForUpdates() {
        Updater.shared.check(userInitiated: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func showAlert(title: String, text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}


// MARK: - Ayarlar penceresi ve kurulum sihirbazı için

extension AppController: RoomHost {
    var roomUsage: [UsageWindow] { manager.usageWindows }
    var roomSource: String { manager.currentSource }
}

extension AppController: SettingsHost {
    var robotVisible: Bool {
        get { manager.visible }
        set {
            manager.visible = newValue
            rebuildMenu()
        }
    }

    var robotLocked: Bool { manager.isLocked }
    var serverPort: UInt16 { server.port }
    var watcherStatus: [String: String] { manager.watcherStatus }

    func setRobotLocked(_ value: Bool) {
        manager.setLocked(value)
        rebuildMenu()
    }

    func setAlwaysOnTop(_ value: Bool) {
        manager.setAlwaysOnTop(value)
        rebuildMenu()
    }

    func setRobotScale(_ value: Double) {
        manager.setRobotScale(value)
        rebuildMenu()
    }

    func followSettingChanged() {
        manager.followSettingChanged()
        rebuildMenu()
    }

    func setUsageLine(on: Bool) {
        do {
            if on { try UsageLine.connect() } else { try UsageLine.disconnect() }
        } catch {
            let alert = NSAlert()
            alert.messageText = loc("Bağlanamadı", "Couldn't connect")
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        rebuildMenu()
    }

    func setShield(_ on: Bool) {
        Preferences.shield = on
        if HookInstaller.isInstalled(.claude) { try? HookInstaller.install(.claude) }
        rebuildMenu()
    }

    func focusChanged() {
        manager.focusChanged()
        rebuildMenu()
    }

    func showSummary() {
        manager.showSummary()
    }

    func settingsChanged() {
        rebuildMenu()
    }
}
