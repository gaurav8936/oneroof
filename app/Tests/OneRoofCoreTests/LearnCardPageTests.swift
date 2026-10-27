import XCTest
@testable import OneRoofCore

/// LAB-1305 · Learn › a card's Listen tab shows the card's own deck page (or the native fallback when there is none).
final class LearnCardPageTests: XCTestCase {
    private func deck(html: String = "skills/foundations/context-as-structure/context-as-structure.html") throws -> LearnDeck {
        let json = """
        {"version": "0.2.0",
         "tracks": [{"id": "foundations", "suit": "spades", "intro": "Big", "cards": ["context-as-structure", "loops-first"]}],
         "cards": [{"slug": "context-as-structure", "track": "foundations", "title": "Context as structure",
                    "skill": "skills/foundations/context-as-structure/SKILL.md", "spec": "skills/foundations/context-as-structure/spec.json",
                    "html": "\(html)", "sections": [], "scenes": 12, "est_seconds": 300},
                   {"slug": "loops-first", "track": "foundations", "title": "Loops first",
                    "skill": "skills/foundations/loops-first/SKILL.md", "spec": "skills/foundations/loops-first/spec.json",
                    "html": "skills/foundations/loops-first/loops-first.html", "sections": [], "scenes": 9, "est_seconds": 200}]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
    }

    func testCardWithAPageLoadsItWithTheDeckRootReadable() throws {
        let s = try XCTUnwrap(LearnCardPage.source("context-as-structure", in: try deck(), exists: { _ in true }))
        XCTAssertEqual(s.page, "/deck/skills/foundations/context-as-structure/context-as-structure.html")
        XCTAssertEqual(s.readRoot, "/deck")      // the page's _audio clips and the field-manual pages it links load
        XCTAssertTrue(s.url.isFileURL)
        XCTAssertTrue(s.readAccess.hasDirectoryPath)
        XCTAssertTrue(s.page.hasPrefix(s.readAccess.path + "/"))
    }

    func testCardWithoutAPageFallsBackToTheNativeView() throws {
        XCTAssertNil(LearnCardPage.source("context-as-structure", in: try deck(), exists: { _ in false }))   // file missing
        XCTAssertNil(LearnCardPage.source("context-as-structure", in: try deck(html: ""), exists: { _ in true }))   // none listed
        XCTAssertNil(LearnCardPage.source("not-a-card", in: try deck(), exists: { _ in true }))
    }

    func testALinkToAnotherCardsPageOpensThatCard() throws {
        let d = try deck()
        XCTAssertEqual(LearnCardPage.linkedCard("/deck/skills/foundations/context-as-structure/../loops-first/loops-first.html", in: d), "loops-first")
        XCTAssertNil(LearnCardPage.linkedCard("/deck/content/field-manual/foundations.html", in: d))   // other deck pages load in place
        XCTAssertNil(LearnCardPage.linkedCard("/elsewhere/loops-first.html", in: d))
    }

    func testBridgeReportsPagePlaybackAndCanPauseIt() {
        let js = LearnCardPage.bridgeScript
        XCTAssertTrue(js.contains("messageHandlers.\(LearnCardPage.handler)"))
        XCTAssertTrue(js.contains("HTMLMediaElement.prototype.play"))
        XCTAssertTrue(js.contains("speechSynthesis.speak"))
        XCTAssertTrue(js.contains("speechSynthesis.cancel()"))
        XCTAssertTrue(js.contains("window.__oneroofPause"))
        XCTAssertTrue(LearnCardPage.pauseScript.contains("__oneroofPause"))
        XCTAssertTrue(LearnCardPage.showSceneScript(3, tracks: 12).contains("d.length === 12 && d[3]"))
    }

    /// The deck in the repository: every card page has its own sections menu (why the native Chapters list goes) and the
    /// pause hook's play button. Reads the deck the build bundles (ONEROOF_AE_DECK_REPO); skipped when it is not set.
    func testEveryDeckPageHasItsOwnSectionsMenu() throws {
        guard let root = ProcessInfo.processInfo.environment["ONEROOF_AE_DECK_REPO"], let d = LearnDeck.load(deck: root)
        else { throw XCTSkip("set ONEROOF_AE_DECK_REPO to the deck checkout to run this") }
        var missing: [String] = []
        for slug in d.cards.keys.sorted() {
            guard let s = LearnCardPage.source(slug, in: d), let html = try? String(contentsOfFile: s.page, encoding: .utf8) else { missing.append(slug + " (no page)"); continue }
            if !html.contains(#"id="sections""#) || !html.contains(#"id="play""#) || !html.contains(#"id="dots""#) { missing.append(slug) }
        }
        XCTAssertEqual(missing, [])
    }
}
