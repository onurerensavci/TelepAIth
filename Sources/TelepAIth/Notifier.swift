import AppKit
import UserNotifications

/// macOS bildirimleri.
/// - .app olarak çalışınca Bildirim Merkezi kullanılır; izin yoksa ya da gönderilemezse osascript'e düşer.
/// - İzin durumu takip edilir: kapalıysa menüde ve ayarlarda uyarı çıkar.
/// - Bildirime tıklayınca ilgili uygulama (Claude penceresi, terminal…) öne gelir.
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    /// Son bildirim sesinin çaldığı an (ses en fazla 10 sn'de bir)
    private var lastSoundAt = Date.distantPast

    enum Status: Equatable {
        case unknown, authorized, denied, notDetermined, unavailable

        var text: String {
            switch self {
            case .unknown: return loc("bakılıyor…", "checking…")
            case .authorized: return loc("izin var", "allowed")
            case .denied: return loc("izin kapalı", "turned off")
            case .notDetermined: return loc("izin sorulmadı", "not asked yet")
            case .unavailable: return loc("yedek yöntem (osascript)", "fallback (osascript)")
            }
        }
    }

    private(set) var status: Status = .unknown
    private(set) var lastError: String?
    var onStatusChange: (() -> Void)?
    /// Bildirime tıklanınca: gidilecek yer
    var onClick: ((AppTarget) -> Void)?

    private var canUseCenter: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }

    func setup() {
        guard canUseCenter else {
            setStatus(.unavailable)
            return
        }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.getNotificationSettings { [weak self] settings in
            if settings.authorizationStatus == .notDetermined {
                self?.requestPermission()
            } else {
                self?.refreshStatus()
            }
        }
    }

    /// İzin penceresini açar (daha önce sorulmadıysa). Reddedildiyse Sistem Ayarları'nı açmak gerekir.
    func requestPermission(completion: ((Bool) -> Void)? = nil) {
        guard canUseCenter else { completion?(false); return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            if let error = error { self?.lastError = error.localizedDescription }
            self?.refreshStatus()
            DispatchQueue.main.async { completion?(granted) }
        }
    }

    /// Bildirim izninin güncel durumunu okur (menü açılırken ve ayarlarda çağrılır).
    func refreshStatus() {
        guard canUseCenter else { setStatus(.unavailable); return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let new: Status
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral: new = .authorized
            case .denied: new = .denied
            case .notDetermined: new = .notDetermined
            @unknown default: new = .unknown
            }
            self?.setStatus(new)
        }
    }

    private func setStatus(_ new: Status) {
        DispatchQueue.main.async {
            guard self.status != new else { return }
            self.status = new
            self.onStatusChange?()
        }
    }

    /// Sistem Ayarları → Bildirimler → TelepAIth
    static func openSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.telepaith.app"
        let urls = ["x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)",
                    "x-apple.systempreferences:com.apple.preference.notifications"]
        for s in urls {
            if let url = URL(string: s), NSWorkspace.shared.open(url) { return }
        }
    }

    func notify(title: String, body: String, target: AppTarget? = nil, force: Bool = false) {
        guard force || Preferences.notificationsEnabled else { return }
        guard canUseCenter, status != .denied else {
            fallback(title: title, body: body)
            return
        }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        // Ses en fazla 10 sn'de bir: art arda gelen bildirimler sessiz düşer ("din din din" olmasın)
        let now = Date()
        if now.timeIntervalSince(lastSoundAt) >= 10 {
            content.sound = .default
            lastSoundAt = now
        }
        var info: [String: Any] = [:]
        if let pid = target?.pid { info["pid"] = Int(pid) }
        if let id = target?.bundleID { info["bundle"] = id }
        content.userInfo = info
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            guard let error = error else { return }
            // Bildirim Merkezi reddetti (izin, imza…): yine de haber ver
            self?.lastError = error.localizedDescription
            self?.fallback(title: title, body: body)
            self?.refreshStatus()
        }
    }

    /// Ayarlar ve menüden: "bildirimler çalışıyor mu?"
    func sendTest() {
        refreshStatus()
        notify(title: withEmoji("🔔", AppInfo.name),
               body: loc("Bildirimler çalışıyor. Bunu görüyorsan her şey yolunda.",
                         "Notifications work. If you can see this, you're all set."),
               force: true)
    }

    private func fallback(title: String, body: String) {
        let script = "display notification \(Notifier.quote(body)) with title \(Notifier.quote(title))"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        try? process.run()
    }

    // Uygulama öndeyken de bildirimi göster
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // Bildirime tıklanınca ilgili uygulamaya git
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let info = response.notification.request.content.userInfo
        let target = AppTarget(pid: (info["pid"] as? Int).map { Int32($0) }, bundleID: info["bundle"] as? String)
        DispatchQueue.main.async { [weak self] in
            if !target.isEmpty { self?.onClick?(target) }
        }
        completionHandler()
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
