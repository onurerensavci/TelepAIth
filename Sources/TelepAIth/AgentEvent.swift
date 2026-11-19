import Foundation

enum RobotState: String, CaseIterable {
    case idle, thinking, reading, searching, editing, running, delegating, waiting, done, error, sleeping

    var isWorking: Bool {
        switch self {
        case .thinking, .reading, .searching, .editing, .running, .delegating: return true
        default: return false
        }
    }

    /// Birden fazla oturum varken hangisinin gösterileceği.
    var priority: Int {
        switch self {
        case .waiting: return 6
        case .error: return 5
        case .thinking, .reading, .searching, .editing, .running, .delegating: return 4
        case .done: return 3
        case .idle: return 2
        case .sleeping: return 1
        }
    }

    var label: String {
        switch self {
        case .idle: return "Boşta"
        case .thinking: return "Düşünüyor"
        case .reading: return "Okuyor"
        case .searching: return "Arıyor"
        case .editing: return "Düzenliyor"
        case .running: return "Komut çalıştırıyor"
        case .delegating: return "Alt ajan çalıştırıyor"
        case .waiting: return "Seni bekliyor"
        case .done: return "Bitti"
        case .error: return "Hata"
        case .sleeping: return "Uyuyor"
        }
    }

    var symbol: String {
        switch self {
        case .idle: return "circle"
        case .thinking: return "ellipsis"
        case .reading: return "book"
        case .searching: return "magnifyingglass"
        case .editing: return "pencil"
        case .running: return "terminal"
        case .delegating: return "person.2"
        case .waiting: return "hand.raised"
        case .done: return "checkmark"
        case .error: return "exclamationmark.triangle"
        case .sleeping: return "moon"
        }
    }
}

enum EventKind {
    case sessionStart, prompt, tool, toolDone, waiting, stop, failure, interrupt, sessionEnd, quota, generic, heartbeat
}

struct AgentEvent {
    var source: String
    var sessionID: String
    var kind: EventKind
    var state: RobotState? = nil
    var text: String? = nil
    var project: String? = nil
    var lastMessage: String? = nil
    var forceNotify = false
}

/// Gelen HTTP isteğini robotun anlayacağı olaya çevirir.
enum EventParser {
    static func parse(path: String, query: [String: String], body: Data) -> AgentEvent? {
        let json = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        if path.hasPrefix("/claudebar") { return claudeBar(json) }
        let source = Themes.canonical(query["source"] ?? (json["agent"] as? String) ?? "custom")
        if let hook = json["hook_event_name"] as? String { return hookEvent(hook, json, source: source) }
        return generic(json, source: source)
    }

    // MARK: Claude Code ve Codex hook'ları (ikisi aynı formatı kullanıyor)

    private static func hookEvent(_ name: String, _ j: [String: Any], source: String) -> AgentEvent {
        let session = (j["session_id"] as? String) ?? "default"
        let project = (j["cwd"] as? String).map { URL(fileURLWithPath: $0).lastPathComponent }
        var e = AgentEvent(source: source, sessionID: session, kind: .heartbeat, project: project)
        let tool = j["tool_name"] as? String ?? ""
        let input = j["tool_input"] as? [String: Any] ?? [:]

        switch name {
        case "SessionStart":
            e.kind = .sessionStart
            e.state = .idle
            e.text = "Yeni oturum" + (project.map { ": \($0)" } ?? "")
        case "UserPromptSubmit":
            e.kind = .prompt
            e.state = .thinking
            e.text = "Düşünüyor…"
        case "PreToolUse":
            let d = ToolDescriber.describe(tool: tool, input: input)
            e.kind = d.state == .waiting ? .waiting : .tool
            e.state = d.state
            e.text = d.text
        case "PostToolUse", "PostToolUseFailure":
            e.kind = .toolDone
        case "PermissionRequest":
            e.kind = .waiting
            e.state = .waiting
            let detail = (input["description"] as? String).map { " — " + clip($0, 60) }
                ?? ToolDescriber.commandString(input).map { " — " + clip($0, 60) }
                ?? ""
            e.text = "Onayını bekliyor: " + ToolDescriber.shortName(tool) + detail
        case "Notification":
            e.kind = .waiting
            e.state = .waiting
            e.text = translateNotification(j["message"] as? String)
        case "Stop":
            e.kind = .stop
            e.state = .done
            e.lastMessage = j["last_assistant_message"] as? String
        case "StopFailure":
            e.kind = .failure
            e.state = .error
            e.text = "Bir hatayla durdu" + ((j["error"] as? String).map { ": " + clip($0, 60) } ?? "")
        case "SubagentStart":
            e.kind = .tool
            e.state = .delegating
            e.text = "Alt ajan: " + ((j["agent_type"] as? String) ?? "başladı")
        case "PreCompact":
            e.kind = .tool
            e.state = .thinking
            e.text = "Hafızasını toparlıyor"
        case "Interrupt":
            e.kind = .interrupt
            e.state = .idle
            e.text = "Durduruldu"
        case "SessionEnd":
            e.kind = .sessionEnd
            e.text = "Oturum kapandı"
        default:
            e.kind = .heartbeat
        }
        return e
    }

