import Foundation

/// Günlük özet için sayaçlar: her AI'ın bugün kaç iş bitirdiği, ne kadar çalıştığı, kaç dosya düzenlediği.
/// UserDefaults'ta gün gün tutulur (son 90 gün; Emek sekmesi son 30 günü gösterir).
final class DailyStats {
    static let shared = DailyStats()

    struct Day: Codable, Equatable {
        var turns = 0
        var seconds: Double = 0
        var tools = 0
        var edits = 0
        var waits = 0
        /// Proje → [saniye, tur]: Emek sekmesi için (eski kayıtlarda yok)
        var projects: [String: [Double]]? = nil
    }

    static let keepDays = 90

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

    func recordTurn(source: String, seconds: Double, tools: Int, edits: Int, at date: Date = Date(), project: String? = nil) {
        update(source: source, at: date) { d in
            d.turns += 1
            d.seconds += max(0, seconds)
            d.tools += tools
            d.edits += edits
            if let project = project, !project.trimmingCharacters(in: .whitespaces).isEmpty {
                var projects = d.projects ?? [:]
                let old = projects[project] ?? [0, 0]
                projects[project] = [old[0] + max(0, seconds), old[1] + 1]
                d.projects = projects
            }
        }
    }

    /// Bugün (tüm AI'lar) kaç tur
    func turnsOn(_ date: Date) -> Int {
        (days[DailyStats.dayKey(date)] ?? [:]).values.reduce(0) { $0 + $1.turns }
    }

    /// Emek: son `count` gün (bugün dahil), günlük AI saniyeleri ve projeler.
    func effort(today: Date, days count: Int) -> Effort {
        var list: [EffortDay] = []
        var bySource: [String: Double] = [:]
        var projects: [String: (seconds: Double, turns: Int)] = [:]
        var turns = 0, edits = 0
        for i in stride(from: count - 1, through: 0, by: -1) {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: today) ?? today
            let key = DailyStats.dayKey(date)
            var secs: [String: Double] = [:]
            for (src, d) in days[key] ?? [:] {
                let canon = Themes.canonical(src)
                secs[canon, default: 0] += d.seconds
                bySource[canon, default: 0] += d.seconds
                turns += d.turns
                edits += d.edits
                for (name, pv) in d.projects ?? [:] where pv.count == 2 {
                    let old = projects[name] ?? (0, 0)
                    projects[name] = (old.seconds + pv[0], old.turns + Int(pv[1]))
                }
            }
            list.append(EffortDay(day: key, secondsBySource: secs))
        }
        let total = bySource.values.reduce(0, +)
        let projectSeconds = projects.values.reduce(0) { $0 + $1.seconds }
        let rows = projects.map { EffortProject(name: $0.key, seconds: $0.value.seconds, turns: $0.value.turns,
                                                share: projectSeconds > 0 ? $0.value.seconds / projectSeconds : 0) }
            .sorted { $0.seconds > $1.seconds }
        return Effort(days: list, projects: rows, bySource: bySource, totalSeconds: total, totalTurns: turns, totalEdits: edits)
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
        if days.count > DailyStats.keepDays {
            for old in days.keys.sorted().prefix(days.count - DailyStats.keepDays) { days.removeValue(forKey: old) }
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
