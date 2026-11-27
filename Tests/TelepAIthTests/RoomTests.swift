import XCTest
@testable import TelepAIth

/// Windows'taki RoomTests.cs'in aynısı.
final class RoomTests: XCTestCase {
    override func setUp() {
        super.setUp()
        Language.set(.tr)
    }

    func testOutfitsParseAndColors() {
        XCTAssertEqual(Outfits.all.count, 30)
        XCTAssertTrue(Outfits.all.allSatisfy { Outfits.slots.contains($0.slot) && !$0.shapes.isEmpty && !$0.name.isEmpty })
        XCTAssertEqual(Set(Outfits.all.map(\.id)).count, Outfits.all.count)
        XCTAssertTrue(Outfits.all.compactMap(\.achievement).allSatisfy { Achievements.find($0) != nil })
        let c = Outfits.color("#FF8FB180", theme: (0, 0, 0))
        XCTAssertEqual(c.r, 1, accuracy: 0.001)
        XCTAssertEqual(c.a, 128.0 / 255, accuracy: 0.001)
        XCTAssertEqual(Outfits.color("theme-dark", theme: (100.0 / 255, 100.0 / 255, 100.0 / 255)).r, 72.0 / 255, accuracy: 0.001)
        XCTAssertTrue(Outfits.find("beanie")!.shapes.contains { $0.fill?.radial?.count == 3 && ($0.fill?.stops.count ?? 0) >= 2 })
        XCTAssertTrue(Outfits.find("crown")!.shapes.contains { $0.fill?.linear?.count == 4 })
        let sway = Outfits.find("beanie")!.shapes.compactMap(\.anim).first!
        XCTAssertEqual(sway.kind, "sway")
        XCTAssertEqual(sway.at(0.25 / sway.speed).rotate, sway.amount, accuracy: 0.001)
        let rise = Outfits.find("gramophone")!.shapes.compactMap(\.anim).first { $0.kind == "rise" }!
        XCTAssertEqual(rise.at(0.5 / rise.speed).dy, -rise.amount / 2, accuracy: 0.001)
        XCTAssertEqual(OutfitAnim(kind: "twinkle", amount: 1, speed: 1, offset: 0, pivot: nil).at(0.5).opacity, 0)
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
        let cap = Outfits.find("beanie")!
        XCTAssertFalse(Outfits.unlocked(cap, ProgressData()))
        var rich = ProgressData()
        rich.turns = 30
        XCTAssertTrue(Outfits.unlocked(cap, rich))
        XCTAssertTrue(Outfits.unlockHint(Outfits.find("scarf")!).contains("Erkenci"))
        // Eski kayıt (eksik alanlar) okunur
        let old = try! JSONDecoder().decode(ProgressData.self, from: Data(#"{"turns":5}"#.utf8))
        XCTAssertEqual(old.turns, 5)
        XCTAssertEqual(old.toldLevel, 1)
    }

    func testOutfitTypesAndNews() {
        // 6 tip × 5 parça: her yuvadan bir tane, biri gizli ödül
        XCTAssertEqual(Outfits.types.count, 6)
        for t in Outfits.types {
            let items = Outfits.items(of: t.id)
            XCTAssertEqual(Set(items.map(\.slot)), Set(Outfits.slots), t.id)
            XCTAssertEqual(items.filter(\.legendary).count, 1, t.id)
            XCTAssertNil(items.first(where: \.legendary)?.achievement, t.id)   // gizli ödül seviyeyle açılır
        }
        var p = ProgressData()
        XCTAssertEqual(Outfits.displayName(Outfits.find("crown")!, p), "Gizli ödül")
        XCTAssertFalse(Outfits.typeComplete("coder", p))
        // Yeni açılanlar: ilk seferde sessizce kaydedilir, sonra yeni açılanlar bir kez söylenir
        let pr = Progress(defaultsKey: nil)
        XCTAssertTrue(pr.takeOutfitNews().items.isEmpty)
        for _ in 0..<30 { pr.turn(source: "claude", seconds: 60, tools: 1, edits: 1, at: Date(), todayTurns: 1) }
        let news = pr.takeOutfitNews()
        XCTAssertTrue(news.items.contains { $0.id == "beanie" } && news.items.contains { $0.id == "lanyard" })
        XCTAssertTrue(pr.takeOutfitNews().items.isEmpty)
        let lines = Outfits.newsLines(news.items, [Outfits.findType("king")!])
        XCTAssertTrue(lines.first!.hasPrefix("🎉 Gardıropta açıldı: "))
        XCTAssertTrue(lines.last!.contains("Kral tipi tamamlandı"))
        XCTAssertTrue(Outfits.newsLines([Outfits.find("crown")!], []).first!.contains("Gizli ödül açıldı: Taç"))
        p.turns = 5000; p.edits = 5000; p.ciPassed = 30; p.earlyTurns = 10; p.maxParallel = 3; p.sources = ["claude", "gpt"]
        XCTAssertTrue(Outfits.typeComplete("coder", p))
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

    func testSidebarIgnoresConversationJunk() {
        // Sohbetin içindeki yazılar (mesaj, mesaj düğmesi, kenar çubuğu düğmesi) sohbet sayılmaz: sadece bağlantısı olan satırlar
        let junk = SidebarChats.parse([
            SidebarItem(name: "", help: "running", url: nil, rect: CGRect(x: 300, y: 200, width: 8, height: 8)),
            SidebarItem(name: "You said: /Volumes/LaCie/spark", help: "", url: nil, rect: CGRect(x: 320, y: 196, width: 300, height: 20)),
            SidebarItem(name: "", help: "running", url: nil, rect: CGRect(x: 10, y: 10, width: 8, height: 8)),
            SidebarItem(name: "Sidebar", help: "", url: nil, rect: CGRect(x: 30, y: 6, width: 30, height: 20)),
        ])
        XCTAssertTrue(junk.isEmpty)
        XCTAssertEqual(SidebarChats.stripStatus("You said: merhaba"), "")
        XCTAssertEqual(SidebarChats.stripStatus("Copywriting fikirleri"), "Copywriting fikirleri")
        // Claude'un biçimi: durum sadece boşlukla, büyük harfle eklenir (kullanıcının günlüğündeki gerçek adlar)
        XCTAssertEqual(SidebarChats.statusOf("SCAM OR LEGIT video konsepti Running"), .running)
        XCTAssertEqual(SidebarChats.statusOf("TelepAIth Running Includes an artifact"), .running)
        XCTAssertEqual(SidebarChats.statusOf("Spark Win Cash video Needs input"), .waiting)
        XCTAssertNil(SidebarChats.statusOf("marathon running"))
        XCTAssertEqual(SidebarChats.stripStatus("SCAM OR LEGIT video konsepti Running"), "SCAM OR LEGIT video konsepti")
        XCTAssertEqual(SidebarChats.stripStatus("TelepAIth Running Includes an artifact"), "TelepAIth")
        // Claude'un adın sonuna eklediği işaretler temizlenir
        XCTAssertEqual(SidebarChats.stripStatus("TelepAIth Includes an artifact"), "TelepAIth")
        XCTAssertEqual(SidebarChats.stripStatus("Tarif, Starred · running"), "Tarif")
        // Claude sohbetleri resmî bağlantıyla açılır
        XCTAssertEqual(SidebarChats.deepLink("https://claude.ai/chat/0b6a5e2c-1d2f-4c3b-9a8e-123456789abc?x=1")?.absoluteString,
                       "claude://claude.ai/chat/0b6a5e2c-1d2f-4c3b-9a8e-123456789abc")
        XCTAssertNil(SidebarChats.deepLink("https://claude.ai/recents"))
        XCTAssertNil(SidebarChats.deepLink("https://chatgpt.com/c/0b6a5e2c-1d2f"))
        // Açık sohbetin adı: adresi eşleşen bağlantı; yoksa seçili bağlantı; yoksa seçili satır (sekmeler sayılmaz)
        let side = [
            SidebarItem(name: "Chats", help: "", url: "https://claude.ai/recents", rect: CGRect(x: 0, y: 0, width: 100, height: 20), current: true),
            SidebarItem(name: "Code", help: "", url: nil, rect: CGRect(x: 0, y: 30, width: 100, height: 20), current: true),
            SidebarItem(name: "Video kurgusu", help: "", url: "https://claude.ai/chat/aaa", rect: CGRect(x: 0, y: 60, width: 100, height: 20)),
        ]
        XCTAssertEqual(SidebarChats.currentTitle(side, currentChat: "https://claude.ai/chat/aaa"), "Video kurgusu")
        XCTAssertNil(SidebarChats.currentTitle(side, currentChat: nil))
        // Gerçek hata (günlükten): Claude'un "…bekliyor" diye biten cevabı sohbet satırı sanılıyordu
        let reply = SidebarItem(name: "içinde üç versiyonu kurdum: bir T, iki Spark. Hepsi 1080×1920, 30 fps, tam 60 sn. Render almadım, onay bekliyor",
                                help: "", url: nil, rect: CGRect(x: 300, y: 400, width: 500, height: 20))
        XCTAssertTrue(SidebarChats.parse([reply]).isEmpty)
        let navRow = SidebarItem(name: "Spark videoları · running", help: "", url: nil, rect: CGRect(x: 10, y: 100, width: 200, height: 20))
        let picked = SidebarChats.pickSidebar([(navRow, true, false), (reply, false, true)])
        XCTAssertTrue(picked.viaNav && picked.items == [navRow])
        let noNav = SidebarChats.pickSidebar([(navRow, false, false), (reply, false, true)])
        XCTAssertTrue(!noNav.viaNav && noNav.items == [navRow])
        XCTAssertTrue(SidebarChats.isNavigation(kind: "AXLandmarkNavigation", name: "") && SidebarChats.isNavigation(kind: "", name: "Sidebar"))
        XCTAssertTrue(SidebarChats.isMainContent(kind: "AXLandmarkMain"))
        let code = [SidebarItem(name: "Klasördeki üç versiyonu karşılaştır", help: "", url: nil,
                                rect: CGRect(x: 0, y: 0, width: 200, height: 20), current: true)]
        XCTAssertEqual(SidebarChats.currentTitle(code, currentChat: nil), "Klasördeki üç versiyonu karşılaştır")
    }
}
