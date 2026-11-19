import Foundation

/// Claude Code ve Codex'e "olayları TelepAIth'e gönder" hook'larını ekler/kaldırır.
/// İki araç da aynı hooks formatını kullanıyor. Kendi kayıtlarımızı __telepaith_hook işaretiyle tanırız,
/// başka araçların hook'larına dokunmayız.
enum HookTarget: String, CaseIterable {
    case claude
    case codex

    var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex (GPT)"
        }
    }

    var source: String {
        switch self {
        case .claude: return "claude"
        case .codex: return "gpt"
        }
    }

    var fileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            return home.appendingPathComponent(".claude/settings.json")
        case .codex:
            if let custom = ProcessInfo.processInfo.environment["CODEX_HOME"], !custom.isEmpty {
                return URL(fileURLWithPath: custom).appendingPathComponent("hooks.json")
            }
            return home.appendingPathComponent(".codex/hooks.json")
        }
    }

    var events: [(name: String, matcher: String?)] {
        switch self {
        case .claude:
            return [("SessionStart", nil), ("SessionEnd", nil), ("UserPromptSubmit", nil),
                    ("PreToolUse", "*"), ("PostToolUse", "*"), ("Notification", nil),
                    ("Stop", nil), ("StopFailure", nil), ("SubagentStart", nil), ("PreCompact", nil)]
        case .codex:
            return [("SessionStart", nil), ("SessionEnd", nil), ("UserPromptSubmit", nil),
                    ("PreToolUse", "*"), ("PostToolUse", "*"), ("PermissionRequest", "*"),
                    ("Stop", nil), ("SubagentStart", nil), ("PreCompact", nil), ("Interrupt", nil)]
        }
    }
}

enum HookError: LocalizedError {
    case invalidJSON(URL)

    var errorDescription: String? {
        switch self {
        case .invalidJSON(let url):
            return loc("\(url.path) geçerli bir JSON değil. Dosyayı düzeltip tekrar dene.",
                       "\(url.path) isn't valid JSON. Fix the file and try again.")
        }
    }
}

enum HookInstaller {
    /// Hook komutu: olay JSON'unu okur, arka planda TelepAIth'e POST eder, hemen çıkar.
    /// ClaudeBar'ın kota ölçmek için açtığı oturumları (CLAUDEBAR_PROBE=1) yok sayar.
    static func command(source: String) -> String {
        let m = AppInfo.hookMarker
        let portFile = "$HOME/\(AppInfo.supportDirName)/port"
        let url = "http://127.0.0.1:${PORT}/event?source=\(source)"
        return "\(m)() { [ \"$CLAUDEBAR_PROBE\" = \"1\" ] && return 0; P=$(cat); "
            + "PORT=$(cat \"\(portFile)\" 2>/dev/null || echo \(AppInfo.defaultPort)); "
            + "{ printf '%s' \"$P\" | curl -s -m 3 --noproxy '*' -H 'Content-Type: application/json' -H 'Expect:' --data-binary @- \"\(url)\"; } >/dev/null 2>&1 & }; \(m)"
    }

    /// Kalkan: tehlikeli görünen Bash komutlarında Claude Code'un onay sormasını sağlar
    /// (komutu engellemez, sadece "izin veriyor musun?" diye sordurur).
    static let shieldCommand = #"__telepaith_hook_shield() { P=$(cat); if printf '%s' "$P" | grep -qiE 'rm[[:space:]]+-[a-z]*r[a-z]*f|rm[[:space:]]+-[a-z]*f[a-z]*r|git[[:space:]]+push[^"]*(--force|[[:space:]]-f([^a-z]|$))|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[a-z]*f|drop[[:space:]]+(table|database)|mkfs|dd[[:space:]]+if=|chmod[[:space:]]+-r[[:space:]]+777|sudo[[:space:]]+rm'; then printf '%s' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"TelepAIth kalkanı: tehlikeli görünen komut, onayın gerekiyor."}}'; fi; }; __telepaith_hook_shield"#

    static func isInstalled(_ target: HookTarget) -> Bool {
        guard let data = try? Data(contentsOf: target.fileURL.resolvingSymlinksInPath()),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.contains(AppInfo.hookMarker)
    }

    static func install(_ target: HookTarget) throws {
        let url = target.fileURL.resolvingSymlinksInPath()
        var root = try load(url)
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        let cmd = command(source: target.source)
        for event in target.events {
            var groups = cleaned(hooks[event.name] as? [[String: Any]] ?? [])
            var group: [String: Any] = ["hooks": [["type": "command", "command": cmd]]]
            if let matcher = event.matcher { group["matcher"] = matcher }
            groups.append(group)
            if target == .claude && event.name == "PreToolUse" && Preferences.shield {
                groups.append(["matcher": "Bash", "hooks": [["type": "command", "command": shieldCommand]]])
            }
            hooks[event.name] = groups
        }
        root["hooks"] = hooks
        try save(root, to: url)
    }

    static func uninstall(_ target: HookTarget) throws {
        let url = target.fileURL.resolvingSymlinksInPath()
        var root = try load(url)
        guard var hooks = root["hooks"] as? [String: Any] else { return }
        for (name, value) in hooks {
            guard let groups = value as? [[String: Any]] else { continue }
            let kept = cleaned(groups)
            if kept.isEmpty { hooks.removeValue(forKey: name) } else { hooks[name] = kept }
        }
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try save(root, to: url)
    }

    private static func cleaned(_ groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { (group: [String: Any]) -> [String: Any]? in
            guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
            let kept = handlers.filter { handler in
                !((handler["command"] as? String) ?? "").contains(AppInfo.hookMarker)
            }
            if kept.isEmpty && !handlers.isEmpty { return nil }
            var copy = group
            copy["hooks"] = kept
            return copy
        }
    }

    private static func load(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        if data.isEmpty { return [:] }
        guard let dict = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw HookError.invalidJSON(url)
        }
        return dict
    }

    private static func save(_ root: [String: Any], to url: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // İlk değişiklikten önce bir kez yedek al
        let backup = url.appendingPathExtension("telepaith-backup")
        if fm.fileExists(atPath: url.path) && !fm.fileExists(atPath: backup.path) {
            try? fm.copyItem(at: url, to: backup)
        }
        let data = try JSONSerialization.data(withJSONObject: root,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
