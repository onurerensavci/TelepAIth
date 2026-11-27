import Foundation

/// Yenilikler (Windows'ta TelepAIth.Core/WhatsNew.cs, aynı kurallar): assets/whatsnew.json'dan gömülü liste ve GitHub sürüm notları.
/// Güncellemeye basınca kısaca ne geldiğini, güncellemeden sonra da yeni bir özelliği robot söyler.
enum WhatsNew {
    struct Entry {
        let version: String
        let tr: [String]
        let en: [String]
        var items: [String] { Language.current == .tr ? tr : en }
    }

    static let all: [Entry] = parse(WhatsNewData.json)

    static func parse(_ json: String) -> [Entry] {
        guard let arr = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [[String: Any]] else { return [] }
        return arr.map { n in
            Entry(version: n["version"] as? String ?? "", tr: (n["tr"] as? [String] ?? []).filter { !$0.isEmpty },
                  en: (n["en"] as? [String] ?? []).filter { !$0.isEmpty })
        }
    }

    static func entry(for version: String) -> Entry? {
        let v = version.hasPrefix("v") ? String(version.dropFirst()) : version
        return all.first { $0.version == v }
    }

    /// Sürümün kısa özeti: GitHub notlarındaki "<!-- tr -->" / "<!-- en -->" bölümü, yoksa gömülü liste,
    /// o da yoksa notlardaki "- " maddeleri ("Full Changelog" gibi satırlar atlanır).
    static func summary(_ version: String, notes: String?, max: Int = 4) -> [String] {
        let lines = (notes ?? "").replacingOccurrences(of: "\r", with: "").components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        let marker = Language.current == .tr ? "<!-- tr -->" : "<!-- en -->"
        var items: [String] = []
        if let start = lines.firstIndex(of: marker) {
            items = lines[(start + 1)...].prefix { !$0.hasPrefix("<!--") }.filter { $0.hasPrefix("- ") }
                .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
        }
        if items.isEmpty, let e = entry(for: version) { items = e.items }
        if items.isEmpty {
            items = lines.filter { $0.hasPrefix("- ") || $0.hasPrefix("* ") }.map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.contains("http") && !$0.contains("@") }
        }
        return Array(items.prefix(max))
    }

    /// Balonda madde listesi: "\n• …\n• …" (boşsa boş)
    static func bullets(_ items: [String]) -> String {
        items.isEmpty ? "" : "\n• " + items.joined(separator: "\n• ")
    }

    /// Güncellemeden sonra robotun söylediği: "🎁 0.24.0 geldi! Neler var:" ve ilk üç madde
    static func afterUpdate(_ version: String) -> String? {
        guard let e = entry(for: version), !e.items.isEmpty else { return nil }
        return "🎁 " + loc("\(version) geldi! Neler var:", "\(version) is here! What's new:") + bullets(Array(e.items.prefix(3)))
    }
}
