import Foundation
import ServiceManagement

/// "Mac açılınca başlasın": macOS'un giriş öğeleri (Sistem Ayarları → Genel → Giriş Öğeleri).
enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    /// macOS kullanıcının onayını bekliyorsa (Giriş Öğeleri'nde kapalı görünüyorsa)
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    /// Açar/kapatır. Hata olursa açıklamasını döner.
    @discardableResult
    static func set(_ on: Bool) -> String? {
        do {
            if on {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled || SMAppService.mainApp.status == .requiresApproval {
                    try SMAppService.mainApp.unregister()
                }
            }
            Preferences.launchAtLoginChosen = true
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// İlk açılışta varsayılan olarak açık (Windows'taki gibi); kullanıcı sonra kapatabilir.
    static func applyDefaultOnce() {
        guard !Preferences.launchAtLoginChosen else { return }
        set(true)
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
