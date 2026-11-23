import AppKit
import SwiftUI

/// Ayarlar penceresinin ve kurulum sihirbazının uygulamadan istedikleri (AppController sağlar).
protocol SettingsHost: AnyObject {
    var robotVisible: Bool { get set }
    var robotLocked: Bool { get }
    var serverPort: UInt16 { get }
    var watcherStatus: [String: String] { get }
    func setRobotLocked(_ value: Bool)
    func setAlwaysOnTop(_ value: Bool)
    func setRobotScale(_ value: Double)
    func followSettingChanged()
    func setWatchApps(_ value: Bool)
    /// quiet: bilgi pencerelerini gösterme (sihirbazda)
    func setHook(_ target: HookTarget, on: Bool, quiet: Bool)
    func setNarrator(on: Bool)
    func setShield(_ on: Bool)
    func focusChanged()
    func showClaudeBarHelp()
    func showSummary()
    func settingsChanged()
}

/// Ayarlar ve sihirbaz için canlı durum: pencere açıkken saniyede bir yenilenir
/// (izin verildi mi, hook bağlı mı, bildirim izni…).
final class SettingsModel: ObservableObject {
    weak var host: SettingsHost?
    @Published private(set) var revision = 0
    private var timer: Timer?

    init(host: SettingsHost) {
        self.host = host
    }

