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
        if let error = serverError { return "Sunucu açılamadı: \(clip(error, 40))" }
        return "\(AppInfo.name) · başlatılıyor…"
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
            let update = actionItem("Güncelle: \(release.version) hazır", #selector(installUpdate))
            update.attributedTitle = NSAttributedString(string: "⬆︎ Güncelle: \(release.version) hazır",
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
        menu.addItem(toggleItem("Robotları göster", on: manager.visible, action: #selector(toggleRobots)))
        menu.addItem(toggleItem("Bildirimler", on: Preferences.notificationsEnabled, action: #selector(toggleNotifications)))

        menu.addItem(.separator())
        let connections = NSMenuItem(title: "Bağlantılar", action: nil, keyEquivalent: "")
        connections.isEnabled = false
        menu.addItem(connections)
        for target in HookTarget.allCases {
            let item = toggleItem(target.displayName, on: HookInstaller.isInstalled(target), action: #selector(toggleHook(_:)))
            item.representedObject = target.rawValue
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let claudeBar = actionItem("ClaudeBar kota uyarıları…", #selector(showClaudeBarHelp))
        claudeBar.indentationLevel = 1
        menu.addItem(claudeBar)

        menu.addItem(.separator())
        let demo = NSMenuItem(title: "Dene", action: nil, keyEquivalent: "")
        let demoMenu = NSMenu()
        demoMenu.addItem(actionItem("Claude: kısa bir görev", #selector(demoClaude)))
        demoMenu.addItem(actionItem("GPT: onay beklesin", #selector(demoGPTWaiting)))
        demoMenu.addItem(actionItem("Claude: kota uyarısı", #selector(demoQuota)))
        demo.submenu = demoMenu
        menu.addItem(demo)
        menu.addItem(actionItem("Ayar klasörünü aç", #selector(openSupportDir)))
        menu.addItem(actionItem("Renkleri ve kostümleri yeniden yükle", #selector(reloadAppearance)))
        let checkTitle = Updater.shared.isBusy ? "Güncelleme indiriliyor…" : "Güncellemeleri denetle…"
        let check = actionItem(checkTitle, #selector(checkForUpdates))
        check.isEnabled = !Updater.shared.isBusy
        menu.addItem(check)

        menu.addItem(.separator())
        menu.addItem(actionItem("Çıkış", #selector(quit), key: "q"))

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
                    info = "Yeni açacağın Claude Code oturumları robota haber verecek. Açık oturumlar yeniden başlatılınca bağlanır.\n\nAyarların yedeği: ~/.claude/settings.json.telepaith-backup"
                case .codex:
                    info = "Codex yeni hook'lar için onay istiyor: Codex'i bir sonraki açışında /hooks yazıp TelepAIth hook'larını onayla. Sonra yeni oturumlar robota haber verecek."
                }
                showAlert(title: "\(target.displayName) bağlandı", text: info)
            }
        } catch {
            showAlert(title: "Bağlanamadı", text: error.localizedDescription)
        }
        rebuildMenu()
    }

    @objc private func showClaudeBarHelp() {
        let url = "http://localhost:\(server.port > 0 ? server.port : AppInfo.defaultPort)/claudebar"
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "ClaudeBar kota uyarılarını robota bağla"
        alert.informativeText = """
        ClaudeBar → Settings → Sync & Alerts → Webhooks → Add Webhook:

        URL: \(url)
        Channel: JSON
        Sends: Quota alerts ve Status alerts

        Sonra "Send a test" ile dene. Kota azalınca ilgili robot uyarır.
        """
        alert.addButton(withTitle: "URL'yi kopyala")
        alert.addButton(withTitle: "Tamam")
        if alert.runModal() == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url, forType: .string)
        }
    }

    @objc private func demoClaude() {
        let s = "demo-\(Int.random(in: 1000...9999))"
        play([
            (0, AgentEvent(source: "claude", sessionID: s, kind: .prompt, state: .thinking, text: "Düşünüyor…", project: "demo-proje")),
            (2, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .reading, text: "Okuyor: App.swift", project: "demo-proje")),
            (5, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .editing, text: "Düzenliyor: App.swift", project: "demo-proje")),
            (8, AgentEvent(source: "claude", sessionID: s, kind: .tool, state: .running, text: "Komut: swift test", project: "demo-proje")),
            (12, AgentEvent(source: "claude", sessionID: s, kind: .stop, state: .done, project: "demo-proje",
                            lastMessage: "Testler geçti, değişiklik hazır.", forceNotify: true)),
        ])
    }

    @objc private func demoGPTWaiting() {
        let s = "demo-\(Int.random(in: 1000...9999))"
        play([
            (0, AgentEvent(source: "gpt", sessionID: s, kind: .prompt, state: .thinking, text: "Düşünüyor…", project: "web-app")),
            (2, AgentEvent(source: "gpt", sessionID: s, kind: .tool, state: .searching, text: "Arıyor: useEffect", project: "web-app")),
            (5, AgentEvent(source: "gpt", sessionID: s, kind: .waiting, state: .waiting,
                           text: "Onayını bekliyor: Bash — npm install", project: "web-app")),
            (11, AgentEvent(source: "gpt", sessionID: s, kind: .toolDone)),
            (12, AgentEvent(source: "gpt", sessionID: s, kind: .tool, state: .running, text: "Komut: npm install", project: "web-app")),
            (15, AgentEvent(source: "gpt", sessionID: s, kind: .stop, state: .done, project: "web-app")),
        ])
    }

    @objc private func demoQuota() {
        manager.handle(AgentEvent(source: "claude", sessionID: "claudebar", kind: .quota,
                                  text: "Kalan kota: %18 (demo)", forceNotify: true))
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
