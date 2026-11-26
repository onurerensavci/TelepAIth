import XCTest
@testable import TelepAIth

/// Windows'taki RoomTests.cs'in aynısı.
final class RoomTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Language.set(.tr)
    }

    func testOutfitsParseAndColors() {
        XCTAssertEqual(Outfits.all.count, 17)
        XCTAssertTrue(Outfits.all.allSatisfy { Outfits.slots.contains($0.slot) && !$0.shapes.isEmpty && !$0.name.isEmpty })
        XCTAssertEqual(Set(Outfits.all.map(\.id)).count, Outfits.all.count)
        XCTAssertTrue(Outfits.all.compactMap(\.achievement).allSatisfy { Achievements.find($0) != nil })
        let c = Outfits.color("#FF8FB180", theme: (0, 0, 0))
        XCTAssertEqual(c.r, 1, accuracy: 0.001)
        XCTAssertEqual(c.a, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(Outfits.color("theme-dark", theme: (100.0 / 255, 100.0 / 255, 100.0 / 255)).r, 72.0 / 255, accuracy: 0.001)
        XCTAssertTrue(Outfits.find("beanie")!.shapes.contains { $0.fill?.radial?.count == 3 && ($0.fill?.stops.count ?? 0) >= 2 })
        XCTAssertTrue(Outfits.find("tophat")!.shapes.contains { $0.fill?.linear?.count == 4 })
        // Her yol okunabiliyor
        for item in Outfits.all { for s in item.shapes { if let d = s.path { XCTAssertFalse(SVGPath.parse(d).isEmpty, item.id) } } }
    }

    func testLevelsGrow() {
        XCTAssertEqual(Levels.level(xp: 0), 1)
        XCTAssertEqual(Levels.level(xp: 99), 1)
        XCTAssertEqual(Levels.level(xp: 100), 2)
        XCTAssertEqual(Levels.level(xp: 300), 3)
        XCTAssertEqual(Levels.level(xp: 4500), 10)
        XCTAssertEqual(Levels.level(xp: 4499), 9)
        var p = ProgressData()
        p.turns = 20
        XCTAssertEqual(Levels.level(p), 2)
        XCTAssertEqual(Levels.next(p).left, 100)
        XCTAssertEqual(Levels.next(p).fraction, 0.5, accuracy: 0.001)
    }

    func testProgressStreaksAndNews() {
        let pr = Progress(defaultsKey: nil)
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 1, minute: 30))!
        pr.turn(source: "claude", seconds: 120, tools: 5, edits: 2, at: day, todayTurns: 1)
        pr.turn(source: "gpt", seconds: 30, tools: 0, edits: 0, at: day.addingTimeInterval(3600), todayTurns: 2)
        pr.turn(source: "claude", seconds: 60, tools: 1, edits: 1, at: day.addingTimeInterval(86400 + 36000), todayTurns: 1)
        pr.turn(source: "claude", seconds: 60, tools: 1, edits: 1, at: day.addingTimeInterval(3 * 86400 + 36000), todayTurns: 1)
        pr.parallel(3)
        pr.parallel(2)
        let d = pr.snapshot()
        XCTAssertEqual(d.turns, 4)
        XCTAssertEqual(d.activeDays, 3)
        XCTAssertEqual(d.streak, 1)
        XCTAssertEqual(d.bestStreak, 2)
        XCTAssertEqual(d.nightTurns, 2)
        XCTAssertEqual(d.maxParallel, 3)
        XCTAssertEqual(d.sources.count, 2)
        let news = pr.takeNews()
        XCTAssertTrue(news.achievements.contains { $0.id == "hello" } && news.achievements.contains { $0.id == "lead" })
        XCTAssertTrue(pr.takeNews().achievements.isEmpty)
        let cap = Outfits.find("cap")!
        XCTAssertFalse(Outfits.unlocked(cap, ProgressData()))
        var rich = ProgressData()
        rich.turns = 30
        XCTAssertTrue(Outfits.unlocked(cap, rich))
        XCTAssertTrue(Outfits.unlockHint(Outfits.find("party")!).contains("Büyük gün"))
        // Eski kayıt (eksik alanlar) okunur
        let old = try! JSONDecoder().decode(ProgressData.self, from: Data(#"{"turns":5}"#.utf8))
        XCTAssertEqual(old.turns, 5)
        XCTAssertEqual(old.toldLevel, 1)
    }

    func testEffortByProject() {
        let st = DailyStats()
        let today = Date()
        // Benzersiz proje adlarıyla (gerçek kayıtlar karışmasın)
        let tag = UUID().uuidString.prefix(6)
        st.recordTurn(source: "claude", seconds: 3600, tools: 1, edits: 1, at: today, project: "shop-\(tag)")
        st.recordTurn(source: "claude", seconds: 1800, tools: 1, edits: 1, at: today.addingTimeInterval(-86400), project: "api-\(tag)")
        let e = st.effort(today: today, days: 7)
        XCTAssertEqual(e.days.count, 7)
        XCTAssertEqual(e.days.last?.day, DailyStats.dayKey(today))
        XCTAssertNotNil(e.projects.first { $0.name == "shop-\(tag)" })
        XCTAssertGreaterThanOrEqual(e.totalSeconds, 5400)
    }

    func testMenuTitlesCapitalized() {
        XCTAssertEqual(menuTitle("Robotun odası…"), "Robotun Odası")
        XCTAssertEqual(menuTitle("Güncellemeleri denetle…"), "Güncellemeleri Denetle")
        XCTAssertEqual(menuTitle("İzni sıfırla ve yeniden iste"), "İzni Sıfırla ve Yeniden İste")
        XCTAssertEqual(menuTitle("⚠︎ Bildirimler macOS'ta kapalı — aç…"), "⚠︎ Bildirimler macOS'ta Kapalı — Aç")
        XCTAssertEqual(menuTitle("Claude: izin istesin (İzin ver / Reddet)"), "Claude: İzin İstesin (İzin Ver / Reddet)")
        Language.set(.en)
        XCTAssertEqual(menuTitle("Bring robot to this desktop"), "Bring Robot to This Desktop")
        Language.set(.tr)
    }
}
