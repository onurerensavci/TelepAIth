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
}

enum Approval {
    /// Balondan izin verilebilecek en uzun komut (tamamı balonda okunabilsin).
    static let maxAllowLength = 120
    private static let plainKeys: Set<String> = ["command", "description", "timeout", "run_in_background"]

    /// "İzin ver" sadece tamamı okunabilen kısa, tek satırlık bir kabuk komutunda gösterilir. Dosya düzenlemesi (balon
    /// değişikliği göstermez), uzun komut ya da ne yaptığını söylemeyen araç balondan sadece reddedilebilir.
    static func canAllow(tool: String?, input: [String: Any]) -> Bool {
        guard tool == "Bash" || tool == "PowerShell", let cmd = ToolDescriber.commandString(input),
              !cmd.isEmpty, !cmd.contains("\n"), !cmd.contains("\r"), cmd.count <= maxAllowLength else { return false }
        return input.keys.allSatisfy { plainKeys.contains($0) }
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
    let created = Date()
    private let respond: (String) -> Void
    private(set) var finished = false

    init(event: AgentEvent, body: Data, respond: @escaping (String) -> Void) {
        PendingApproval.counter += 1
        id = PendingApproval.counter
        self.event = event
        suggestions = Approval.suggestions(body)
        canAllow = Approval.canAllow(body)
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
