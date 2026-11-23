import Foundation

/// Robottan onay: Claude Code'un PermissionRequest hook'una dönen karar.
enum ApprovalChoice: String, CaseIterable {
    case allow, always, deny
}

/// Balonda gösterilecek izin sorusu (düğmeler)
struct ApprovalPrompt: Equatable {
    let id: Int
    let hasAlways: Bool
}

enum Approval {
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
    let created = Date()
    private let respond: (String) -> Void
    private(set) var finished = false

    init(event: AgentEvent, body: Data, respond: @escaping (String) -> Void) {
        PendingApproval.counter += 1
        id = PendingApproval.counter
        self.event = event
        suggestions = Approval.suggestions(body)
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
