import XCTest
@testable import TelepAIth

final class TelepAIthTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Language.set(.tr)
    }

    func testScaryCommands() {
        XCTAssertTrue(Reactions.isScary("rm -rf build"))
        XCTAssertTrue(Reactions.isScary("git push --force origin main"))
        XCTAssertTrue(Reactions.isScary("git reset --hard HEAD~1"))
        XCTAssertFalse(Reactions.isScary("git push origin main"))
        XCTAssertFalse(Reactions.isScary("ls -la"))
    }

    func testTestCommands() {
        XCTAssertTrue(Reactions.isTest("npm test"))
        XCTAssertTrue(Reactions.isTest("swift test"))
        XCTAssertFalse(Reactions.isTest("npm install foo@latest"))
        XCTAssertTrue(Reactions.isCommit("git commit -m 'x'"))
        XCTAssertTrue(Reactions.isPush("git push origin main"))
    }

    func testCommandEmoji() {
        XCTAssertEqual(ToolDescriber.commandEmoji("git push"), "🚀")
        XCTAssertEqual(ToolDescriber.commandEmoji("npm install react"), "📦")
        XCTAssertEqual(ToolDescriber.commandEmoji("npm test"), "🧪")
        XCTAssertEqual(ToolDescriber.commandEmoji("echo hi"), "💻")
    }

    func testPromptReactions() {
        XCTAssertEqual(Reactions.onPrompt("teşekkürler harika oldu")?.mood, .pleased)
        XCTAssertEqual(Reactions.onPrompt("NEDEN HALA ÇALIŞMIYOR BU")?.mood, .shocked)
        XCTAssertEqual(Reactions.onPrompt("neden çalışmıyor")?.mood, .nervous)
        XCTAssertNil(Reactions.onPrompt("bir liste yap"))
    }

    func testHookParsing() {
        let json = #"{"hook_event_name":"PreToolUse","session_id":"s1","cwd":"/x/proj","tool_name":"Bash","tool_input":{"command":"npm test"}}"#
        let e = EventParser.parse(path: "/event", query: ["source": "claude"], body: Data(json.utf8))
        XCTAssertEqual(e?.source, "claude")
        XCTAssertEqual(e?.kind, .tool)
        XCTAssertEqual(e?.state, .running)
        XCTAssertEqual(e?.project, "proj")
        XCTAssertEqual(e?.mood, .nervous)
    }

    func testCodexPatchFile() {
        let input: [String: Any] = ["input": "*** Begin Patch\n*** Update File: src/app.ts\n@@"]
        let d = ToolDescriber.describe(tool: "apply_patch", input: input)
        XCTAssertEqual(d.state, .editing)
        XCTAssertEqual(d.text, "Düzenliyor: app.ts")
    }

    func testGenericEventAndAliases() {
        let e = EventParser.parse(path: "/event", query: ["source": "codex"], body: Data(#"{"state":"done","text":"ok"}"#.utf8))
        XCTAssertEqual(e?.source, "gpt")
        XCTAssertEqual(e?.kind, .stop)
        XCTAssertNil(EventParser.parse(path: "/event", query: [:], body: Data("{}".utf8)))
    }

    func testClaudeBarWebhook() {
        let e = EventParser.parse(path: "/claudebar", query: [:], body: Data(#"{"type":"quota","provider":"claude","left":18}"#.utf8))
        XCTAssertEqual(e?.kind, .quota)
        XCTAssertEqual(e?.text, "Kalan kota: %18")
    }

    func testVersionCompare() {
        XCTAssertTrue(Updater.isNewer("0.10.0", than: "0.9.3"))
        XCTAssertFalse(Updater.isNewer("0.8.3", than: "0.8.3"))
        XCTAssertTrue(Updater.isNewer("1.0", than: "0.9.9"))
    }

    func testDuration() {
        XCTAssertEqual(formatDuration(42), "42 sn")
        XCTAssertEqual(formatDuration(75), "1 dk 15 sn")
        XCTAssertEqual(formatDuration(3600), "1 sa")
    }

    func testWorkPhases() {
        XCTAssertEqual(AppWatcher.WorkPhase.match("searched the web"), .looking)
        XCTAssertEqual(AppWatcher.WorkPhase.match("ran 4 commands"), .running)
        XCTAssertEqual(AppWatcher.WorkPhase.match("running tests"), .testing)
        XCTAssertEqual(AppWatcher.WorkPhase.match("checking the github build"), .reading)
        XCTAssertNil(AppWatcher.WorkPhase.match("hmm"))
    }

    func testHTTPParsing() {
        let raw = "POST /event?source=claude HTTP/1.1\r\nHost: x\r\nContent-Length: 2\r\n\r\n{}"
        guard case .complete(let request) = HTTPRequest.parse(Data(raw.utf8)) else {
            return XCTFail("istek tamamlanmalıydı")
        }
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.path, "/event")
        XCTAssertEqual(request.query["source"], "claude")
        XCTAssertEqual(request.body, Data("{}".utf8))
    }

    func testQuotaLeftFromClaudeBar() {
        let e = EventParser.parse(path: "/claudebar", query: [:], body: Data(#"{"type":"quota","provider":"claude","left":18}"#.utf8))
        XCTAssertEqual(e?.quotaLeft, 18)
        let m = RobotModel(source: "claude")
        _ = m.apply(e!)
        XCTAssertEqual(m.quotaLeft, 18)
    }

    func testTerminalTarget() {
        XCTAssertEqual(AppTarget.bundleID(app: "com.apple.Terminal", term: "iTerm.app"), "com.apple.Terminal")
        XCTAssertEqual(AppTarget.bundleID(app: "", term: "iTerm.app"), "com.googlecode.iterm2")
        XCTAssertNil(AppTarget.bundleID(app: nil, term: "unknown"))
        let body = Data(#"{"hook_event_name":"UserPromptSubmit","session_id":"s1","prompt":"merhaba"}"#.utf8)
        let e = EventParser.parse(path: "/event", query: ["source": "claude", "app": "com.mitchellh.ghostty"], body: body)
        XCTAssertEqual(e?.appBundleID, "com.mitchellh.ghostty")
        XCTAssertTrue(HookInstaller.command(source: "claude").contains("app=${__CFBundleIdentifier:-}"))
    }

    func testGesturesAndEyeGlyphs() {
        let m = RobotModel(source: "claude")
        let t0 = Date()
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .prompt, state: .thinking, text: "x"), now: t0)
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .waiting, state: .waiting, text: "onay"), now: t0.addingTimeInterval(1))
        XCTAssertEqual(m.eyeGlyph(at: t0.addingTimeInterval(1.5)), "!")
        var q = AgentEvent(source: "claude", sessionID: "s", kind: .waiting, state: .waiting, text: "Bir soru?")
        q.emoji = "❓"
        _ = m.apply(q, now: t0.addingTimeInterval(2))
        XCTAssertTrue(m.isAsking)
        XCTAssertEqual(m.eyeGlyph(at: t0.addingTimeInterval(2.5)), "?")
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .toolDone, state: .thinking), now: t0.addingTimeInterval(3))
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .stop, state: .done), now: t0.addingTimeInterval(4))
        XCTAssertEqual(m.gesture, Gesture.none)   // başparmak kaldırıldı; normal bitişte el hareketi yok
        XCTAssertEqual(m.eyeGlyph(at: m.visualChangedAt.addingTimeInterval(0.5)), "✓")
        XCTAssertNil(m.eyeGlyph(at: m.visualChangedAt.addingTimeInterval(2)))
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .prompt, state: .thinking, text: "y"), now: t0.addingTimeInterval(10))
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .failure, state: .error, text: "patladı"), now: t0.addingTimeInterval(11))
        XCTAssertEqual(m.gesture, .facepalm)
        let w = RobotModel(source: "gpt")
        w.wake(greet: "Merhaba", always: true)
        XCTAssertEqual(w.gesture, .wave)
        w.react(.dizzy, for: 2.5, say: "Başım döndü!")
        XCTAssertEqual(w.mood, .dizzy)
        XCTAssertNil(w.eyeGlyph(at: Date()))
    }

    func testDisplayStaysPutWhileBothWork() {
        let claude = RobotModel(source: "claude"), gpt = RobotModel(source: "gpt")
        let all = [claude, gpt]
        let t0 = Date()
        _ = claude.apply(AgentEvent(source: "claude", sessionID: "app-1-0", kind: .prompt, state: .thinking, text: "a"), now: t0)
        var shown = RobotModel.pickDisplay(all, current: claude, now: t0) ?? claude
        XCTAssertTrue(shown === claude)
        // ChatGPT'ye de yazdın: en son başlayan öne çıkar
        _ = gpt.apply(AgentEvent(source: "gpt", sessionID: "app-2-0", kind: .prompt, state: .thinking, text: "b"), now: t0.addingTimeInterval(5))
        shown = RobotModel.pickDisplay(all, current: shown, now: t0.addingTimeInterval(5)) ?? shown
        XCTAssertTrue(shown === gpt)
        // İkisi de çalışırken Claude'un aşama mesajları kafayı geri çekmez
        for i in 0..<10 {
            let at = t0.addingTimeInterval(6 + Double(i) * 2)
            _ = claude.apply(AgentEvent(source: "claude", sessionID: "app-1-0", kind: .status,
                                        state: i % 2 == 0 ? .reading : .editing, text: "aşama \(i)"), now: at)
            gpt.refresh(now: at)
            XCTAssertNil(RobotModel.pickDisplay(all, current: shown, now: at), "aşama \(i)")
        }
        let minis = RobotModel.minis(all, current: shown, now: t0.addingTimeInterval(30))
        XCTAssertEqual(minis.map { $0.source }, ["claude"])
        // Claude onay isteyince öne geçer
        _ = claude.apply(AgentEvent(source: "claude", sessionID: "app-1-0", kind: .waiting, state: .waiting, text: "onay"),
                         now: t0.addingTimeInterval(31))
        gpt.refresh(now: t0.addingTimeInterval(31))
        shown = RobotModel.pickDisplay(all, current: shown, now: t0.addingTimeInterval(31)) ?? shown
        XCTAssertTrue(shown === claude)
        XCTAssertEqual(RobotModel.minis(all, current: shown, now: t0.addingTimeInterval(31)).map { $0.source }, ["gpt"])
    }

    func testGazeWaitsUntilAllQuiet() {
        let claude = RobotModel(source: "claude"), gpt = RobotModel(source: "gpt")
        let all = [claude, gpt]
        let t0 = Date()
        XCTAssertTrue(RobotModel.canGaze(all, now: t0))
        _ = claude.apply(AgentEvent(source: "claude", sessionID: "s", kind: .prompt, state: .thinking, text: "a"), now: t0)
        _ = gpt.apply(AgentEvent(source: "gpt", sessionID: "g", kind: .prompt, state: .thinking, text: "b"), now: t0)
        XCTAssertFalse(RobotModel.canGaze(all, now: t0.addingTimeInterval(1)))
        _ = claude.apply(AgentEvent(source: "claude", sessionID: "s", kind: .stop, state: .done), now: t0.addingTimeInterval(10))
        claude.refresh(now: t0.addingTimeInterval(40))
        gpt.refresh(now: t0.addingTimeInterval(40))
        XCTAssertFalse(RobotModel.canGaze(all, now: t0.addingTimeInterval(40)), "öteki AI çalışırken izlemez")
        XCTAssertFalse(RobotModel.pinWins(claude, among: all))
        gpt.refresh(now: t0.addingTimeInterval(49.9))
        _ = gpt.apply(AgentEvent(source: "gpt", sessionID: "g", kind: .stop, state: .done), now: t0.addingTimeInterval(50))
        claude.refresh(now: t0.addingTimeInterval(60))
        gpt.refresh(now: t0.addingTimeInterval(60))
        XCTAssertFalse(RobotModel.canGaze(all, now: t0.addingTimeInterval(60)), "bitince 20 sn beklenir")
        claude.refresh(now: t0.addingTimeInterval(71))
        gpt.refresh(now: t0.addingTimeInterval(71))
        XCTAssertTrue(RobotModel.canGaze(all, now: t0.addingTimeInterval(71)))
        XCTAssertTrue(RobotModel.pinWins(claude, among: all))
    }

    func testSidebarStatusWords() {
        XCTAssertEqual(SidebarChats.statusOf("Running"), .running)
        XCTAssertEqual(SidebarChats.statusOf("Tarif önerisi, running"), .running)
        XCTAssertEqual(SidebarChats.statusOf("Kod incelemesi · Awaiting answer"), .waiting)
        XCTAssertNil(SidebarChats.statusOf("Running a marathon plan"))
        XCTAssertNil(SidebarChats.statusOf("Working with CSV files"))
        XCTAssertEqual(SidebarChats.stripStatus("Tarif önerisi, running"), "Tarif önerisi")
        XCTAssertEqual(SidebarChats.stripStatus("Kod (running)"), "Kod")
    }

    func testSidebarBackgroundChats() {
        let bg = SidebarChats(source: "claude", pid: 77)
        func row(_ i: Int) -> CGRect { CGRect(x: 10, y: 100 + i * 30, width: 240, height: 28) }
        func dot(_ i: Int) -> CGRect { CGRect(x: 230, y: 108 + i * 30, width: 8, height: 8) }
        var items = [
            SidebarItem(name: "Sohbet A", help: "", url: "https://claude.ai/chat/aaa", rect: row(0), current: true),
            SidebarItem(name: "", help: "Running", url: nil, rect: dot(0)),
            SidebarItem(name: "Sohbet B", help: "", url: "https://claude.ai/chat/bbb", rect: row(1)),
            SidebarItem(name: "", help: "Running", url: nil, rect: dot(1)),
            SidebarItem(name: "Sohbet C", help: "", url: "https://claude.ai/chat/ccc", rect: row(2)),
        ]
        var ev = bg.update(items, currentChat: "https://claude.ai/chat/aaa", now: 0)
        XCTAssertEqual(ev.count, 1)
        XCTAssertEqual(ev.first?.kind, .prompt)
        XCTAssertEqual(ev.first?.project, "Sohbet B")
        XCTAssertEqual(ev.first?.appPID, 77)
        let id = ev[0].sessionID
        XCTAssertTrue(id.hasPrefix("bg-77-"))
        XCTAssertNotEqual(RobotModel.sessionGroup(id), "desktop")
        XCTAssertTrue(bg.update(items, currentChat: "https://claude.ai/chat/aaa", now: 10).isEmpty)
        ev = bg.update(items, currentChat: "https://claude.ai/chat/aaa", now: 25)
        XCTAssertEqual(ev.map { $0.kind }, [.heartbeat])
        items[2] = SidebarItem(name: "Sohbet B, awaiting answer", help: "", url: "https://claude.ai/chat/bbb", rect: row(1))
        items.remove(at: 3)
        ev = bg.update(items, currentChat: "https://claude.ai/chat/aaa", now: 30)
        XCTAssertEqual(ev.map { $0.kind }, [.waiting])
        items[2] = SidebarItem(name: "Sohbet B", help: "", url: "https://claude.ai/chat/bbb", rect: row(1))
        items.append(SidebarItem(name: "", help: "Running", url: nil, rect: dot(1)))
        ev = bg.update(items, currentChat: "https://claude.ai/chat/aaa", now: 40)
        XCTAssertEqual(ev.map { $0.kind }, [.status])
        items.removeLast()
        ev = bg.update(items, currentChat: "https://claude.ai/chat/aaa", now: 60)
        XCTAssertEqual(ev.map { $0.kind }, [.stop])
        XCTAssertTrue(ev[0].forceNotify)
        XCTAssertEqual(ev[0].sessionID, id)
        XCTAssertEqual(bg.count, 0)
        // Açılan sohbet ya da görünmeyen satır "bitti" sayılmaz
        let b = SidebarItem(name: "Sohbet B · running", help: "", url: "https://claude.ai/chat/bbb?x=1", rect: row(1))
        _ = bg.update([b], currentChat: "https://claude.ai/chat/aaa", now: 100)
        XCTAssertEqual(bg.update([b], currentChat: "https://claude.ai/chat/bbb", now: 130).map { $0.kind }, [.sessionEnd])
        _ = bg.update([b], currentChat: "https://claude.ai/chat/aaa", now: 140)
        XCTAssertEqual(bg.update([], currentChat: "https://claude.ai/chat/aaa", now: 180).map { $0.kind }, [.sessionEnd])
    }

    func testOneMiniPerOtherAI() {
        let claude = RobotModel(source: "claude"), gpt = RobotModel(source: "gpt")
        let t0 = Date()
        for id in ["a", "b", "bg-1-x"] {
            _ = claude.apply(AgentEvent(source: "claude", sessionID: id, kind: .prompt, state: .thinking, text: "iş"), now: t0)
        }
        _ = gpt.apply(AgentEvent(source: "gpt", sessionID: "g1", kind: .prompt, state: .thinking, text: "iş"), now: t0)
        _ = gpt.apply(AgentEvent(source: "gpt", sessionID: "g2", kind: .waiting, state: .waiting, text: "onay"), now: t0)
        var minis = RobotModel.minis([claude, gpt], current: claude, now: t0.addingTimeInterval(1))
        XCTAssertEqual(minis.map { $0.id }, ["gpt"])
        XCTAssertEqual(minis.first?.state, .waiting)
        XCTAssertTrue(minis.first?.label.contains("+1") == true)
        minis = RobotModel.minis([claude, gpt], current: gpt, now: t0.addingTimeInterval(1))
        XCTAssertEqual(minis.map { $0.id }, ["claude"])
    }

    func testDraftChatAddress() {
        XCTAssertTrue(AppWatcher.isDraftChat("https://claude.ai/new"))
        XCTAssertTrue(AppWatcher.isDraftChat("https://chatgpt.com/"))
        XCTAssertTrue(AppWatcher.isDraftChat("https://chatgpt.com/?model=gpt-5"))
        XCTAssertFalse(AppWatcher.isDraftChat("https://claude.ai/chat/3f2a9c1e"))
        XCTAssertFalse(AppWatcher.isDraftChat("https://chatgpt.com/c/6741"))
        XCTAssertFalse(AppWatcher.isDraftChat("ChatGPT"))
    }

    func testSessionTargetAndMinis() {
        let m = RobotModel(source: "claude")
        var a = AgentEvent(source: "claude", sessionID: "a", kind: .prompt, state: .thinking, text: "x")
        a.appBundleID = "com.apple.Terminal"
        _ = m.apply(a)
        _ = m.apply(AgentEvent(source: "claude", sessionID: "b", kind: .waiting, state: .waiting, text: "onay"))
        // Bekleyen oturum öne çıkar, diğeri minik kafa olur
        XCTAssertEqual(m.state, .waiting)
        XCTAssertNotNil(m.waitingSince)
        let minis = m.miniSessions(excluding: m.bestSessionID)
        XCTAssertEqual(minis.count, 1)
        XCTAssertEqual(minis.first?.state, .thinking)
    }

    func testDailySummary() {
        let stats = DailyStats()
        let day = Date(timeIntervalSince1970: 1_700_000_000)
        stats.recordTurn(source: "claude", seconds: 125, tools: 4, edits: 3, at: day)
        stats.recordTurn(source: "claude", seconds: 60, tools: 1, edits: 0, at: day)
        let text = stats.summary(names: { _ in "Claude" }, date: day) ?? ""
        XCTAssertTrue(text.hasPrefix("Claude: 2 iş"), text)
        XCTAssertTrue(text.contains("3 düzenleme"), text)
    }

    func testFocusMode() {
        FocusMode.turnOn(for: 60)
        XCTAssertTrue(FocusMode.manualActive)
        FocusMode.turnOff()
        XCTAssertFalse(FocusMode.manualActive)
        XCTAssertTrue(FocusMode.isMeetingApp("us.zoom.xos"))
        XCTAssertFalse(FocusMode.isMeetingApp("com.apple.Safari"))
    }

    func testRobotScale() {
        let old = Preferences.robotScale
        Preferences.robotScale = 1.6
        XCTAssertEqual(Layout.headSize.width, 160, accuracy: 0.01)
        XCTAssertEqual(Layout.windowSize.width, 448, accuracy: 0.01)
        Preferences.robotScale = 5
        XCTAssertEqual(Preferences.robotScale, 1.8, accuracy: 0.001)
        Preferences.robotScale = old
    }

    func testApprovalDecision() throws {
        let body = Data(#"{"hook_event_name":"PermissionRequest","session_id":"s1","tool_name":"Bash","tool_input":{"command":"npm install"},"permission_suggestions":[{"type":"addRules","rules":[{"toolName":"Bash","ruleContent":"npm install"}],"behavior":"allow","destination":"localSettings"}]}"#.utf8)
        let sug = Approval.suggestions(body)
        XCTAssertEqual(sug?.count, 1)
        func decision(_ c: ApprovalChoice) throws -> [String: Any] {
            let j = try JSONSerialization.jsonObject(with: Data(Approval.decision(c, suggestions: sug).utf8)) as! [String: Any]
            let out = j["hookSpecificOutput"] as! [String: Any]
            XCTAssertEqual(out["hookEventName"] as? String, "PermissionRequest")
            return out["decision"] as! [String: Any]
        }
        XCTAssertEqual(try decision(.allow)["behavior"] as? String, "allow")
        XCTAssertNil(try decision(.allow)["updatedPermissions"])
        XCTAssertNotNil(try decision(.always)["updatedPermissions"])
        XCTAssertEqual(try decision(.deny)["behavior"] as? String, "deny")
        XCTAssertNotNil(try decision(.deny)["message"])
        XCTAssertNil(Approval.suggestions(Data(#"{"tool_name":"Edit"}"#.utf8)))
        // Hook komutu: bekleyen curl, işaretli (kaldırılabilir)
        let cmd = HookInstaller.permissionCommand(source: "claude")
        XCTAssertTrue(cmd.contains("/permission?source=claude"))
        XCTAssertTrue(cmd.contains(AppInfo.hookMarker))
    }

    func testClaudeAskingQuestion() {
        let r = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertEqual(AppWatcher.question([("Claude is asking: Deneme sorusu: çalışıyor mu?", r)]), "Deneme sorusu: çalışıyor mu?")
        XCTAssertNil(AppWatcher.question([("Claude is AI and can make mistakes.", r)]))
    }
}
