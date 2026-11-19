import AppKit

/// GitHub Releases üzerinden güncelleme.
/// Depo adı derleme sırasında Info.plist'e yazılır (TelepAIthUpdateRepo = "kullanici/TelepAIth").
/// Depo herkese açık (public) olmalı: GitHub API'si gizli depolara anahtarsız erişim vermiyor.
final class Updater {
    struct Release {
        let version: String
        let notes: String
        let assetURL: URL
        let pageURL: URL?
    }

    struct UpdateError: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    static let shared = Updater()

    private(set) var available: Release?
    private(set) var isBusy = false
    var onChange: (() -> Void)?
    private var timer: Timer?

    var repo: String? {
        let raw = (Bundle.main.object(forInfoDictionaryKey: "TelepAIthUpdateRepo") as? String) ?? ""
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.contains("/") ? value : nil
    }

    var currentVersion: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0.0.0"
    }

    func startAutomaticChecks() {
        guard repo != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) { [weak self] in
            self?.check(userInitiated: false)
        }
        let t = Timer(timeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Denetleme

    func check(userInitiated: Bool) {
        guard let repo = repo, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            if userInitiated {
                alert("Güncelleme kaynağı yok",
                      "Bu kopya bir GitHub deposuna bağlı değil. GitHub Releases'tan indirilen sürümü kullan ya da uygulamayı git deposunun içinden scripts/build-app.sh ile derle.")
            }
            return
        }
        guard !isBusy else { return }

        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(AppInfo.name, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.handle(data: data, response: response, error: error, userInitiated: userInitiated)
            }
        }.resume()
    }

    private func handle(data: Data?, response: URLResponse?, error: Error?, userInitiated: Bool) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard error == nil, status == 200, let data = data,
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let tag = json["tag_name"] as? String else {
            if userInitiated {
                let reason: String
                if status == 404 {
                    reason = "Depoda henüz yayınlanmış bir sürüm yok ya da depo gizli (private)."
                } else if let error = error {
                    reason = error.localizedDescription
                } else {
                    reason = "GitHub'a ulaşılamadı (HTTP \(status))."
                }
                alert("Güncelleme denetlenemedi", reason)
            }
            return
        }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Updater.isNewer(version, than: currentVersion) else {
            available = nil
            onChange?()
            if userInitiated { alert("Güncelsin", "\(AppInfo.name) \(currentVersion) en son sürüm.") }
            return
        }

        let assets = json["assets"] as? [[String: Any]] ?? []
        let zips = assets.filter { (($0["name"] as? String) ?? "").hasSuffix(".zip") }
        let zip = zips.first(where: { (($0["name"] as? String) ?? "").hasPrefix(AppInfo.name) }) ?? zips.first

        guard let urlString = zip?["browser_download_url"] as? String, let assetURL = URL(string: urlString) else {
            if userInitiated {
                alert("Güncelleme hazır değil", "\(version) sürümü yayınlanmış ama .zip dosyası henüz yüklenmemiş. Birkaç dakika sonra tekrar dene.")
            }
            return
        }

        let pageURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
        let release = Release(version: version, notes: (json["body"] as? String) ?? "", assetURL: assetURL, pageURL: pageURL)
        let isNew = available?.version != version
        available = release
        onChange?()

        if userInitiated {
            promptInstall()
        } else if isNew {
            Notifier.shared.notify(title: "\(AppInfo.name) \(version) hazır",
                                   body: "Menü çubuğundaki ikondan güncelleyebilirsin.")
        }
    }

    /// "0.10.0" > "0.9.3"
    static func isNewer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] {
            s.split(separator: ".").map { part in Int(part.prefix(while: { $0.isNumber })) ?? 0 }
        }
        let x = parts(a)
        let y = parts(b)
        for i in 0..<Swift.max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0
            let r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: - Kurulum

    func promptInstall() {
        guard let release = available else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "\(AppInfo.name) \(release.version) hazır"
        var info = "Şu anki sürüm: \(currentVersion)"
        if !release.notes.isEmpty {
            info += "\n\n" + String(release.notes.prefix(700))
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Güncelle ve yeniden başlat")
        alert.addButton(withTitle: "Sonra")
        if release.pageURL != nil { alert.addButton(withTitle: "Sürüm sayfası") }

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            install(release)
        } else if response == .alertThirdButtonReturn, let page = release.pageURL {
            NSWorkspace.shared.open(page)
        }
    }

    private func install(_ release: Release) {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            alert("Güncellenemedi", "Uygulama .app olarak çalışmıyor (swift run ile mi açtın?).")
            return
        }
        let parent = appURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            alert("Güncellenemedi", "\(parent) klasörüne yazma izni yok. Yeni sürümü sürüm sayfasından elle indir.")
            if let page = release.pageURL { NSWorkspace.shared.open(page) }
            return
        }

        isBusy = true
        onChange?()
        URLSession.shared.downloadTask(with: release.assetURL) { tempURL, _, error in
            // İndirilen dosya bu blok bitince silinir; hemen taşı.
            var zipURL: URL?
            if let tempURL = tempURL {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(AppInfo.name)-\(UUID().uuidString).zip")
                if (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil { zipURL = dest }
            }
            DispatchQueue.main.async {
                self.finishInstall(zip: zipURL, error: error, appURL: appURL)
            }
        }.resume()
    }

    private func finishInstall(zip: URL?, error: Error?, appURL: URL) {
        isBusy = false
        onChange?()
        guard let zip = zip, error == nil else {
            alert("İndirilemedi", error?.localizedDescription ?? "Dosya indirilemedi.")
            return
        }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppInfo.name)-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let items = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError("Zip içinde \(AppInfo.name).app bulunamadı.")
            }
            let script = work.appendingPathComponent("install.sh")
            try Updater.installScript.write(to: script, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, appURL.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            alert("Güncellenemedi", error.localizedDescription)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw UpdateError("\(tool) başarısız oldu (kod \(process.terminationStatus)).")
        }
    }

    /// Uygulama kapandıktan sonra eski .app'i yenisiyle değiştirir ve yeniden açar.
    /// Bir sorun olursa eski sürümü geri koyar.
    private static let installScript = """
    #!/bin/bash
    PID="$1"; NEW="$2"; DEST="$3"
    case "$DEST" in *.app) ;; *) exit 1 ;; esac
    [ -d "$NEW" ] || exit 1
    for i in $(seq 1 150); do
      kill -0 "$PID" 2>/dev/null || break
      sleep 0.2
    done
    OLD="${DEST%.app}.old.app"
    /bin/rm -rf "$OLD"
    if /bin/mv "$DEST" "$OLD"; then
      if /usr/bin/ditto "$NEW" "$DEST"; then
        /bin/rm -rf "$OLD"
      else
        /bin/rm -rf "$DEST"
        /bin/mv "$OLD" "$DEST"
      fi
    fi
    /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
    /usr/bin/open "$DEST"

    """

    private func alert(_ title: String, _ text: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.runModal()
    }
}
