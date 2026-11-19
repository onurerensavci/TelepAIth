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
}