    private static func translateNotification(_ message: String?) -> String {
        guard let msg = message, !msg.isEmpty else { return "Seni bekliyor" }
        let lower = msg.lowercased()
        if lower.contains("permission") {
            if let r = msg.range(of: "to use ") { return "Onayını bekliyor: " + String(msg[r.upperBound...]) }
            return "Onayını bekliyor"
        }
        if lower.contains("waiting for your input") { return "Cevabını bekliyor" }
        return clip(msg, 90)
    }

    // MARK: ClaudeBar webhook'u (JSON kanalı)

    private static func claudeBar(_ j: [String: Any]) -> AgentEvent? {
        let source = Themes.canonical(j["provider"] as? String ?? "claude")
        let type = j["type"] as? String ?? "test"
        var state: RobotState? = nil
        var text: String
        switch type {
        case "quota":
            if let left = (j["left"] as? NSNumber)?.intValue {
                text = "Kalan kota: %\(left)"
            } else {
                text = "Kota azalıyor"
            }
        case "status":
            switch (j["status"] as? String) ?? "" {
            case "critical": text = "Kota kritik seviyede!"
            case "depleted":
                text = "Kota bitti!"
                state = .error
            default: text = "Kota uyarısı"
            }
        case "signedOut":
            text = "Oturumu kapanmış, tekrar giriş yap"
        case "recap":
            text = "Haftalık özet geldi"
        default:
            text = "ClaudeBar bağlantısı çalışıyor"
        }
        if let login = j["login"] as? String, !login.isEmpty { text += " (\(login))" }
        return AgentEvent(source: source, sessionID: "claudebar", kind: .quota, state: state, text: text, forceNotify: type != "recap")
    }

    // MARK: Genel format — başka bir AI'ı bağlamak için
    // POST /event?source=gemini  {"state": "running", "text": "Testler çalışıyor", "session": "1", "project": "app"}

    private static func generic(_ j: [String: Any], source: String) -> AgentEvent? {
        let synonyms: [String: RobotState] = [
            "working": .thinking, "busy": .thinking, "writing": .editing, "coding": .editing,
            "finished": .done, "complete": .done, "completed": .done,
            "blocked": .waiting, "needs_input": .waiting, "failed": .error,
        ]
        let rawState: String? = (j["state"] as? String)?.lowercased()
        let state: RobotState? = rawState.flatMap { RobotState(rawValue: $0) ?? synonyms[$0] }
        let text = j["text"] as? String
        if state == nil && text == nil { return nil }

        var kind = EventKind.generic
        if state == .done { kind = .stop } else if state == .waiting { kind = .waiting } else if state == .error { kind = .failure }

        return AgentEvent(source: source,
                          sessionID: (j["session"] as? String) ?? "default",
                          kind: kind,
                          state: state,
                          text: text,
                          project: j["project"] as? String,
                          lastMessage: nil,
                          forceNotify: (j["notify"] as? Bool) ?? false)
    }
}

