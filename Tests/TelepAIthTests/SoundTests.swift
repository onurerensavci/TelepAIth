import XCTest
@testable import TelepAIth

final class SoundTests: XCTestCase {
    func testSoundKindsAndNotices() {
        let oldMuted = Preferences.muted
        let oldDone = Preferences.sound("done")
        defer {
            Preferences.muted = oldMuted
            Preferences.setSound("done", oldDone)
        }
        // Ayarlar: kapatılan tür susar, sessize alınca hepsi susar
        XCTAssertEqual(Preferences.soundKinds.count, 7)
        Preferences.muted = false
        Preferences.setSound("done", false)
        XCTAssertFalse(Preferences.soundOn("done"))
        Preferences.setSound("done", true)
        XCTAssertTrue(Preferences.soundOn("done"))
        Preferences.muted = true
        XCTAssertFalse(Preferences.soundOn("done"))

        // Her bildirim kendi türünü taşır
        let m = RobotModel(source: "claude")
        let t0 = Date()
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .prompt, state: .thinking, text: "x"), now: t0)
        XCTAssertEqual(m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .waiting, state: .waiting, text: "onay"),
                               now: t0.addingTimeInterval(1))?.kind, "waiting")
        XCTAssertEqual(m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .failure, state: .error, text: "hata"),
                               now: t0.addingTimeInterval(2))?.kind, "error")
        _ = m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .prompt, state: .thinking, text: "x"), now: t0.addingTimeInterval(3))
        XCTAssertEqual(m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .stop, state: .done, text: "bitti", forceNotify: true),
                               now: t0.addingTimeInterval(4))?.kind, "done")
        XCTAssertEqual(m.apply(AgentEvent(source: "claude", sessionID: "s", kind: .insight, text: "Takıldı"),
                               now: t0.addingTimeInterval(5))?.kind, "alert")
        XCTAssertEqual(m.apply(AgentEvent(source: "claude", sessionID: "usage", kind: .insight, text: "%80"),
                               now: t0.addingTimeInterval(6))?.kind, "usage")
    }
}
