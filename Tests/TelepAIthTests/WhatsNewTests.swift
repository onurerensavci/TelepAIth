import XCTest
@testable import TelepAIth

/// Windows'taki WhatsNewTests.cs'in aynısı.
final class WhatsNewTests: XCTestCase {
    func testWhatsNewSummaries() {
        Language.set(.tr)
        XCTAssertNotNil(WhatsNew.entry(for: "0.23.0"))
        XCTAssertNotNil(WhatsNew.entry(for: "v0.23.0"))
        let notes = "## Yenilikler\n<!-- tr -->\n- Bir\n- İki\n\n## What's new\n<!-- en -->\n- One\n<!-- end -->\n\n**Full Changelog**: https://x"
        XCTAssertEqual(WhatsNew.summary("9.9.9", notes: notes), ["Bir", "İki"])
        XCTAssertEqual(WhatsNew.summary("0.23.0", notes: "**Full Changelog**: https://x").first, WhatsNew.entry(for: "0.23.0")?.tr.first)
        XCTAssertTrue(WhatsNew.summary("9.9.9", notes: "**Full Changelog**: https://x").isEmpty)
        XCTAssertEqual(WhatsNew.bullets(["A", "B"]), "\n• A\n• B")
        XCTAssertEqual(WhatsNew.bullets([]), "")
        XCTAssertTrue(WhatsNew.afterUpdate("0.23.0")!.hasPrefix("🎁 0.23.0 geldi! Neler var:\n• "))
        XCTAssertNil(WhatsNew.afterUpdate("0.0.1"))
    }
}
