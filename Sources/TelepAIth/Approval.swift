import Foundation

/// Robottan onay: Claude Code'un PermissionRequest hook'una dönen karar.
enum ApprovalChoice: String, CaseIterable {
    case allow, always, deny
}

/// Balonda gösterilecek izin sorusu (düğmeler)
struct ApprovalPrompt: Equatable {
    let id: Int
    let hasAlways: Bool
    /// "İzin ver" sadece tamamı okunabilen kısa kabuk komutunda (yoksa balondan sadece reddedilir)
    var canAllow = true
    /// Balonun içeriği: başlık, ne istediği, kod kutusundaki komut
    var card: ApprovalCard? = nil
}

/// Onay balonunun içeriği: başlık, ne istediği, kod kutusundaki metin (yoksa nil)
struct ApprovalCard: Equatable {
    let title: String
    let action: String
    let code: String?
}

enum Approval {
    /// Balondan izin verilebilecek en uzun komut: balondaki kod kutusunun iki satırına sığsın, tamamı okunsun.
    static let maxAllowLength = 80
    private static let plainKeys: Set<String> = ["command", "description", "timeout", "run_in_background"]

    /// "İzin ver" sadece tamamı okunabilen kısa, tek satırlık bir kabuk komutunda gösterilir. Dosya düzenlemesi (balon
    /// değişikliği göstermez), uzun komut ya da ne yaptığını söylemeyen araç balondan sadece reddedilebilir.
    static func canAllow(tool: String?, input: [String: Any]) -> Bool {
        guard tool == "Bash" || tool == "PowerShell", let cmd = ToolDescriber.commandString(input),
              !cmd.isEmpty, !cmd.contains("\n"), !cmd.contains("\r"), cmd.count <= maxAllowLength else { return false }
        return input.keys.allSatisfy { plainKeys.contains($0) }
    }

    /// Onay balonu: "‘shop’ seni bekliyor" başlığı, "Bash kullanmak istiyor" satırı ve kod kutusundaki komut
    /// (ya da dosya adı, adres, arama). Windows'ta Approval.Card ile aynı.
    static func card(_ body: Data, fallbackName: String) -> ApprovalCard {
        let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let project = (j["cwd"] as? String).flatMap { $0.isEmpty ? nil : lastPart($0) }
        let title = project.map { loc("‘\($0)’ seni bekliyor", "‘\($0)’ is waiting for you") }
            ?? loc("\(fallbackName) seni bekliyor", "\(fallbackName) is waiting for you")
        let tool = j["tool_name"] as? String ?? ""
        let input = j["tool_input"] as? [String: Any] ?? [:]
        let name = tool.hasPrefix("mcp__") ? (tool.components(separatedBy: "__").last ?? tool) : tool
        let action: String
        switch tool {
        case "Edit", "MultiEdit", "NotebookEdit": action = loc("bir dosyayı değiştirmek istiyor", "wants to edit a file")
        case "Write": action = loc("bir dosya yazmak istiyor", "wants to write a file")
        case "": action = loc("onayını istiyor", "needs your approval")
        default: action = loc("\(name) kullanmak istiyor", "wants to use \(name)")
        }
        var code: String?
        if let cmd = ToolDescriber.commandString(input) {
            code = cmd.replacingOccurrences(of: "\r\n", with: " ⏎ ").replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        } else if let f = (input["file_path"] as? String) ?? (input["notebook_path"] as? String), !f.isEmpty {
            code = lastPart(f)
        } else {
            code = (input["url"] as? String) ?? (input["pattern"] as? String) ?? (input["query"] as? String) ?? (input["description"] as? String)
        }
        if let c = code, c.count > 200 { code = String(c.prefix(200)) + "…" }
        if let c = code, c.trimmingCharacters(in: .whitespaces).isEmpty { code = nil }
        return ApprovalCard(title: title, action: action, code: code)
    }

    /// Yolun son parçası (Mac ve Windows ayraçlarıyla)
    private static func lastPart(_ path: String) -> String {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? path
    }

    static func canAllow(_ body: Data) -> Bool {
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return false }
        return canAllow(tool: j["tool_name"] as? String, input: j["tool_input"] as? [String: Any] ?? [:])
    }

    /// Claude'un önerdiği izin kuralları (permission_suggestions) varsa "Hep izin ver" gösterilir
    static func suggestions(_ body: Data) -> [Any]? {
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let s = j["permission_suggestions"] as? [Any], !s.isEmpty else { return nil }
        return s
    }

    static func decision(_ choice: ApprovalChoice, suggestions: [Any]?) -> String {
        var decision: [String: Any]
        switch choice {
        case .deny:
            decision = ["behavior": "deny",
                        "message": loc("Kullanıcı bunu TelepAIth robotundan reddetti.", "The user declined this from the TelepAIth robot.")]
        case .always where suggestions != nil:
            decision = ["behavior": "allow", "updatedPermissions": suggestions!]
        default:
            decision = ["behavior": "allow"]
        }
        let out: [String: Any] = ["hookSpecificOutput": ["hookEventName": "PermissionRequest", "decision": decision]]
        guard let data = try? JSONSerialization.data(withJSONObject: out),
              let text = String(data: data, encoding: .utf8) else { return "" }
        return text
    }
}

/// Robotun cevabını bekleyen bir izin isteği. answer: karar JSON'u; release: boş cevap (soru terminalde çıkar).
final class PendingApproval {
    private static var counter = 0
    let id: Int
    let event: AgentEvent
    let suggestions: [Any]?
    let canAllow: Bool
    let card: ApprovalCard
    let created = Date()
    private let respond: (String) -> Void
    private(set) var finished = false

    init(event: AgentEvent, body: Data, respond: @escaping (String) -> Void) {
        PendingApproval.counter += 1
        id = PendingApproval.counter
        self.event = event
        suggestions = Approval.suggestions(body)
        canAllow = Approval.canAllow(body)
        card = Approval.card(body, fallbackName: Themes.shared.theme(for: event.source).displayName)
        self.respond = respond
    }

    func answer(_ json: String) {
        guard !finished else { return }
        finished = true
        respond(json)
    }

    func release() { answer("") }

    /// Hook bağlantıyı kapattı (Claude Code vazgeçti)
    func closed() { finished = true }
}
