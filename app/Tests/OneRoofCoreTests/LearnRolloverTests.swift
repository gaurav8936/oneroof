import XCTest
@testable import OneRoofCore

/// LAB-1621 / LAB-1629 · a card played to its end rolls over to the next card; the player bar's ⏮ ⏭ and back to band.
final class LearnRolloverTests: XCTestCase {
    /// Two bands: context (start here: four-bands, band-context; track vault: v1, v2) and loops (start here: band-loops;
    /// track goals: g1).
    private func deck() throws -> LearnDeck {
        func card(_ s: String, _ track: String) -> String {
            "{\"slug\": \"\(s)\", \"track\": \"\(track)\", \"title\": \"Title \(s)\", \"html\": \"skills/\(track)/\(s)/\(s).html\", \"sections\": [], \"scenes\": 3}"
        }
        let json = """
        {"version": "0.2.3",
         "bands": [{"id": "context", "n": "01", "title": "Context", "tracks": ["intro", "vault"], "start_here": ["four-bands", "band-context"]},
                   {"id": "loops", "n": "02", "title": "Loops", "tracks": ["goals"], "start_here": ["band-loops"]}],
         "tracks": [{"id": "intro", "cards": ["four-bands", "band-context"]}, {"id": "vault", "cards": ["v1", "v2"]},
                    {"id": "goals", "cards": ["band-loops", "g1"]}],
         "cards": [\(card("four-bands", "intro")), \(card("band-context", "intro")), \(card("v1", "vault")), \(card("v2", "vault")),
                   \(card("band-loops", "goals")), \(card("g1", "goals"))]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
    }

    func testNextFollowsTheBandThenTheNextBandsFirstStartHereCard() throws {
        let d = try deck()
        XCTAssertEqual(d.lists["context"], ["four-bands", "band-context", "v1", "v2"])
        XCTAssertEqual(LearnRollover.next(after: "four-bands", in: d), "band-context")
        XCTAssertEqual(LearnRollover.next(after: "v1", in: d), "v2")
        XCTAssertEqual(LearnRollover.next(after: "v2", in: d), "band-loops")      // end of band → next band's start here
        XCTAssertEqual(LearnRollover.next(after: "band-loops", in: d), "g1")
        XCTAssertNil(LearnRollover.next(after: "g1", in: d))                    // the last band's last card: the run stops
        XCTAssertNil(LearnRollover.next(after: "nope", in: d))
    }

    func testPreviousIsTheSameOrderBackwards() throws {
        let d = try deck()
        XCTAssertEqual(LearnRollover.previous(before: "g1", in: d), "band-loops")
        XCTAssertEqual(LearnRollover.previous(before: "band-loops", in: d), "v2")   // start of band → previous band's last
        XCTAssertEqual(LearnRollover.previous(before: "band-context", in: d), "four-bands")
        XCTAssertNil(LearnRollover.previous(before: "four-bands", in: d))
    }

    func testEndedMessageFromTheCardPage() {
        XCTAssertEqual(LearnRollover.endedCard(["type": "ended", "card": "v1"], fallback: "x"), "v1")
        XCTAssertEqual(LearnRollover.endedCard(["type": "ended"], fallback: "x"), "x")
        XCTAssertEqual(LearnRollover.endedCard("ended", fallback: "x"), "x")
        XCTAssertNil(LearnRollover.endedCard(["type": "ae-nav", "to": "band"], fallback: "x"))
        XCTAssertNil(LearnRollover.endedCard("play", fallback: "x"))
        XCTAssertEqual(LearnRollover.handler, "aeCard")
    }

    func testNavMessages() {
        XCTAssertEqual(LearnRollover.navRequest(["type": "ae-nav", "to": "next-card", "card": "v1", "playing": true], fallback: "x"),
                       .init(to: .nextCard, card: "v1", playing: true))
        XCTAssertEqual(LearnRollover.navRequest(["type": "ae-nav", "to": "prev-card"], fallback: "x"), .init(to: .prevCard, card: "x", playing: nil))
        XCTAssertEqual(LearnRollover.navRequest(["type": "ae-nav", "to": "band", "card": "v2"], fallback: "x")?.to, .band)
        XCTAssertNil(LearnRollover.navRequest(["type": "ae-nav", "to": "sideways"], fallback: "x"))
        XCTAssertNil(LearnRollover.navRequest(["type": "ended"], fallback: "x"))
    }

    func testAutoplayURLAndCountdownLine() {
        let u = LearnRollover.url("/deck/skills/a b/c.html", autoplay: true)
        XCTAssertTrue(u.isFileURL)
        XCTAssertEqual(u.query, "autoplay=1")
        XCTAssertEqual(u.path, "/deck/skills/a b/c.html")
        XCTAssertNil(LearnRollover.url("/deck/c.html", autoplay: false).query)
        XCTAssertEqual(LearnRollover.label(title: "Band 01 · Context", left: 3), "Next: Band 01 · Context in 3…")
        XCTAssertEqual(LearnRollover.seconds, 3)
        XCTAssertTrue(LearnRollover.playScript.contains("ae-play"))
        XCTAssertTrue(LearnRollover.endedScript(card: "v1'); evil(").contains("card: 'v1evil'"))
    }

    func testAutoAdvanceIsOnByDefaultAndSurvivesOldAppSettings() throws {
        XCTAssertTrue(AppSettings().learnAutoAdvance)
        let old = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(old.learnAutoAdvance)
        var off = AppSettings(); off.learnAutoAdvance = false
        let back = try JSONDecoder().decode(AppSettings.self, from: try JSONEncoder().encode(off))
        XCTAssertFalse(back.learnAutoAdvance)
    }
}

/// LAB-1628 · the dark code panel's text helpers.
final class CodeTextTests: XCTestCase {
    func testFrontMatterSplitsFromTheBody() {
        let s = CodeText.split("---\nname: loops-first\ndescription: Hand it a loop\n---\n\n# Loops first\n\nBody.")
        XCTAssertEqual(s.front, "name: loops-first\ndescription: Hand it a loop")
        XCTAssertEqual(s.body, "# Loops first\n\nBody.")
        let none = CodeText.split("# Title\n---\nnot front-matter")
        XCTAssertNil(none.front)
        XCTAssertEqual(none.body, "# Title\n---\nnot front-matter")
        XCTAssertNil(CodeText.split("---\nunclosed: yes").front)
    }

    func testLanguagesForFilesAndFences() {
        XCTAssertEqual(CodeText.language(path: "/x/SKILL.md"), .markdown)
        XCTAssertEqual(CodeText.language(path: "/x/spec.json"), .json)
        XCTAssertEqual(CodeText.language(path: "/x/run.sh"), .shell)
        XCTAssertEqual(CodeText.language(path: "/x/a.swift"), .swift)
        XCTAssertEqual(CodeText.language(path: "/x/a.ts"), .typescript)
        XCTAssertEqual(CodeText.language(path: "/x/page.html"), .plain)
        XCTAssertEqual(CodeText.language(fence: "yaml"), .yaml)
        XCTAssertEqual(CodeText.language(fence: "bash"), .shell)
        XCTAssertEqual(CodeText.label(.plain), "text")
    }

    func testPreviewCutsLongFiles() {
        let long = (1...500).map { "line \($0)" }.joined(separator: "\n")
        let p = CodeText.preview(long, maxLines: 400)
        XCTAssertTrue(p.cut)
        XCTAssertEqual(p.text.components(separatedBy: "\n").count, 400)
        XCTAssertFalse(CodeText.preview("a\nb", maxLines: 400).cut)
        XCTAssertEqual(CodeText.preview("a\nb\n", maxLines: 2).cut, false)
    }
}
