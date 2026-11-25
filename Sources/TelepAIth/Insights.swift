import Foundation

// Hook'lardan ve Claude Code'un durum satırından çıkan uyarılar (Windows'ta TelepAIth.Core/Insights.cs, aynı kurallar):
// kullanım sınırları, aynı adımda takılma, iki sohbetin aynı dosyayı düzenlemesi, push sonrası CI, commit'lenmemiş iş.

/// Bir kullanım penceresi: five_hour (oturum) ya da seven_day (hafta), yüzde kaç dolu, ne zaman yenilenir.
struct UsageWindow: Equatable {
    let kind: String
    var percent: Int
    var resetsAt: Date?
}

enum UsageLimits {
    static func length(_ kind: String) -> TimeInterval? {
        switch kind {
        case "five_hour": return 5 * 3600
        case "seven_day": return 7 * 24 * 3600
        default: return nil
        }
    }

    static func name(_ kind: String) -> String { kind == "five_hour" ? loc("Oturum", "Session") : loc("Hafta", "Week") }

    /// Claude Code'un durum satırına verdiği JSON'dan pencereler (rate_limits.five_hour / seven_day).
    static func parse(_ body: Data) -> [UsageWindow] {
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let limits = j["rate_limits"] as? [String: Any] else { return [] }
        var list: [UsageWindow] = []
        for kind in ["five_hour", "seven_day"] {
            guard let w = limits[kind] as? [String: Any], let p = (w["used_percentage"] as? NSNumber)?.doubleValue else { continue }
            var resets: Date?
            if let s = (w["resets_at"] as? NSNumber)?.doubleValue, s > 0 { resets = Date(timeIntervalSince1970: floor(s)) }
            list.append(UsageWindow(kind: kind, percent: Int((Swift.min(100, Swift.max(0, p))).rounded()), resetsAt: resets))
        }
        return list
    }

    /// Bu hızla giderse ne zaman dolar? Yenilenmeden önce dolmayacaksa ya da bilinmiyorsa nil.
    static func fillsAt(_ w: UsageWindow, now: Date) -> Date? {
        guard let reset = w.resetsAt, let length = length(w.kind), w.percent > 0, w.percent < 100 else { return nil }
        let start = reset.addingTimeInterval(-length)
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= 600 else { return nil }
        let fill = start.addingTimeInterval(elapsed * 100 / Double(w.percent))
        return fill < reset ? fill : nil
    }

    /// "16:40" ya da başka günse "Cum 16:40"
    static func clock(_ at: Date, now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: Language.current == .tr ? "tr_TR" : "en_US")
        f.dateFormat = Calendar.current.isDate(at, inSameDayAs: now) ? "HH:mm" : "EEE HH:mm"
        return f.string(from: at)
    }

    /// Sohbet listesinin başındaki satır: "Oturum %42 · 16:40'ta dolar"
    static func line(_ w: UsageWindow, now: Date) -> String {
        let text = loc("\(name(w.kind)) %\(w.percent)", "\(name(w.kind)) \(w.percent)%")
        if let fill = fillsAt(w, now: now) {
            return text + " · " + loc("\(clock(fill, now: now))'ta dolar", "full at \(clock(fill, now: now))")
        }
        if let reset = w.resetsAt, w.percent >= 50 {
            return text + " · " + loc("\(clock(reset, now: now))'de yenilenir", "resets \(clock(reset, now: now))")
        }
        return text
    }
}

/// Son bilinen kullanım sınırları ve eşik bildirimleri (%80 geçti, %95 neredeyse bitti, yenilendi).
final class UsageTracker {
    /// Durum satırı bu kadar süre bir şey demezse eski bilgi gösterilmez.
    static let stale: TimeInterval = 12 * 3600

    private var windows: [String: UsageWindow] = [:]
    private var told: [String: Int] = [:]   // 0 yok, 1 %80 söylendi, 2 %95 söylendi
    private var first = true
    private(set) var updatedAt: Date?

    func update(_ body: Data, now: Date) -> [AgentEvent] {
        let fresh = UsageLimits.parse(body)
        guard !fresh.isEmpty else { return [] }
        updatedAt = now
        var events: [AgentEvent] = []
        for w in fresh {
            // Yeni pencere başladıysa (yenilenme zamanı ileri kaydı) eşikler sıfırlanır
            if let old = windows[w.kind], let oldReset = old.resetsAt, let newReset = w.resetsAt,
               newReset > oldReset.addingTimeInterval(60) {
                told[w.kind] = 0
            }
            windows[w.kind] = w
            let level = w.percent >= 95 ? 2 : w.percent >= 80 ? 1 : 0
            let had = told[w.kind] ?? 0
            if level < had && w.percent < 75 { told[w.kind] = 0 }   // yenilenmiş
            guard level > had else { continue }
            told[w.kind] = level
            // Uygulama açılınca ilk okumada %80'i tekrar söyleme; %95 her zaman söylenir
            if first && level < 2 { continue }
            events.append(UsageTracker.notice(w, level: level, now: now))
        }
        first = false
        return events
    }

