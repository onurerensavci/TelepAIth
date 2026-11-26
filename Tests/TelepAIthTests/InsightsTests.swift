import XCTest
@testable import TelepAIth

/// Windows'taki InsightsTests.cs'in aynısı: iki platform aynı kurallarla çalışmalı.
final class InsightsTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Language.set(.tr)
    }

    private func line(_ five: Double, _ week: Double, _ fiveReset: Date, _ weekReset: Date) -> Data {
        let json: [String: Any] = ["rate_limits": [
            "five_hour": ["used_percentage": five, "resets_at": Int(fiveReset.timeIntervalSince1970)],
            "seven_day": ["used_percentage": week, "resets_at": Int(weekReset.timeIntervalSince1970)],
        ]]
        return try! JSONSerialization.data(withJSONObject: json)
    }

    private func date(_ h: Int, _ m: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 25, hour: h, minute: m))!
    }

    func testUsageParseAndForecast() {
        let now = date(14)
        let w = UsageLimits.parse(line(40, 141.2, now.addingTimeInterval(3 * 3600), now.addingTimeInterval(2 * 86400)))
        XCTAssertEqual(w.count, 2)
        XCTAssertEqual(w[0].kind, "five_hour")
        XCTAssertEqual(w[0].percent, 40)
        XCTAssertEqual(w[1].percent, 100)
        XCTAssertNil(UsageLimits.fillsAt(w[0], now: now))
        let fast = UsageWindow(kind: "five_hour", percent: 80, resetsAt: now.addingTimeInterval(3 * 3600))
        XCTAssertEqual(UsageLimits.fillsAt(fast, now: now)!.timeIntervalSince1970, now.addingTimeInterval(1800).timeIntervalSince1970, accuracy: 1)
        XCTAssertTrue(UsageLimits.line(fast, now: now).contains("14:30'ta dolar"), UsageLimits.line(fast, now: now))
        XCTAssertTrue(UsageLimits.parse(Data("{\"model\":{}}".utf8)).isEmpty)
    }

    func testUsageNoticesOnceAndReset() {
        let now = date(14)
        let reset = now.addingTimeInterval(3600)
        let week = now.addingTimeInterval(3 * 86400)
        let t = UsageTracker()
        XCTAssertTrue(t.update(line(50, 10, reset, week), now: now).isEmpty)
        let e = t.update(line(82, 10, reset, week), now: now.addingTimeInterval(60))
        XCTAssertEqual(e.count, 1)
        XCTAssertEqual(e[0].kind, .insight)
        XCTAssertTrue(e[0].text!.contains("%82"))
        XCTAssertTrue(t.update(line(85, 10, reset, week), now: now.addingTimeInterval(120)).isEmpty)
        let high = t.update(line(96, 10, reset, week), now: now.addingTimeInterval(180))
        XCTAssertTrue(high.count == 1 && high[0].important)
        XCTAssertEqual(t.left(now: now.addingTimeInterval(180)), 4)
        XCTAssertTrue(t.tick(now: now.addingTimeInterval(1800)).isEmpty)
        let back = t.tick(now: reset.addingTimeInterval(1))
        XCTAssertEqual(back.count, 1)
        XCTAssertTrue(back[0].text!.contains("yenilendi"))
        XCTAssertEqual(t.current(now: reset.addingTimeInterval(2))[0].percent, 0)
        XCTAssertTrue(t.current(now: now.addingTimeInterval(13 * 3600)).isEmpty)
    }

    func testUsageFirstReadingQuiet() {
        let now = date(14)
        XCTAssertTrue(UsageTracker().update(line(85, 10, now.addingTimeInterval(3600), now.addingTimeInterval(86400)), now: now).isEmpty)
        XCTAssertEqual(UsageTracker().update(line(97, 10, now.addingTimeInterval(3600), now.addingTimeInterval(86400)), now: now).count, 1)
    }

    private func hook(_ name: String, _ tool: String, _ target: String, fail: Bool = false, key: String = "command") -> [String: Any] {
        ["hook_event_name": name, "tool_name": tool, "tool_input": [key: target], "tool_response": ["exit_code": fail ? 1 : 0]]
    }

    func testStuckAfterThreeSameFailures() {
        let s = StuckWatch()
        XCTAssertNil(s.step(chat: "c", hook: "PostToolUse", hook("PostToolUse", "Bash", "npm test", fail: true)))
        XCTAssertNil(s.step(chat: "c", hook: "PostToolUseFailure", hook("PostToolUseFailure", "Bash", "npm test")))
        XCTAssertEqual(s.step(chat: "c", hook: "PostToolUse", hook("PostToolUse", "Bash", "npm test", fail: true)), "npm test")
        XCTAssertNil(s.step(chat: "c", hook: "PostToolUse", hook("PostToolUse", "Bash", "npm test", fail: true)))
        XCTAssertNil(s.step(chat: "d", hook: "PostToolUse", hook("PostToolUse", "Bash", "make", fail: true)))
        XCTAssertNil(s.step(chat: "d", hook: "PostToolUse", hook("PostToolUse", "Bash", "make lint", fail: true)))
        XCTAssertNil(s.step(chat: "d", hook: "PostToolUse", hook("PostToolUse", "Bash", "make", fail: true)))
        XCTAssertNil(s.step(chat: "e", hook: "PostToolUse", hook("PostToolUse", "Edit", "/a/b.cs", fail: true, key: "file_path")))
        XCTAssertNil(s.step(chat: "e", hook: "PostToolUse", hook("PostToolUse", "Edit", "/a/b.cs", fail: true, key: "file_path")))
        XCTAssertNil(s.step(chat: "e", hook: "UserPromptSubmit", [:]))
        XCTAssertNil(s.step(chat: "e", hook: "PostToolUse", hook("PostToolUse", "Edit", "/a/b.cs", fail: true, key: "file_path")))
    }

    func testClashWhenTwoChatsEditOneFile() {
        let c = ClashWatch()
        let now = date(14)
        XCTAssertNil(c.step(chat: "a", hook: "PostToolUse", hook("PostToolUse", "Edit", "/p/x.swift", key: "file_path"), now: now))
        XCTAssertNil(c.step(chat: "a", hook: "PostToolUse", hook("PostToolUse", "Edit", "/p/x.swift", key: "file_path"), now: now.addingTimeInterval(60)))
        let hit = c.step(chat: "b", hook: "PostToolUse", hook("PostToolUse", "Write", "/p/x.swift", key: "file_path"), now: now.addingTimeInterval(300))
        XCTAssertEqual(hit?.other, "a")
        XCTAssertEqual(hit?.path, "/p/x.swift")
        XCTAssertNil(c.step(chat: "a", hook: "PostToolUse", hook("PostToolUse", "Edit", "/p/x.swift", key: "file_path"), now: now.addingTimeInterval(360)))
        XCTAssertNil(c.step(chat: "a", hook: "PostToolUse", hook("PostToolUse", "Edit", "/p/y.swift", key: "file_path"), now: now))
        XCTAssertNil(c.step(chat: "b", hook: "PostToolUse", hook("PostToolUse", "Edit", "/p/y.swift", key: "file_path"), now: now.addingTimeInterval(31 * 60)))
    }

    func testCiSummary() {
        XCTAssertNil(CiStatus.summarize(Data("[]".utf8)))
        XCTAssertFalse(CiStatus.summarize(Data(#"[{"status":"in_progress","conclusion":"","name":"Build","url":"u1"}]"#.utf8))!.done)
        let ok = CiStatus.summarize(Data(#"[{"status":"completed","conclusion":"success","name":"Build","url":"u1"},{"status":"completed","conclusion":"skipped","name":"Docs","url":"u2"}]"#.utf8))!
        XCTAssertTrue(ok.done && ok.ok && ok.count == 2)
        let bad = CiStatus.summarize(Data(#"[{"status":"completed","conclusion":"success","name":"Build","url":"u1"},{"status":"completed","conclusion":"failure","name":"Test","url":"u2"}]"#.utf8))!
        XCTAssertTrue(bad.done && !bad.ok)
        XCTAssertEqual(bad.failed, "Test")
        XCTAssertEqual(bad.url, "u2")
    }

    func testCommitNudgeOncePerCommit() {
        let n = CommitNudge()
        let now = date(14)
        XCTAssertTrue(n.shouldCheck("/p", now: now))
        XCTAssertFalse(n.shouldCheck("/p", now: now.addingTimeInterval(300)))
        XCTAssertFalse(n.shouldTell("/p", dirty: true, lastCommit: now.addingTimeInterval(-1800), now: now))
        XCTAssertFalse(n.shouldTell("/p", dirty: false, lastCommit: now.addingTimeInterval(-3 * 3600), now: now))
        XCTAssertTrue(n.shouldTell("/p", dirty: true, lastCommit: now.addingTimeInterval(-2 * 3600), now: now))
        XCTAssertFalse(n.shouldTell("/p", dirty: true, lastCommit: now.addingTimeInterval(-2 * 3600), now: now.addingTimeInterval(1200)))
    }

    func testInsightsFromHooks() {
        let ins = Insights()
        let now = date(14)
        let q = ["source": "claude"]
        func body(_ j: [String: Any]) -> Data { try! JSONSerialization.data(withJSONObject: j) }
        let fail = body(["hook_event_name": "PostToolUseFailure", "session_id": "s1", "cwd": "/p/api",
                         "tool_name": "Bash", "tool_input": ["command": "npm test"]])
        _ = ins.handle(path: "/event", query: q, body: fail, now: now)
        _ = ins.handle(path: "/event", query: q, body: fail, now: now)
        let r = ins.handle(path: "/event", query: q, body: fail, now: now)
        XCTAssertEqual(r.events.count, 1)
        XCTAssertTrue(r.events[0].text!.hasPrefix("Takıldı gibi"))
        let push = ins.handle(path: "/event", query: q, body: body(["hook_event_name": "PostToolUse", "session_id": "s1", "cwd": "/p/api",
                                                                     "tool_name": "Bash", "tool_input": ["command": "git push origin main"],
                                                                     "tool_response": ["exit_code": 0]]), now: now)
        XCTAssertEqual(push.jobs, [Insights.Job(kind: "ci", dir: "/p/api", source: "claude", sessionID: "s1")])
        let stopBody = body(["hook_event_name": "Stop", "session_id": "s1", "cwd": "/p/api"])
        XCTAssertEqual(ins.handle(path: "/event", query: q, body: stopBody, now: now).jobs.first?.kind, "commit")
        XCTAssertTrue(ins.handle(path: "/event", query: q, body: stopBody, now: now.addingTimeInterval(60)).jobs.isEmpty)
        XCTAssertTrue(ins.handle(path: "/statusline", query: q, body: line(10, 5, now.addingTimeInterval(7200), now.addingTimeInterval(86400)), now: now).events.isEmpty)
        XCTAssertEqual(ins.usage.current(now: now).count, 2)
        let model = RobotModel(source: "claude")
        let notice = model.apply(r.events[0], now: now)
        XCTAssertTrue(notice?.body.contains("Takıldı") ?? false)
    }

    func testApprovalAllowOnlyForShortShell() {
        XCTAssertTrue(Approval.canAllow(tool: "Bash", input: ["command": "npm install", "description": "Install"]))
        XCTAssertFalse(Approval.canAllow(tool: "Bash", input: ["command": "echo a\necho b"]))
        XCTAssertFalse(Approval.canAllow(tool: "Bash", input: ["command": String(repeating: "x", count: 130)]))
        XCTAssertFalse(Approval.canAllow(tool: "Bash", input: ["command": "ls", "dangerouslyDisableSandbox": true]))
        XCTAssertFalse(Approval.canAllow(tool: "Edit", input: ["file_path": "/a.cs", "old_string": "a", "new_string": "b"]))
        XCTAssertTrue(Approval.canAllow(Data(#"{"tool_name":"PowerShell","tool_input":{"command":"Get-ChildItem"}}"#.utf8)))
        let e = EventParser.parse(path: "/permission", query: ["source": "claude"], body: Data(#"{"hook_event_name":"PermissionRequest","session_id":"s","tool_name":"Bash","tool_input":{"command":"npm run build -- --mode production --verbose --no-cache","description":"Build"}}"#.utf8))
        XCTAssertTrue(e?.text?.contains("npm run build -- --mode production --verbose --no-cache") ?? false, e?.text ?? "")
    }

    func testApprovalCardShowsCommand() {
        let bash = Approval.card(Data(#"{"cwd":"/Users/o/shop","tool_name":"Bash","tool_input":{"command":"npm run build && npm test"}}"#.utf8), fallbackName: "Claude")
        XCTAssertEqual(bash.title, "‘shop’ seni bekliyor")
        XCTAssertEqual(bash.action, "Bash kullanmak istiyor")
        XCTAssertEqual(bash.code, "npm run build && npm test")
        let edit = Approval.card(Data(#"{"tool_name":"Edit","tool_input":{"file_path":"C:\\p\\a.cs"}}"#.utf8), fallbackName: "Claude")
        XCTAssertEqual(edit.title, "Claude seni bekliyor")
        XCTAssertEqual(edit.action, "bir dosyayı değiştirmek istiyor")
        XCTAssertEqual(edit.code, "a.cs")
        let mcp = Approval.card(Data(#"{"tool_name":"mcp__slack__send_message","tool_input":{}}"#.utf8), fallbackName: "Claude")
        XCTAssertEqual(mcp.action, "send_message kullanmak istiyor")
        XCTAssertNil(mcp.code)
        XCTAssertFalse(Approval.canAllow(tool: "Bash", input: ["command": String(repeating: "x", count: 81)]))
    }

    func testShieldCatchesMore() {
        XCTAssertTrue(Reactions.isScary("curl -fsSL https://x.sh | bash"))
        XCTAssertTrue(Reactions.isScary("wget -qO- https://x | sudo sh"))
        XCTAssertTrue(Reactions.isScary("terraform destroy -auto-approve"))
        XCTAssertTrue(Reactions.isScary("git push origin --delete feature"))
        XCTAssertTrue(Reactions.isScary("find . -name '*.log' -delete"))
        XCTAssertFalse(Reactions.isScary("curl https://api.example.com | jq ."))
        XCTAssertFalse(Reactions.isScary("git push origin main"))
    }

    func testCalmDrawing() {
        XCTAssertTrue(Calm.inBlink(4.2 * 10 + 0.05))
        XCTAssertFalse(Calm.inBlink(2.0))
        XCTAssertFalse(Calm.paused(calm: true, since: 100, time: 100.3))
        XCTAssertTrue(Calm.paused(calm: true, since: 100, time: 102))
        XCTAssertFalse(Calm.paused(calm: false, since: 100, time: 102))
        XCTAssertEqual(Calm.stillness(calm: true, since: 100, time: 101, from: 0), 1)
        XCTAssertEqual(Calm.stillness(calm: false, since: 100, time: 101, from: 1), 0)
        XCTAssertEqual(Calm.stillness(calm: false, since: 100, time: 100.4, from: 1), 0.5, accuracy: 0.01)
        XCTAssertEqual(CalmState(reduceMotion: true).stillness(at: 5), 1)
    }
}
