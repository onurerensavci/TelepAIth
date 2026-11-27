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
    /// İndirme durumu (ana iş parçacığında): robot balonda söyler
    var onProgress: ((String) -> Void)?
    private var progressObservation: NSKeyValueObservation?
    private var lastProgressReport = Date.distantPast
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
        // Yarım saatte bir bak; yeni sürüm varsa robot söyler (sağlık ışığı turuncu olur)
        let t = Timer(timeInterval: 30 * 60, repeats: true) { [weak self] _ in
            self?.check(userInitiated: false)
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // MARK: - Denetleme

    func check(userInitiated: Bool) {
        guard let repo = repo, let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            if userInitiated {
                alert(loc("Güncelleme kaynağı yok", "No update source"),
                      loc("Bu kopya bir GitHub deposuna bağlı değil. GitHub Releases'tan indirilen sürümü kullan ya da uygulamayı git deposunun içinden scripts/build-app.sh ile derle.",
                          "This copy isn't linked to a GitHub repository. Use the version from GitHub Releases, or build the app inside the git repository with scripts/build-app.sh."))
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
                    reason = loc("Depoda henüz yayınlanmış bir sürüm yok ya da depo gizli (private).", "The repository has no published release yet, or it is private.")
                } else if let error = error {
                    reason = error.localizedDescription
                } else {
                    reason = loc("GitHub'a ulaşılamadı (HTTP \(status)).", "Couldn't reach GitHub (HTTP \(status)).")
                }
                alert(loc("Güncelleme denetlenemedi", "Couldn't check for updates"), reason)
            }
            return
        }

        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard Updater.isNewer(version, than: currentVersion) else {
            available = nil
            onChange?()
            if userInitiated { alert(loc("Güncelsin", "You're up to date"), loc("\(AppInfo.name) \(currentVersion) en son sürüm.", "\(AppInfo.name) \(currentVersion) is the latest version.")) }
            return
        }

        let assets = json["assets"] as? [[String: Any]] ?? []
        // Windows paketi (Windows-TelepAIth-x64.zip) aynı sürümde durur; Mac onu asla seçmesin
        let zips = assets.filter {
            let name = (($0["name"] as? String) ?? "")
            return name.hasSuffix(".zip") && !name.lowercased().contains("windows")
        }
        let zip = zips.first(where: { (($0["name"] as? String) ?? "").hasPrefix(AppInfo.name) }) ?? zips.first

        guard let urlString = zip?["browser_download_url"] as? String, let assetURL = URL(string: urlString) else {
            if userInitiated {
                alert(loc("Güncelleme hazır değil", "Update not ready"),
                      loc("\(version) sürümü yayınlanmış ama .zip dosyası henüz yüklenmemiş. Birkaç dakika sonra tekrar dene.",
                          "Version \(version) is published but its .zip isn't uploaded yet. Try again in a few minutes."))
            }
            return
        }

        let pageURL = (json["html_url"] as? String).flatMap { URL(string: $0) }
        let release = Release(version: version, notes: (json["body"] as? String) ?? "", assetURL: assetURL, pageURL: pageURL)
        let isNew = available?.version != version
        available = release
        onChange?()

        if userInitiated {
            installNow()
        } else if isNew {
            Notifier.shared.notify(title: withEmoji("⬆️", loc("\(AppInfo.name) \(version) hazır", "\(AppInfo.name) \(version) is ready")),
                                   body: loc("Menü çubuğundaki ikondan güncelleyebilirsin.", "Update it from the menu bar icon."), kind: "summary")
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

    /// Güncelle: pencere sormadan indirir, kurar ve yeniden başlatır (robot ilerlemeyi balonda söyler,
    /// açılınca da ne geldiğini anlatır)
    func installNow() {
        guard let release = available, !isBusy else { return }
        install(release)
    }

    private func install(_ release: Release) {
        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            alert(loc("Güncellenemedi", "Update failed"), loc("Uygulama .app olarak çalışmıyor (swift run ile mi açtın?).", "The app isn't running as an .app bundle (did you start it with swift run?)."))
            return
        }
        let parent = appURL.deletingLastPathComponent().path
        guard FileManager.default.isWritableFile(atPath: parent) else {
            alert(loc("Güncellenemedi", "Update failed"),
                  loc("\(parent) klasörüne yazma izni yok. Yeni sürümü sürüm sayfasından elle indir.",
                      "No write permission for \(parent). Download the new version from the release page."))
            if let page = release.pageURL { NSWorkspace.shared.open(page) }
            return
        }

        isBusy = true
        onChange?()
        onProgress?(withEmoji("⬇️", loc("\(release.version) indiriliyor…", "Downloading \(release.version)…")))
        let task = URLSession.shared.downloadTask(with: release.assetURL) { tempURL, _, error in
            // İndirilen dosya bu blok bitince silinir; hemen taşı.
            var zipURL: URL?
            if let tempURL = tempURL {
                let dest = FileManager.default.temporaryDirectory
                    .appendingPathComponent("\(AppInfo.name)-\(UUID().uuidString).zip")
                if (try? FileManager.default.moveItem(at: tempURL, to: dest)) != nil { zipURL = dest }
            }
            DispatchQueue.main.async {
                self.progressObservation = nil
                self.finishInstall(zip: zipURL, error: error, appURL: appURL)
            }
        }
        // İlerleme: "İndiriliyor %42 · 0.4 / 0.9 MB"
        let version = release.version
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            DispatchQueue.main.async {
                guard let self = self, Date().timeIntervalSince(self.lastProgressReport) > 0.4 else { return }
                self.lastProgressReport = Date()
                let done = Double(progress.completedUnitCount) / 1_048_576
                let total = Double(progress.totalUnitCount) / 1_048_576
                let size = total > 0 ? String(format: " · %.1f / %.1f MB", done, total) : ""
                self.onProgress?(withEmoji("⬇️", loc("\(version) indiriliyor", "Downloading \(version)")
                    + " %\(Int(progress.fractionCompleted * 100))" + size))
            }
        }
        task.resume()
    }

    private func finishInstall(zip: URL?, error: Error?, appURL: URL) {
        isBusy = false
        onChange?()
        guard let zip = zip, error == nil else {
            alert(loc("İndirilemedi", "Download failed"), error?.localizedDescription ?? loc("Dosya indirilemedi.", "The file couldn't be downloaded."))
            return
        }
        onProgress?(withEmoji("📦", loc("Kuruluyor, birazdan dönerim…", "Installing, back in a moment…")))
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(AppInfo.name)-update-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
            try Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])
            let items = try FileManager.default.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
            guard let newApp = items.first(where: { $0.pathExtension == "app" }) else {
                throw UpdateError(loc("Zip içinde \(AppInfo.name).app bulunamadı.", "\(AppInfo.name).app wasn't found in the zip."))
            }
            let script = work.appendingPathComponent("install.sh")
            try Updater.installScript.write(to: script, atomically: true, encoding: .utf8)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [script.path, String(ProcessInfo.processInfo.processIdentifier), newApp.path, appURL.path]
            try process.run()
            NSApp.terminate(nil)
        } catch {
            alert(loc("Güncellenemedi", "Update failed"), error.localizedDescription)
        }
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            throw UpdateError(loc("\(tool) başarısız oldu (kod \(process.terminationStatus)).", "\(tool) failed (code \(process.terminationStatus))."))
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
