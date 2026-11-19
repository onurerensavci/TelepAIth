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
        Notifier.shared.setup()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        manager.onChange = { [weak self] in self?.rebuildMenu() }
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
                guard let self = self,
                      let event = EventParser.parse(path: path, query: query, body: body) else { return }
                self.manager.handle(event)
            }
        }
        server.start(preferredPort: AppInfo.defaultPort)

        Updater.shared.onChange = { [weak self] in self?.rebuildMenu() }
        Updater.shared.startAutomaticChecks()

        // Kurulu hook'ları güncel komutla yenile (uygulama güncellenince eski komut kalmasın)
        for target in HookTarget.allCases where HookInstaller.isInstalled(target) {
            try? HookInstaller.install(target)
        }
        rebuildMenu()
    }

    func stop() {
        server.stop()
        try? FileManager.default.removeItem(at: AppInfo.portFile)
    }

    // MARK: - Menü

    private var serverLine: String {
        let version = Updater.shared.currentVersion
        if server.port > 0 { return "\(AppInfo.name) \(version) · 127.0.0.1:\(server.port)" }
        if let error = serverError { return loc("Sunucu açılamadı: ", "Server failed: ") + clip(error, 40) }
        return "\(AppInfo.name) · " + loc("başlatılıyor…", "starting…")
    }

    private func updateIcon() {
        let waiting = manager.models.contains { $0.state == .waiting }
        let image = NSImage(systemSymbolName: waiting ? "exclamationmark.bubble" : "wand.and.stars",
                            accessibilityDescription: AppInfo.name)
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    private func rebuildMenu() {
        updateIcon()
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: serverLine, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)

        if let release = Updater.shared.available {
            let title = "⬆︎ " + loc("Güncelle: \(release.version) hazır", "Update: \(release.version) is ready")
            let update = actionItem(title, #selector(installUpdate))
            update.attributedTitle = NSAttributedString(string: title,
                                                        attributes: [.font: NSFont.boldSystemFont(ofSize: 13)])
            update.isEnabled = !Updater.shared.isBusy
            menu.addItem(update)
        }

        for model in manager.models {
            let item = NSMenuItem(title: "", action: #selector(showRobotHistory(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = model.source
            let title = NSMutableAttributedString(string: "● ", attributes: [.foregroundColor: model.theme.color])
            title.append(NSAttributedString(string: "\(model.theme.displayName) — \(model.statusLine)",
                                            attributes: [.font: NSFont.menuFont(ofSize: 0)]))
            item.attributedTitle = title
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(toggleItem(loc("Robotları göster", "Show robots"), on: manager.visible, action: #selector(toggleRobots)))
        menu.addItem(toggleItem(loc("Bildirimler", "Notifications"), on: Preferences.notificationsEnabled,
                                action: #selector(toggleNotifications)))
        menu.addItem(toggleItem(loc("Emojiler", "Emojis"), on: Preferences.emojiEnabled, action: #selector(toggleEmoji)))

        let language = NSMenuItem(title: loc("Dil", "Language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for lang in Language.allCases {
            let item = toggleItem(lang.displayName, on: Language.current == lang, action: #selector(selectLanguage(_:)))
            item.representedObject = lang.rawValue
            languageMenu.addItem(item)
        }
        language.submenu = languageMenu
        menu.addItem(language)

        menu.addItem(.separator())
        let connections = NSMenuItem(title: loc("Bağlantılar", "Connections"), action: nil, keyEquivalent: "")
        connections.isEnabled = false
        menu.addItem(connections)
        for target in HookTarget.allCases {
            let item = toggleItem(target.displayName, on: HookInstaller.isInstalled(target), action: #selector(toggleHook(_:)))
            item.representedObject = target.rawValue
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let claudeBar = actionItem(loc("ClaudeBar kota uyarıları…", "ClaudeBar quota alerts…"), #selector(showClaudeBarHelp))
        claudeBar.indentationLevel = 1
        menu.addItem(claudeBar)

        menu.addItem(.separator())
        let demo = NSMenuItem(title: loc("Dene", "Try it"), action: nil, keyEquivalent: "")
        let demoMenu = NSMenu()
        demoMenu.addItem(actionItem(loc("Claude: kısa bir görev", "Claude: a short task"), #selector(demoClaude)))
        demoMenu.addItem(actionItem(loc("GPT: onay beklesin", "GPT: wait for approval"), #selector(demoGPTWaiting)))
        demoMenu.addItem(actionItem(loc("Claude: kota uyarısı", "Claude: quota alert"), #selector(demoQuota)))
        demo.submenu = demoMenu
        menu.addItem(demo)
        menu.addItem(actionItem(loc("Ayar klasörünü aç", "Open settings folder"), #selector(openSupportDir)))
        menu.addItem(actionItem(loc("Renkleri ve kostümleri yeniden yükle", "Reload colors and skins"), #selector(reloadAppearance)))
        let checkTitle = Updater.shared.isBusy
            ? loc("Güncelleme indiriliyor…", "Downloading update…")
            : loc("Güncellemeleri denetle…", "Check for updates…")
        let check = actionItem(checkTitle, #selector(checkForUpdates))
        check.isEnabled = !Updater.shared.isBusy
        menu.addItem(check)

        menu.addItem(.separator())
        menu.addItem(actionItem(loc("Çıkış", "Quit"), #selector(quit), key: "q"))

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

    @objc private func toggleRobots() {
        manager.visible.toggle()
        rebuildMenu()
    }

    @objc private func toggleNotifications() {
        Preferences.notificationsEnabled.toggle()
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
        do {
            if HookInstaller.isInstalled(target) {
                try HookInstaller.uninstall(target)
            } else {
                try HookInstaller.install(target)
                manager.controller(for: target.source)
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

    @objc private func showClaudeBarHelp() {
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
