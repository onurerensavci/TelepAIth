import XCTest
@testable import TelepAIth

final class EffectsTests: XCTestCase {
    func testEffectsPickAndReact() {
        let old = Preferences.costume
        defer { Preferences.costume = old }
        XCTAssertEqual(Effects.all.count, 11)
        XCTAssertEqual(Set(Effects.all.map(\.id)).count, Effects.all.count)
        let cal = Calendar.current
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d, hour: 12))! }
        // Otomatik: Aralık – 6 Ocak kış, sonrasında yok; seçilen efekt her zaman
        Preferences.costume = "auto"
        XCTAssertEqual(Effects.current(day(2026, 12, 10)), "winter")
        XCTAssertEqual(Effects.current(day(2027, 1, 6)), "winter")
        XCTAssertNil(Effects.current(day(2027, 1, 7)))
        Preferences.costume = "rainbow"
        XCTAssertEqual(Effects.current(day(2027, 7, 1)), "rainbow")
        Preferences.costume = "off"
        XCTAssertNil(Effects.current(day(2026, 12, 10)))
        XCTAssertTrue(Effects.isBackground("sun") && !Effects.isBackground("hearts"))
        // Ses çıkaran an: efekt canlanır, sonra söner
        let t0 = day(2027, 3, 1)
        Effects.kick(1, now: t0)
        XCTAssertGreaterThan(Effects.energy(t0, working: false), 0.99)
        let later = Effects.energy(t0.addingTimeInterval(1), working: false)
        XCTAssertTrue(later > 0.1 && later < 0.3)
        XCTAssertLessThan(Effects.energy(t0.addingTimeInterval(5), working: false), 0.01)
        let beat = Effects.energy(t0.addingTimeInterval(60), working: true)
        XCTAssertTrue(beat >= 0.1 && beat <= 0.34)
    }
}