    /// Zamanı gelen "yenilendi" bildirimleri (söylenmiş bir eşik varsa).
    func tick(now: Date) -> [AgentEvent] {
        var events: [AgentEvent] = []
        for w in windows.values {
            guard let reset = w.resetsAt, reset <= now else { continue }
            windows[w.kind] = UsageWindow(kind: w.kind, percent: 0, resetsAt: nil)
            if (told[w.kind] ?? 0) > 0 {
                told[w.kind] = 0
                let name = UsageLimits.name(w.kind)
                var e = AgentEvent(source: "claude", sessionID: "usage", kind: .insight,
                                   text: loc("\(name) limitin yenilendi", "Your \(name.lowercased()) limit is back"), emoji: "🔋")
                e.usageLeft = 100
                events.append(e)
            }
        }
        return events
    }

    /// Gösterilecek pencereler (oturum, hafta); bilgi eskiyse boş.
    func current(now: Date) -> [UsageWindow] {
        guard let at = updatedAt, now.timeIntervalSince(at) <= UsageTracker.stale else { return [] }
        return windows.values
            .map { w in
                if let r = w.resetsAt, r <= now { return UsageWindow(kind: w.kind, percent: 0, resetsAt: nil) }
                return w
            }
            .sorted { ($0.kind == "five_hour" ? 0 : 1) < ($1.kind == "five_hour" ? 0 : 1) }
    }

    /// Gözdeki "%" için kalan yüzde (en dolu pencereye göre).
    func left(now: Date) -> Int? {
        let c = current(now: now)
        guard let most = c.map(\.percent).max() else { return nil }
        return 100 - most
    }

    private static func notice(_ w: UsageWindow, level: Int, now: Date) -> AgentEvent {
        let name = UsageLimits.name(w.kind)
        var text = level >= 2
            ? loc("\(name) limiti neredeyse bitti (%\(w.percent))", "\(name) limit almost used up (\(w.percent)%)")
            : loc("\(name) limitinin %\(w.percent)'i doldu", "\(name) limit is \(w.percent)% used")
        if let fill = UsageLimits.fillsAt(w, now: now) {
            text += " · " + loc("\(UsageLimits.clock(fill, now: now))'ta dolar", "full at \(UsageLimits.clock(fill, now: now))")
        } else if let reset = w.resetsAt {
            text += " · " + loc("\(UsageLimits.clock(reset, now: now))'de yenilenir", "resets \(UsageLimits.clock(reset, now: now))")
        }
        var e = AgentEvent(source: "claude", sessionID: "usage", kind: .insight, text: text, emoji: level >= 2 ? "🪫" : "🔋")
        e.important = level >= 2
        e.usageLeft = 100 - w.percent
        return e
    }
}

/// Bir sohbet aynı adımı (aynı komut ya da aynı dosya) üst üste 3 kez başarısız deniyorsa "takıldı".
final class StuckWatch {
    static let at = 3
    private struct Run { let key: String; let fails: Int; let told: Bool }
    private var runs: [String: Run] = [:]

    /// Takıldıysa denenen şeyin kısa adı (bir kez), yoksa nil.
    func step(chat: String, hook: String, _ j: [String: Any]) -> String? {
        if hook == "UserPromptSubmit" || hook == "SessionEnd" { runs[chat] = nil; return nil }
        guard hook == "PostToolUse" || hook == "PostToolUseFailure",
              let tool = j["tool_name"] as? String, !tool.isEmpty else { return nil }
        let input = j["tool_input"] as? [String: Any] ?? [:]
        let command = ToolDescriber.commandString(input)
        let file = input["file_path"] as? String
        let target = command ?? file ?? ""
        guard !target.isEmpty else { return nil }
        let key = tool + "\n" + target
        let failed = hook == "PostToolUseFailure" || Reactions.looksFailed(j["tool_response"])
        let run = runs[chat]
        guard failed else {
            if run?.key == key { runs[chat] = nil }
            return nil
        }
        let same = run?.key == key
        let fails = same ? (run?.fails ?? 0) + 1 : 1
        let stuck = fails >= StuckWatch.at && !(same && (run?.told ?? false))
        runs[chat] = Run(key: key, fails: fails, told: (same && (run?.told ?? false)) || stuck)
        guard stuck else { return nil }
        if command == nil, let file = file { return clip(URL(fileURLWithPath: file).lastPathComponent, 50) }
        return clip(target, 50)
    }
}

