import XCTest
@testable import OneRoofCore

/// LAB-1894 · the classic Learn screens' self-test hooks drive the shared page now, so existing captures (ui2-screens.tsv
/// A12.*), journeys and perf scenarios keep working: each LEARNMODE place opens the same place, folder paths of the old
/// `skills/` tree map to the deck's `content/cards/`, and the card page hooks run inside the Listen frame.
final class LearnSharedSelfTestTests: XCTestCase {
    func test_learnmode_places_open_the_same_screen() {
        let m = LearnSharedSelfTest.mode
        XCTAssertEqual(m("radio"), .init(hash: "#ae/radio"))
        XCTAssertEqual(m("band:loops"), .init(hash: "#ae/band/loops"))
        XCTAssertEqual(m("band:context:vault"), .init(hash: "#ae/band/context/vault"))
        XCTAssertEqual(m("card:loops-first"), .init(hash: "#ae/card/loops-first"))
        XCTAssertEqual(m("card:loops-first:transcript"), .init(hash: "#ae/card/loops-first/transcript"))
        XCTAssertEqual(m("card:done-when:skill"), .init(hash: "#ae/card/done-when/skill"))
        XCTAssertEqual(m("card:done-when:listen"), .init(hash: "#ae/card/done-when"))
        XCTAssertEqual(m("writing"), .init(hash: "#ae/writing"))
        XCTAssertEqual(m("post:agentic-engineering"), .init(hash: "#ae/post/agentic-engineering"))
        XCTAssertEqual(m("path:vibe-to-prod"), .init(hash: "#ae/path/vibe-to-prod"))
        XCTAssertEqual(m("library"), .init(hash: "#ae/cards"))
        XCTAssertEqual(m("map"), .init(hash: "#ae/cards"))
        XCTAssertEqual(m("nonsense"), .init(hash: "#ae/radio"))
    }

    func test_learnmode_search_folder_and_radio_clicks_run_scripts() {
        let s = LearnSharedSelfTest.mode("search:loop: stop")
        XCTAssertEqual(s.hash, "#ae/cards")
        XCTAssertEqual(s.scripts.map(\.js), [#"oneroofLearnSearch("loop: stop")"#])
        let f = LearnSharedSelfTest.mode("folder:skills/doctrine/approval-gate/SKILL.md")
        XCTAssertEqual(f.hash, "#ae/cards/folder")
        XCTAssertTrue(f.scripts.first?.js.contains(#""content\/cards\/doctrine\/approval-gate\/SKILL.md""#) == true, f.scripts.first?.js ?? "")
        XCTAssertEqual(LearnSharedSelfTest.mode("folder").scripts, [])
        let k = LearnSharedSelfTest.mode("radiokey:context")
        XCTAssertEqual(k.hash, "#ae/radio"); XCTAssertEqual(k.scripts.first?.after, 3.5)
        XCTAssertTrue(k.scripts.first?.js.contains(#"#ae\/band\/context""#) == true)
        XCTAssertTrue(LearnSharedSelfTest.mode("radiochip:context:vault").scripts.first?.js.contains(#"#ae\/band\/context\/vault""#) == true)
        XCTAssertEqual(LearnSharedSelfTest.deckPath("skills/doctrine"), "content/cards/doctrine")
        XCTAssertEqual(LearnSharedSelfTest.deckPath("content/cards/doctrine"), "content/cards/doctrine")
    }

    func test_card_page_hooks_run_in_the_listen_frame_and_rail_folds() {
        let env = ["ONEROOF_SELFTEST_CARDENDED": "2", "ONEROOF_SELFTEST_PAGECLICK": "playAll@1,next\"Card@4", "ONEROOF_SELFTEST_PAGEJS": "3@__AE__.openScene(12)"]
        let s = LearnSharedSelfTest.cardPageScripts(env)
        XCTAssertEqual(s.count, 4)
        XCTAssertTrue(s[0].contains("ae-card-ended") && s[0].contains("},2000)"))
        XCTAssertTrue(s[1].contains("__AE__.openScene(12)") && s[1].contains("},3000)"))
        XCTAssertTrue(s[2].contains("getElementById('playAll')") && s[2].contains("},1000)"))
        XCTAssertTrue(s[3].contains("getElementById('nextCard')"), "an id is letters, digits, - and _ only")
        XCTAssertTrue(LearnSharedSelfTest.cardPageScripts(["ONEROOF_SELFTEST_CARDENDED": "finish@5"])[0].contains("__AE__.finish()"))
        XCTAssertEqual(LearnSharedSelfTest.cardPageScripts([:]), [])
        XCTAssertNotNil(LearnSharedSelfTest.startScript(["ONEROOF_SELFTEST_RAILFOLDED": "1"]))
        XCTAssertNil(LearnSharedSelfTest.startScript([:]))
    }
}
