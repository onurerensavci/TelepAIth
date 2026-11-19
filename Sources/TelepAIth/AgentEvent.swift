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
        case .idle: return loc("Boşta", "Idle")
        case .thinking: return loc("Düşünüyor", "Thinking")
        case .reading: return loc("Okuyor", "Reading")
        case .searching: return loc("Arıyor", "Searching")
        case .editing: return loc("Düzenliyor", "Editing")
        case .running: return loc("Komut çalıştırıyor", "Running a command")
        case .delegating: return loc("Alt ajan çalıştırıyor", "Running a subagent")
        case .waiting: return loc("Seni bekliyor", "Waiting for you")
        case .done: return loc("Bitti", "Done")
        case .error: return loc("Hata", "Error")
        case .sleeping: return loc("Uyuyor", "Sleeping")
        }
    }

    /// Olayın kendi emojisi yoksa kullanılan emoji.
    var emoji: String {
        switch self {
        case .idle: return "🙂"
        case .thinking: return "🔮"
        case .reading: return "📖"
        case .searching: return "🔍"
        case .editing: return "✍️"
        case .running: return "💻"
        case .delegating: return "🧙"
        case .waiting: return "✋"
        case .done: return "🎉"
        case .error: return "💥"
        case .sleeping: return "😴"
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

/// Kısa süreli ruh hâli (mochi gibi): gözlerin desenini ve emojiyi değiştirir.
enum Mood: String {
    case pleased, shocked, nervous, scared, proud, party, tired, dizzy, denied
}

enum EventKind {
    case sessionStart, prompt, tool, status, toolDone, waiting, stop, failure, interrupt, sessionEnd, quota, generic, heartbeat
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
    var emoji: String? = nil
    var mood: Mood? = nil
    var moodSeconds: Double = 3
    /// Bu süreç öndeyken bildirim gösterme (kullanıcı zaten bakıyor)
    var quietIfFrontmostPID: Int32? = nil
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
            e.emoji = "👋"
            e.text = loc("Yeni oturum", "New session") + (project.map { ": \($0)" } ?? "")
        case "UserPromptSubmit":
            e.kind = .prompt
            e.state = .thinking
            e.emoji = "🔮"
            e.text = loc("Düşünüyor…", "Thinking…")
            if let prompt = j["prompt"] as? String, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                e.text = loc("Düşünüyor…", "Thinking…") + "\n«" + clip(prompt, 60) + "»"
                if let reaction = Reactions.onPrompt(prompt) {
                    e.mood = reaction.mood
                    e.moodSeconds = reaction.seconds
                    e.emoji = reaction.emoji
                }
            }
        case "PreToolUse":
            let d = ToolDescriber.describe(tool: tool, input: input)
            e.kind = d.state == .waiting ? .waiting : .tool
            e.state = d.state
            e.text = d.text
            e.emoji = d.emoji
            if d.state == .running, let cmd = ToolDescriber.commandString(input) {
                if Reactions.isScary(cmd) {
                    e.mood = .scared
                    e.moodSeconds = 5
                    e.emoji = "😱"
                    e.text = loc("Dikkat! ", "Careful! ") + clip(cmd, 60)
                } else if Reactions.isTest(cmd) {
                    e.mood = .nervous
                    e.moodSeconds = 4
                }
            }
        case "PostToolUse", "PostToolUseFailure":
            e.kind = .toolDone
            let failed = name == "PostToolUseFailure" || Reactions.looksFailed(j["tool_response"])
            let cmd = ToolDescriber.commandString(input) ?? ""
            if failed {
                e.state = .error   // sadece sayaç için; oturumun durumu değişmez
                if Reactions.isTest(cmd) {
                    e.text = loc("Testler kırıldı", "Tests failed")
                    e.emoji = "😵"
                    e.mood = .dizzy
                    e.moodSeconds = 6
                } else if Reactions.wasRefused(j["tool_response"]) {
                    e.text = loc("İzin verilmedi: ", "Not allowed: ") + ToolDescriber.shortName(tool)
                    e.emoji = "🙅"
                    e.mood = .denied
                    e.moodSeconds = 4
                } else {
                    e.text = loc("Hata: ", "Error: ") + ToolDescriber.shortName(tool)
                    e.emoji = "😬"
                    e.mood = .nervous
                    e.moodSeconds = 4
                }
            } else if !cmd.isEmpty {
                if Reactions.isTest(cmd) {
                    e.text = loc("Testler geçti!", "Tests passed!")
                    e.emoji = "🎉"
                    e.mood = .party
                    e.moodSeconds = 5
                } else if Reactions.isPush(cmd) {
                    e.text = loc("Gönderildi!", "Pushed!")
                    e.emoji = "🚀"
                    e.mood = .party
                    e.moodSeconds = 5
                } else if Reactions.isCommit(cmd) {
                    e.text = loc("Commit atıldı", "Committed")
                    e.emoji = "💾"
                    e.mood = .proud
                    e.moodSeconds = 4
                }
            }
        case "PermissionRequest":
            e.kind = .waiting
            e.state = .waiting
            e.emoji = "✋"
            let detail = (input["description"] as? String).map { " — " + clip($0, 60) }
                ?? ToolDescriber.commandString(input).map { " — " + clip($0, 60) }
                ?? ""
            e.text = loc("Onayını bekliyor: ", "Needs your approval: ") + ToolDescriber.shortName(tool) + detail
        case "Notification":
            e.kind = .waiting
            e.state = .waiting
            let n = translateNotification(j["message"] as? String)
            e.text = n.text
            e.emoji = n.emoji
        case "Stop":
            e.kind = .stop
            e.state = .done
            e.lastMessage = j["last_assistant_message"] as? String
        case "StopFailure":
            e.kind = .failure
            e.state = .error
            e.emoji = "💥"
            e.text = loc("Bir hatayla durdu", "Stopped with an error")
                + ((j["error"] as? String).map { ": " + clip($0, 60) } ?? "")
        case "SubagentStart":
            e.kind = .tool
            e.state = .delegating
            e.emoji = "🧙"
            e.text = loc("Alt ajan: ", "Subagent: ") + ((j["agent_type"] as? String) ?? loc("başladı", "started"))
        case "PreCompact":
            e.kind = .tool
            e.state = .thinking
            e.emoji = "🧠"
            e.text = loc("Hafızasını toparlıyor", "Tidying up its memory")
        case "Interrupt":
            e.kind = .interrupt
            e.state = .idle
            e.emoji = "⏹️"
            e.text = loc("Durduruldu", "Interrupted")
            e.mood = .shocked
            e.moodSeconds = 3
        case "SessionEnd":
            e.kind = .sessionEnd
            e.emoji = "👋"
            e.text = loc("Oturum kapandı", "Session ended")
        default:
            e.kind = .heartbeat
        }
        return e
    }

    private static func translateNotification(_ message: String?) -> (text: String, emoji: String) {
        guard let msg = message, !msg.isEmpty else { return (loc("Seni bekliyor", "Waiting for you"), "👀") }
        let lower = msg.lowercased()
        if lower.contains("permission") {
            if let r = msg.range(of: "to use ") {
                return (loc("Onayını bekliyor: ", "Needs your approval: ") + String(msg[r.upperBound...]), "✋")
            }
            return (loc("Onayını bekliyor", "Needs your approval"), "✋")
        }
        if lower.contains("waiting for your input") {
            return (loc("Cevabını bekliyor", "Waiting for your reply"), "👀")
        }
        return (clip(msg, 90), "🔔")
    }

    // MARK: ClaudeBar webhook'u (JSON kanalı)

    private static func claudeBar(_ j: [String: Any]) -> AgentEvent? {
        let source = Themes.canonical(j["provider"] as? String ?? "claude")
        let type = j["type"] as? String ?? "test"
        var state: RobotState? = nil
        var text: String
        var emoji = "⚠️"
        switch type {
        case "quota":
            emoji = "🔋"
            if let left = (j["left"] as? NSNumber)?.intValue {
                text = loc("Kalan kota: %\(left)", "Quota left: \(left)%")
            } else {
                text = loc("Kota azalıyor", "Quota is running low")
            }
        case "status":
            switch (j["status"] as? String) ?? "" {
            case "critical":
                text = loc("Kota kritik seviyede!", "Quota is critical!")
                emoji = "🪫"
            case "depleted":
                text = loc("Kota bitti!", "Quota is used up!")
                emoji = "🪫"
                state = .error
            default:
                text = loc("Kota uyarısı", "Quota warning")
            }
        case "signedOut":
            text = loc("Oturumu kapanmış, tekrar giriş yap", "Signed out, please log in again")
            emoji = "🔑"
        case "recap":
            text = loc("Haftalık özet geldi", "Your weekly recap is here")
            emoji = "📊"
        default:
            text = loc("ClaudeBar bağlantısı çalışıyor", "ClaudeBar connection works")
            emoji = "🔗"
        }
        if let login = j["login"] as? String, !login.isEmpty { text += " (\(login))" }
        return AgentEvent(source: source, sessionID: "claudebar", kind: .quota, state: state, text: text,
                          forceNotify: type != "recap", emoji: emoji)
    }

    // MARK: Genel format — başka bir AI'ı bağlamak için
    // POST /event?source=gemini  {"state": "running", "text": "Testler çalışıyor", "emoji": "🧪"}

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
                          forceNotify: (j["notify"] as? Bool) ?? false,
                          emoji: (j["emoji"] as? String) ?? state?.emoji)
    }
}

