import Foundation

/// Günlük özet için sayaçlar: her AI'ın bugün kaç iş bitirdiği, ne kadar çalıştığı, kaç dosya düzenlediği.
/// UserDefaults'ta gün gün tutulur (son 14 gün).
final class DailyStats {
    static let shared = DailyStats()

    struct Day: Codable, Equatable {
        var turns = 0
        var seconds: Double = 0
        var tools = 0
        var edits = 0
        var waits = 0
    }

    private let key = "dailyStats"
    private let shownKey = "dailySummaryShown"
    private var days: [String: [String: Day]]   // tarih → kaynak → sayaçlar

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: [String: Day]].self, from: data) {
            days = decoded
        } else {
            days = [:]
        }
    }

    static func dayKey(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    func recordTurn(source: String, seconds: Double, tools: Int, edits: Int, at date: Date = Date()) {
        update(source: source, at: date) { d in
            d.turns += 1
            d.seconds += max(0, seconds)
            d.tools += tools
            d.edits += edits
        }
    }

    func recordWait(source: String, at date: Date = Date()) {
        update(source: source, at: date) { $0.waits += 1 }
    }

    private func update(source: String, at date: Date, _ change: (inout Day) -> Void) {
        let k = DailyStats.dayKey(date)
        var day = days[k]?[source] ?? Day()
        change(&day)
        days[k, default: [:]][source] = day
        // Eski günleri at
        if days.count > 14 {
            for old in days.keys.sorted().prefix(days.count - 14) { days.removeValue(forKey: old) }
        }
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(days) { UserDefaults.standard.set(data, forKey: key) }
    }

    func today(_ date: Date = Date()) -> [String: Day] {
        days[DailyStats.dayKey(date)] ?? [:]
    }

    var hasActivityToday: Bool { today().values.contains { $0.turns > 0 } }

    /// "Claude bugün 2 sa 10 dk çalıştı, 14 iş bitirdi, 31 düzenleme yaptı · GPT …"
    func summary(names: (String) -> String, date: Date = Date()) -> String? {
        let entries = today(date).filter { $0.value.turns > 0 }.sorted { $0.value.seconds > $1.value.seconds }
        guard !entries.isEmpty else { return nil }
        return entries.map { source, d in
            var parts = [loc("\(d.turns) iş", "\(d.turns) task\(d.turns == 1 ? "" : "s")")]
            if d.seconds >= 60 { parts.append(formatDuration(d.seconds)) }
            if d.edits > 0 { parts.append(loc("\(d.edits) düzenleme", "\(d.edits) edit\(d.edits == 1 ? "" : "s")")) }
            if d.waits > 0 { parts.append(loc("\(d.waits) kez seni bekledi", "waited for you \(d.waits)×")) }
            return names(source) + ": " + parts.joined(separator: ", ")
        }.joined(separator: "\n")
    }

    /// Bugünün özeti zaten söylendi mi?
    var shownToday: Bool {
        get { UserDefaults.standard.string(forKey: shownKey) == DailyStats.dayKey() }
        set { UserDefaults.standard.set(newValue ? DailyStats.dayKey() : "", forKey: shownKey) }
    }
}
