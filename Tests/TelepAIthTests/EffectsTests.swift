import XCTest
@testable import TelepAIth

/// Windows'taki EffectsTests.cs'in aynısı.
final class EffectsTests: XCTestCase {
    func testEffectsPickAndReact() {
        let old = Preferences.costume
        defer { Preferences.costume = old; Effects.reset() }
        Language.set(.tr)
        XCTAssertEqual(Effects.all.count, 11)
        let cal = Calendar.current
        func day(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))! }
        XCTAssertEqual(Effects.season(day(2026, 12, 10)), "winter")
        XCTAssertEqual(Effects.season(day(2027, 4, 2)), "rainbow")
        XCTAssertEqual(Effects.season(day(2027, 7, 1)), "sun")
        XCTAssertEqual(Effects.season(day(2026, 11, 26)), "leaves")
        XCTAssertEqual(Effects.season(day(2026, 12, 31)), "confetti")
        XCTAssertEqual(Effects.season(day(2027, 2, 14)), "hearts")
        XCTAssertEqual(Effects.feeling("Sevgilime bir aşk mektubu yaz"), "hearts")
        XCTAssertEqual(Effects.feeling("Tebrikler, başardık!"), "confetti")
        XCTAssertNil(Effects.feeling("README'yi düzelt"))

        let t0 = day(2027, 7, 1)
        Effects.reset()
        Preferences.costume = "rainbow"
        XCTAssertEqual(Effects.visible(t0, working: false)?.id, "rainbow")
        Preferences.costume = "off"
        XCTAssertNil(Effects.visible(t0, working: true))
        XCTAssertNil(Effects.hear("seni seviyorum", now: t0))
        Preferences.costume = "auto"
        XCTAssertNil(Effects.visible(t0, working: false))
        XCTAssertEqual(Effects.visible(t0, working: true)?.id, "sun")
        XCTAssertEqual(Effects.visible(t0.addingTimeInterval(20), working: false)?.alpha, 1)
        let half = Effects.visible(t0.addingTimeInterval(30), working: false)?.alpha ?? 0
        XCTAssertTrue(half > 0.4 && half < 0.6)
        XCTAssertNil(Effects.visible(t0.addingTimeInterval(40), working: false))
        XCTAssertEqual(Effects.hear("Sevgilim için şiir", now: t0.addingTimeInterval(100)), "hearts")
        XCTAssertEqual(Effects.visible(t0.addingTimeInterval(110), working: false)?.id, "hearts")
        XCTAssertEqual(Effects.visible(t0.addingTimeInterval(131), working: false)?.id, "sun")
        XCTAssertTrue(Effects.winterCostume(day(2027, 1, 10)) && !Effects.winterCostume(day(2027, 7, 1)))
        Effects.reset()
        Effects.kick(1, now: t0)
        XCTAssertGreaterThan(Effects.energy(t0, working: false), 0.99)
        let later = Effects.energy(t0.addingTimeInterval(1), working: false)
        XCTAssertTrue(later > 0.1 && later < 0.3)
        XCTAssertLessThan(Effects.energy(t0.addingTimeInterval(5), working: false), 0.01)
    }
}