/// Araç çağrısını kısa bir cümleye ve emojiye çevirir.
enum ToolDescriber {
    static func describe(tool: String, input: [String: Any]) -> (state: RobotState, text: String, emoji: String) {
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
            return loc("dosya", "a file")
        }

        switch t {
        case "bash", "shell", "exec_command", "local_shell", "unified_exec", "container.exec":
            let cmd = commandString(input) ?? "…"
            return (.running, loc("Komut: ", "Command: ") + clip(cmd, 70), commandEmoji(cmd))
        case "read", "read_file", "view_image", "notebookread":
            return (.reading, loc("Okuyor: ", "Reading ") + fileName(), "📖")
        case "edit", "multiedit", "notebookedit", "str_replace_based_edit_tool":
            return (.editing, loc("Düzenliyor: ", "Editing ") + fileName(), "✍️")
        case "write", "create_file":
            return (.editing, loc("Yazıyor: ", "Writing ") + fileName(), "📝")
        case "apply_patch":
            if let f = patchFile(input) { return (.editing, loc("Düzenliyor: ", "Editing ") + f, "✍️") }
            return (.editing, loc("Kod düzenliyor", "Editing code"), "✍️")
        case "grep", "search", "rg":
            return (.searching, loc("Arıyor: ", "Searching for ") + clip(str("pattern", "query") ?? "…", 40), "🔍")
        case "glob", "ls", "list_dir", "list_files":
            return (.searching, loc("Dosyalara bakıyor", "Looking through files")
                    + (str("pattern", "path").map { ": " + clip($0, 40) } ?? ""), "🗂️")
        case "websearch", "web_search", "web_search_preview":
            return (.searching, loc("Web'de arıyor", "Searching the web")
                    + (str("query").map { ": " + clip($0, 50) } ?? ""), "🌐")
        case "webfetch":
            let host = str("url").flatMap { URL(string: $0)?.host } ?? "web"
            return (.reading, loc("Sayfa okuyor: ", "Reading page: ") + host, "🌍")
        case "task", "agent":
            return (.delegating, loc("Alt ajan: ", "Subagent: ")
                    + clip(str("description", "subagent_type") ?? loc("çalışıyor", "working"), 50), "🧙")
        case "todowrite", "update_plan":
            return (.thinking, loc("Plan yapıyor", "Making a plan"), "🗺️")
        case "askuserquestion", "request_user_input":
            return (.waiting, loc("Sana bir soru soruyor", "Has a question for you"), "❓")
        case "exitplanmode":
            return (.waiting, loc("Planını onaylamanı bekliyor", "Wants you to approve the plan"), "📋")
        default:
            let label = loc("Araç: ", "Tool: ")
            if t.hasPrefix("mcp__") { return (.running, label + shortName(tool), "🔌") }
            if t.contains("search") || t.contains("find") { return (.searching, label + tool, "🔍") }
            if t.contains("read") || t.contains("get") || t.contains("fetch") { return (.reading, label + tool, "📖") }
            if t.contains("write") || t.contains("edit") || t.contains("patch") { return (.editing, label + tool, "✍️") }
            return (.running, label + tool, "🛠️")
        }
    }

    /// Komutun ne yaptığına göre emoji: test 🧪, paket 📦, git push 🚀…
    static func commandEmoji(_ command: String) -> String {
        let c = " " + command.lowercased() + " "
        func has(_ words: String...) -> Bool { words.contains { c.contains($0) } }

        if has(" git push") { return "🚀" }
        if has(" git commit") { return "💾" }
        if has(" git ") { return "🌿" }
        if has(" npm install", " npm i ", " yarn add", " pnpm add", " pnpm install", " yarn install",
               " pip install", " pip3 install", " brew install", " cargo add", " pod install", " bun add", " bun install") { return "📦" }
        if has(" test", "test ", "test:", " jest", " vitest", " pytest", " rspec") { return "🧪" }
        if has(" build", " make ", " xcodebuild", " tsc", " webpack", " vite build", " gradle") { return "🔨" }
        if has(" lint", " eslint", " swiftlint", " prettier", " ruff", " black ") { return "🧹" }
        if has(" docker") { return "🐳" }
        if has(" curl ", " wget ") { return "🌐" }
        if has(" rm ", " rmdir ") { return "🗑️" }
        if has(" npm run dev", " npm start", " yarn dev", " pnpm dev", " serve ", " uvicorn", " flask run") { return "🏃" }
        if has(" ls ", " cat ", " grep ", " rg ", " find ", " head ", " tail ") { return "👀" }
        return "💻"
    }

    /// mcp__github__create_issue → "create_issue (github)"
    static func shortName(_ tool: String) -> String {
        guard tool.hasPrefix("mcp__") else { return tool.isEmpty ? loc("araç", "tool") : tool }
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

/// Mochi'den esinlenen tepkiler: istemin tonu, tehlikeli komutlar, test/commit/push.
enum Reactions {
    struct PromptReaction {
        let mood: Mood
        let seconds: Double
        let emoji: String
    }

    static func onPrompt(_ text: String) -> PromptReaction? {
        let said = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = said.lowercased()

        let thanks = ["teşekkür", "tesekkur", "sağol", "sagol", "sağ ol", "eyvallah", "tşk", "tsk", "eline sağlık",
                      "harika", "süper", "super", "mükemmel", "aferin", "bravo", "helal", "efsane", "şahane",
                      "thanks", "thank you", "thx", "great job", "awesome", "perfect", "well done", "nice work", "love it"]
        if thanks.contains(where: { low.contains($0) }) {
            return PromptReaction(mood: .pleased, seconds: 3, emoji: "🥰")
        }

        let letters = said.filter { $0.isLetter }
        let upper = letters.filter { $0.isUppercase }
        if letters.count >= 8 && Double(upper.count) / Double(letters.count) > 0.7 {
            return PromptReaction(mood: .shocked, seconds: 2.5, emoji: "😳")
        }

        let frustration = ["çalışmıyor", "calismiyor", "bozuk", "olmadı", "olmadi", "neden", "niye", "yine", "hala ",
                           "hâlâ", "saçma", "yanlış", "??", "doesn't work", "not working", "broken", "still", "why", "again", "wtf"]
        if frustration.contains(where: { low.contains($0) }) {
            return PromptReaction(mood: .nervous, seconds: 3, emoji: "😬")
        }
        return nil
    }

    static func isScary(_ command: String) -> Bool {
        let c = command.lowercased()
        let patterns = [#"\brm\s+-[a-z]*r[a-z]*f"#, #"\brm\s+-[a-z]*f[a-z]*r"#, #"git\s+push\b.*(--force|\s-f\b)"#,
                        #"git\s+reset\s+--hard"#, #"git\s+clean\s+-[a-z]*f"#, #"\bdrop\s+(table|database)\b"#,
                        #"\bmkfs\b"#, #"\bdd\s+if="#, #"chmod\s+-r\s+777"#, #"sudo\s+rm\b"#]
        return patterns.contains { c.range(of: $0, options: .regularExpression) != nil }
    }

    static func isTest(_ command: String) -> Bool {
        let c = (" " + command.lowercased() + " ").replacingOccurrences(of: "latest", with: "")
        return [" test", "test ", "test:", " jest", " vitest", " pytest", " rspec", "go test", "swift test", "cargo test"]
            .contains { c.contains($0) }
    }

    static func isCommit(_ command: String) -> Bool {
        command.range(of: #"git\s+commit\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func isPush(_ command: String) -> Bool {
        command.range(of: #"git\s+push\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Aracın cevabı hata gibi mi? (Claude Code ve Codex farklı alanlar kullanıyor)
    static func looksFailed(_ response: Any?) -> Bool {
        guard let r = response as? [String: Any] else { return false }
        if (r["is_error"] as? Bool) == true || (r["isError"] as? Bool) == true { return true }
        if let code = (r["exit_code"] as? NSNumber) ?? (r["exitCode"] as? NSNumber) { return code.intValue != 0 }
        if (r["success"] as? Bool) == false { return true }
        return false
    }

    static func wasRefused(_ response: Any?) -> Bool {
        let text: String
        if let r = response as? [String: Any] {
            text = r.values.compactMap { $0 as? String }.joined(separator: " ")
        } else {
            text = (response as? String) ?? ""
        }
        return text.range(of: #"doesn't want to proceed|user (rejected|denied|declined)|permission.*denied|was rejected"#,
                          options: [.regularExpression, .caseInsensitive]) != nil
    }
}