/// Araç çağrısını Türkçe kısa bir cümleye çevirir.
enum ToolDescriber {
    static func describe(tool: String, input: [String: Any]) -> (state: RobotState, text: String) {
        let t = tool.lowercased()

        func str(_ keys: String...) -> String? {
            for k in keys {
                if let v = input[k] as? String, !v.isEmpty { return v }
            }
            return nil
        }
        func fileName() -> String {
            if let p = str("file_path", "path", "notebook_path", "filePath") {
                return URL(fileURLWithPath: p).lastPathComponent
            }
            return "dosya"
        }

        switch t {
        case "bash", "shell", "exec_command", "local_shell", "unified_exec", "container.exec":
            return (.running, "Komut: " + clip(commandString(input) ?? "…", 70))
        case "read", "read_file", "view_image", "notebookread":
            return (.reading, "Okuyor: " + fileName())
        case "edit", "multiedit", "notebookedit", "str_replace_based_edit_tool":
            return (.editing, "Düzenliyor: " + fileName())
        case "write", "create_file":
            return (.editing, "Yazıyor: " + fileName())
        case "apply_patch":
            if let f = patchFile(input) { return (.editing, "Düzenliyor: " + f) }
            return (.editing, "Kod düzenliyor")
        case "grep", "search", "rg":
            return (.searching, "Arıyor: " + clip(str("pattern", "query") ?? "…", 40))
        case "glob", "ls", "list_dir", "list_files":
            return (.searching, "Dosyalara bakıyor" + (str("pattern", "path").map { ": " + clip($0, 40) } ?? ""))
        case "websearch", "web_search", "web_search_preview":
            return (.searching, "Web'de arıyor" + (str("query").map { ": " + clip($0, 50) } ?? ""))
        case "webfetch":
            let host = str("url").flatMap { URL(string: $0)?.host } ?? "web"
            return (.reading, "Sayfa okuyor: " + host)
        case "task", "agent":
            return (.delegating, "Alt ajan: " + clip(str("description", "subagent_type") ?? "çalışıyor", 50))
        case "todowrite", "update_plan":
            return (.thinking, "Plan yapıyor")
        case "askuserquestion", "request_user_input":
            return (.waiting, "Sana bir soru soruyor")
        case "exitplanmode":
            return (.waiting, "Planını onaylamanı bekliyor")
        default:
            if t.hasPrefix("mcp__") {
                return (.running, "Araç: " + shortName(tool))
            }
            if t.contains("search") || t.contains("find") { return (.searching, "Araç: \(tool)") }
            if t.contains("read") || t.contains("get") || t.contains("fetch") { return (.reading, "Araç: \(tool)") }
            if t.contains("write") || t.contains("edit") || t.contains("patch") { return (.editing, "Araç: \(tool)") }
            return (.running, "Araç: \(tool)")
        }
    }

    /// mcp__github__create_issue → "create_issue (github)"
    static func shortName(_ tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool.isEmpty ? "araç" : tool }
        let parts = tool.components(separatedBy: "__")
        guard parts.count >= 3 else { return tool }
        return parts[2...].joined(separator: "__") + " (\(parts[1]))"
    }

    static func commandString(_ input: [String: Any]) -> String? {
        if let s = input["command"] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let arr = input["command"] as? [String], !arr.isEmpty {
            let shells = ["bash", "zsh", "sh"]
            if arr.count >= 3, shells.contains(URL(fileURLWithPath: arr[0]).lastPathComponent), arr[1].hasPrefix("-") {
                return arr.last
            }
            return arr.joined(separator: " ")
        }
        if let s = input["cmd"] as? String { return s }
        return nil
    }

    /// Codex'in apply_patch girdisinden dosya adını bulur.
    static func patchFile(_ input: [String: Any]) -> String? {
        var blob = input.values.compactMap { $0 as? String }.joined(separator: "\n")
        if let arr = input["command"] as? [String] { blob += "\n" + arr.joined(separator: "\n") }
        for marker in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
            if let r = blob.range(of: marker) {
                let line = blob[r.upperBound...].prefix { $0 != "\n" }
                let path = String(line).trimmingCharacters(in: .whitespaces)
                if !path.isEmpty { return URL(fileURLWithPath: path).lastPathComponent }
            }
        }
        return nil
    }
}