    func startRefreshing() {
        guard timer == nil else { return }
        Notifier.shared.refreshStatus()
        let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Notifier.shared.refreshStatus()
            self?.revision += 1
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopRefreshing() {
        timer?.invalidate()
        timer = nil
    }

    func changed() {
        revision += 1
        host?.settingsChanged()
    }

    /// Preferences'a bağlı bir anahtar; değişince menü de yenilenir.
    func toggle(_ get: @escaping () -> Bool, _ set: @escaping (Bool) -> Void) -> Binding<Bool> {
        Binding(get: get, set: { [weak self] value in
            set(value)
            self?.changed()
        })
    }
}

// MARK: - Ayarlar

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        TabView {
            general.tabItem { Label(loc("Genel", "General"), systemImage: "gearshape") }
            notifications.tabItem { Label(loc("Bildirimler", "Notifications"), systemImage: "bell") }
            focus.tabItem { Label(loc("Odak ve özet", "Focus & summary"), systemImage: "moon") }
            connections.tabItem { Label(loc("Bağlantılar", "Connections"), systemImage: "link") }
        }
        .padding(16)
        .frame(width: 560, height: 470)
        .id(model.revision >= 0 ? Language.current.rawValue : "")   // dil değişince yeniden çiz
    }

    // MARK: Genel

    private var general: some View {
        Form {
            Section {
                Picker(loc("Dil", "Language"), selection: Binding(get: { Language.current }, set: { lang in
                    Language.set(lang)
                    model.changed()
                })) {
                    ForEach(Language.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Picker(loc("Robot boyutu", "Robot size"), selection: Binding(get: { Preferences.robotScale }, set: { value in
                    model.host?.setRobotScale(value)
                    model.changed()
                })) {
                    ForEach(Layout.scaleOptions, id: \.0) { option in
                        Text(loc(option.1, option.2) + " (%\(Int(option.0 * 100)))").tag(option.0)
                    }
                }
                Toggle(loc("Robotu göster", "Show the robot"), isOn: model.toggle({ model.host?.robotVisible ?? true },
                                                                                  { model.host?.robotVisible = $0 }))
                Toggle(loc("Her zaman üstte", "Always on top"), isOn: model.toggle({ Preferences.alwaysOnTop },
                                                                                  { model.host?.setAlwaysOnTop($0) }))
                Toggle(loc("Kilitli (yerinde kalsın, AI pencerelerine gitmesin)", "Locked (stay put, don't follow AI windows)"),
                       isOn: model.toggle({ model.host?.robotLocked ?? false }, { model.host?.setRobotLocked($0) }))
                Toggle(loc("Claude/ChatGPT'ye geçince o pencerenin köşesine gitsin", "Fly to the Claude/ChatGPT window corner"),
                       isOn: model.toggle({ Preferences.followAppWindow }, { value in
                           Preferences.followAppWindow = value
                           model.host?.followSettingChanged()
                       }))
            }
            Section {
                Toggle(loc("Aynı anda çalışan oturumları minik kafalarla göster", "Show other running sessions as mini heads"),
                       isOn: model.toggle({ Preferences.miniHeads }, { Preferences.miniHeads = $0 }))
                Toggle(loc("Eyleme göre emojiler", "Emojis for each action"),
                       isOn: model.toggle({ Preferences.emojiEnabled }, { Preferences.emojiEnabled = $0 }))
                Toggle(loc("Boştayken ara sıra laf atsın", "Idle chatter"),
                       isOn: model.toggle({ Preferences.idleChatter }, { Preferences.idleChatter = $0 }))
                Toggle(loc("Kısa sesler", "Short sounds"),
                       isOn: model.toggle({ Preferences.sounds }, { Preferences.sounds = $0 }))
                Toggle(loc("Önemli anları sesli söylesin", "Say important moments out loud"),
                       isOn: model.toggle({ Preferences.speak }, { value in
                           Preferences.speak = value
                           if value { Speech.say(loc("Merhaba, ben TelepAIth.", "Hi, I'm TelepAIth.")) }
                       }))
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Bildirimler

    private var notifications: some View {
        let status = Notifier.shared.status
        return Form {
            Section {
                HStack {
                    Text(loc("macOS izni", "macOS permission"))
                    Spacer()
                    Circle().fill(status == .authorized ? Color.green : (status == .denied ? Color.red : Color.orange))
                        .frame(width: 8, height: 8)
                    Text(status.text).foregroundColor(.secondary)
                }
                if status == .denied {
                    Text(loc("Bildirimler macOS'ta kapalı. Sistem Ayarları → Bildirimler → TelepAIth'te \"Bildirimlere izin ver\"i aç.",
                             "Notifications are turned off in macOS. Turn on \"Allow notifications\" in System Settings → Notifications → TelepAIth."))
                        .font(.callout).foregroundColor(.secondary)
                }
                HStack {
                    if status == .notDetermined {
                        Button(loc("İzin iste", "Ask for permission")) { Notifier.shared.requestPermission { _ in model.changed() } }
                    }
                    Button(loc("Sistem Ayarları'nı aç", "Open System Settings")) { Notifier.openSettings() }
                    Spacer()
                    Button(loc("Test bildirimi gönder", "Send a test notification")) { Notifier.shared.sendTest() }
                }
                if let error = Notifier.shared.lastError {
                    Text(loc("Son hata: ", "Last error: ") + error).font(.caption).foregroundColor(.secondary)
                }
            }
            Section {
                Toggle(loc("Bildirimler", "Notifications"),
                       isOn: model.toggle({ Preferences.notificationsEnabled }, { Preferences.notificationsEnabled = $0 }))
                Toggle(loc("O uygulamaya bakarken de bildir", "Notify even while I'm looking at that app"),
                       isOn: model.toggle({ Preferences.notifyWhenFrontmost }, { Preferences.notifyWhenFrontmost = $0 }))
                Toggle(loc("Uzun süre onay beklerse ısrar etsin (sallansın, 2 dk sonra hatırlatsın)",
                           "Nag when it waits a long time for approval (wiggle, remind after 2 min)"),
                       isOn: model.toggle({ Preferences.waitReminders }, { Preferences.waitReminders = $0 }))
                HStack {
                    Text(loc("\"Bitti\" bildirimi için en az", "\"Done\" notification after at least"))
                    Spacer()
                    Picker("", selection: Binding(get: { Int(Preferences.longTurnSeconds) }, set: { value in
                        Preferences.longTurnSeconds = Double(value)
                        model.changed()
                    })) {
                        ForEach([0, 10, 20, 60, 180], id: \.self) { s in
                            Text(s == 0 ? loc("her zaman", "always") : formatDuration(Double(s))).tag(s)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 130)
                }
            }
            Section {
                Text(loc("Bildirime ya da robotun balonuna tıklayınca o işin penceresine (Claude, ChatGPT ya da terminal) gidersin.",
                         "Click a notification or the robot's bubble to jump to that task's window (Claude, ChatGPT or your terminal)."))
                    .font(.callout).foregroundColor(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    // MARK: Odak ve özet

    private var focus: some View {
        Form {
            Section {
                HStack {
                    Text(loc("Odak modu", "Focus mode"))
                    Spacer()
                    Text(FocusMode.statusText).foregroundColor(.secondary)
                }
                HStack {
                    Button(loc("1 saat", "1 hour")) { FocusMode.turnOn(for: 3600); after() }
                    Button(loc("Kapatana kadar", "Until I turn it off")) { FocusMode.turnOn(for: nil); after() }
                    Button(loc("Kapat", "Turn off")) { FocusMode.turnOff(); after() }.disabled(!FocusMode.manualActive)
                }
                Toggle(loc("Toplantıdayken kendiliğinden aç (Zoom/Teams öndeyken ya da mikrofon kullanımdayken)",
                           "Turn on automatically in meetings (Zoom/Teams in front, or microphone in use)"),
                       isOn: model.toggle({ Preferences.autoFocusInMeetings }, { value in
                           Preferences.autoFocusInMeetings = value
                           model.host?.focusChanged()
                       }))
                Text(loc("Odak modunda robot soluk durur ve susar; sadece seni bekleyen şeyleri ve hataları söyler.",
                         "In focus mode the robot dims and stays quiet; it only tells you what needs you, and errors."))
                    .font(.callout).foregroundColor(.secondary)
            }
            Section {
                Toggle(loc("Akşam günün özetini söylesin", "Tell me a summary of the day in the evening"),
                       isOn: model.toggle({ Preferences.dailySummary }, { Preferences.dailySummary = $0 }))
                Picker(loc("Saat", "Time"), selection: Binding(get: { Preferences.dailySummaryHour }, set: { value in
                    Preferences.dailySummaryHour = value
                    model.changed()
                })) {
                    ForEach(15..<23, id: \.self) { Text(String(format: "%02d:00", $0)).tag($0) }
                }
                .disabled(!Preferences.dailySummary)
                Button(loc("Bugünün özetini şimdi göster", "Show today's summary now")) { model.host?.showSummary() }
            }
        }
        .formStyle(.grouped)
    }

    private func after() {
        model.host?.focusChanged()
        model.changed()
    }

    // MARK: Bağlantılar

    private var connections: some View {
        Form {
            Section(header: Text(loc("Masaüstü uygulamaları", "Desktop apps"))) {
                Toggle(loc("Claude ve ChatGPT uygulamalarını izle", "Watch the Claude and ChatGPT apps"),
                       isOn: model.toggle({ Preferences.watchApps }, { model.host?.setWatchApps($0) }))
                if Preferences.watchApps {
                    if AppWatcher.isTrusted {
                        let status = model.host?.watcherStatus ?? [:]
                        if status.isEmpty {
                            Text(loc("Claude ya da ChatGPT açık değil.", "Claude or ChatGPT isn't open."))
                                .foregroundColor(.secondary)
                        }
                        ForEach(status.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                            HStack { Text(item.key); Spacer(); Text(item.value).foregroundColor(.secondary) }
                        }
                    } else {
                        HStack {
                            Text("⚠︎ " + loc("Erişilebilirlik izni gerekli", "Accessibility permission needed"))
                            Spacer()
                            Button(loc("Ayarları aç", "Open Settings")) {
                                AppWatcher.requestTrust()
                                AppWatcher.openAccessibilitySettings()
                            }
                            Button(loc("Sıfırla", "Reset")) { AppWatcher.resetAndRequestTrust() }
                        }
                    }
                }
            }
            Section(header: Text(loc("Kodlama ajanları", "Coding agents"))) {
                Toggle("Claude Code", isOn: model.toggle({ HookInstaller.isInstalled(.claude) },
                                                         { model.host?.setHook(.claude, on: $0, quiet: false) }))
                if HookInstaller.isInstalled(.claude) {
                    Toggle(loc("Kalkan: tehlikeli komutlarda onay iste", "Shield: ask before risky commands"),
                           isOn: model.toggle({ Preferences.shield }, { model.host?.setShield($0) }))
                        .padding(.leading, 16)
                    Toggle(loc("Robottan onay ver (balonda İzin ver / Reddet)", "Approve from the robot (Allow / Deny in the bubble)"),
                           isOn: model.toggle({ Preferences.approveFromRobot }, { Preferences.approveFromRobot = $0 }))
                        .padding(.leading, 16)
                        .help(loc("Terminale bakıyorsan soru terminalde sorulur.", "If you're looking at the terminal, it asks there."))
                }
                Toggle("Codex", isOn: model.toggle({ HookInstaller.isInstalled(.codex) },
                                                   { model.host?.setHook(.codex, on: $0, quiet: false) }))
            }
            Section(header: Text(loc("Ekstralar", "Extras"))) {
                Toggle(loc("Anlatıcı (Claude ne yaptığını kendisi söylesin)", "Narrator (Claude tells it in its own words)"),
                       isOn: model.toggle({ NarratorInstaller.isInstalled() }, { model.host?.setNarrator(on: $0) }))
                HStack {
                    Text(loc("ClaudeBar kota uyarıları", "ClaudeBar quota alerts"))
                    Spacer()
                    Button(loc("Nasıl bağlanır?", "How to connect")) { model.host?.showClaudeBarHelp() }
                }
            }
        }
        .formStyle(.grouped)
    }
}

final class SettingsWindow: NSObject, NSWindowDelegate {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    private var model: SettingsModel?

    func show(host: SettingsHost) {
        if window == nil {
            let model = SettingsModel(host: host)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 470),
                             styleMask: [.titled, .closable, .miniaturizable],
                             backing: .buffered, defer: false)
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(model: model))
            w.delegate = self
            w.center()
            window = w
            self.model = model
        }
        window?.title = AppInfo.name + " — " + loc("Ayarlar", "Settings")
        model?.startRefreshing()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopRefreshing()
    }
}

// MARK: - İlk açılış sihirbazı

struct OnboardingView: View {
    @ObservedObject var model: SettingsModel
    let onFinish: () -> Void
    @State private var step = 0

    private let steps = 5

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: welcome
                case 1: notificationsStep
                case 2: accessibilityStep
                case 3: connectionsStep
                default: doneStep
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(28)

            Divider()
            HStack {
                HStack(spacing: 6) {
                    ForEach(0..<steps, id: \.self) { i in
                        Circle().fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
                    }
                }
                Spacer()
                if step > 0 && step < steps - 1 {
                    Button(loc("Geri", "Back")) { step -= 1 }
                }
                if step < steps - 1 {
                    Button(step == 0 ? loc("Başlayalım", "Let's go") : loc("İleri", "Next")) { step += 1 }
                        .keyboardShortcut(.defaultAction)
                } else {
                    Button(loc("Bitir", "Finish")) { onFinish() }
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .frame(width: 540, height: 420)
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(size: 22, weight: .bold)).padding(.bottom, 6)
    }

    private func para(_ text: String) -> some View {
        Text(text).font(.body).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func statusRow(_ ok: Bool, _ okText: String, _ badText: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundColor(ok ? .green : .orange)
            Text(ok ? okText : badText).font(.headline)
        }
        .padding(.vertical, 10)
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    title(loc("TelepAIth'e hoş geldin", "Welcome to TelepAIth"))
                    para(loc("Claude ve GPT o an ne yapıyorsa ekranının köşesindeki robot söyler.",
                             "A little robot in your screen corner tells you what Claude and GPT are doing."))
                }
            }
            para(loc("Birkaç adımda izinleri ve bağlantıları kuralım. Hepsini sonra Ayarlar'dan değiştirebilirsin.",
                     "Let's set up permissions and connections in a few steps. You can change all of it later in Settings."))
                .padding(.top, 8)
        }
    }

    private var notificationsStep: some View {
        let status = Notifier.shared.status
        return VStack(alignment: .leading, spacing: 10) {
            title(loc("Bildirimler", "Notifications"))
            para(loc("Uzun bir iş bitince ya da AI senden onay beklerken haber vereyim.",
                     "I'll let you know when a long task finishes or the AI needs your approval."))
            statusRow(status == .authorized, loc("Bildirim izni var", "Notifications allowed"),
                      status == .denied ? loc("Bildirimler macOS'ta kapalı", "Notifications are off in macOS")
                                        : loc("Henüz izin verilmedi", "Not allowed yet"))
            HStack {
                if status == .notDetermined {
                    Button(loc("Bildirimlere izin ver", "Allow notifications")) { Notifier.shared.requestPermission { _ in model.changed() } }
                } else if status == .denied {
                    Button(loc("Sistem Ayarları'nı aç", "Open System Settings")) { Notifier.openSettings() }
                }
                Button(loc("Test bildirimi gönder", "Send a test")) { Notifier.shared.sendTest() }
            }
        }
    }

    private var accessibilityStep: some View {
        let trusted = AppWatcher.isTrusted
        return VStack(alignment: .leading, spacing: 10) {
            title(loc("Claude ve ChatGPT uygulamaları", "The Claude and ChatGPT apps"))
            para(loc("Masaüstü uygulamalarının ne zaman çalıştığını, onay beklediğini ve bitirdiğini görebilmem için Erişilebilirlik izni gerekiyor. Ekrandan okuduklarım hiçbir yere gönderilmez.",
                     "To see when the desktop apps are working, waiting or done, I need Accessibility permission. Nothing I read from the screen leaves your Mac."))
            statusRow(trusted, loc("Erişilebilirlik izni var", "Accessibility allowed"),
                      loc("Erişilebilirlik izni yok", "No Accessibility permission"))
            if !trusted {
                para(loc("Açılan pencerede TelepAIth'i aç. Listede açık görünüyorsa kapatıp yeniden aç ya da Sıfırla'ya bas.",
                         "Turn on TelepAIth in the window that opens. If it already looks on, toggle it off and on, or press Reset."))
                HStack {
                    Button(loc("İzin ver", "Allow")) {
                        if !Preferences.watchApps { model.host?.setWatchApps(true) }
                        AppWatcher.requestTrust()
                        AppWatcher.openAccessibilitySettings()
                    }
                    Button(loc("Sıfırla", "Reset")) { AppWatcher.resetAndRequestTrust() }
                }
            }
            Toggle(loc("Claude ve ChatGPT uygulamalarını izle", "Watch the Claude and ChatGPT apps"),
                   isOn: model.toggle({ Preferences.watchApps }, { model.host?.setWatchApps($0) }))
                .padding(.top, 6)
        }
    }

    private var connectionsStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title(loc("Kodlama ajanları", "Coding agents"))
            para(loc("Terminalde Claude Code ya da Codex kullanıyorsan bağla; her adımı anında görürüm.",
                     "If you use Claude Code or Codex in the terminal, connect them and I'll see every step."))
            Toggle("Claude Code", isOn: model.toggle({ HookInstaller.isInstalled(.claude) },
                                                     { model.host?.setHook(.claude, on: $0, quiet: true) }))
                .padding(.top, 6)
            Toggle("Codex", isOn: model.toggle({ HookInstaller.isInstalled(.codex) },
                                               { model.host?.setHook(.codex, on: $0, quiet: true) }))
            para(loc("Yeni açacağın oturumlar bağlanır. Codex'te bir kere /hooks yazıp onaylaman gerekir.",
                     "New sessions connect. In Codex, type /hooks once and approve."))
                .font(.callout)
        }
    }

    private var doneStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            title(loc("Hazırız 🎉", "All set 🎉"))
            VStack(alignment: .leading, spacing: 8) {
                tip("cursorarrow.rays", loc("Robotu sürükleyip bir köşeye bırak, oraya yapışır.", "Drag the robot near a corner and it snaps there."))
                tip("text.bubble", loc("Balona tıkla: o işin penceresine gidersin.", "Click the bubble to jump to that task's window."))
                tip("hand.tap", loc("Robota tıkla: son olaylar. Çift tıkla: AI uygulamasını aç.", "Click the robot for recent events. Double-click to open the AI app."))
                tip("contextualmenu.and.cursorarrow", loc("Sağ tık: kilit, her zaman üstte, odak modu, günün özeti.", "Right-click: lock, always on top, focus mode, today's summary."))
                tip("menubar.rectangle", loc("Menü çubuğundaki robot ikonu → Ayarlar.", "Menu bar robot icon → Settings."))
            }
            .padding(.top, 4)
        }
    }

    private func tip(_ symbol: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundColor(.accentColor)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}

final class OnboardingWindow: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindow()
    private var window: NSWindow?
    private var model: SettingsModel?

    func show(host: SettingsHost) {
        if window == nil {
            let model = SettingsModel(host: host)
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = AppInfo.name
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(model: model, onFinish: { [weak self] in
                Preferences.onboardingDone = true
                self?.window?.close()
            }))
            w.delegate = self
            w.center()
            window = w
            self.model = model
        }
        model?.startRefreshing()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        model?.stopRefreshing()
        // Pencereyi kapatmak da "tamam" sayılır; sihirbaz menüden yeniden açılabilir
        Preferences.onboardingDone = true
    }
}