/// İki farklı sohbet 30 dakika içinde aynı dosyayı düzenlerse (bir kez söylenir).
final class ClashWatch {
    static let window: TimeInterval = 30 * 60
    private static let editTools = ["Edit", "Write", "MultiEdit", "NotebookEdit"]
    private struct Edit { let chat: String; let path: String; let at: Date }
    private var edits: [Edit] = []
    private var told = Set<String>()

    /// Çakışma varsa diğer sohbet ve dosya yolu.
    func step(chat: String, hook: String, _ j: [String: Any], now: Date) -> (other: String, path: String)? {
        guard hook == "PostToolUse", ClashWatch.editTools.contains(j["tool_name"] as? String ?? "") else { return nil }
        let input = j["tool_input"] as? [String: Any] ?? [:]
        guard let path = (input["file_path"] as? String) ?? (input["notebook_path"] as? String), !path.isEmpty else { return nil }
        edits.removeAll { now.timeIntervalSince($0.at) > ClashWatch.window || ($0.chat == chat && $0.path == path) }
        let other = edits.filter { $0.chat != chat && $0.path == path }.max { $0.at < $1.at }
        edits.append(Edit(chat: chat, path: path, at: now))
        guard let other = other else { return nil }
        let key = [chat, other.chat].sorted().joined(separator: "\n") + "\n" + path
        return told.insert(key).inserted ? (other.chat, path) : nil
    }
}

/// `gh run list --commit SHA --json status,conclusion,name,url` çıktısının özeti.
enum CiStatus {
    struct Result: Equatable {
        let done: Bool
        let ok: Bool
        let failed: String?
        let url: String?
        let count: Int
    }

    static func summarize(_ data: Data) -> Result? {
        guard let runs = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]], !runs.isEmpty else { return nil }
        let done = runs.allSatisfy { ($0["status"] as? String) == "completed" }
        let bad = runs.first { r in
            guard let c = r["conclusion"] as? String, !c.isEmpty else { return false }
            return !["success", "skipped", "neutral"].contains(c)
        }
        return Result(done: done, ok: done && bad == nil,
                      failed: (bad?["name"] as? String) ?? (bad?["workflowName"] as? String),
                      url: (bad ?? runs[0])["url"] as? String, count: runs.count)
    }
}

/// Tur bittiğinde commit'lenmemiş değişiklik var ve son commit 1,5 saatten eskiyse bir kez hatırlat.
final class CommitNudge {
    static let after: TimeInterval = 90 * 60
    static let checkEvery: TimeInterval = 10 * 60
    private var checked: [String: Date] = [:]
    private var toldFor: [String: Date] = [:]   // klasör → hatırlatılan son commit zamanı
    private let lock = NSLock()

    /// Bu klasöre şimdi bakmaya değer mi (10 dk'da bir)?
    func shouldCheck(_ dir: String, now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let at = checked[dir], now.timeIntervalSince(at) < CommitNudge.checkEvery { return false }
        checked[dir] = now
        return true
    }

    func shouldTell(_ dir: String, dirty: Bool, lastCommit: Date?, now: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard dirty, let last = lastCommit, now.timeIntervalSince(last) >= CommitNudge.after else { return false }
        if toldFor[dir] == last { return false }
        toldFor[dir] = last
        return true
    }
}

/// Hook olaylarını ve durum satırını dinler; robotun söyleyeceği uyarıları ve uygulamanın yapacağı işleri
/// (CI'yi izle, commit durumuna bak) döner. Uygulama işleri kendisi çalıştırır (git/gh).
final class Insights {
    struct Job: Equatable {
        let kind: String   // "ci" | "commit"
        let dir: String
        let source: String
        let sessionID: String
    }

    let usage = UsageTracker()
    let nudge = CommitNudge()
    private let stuck = StuckWatch()
    private let clash = ClashWatch()
    private var projects: [String: String] = [:]

    func handle(path: String, query: [String: String], body: Data, now: Date) -> (events: [AgentEvent], jobs: [Job]) {
        if path.hasPrefix("/statusline") { return (usage.update(body, now: now), []) }
        guard let j = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let hook = j["hook_event_name"] as? String else { return ([], []) }
        var events: [AgentEvent] = []
        var jobs: [Job] = []
        let source = Themes.canonical(query["source"] ?? "claude")
        let session = j["session_id"] as? String ?? "default"
        let chat = source + ":" + session
        let cwd = j["cwd"] as? String
        if let cwd = cwd, !cwd.isEmpty { projects[chat] = Insights.project(cwd) }

        if let what = stuck.step(chat: chat, hook: hook, j) {
            var e = AgentEvent(source: source, sessionID: session, kind: .insight,
                               text: loc("Takıldı gibi: aynı adım \(StuckWatch.at) kez başarısız (\(what))",
                                         "Looks stuck: the same step failed \(StuckWatch.at) times (\(what))"),
                               emoji: "🔁")
            e.mood = .nervous
            e.moodSeconds = 4
            events.append(e)
        }
        if let hit = clash.step(chat: chat, hook: hook, j, now: now) {
            let file = URL(fileURLWithPath: hit.path).lastPathComponent
            var who = ""
            if let mine = projects[chat], let theirs = projects[hit.other], mine != theirs { who = " (\(mine) · \(theirs))" }
            var e = AgentEvent(source: source, sessionID: session, kind: .insight,
                               text: loc("İki sohbet aynı dosyayı düzenliyor: \(file)\(who)",
                                         "Two chats are editing the same file: \(file)\(who)"),
                               emoji: "⚠️")
            e.mood = .nervous
            e.moodSeconds = 3
            e.important = true
            events.append(e)
        }
        if let cwd = cwd, !cwd.isEmpty {
            let input = j["tool_input"] as? [String: Any] ?? [:]
            if hook == "PostToolUse", !Reactions.looksFailed(j["tool_response"]),
               Reactions.isPush(ToolDescriber.commandString(input) ?? "") {
                jobs.append(Job(kind: "ci", dir: cwd, source: source, sessionID: session))
            }
            if hook == "Stop" && nudge.shouldCheck(cwd, now: now) {
                jobs.append(Job(kind: "commit", dir: cwd, source: source, sessionID: session))
            }
        }
        return (events, jobs)
    }

    static func project(_ dir: String) -> String {
        URL(fileURLWithPath: dir).lastPathComponent
    }

    /// CI bitti: "CI geçti" / "CI kırmızı: Build"
    static func ciEvent(_ job: Job, _ r: CiStatus.Result) -> AgentEvent {
        let project = project(job.dir)
        var e: AgentEvent
        if r.ok {
            e = AgentEvent(source: job.source, sessionID: job.sessionID, kind: .insight,
                           text: loc("CI geçti (\(project))", "CI passed (\(project))"), emoji: "✅")
            e.mood = .pleased
            e.moodSeconds = 3
        } else {
            e = AgentEvent(source: job.source, sessionID: job.sessionID, kind: .insight,
                           text: loc("CI kırmızı: \(r.failed ?? "?") (\(project))", "CI failed: \(r.failed ?? "?") (\(project))"), emoji: "❌")
            e.mood = .nervous
            e.moodSeconds = 4
            e.important = true
        }
        return e
    }

    /// Commit'lenmemiş iş hatırlatması
    static func commitEvent(_ job: Job, lastCommit: Date, now: Date) -> AgentEvent {
        let ago = shortDuration(now.timeIntervalSince(lastCommit))
        return AgentEvent(source: job.source, sessionID: job.sessionID, kind: .insight,
                          text: loc("Commit'lenmemiş değişiklikler var · son commit \(ago) önce (\(project(job.dir)))",
                                    "Uncommitted changes · last commit \(ago) ago (\(project(job.dir)))"),
                          emoji: "💾")
    }
}

/// Sakin çizim: robot boştayken (hiçbir şey olmuyorsa) yeniden çizilmez; sadece göz kırpma anlarında birkaç kare.
/// Süzülme sakinleşirken 0,8 sn'de yumuşakça durur, iş gelince yumuşakça başlar.
enum Calm {
    static let settle = 0.8

    /// Göz kırpması 4,2 sn'de bir, 0,12 sn sürer; biraz öncesinden sonrasına kadar çiz.
    static func inBlink(_ time: Double) -> Bool {
        var m = time.truncatingRemainder(dividingBy: 4.2)
        if m < 0 { m += 4.2 }
        return m > 4.1 || m < 0.22
    }

    /// 0 = normal hareket, 1 = tamamen dingin. from: geçiş anındaki dinginlik (yarıda kalan geçiş sıçramasın).
    static func stillness(calm: Bool, since: Double, time: Double, from: Double) -> Double {
        let t = Swift.min(1, Swift.max(0, (time - since) / settle))
        return calm ? from + (1 - from) * t : from * (1 - t)
    }

    /// Çizim durabilir mi: dingin, yerleşmiş ve göz kırpma anında değil.
    static func paused(calm: Bool, since: Double, time: Double) -> Bool {
        calm && time - since >= settle && !inBlink(time)
    }
}

/// Sakin çizim durumu (robot penceresi bunu kafanın çizimine verir).
struct CalmState: Equatable {
    var calm = false
    var since = 0.0
    var from = 0.0
    var reduceMotion = false

    func stillness(at time: Double) -> Double {
        reduceMotion ? 1 : Calm.stillness(calm: calm, since: since, time: time, from: from)
    }
}
