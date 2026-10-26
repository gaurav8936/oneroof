import XCTest
@testable import OneRoofCore

/// LAB-1274 · 1.9.2: Learn in the v2 window is Radio · Writing · All cards. Every way in that used to open a Pages entry
/// lands on a card, a band, Radio or the Help page; "How do I…" lands on the best card. LAB-1272: the band dial's labels.
final class LearnRouteTests: XCTestCase {
    private func card(_ slug: String, _ track: String, title: String, sub: String = "", desc: String = "", triggers: [String] = []) -> String {
        let trig = triggers.map { "\"\($0)\"" }.joined(separator: ", ")
        return #"{"slug": "\#(slug)", "track": "\#(track)", "title": "\#(title)", "subtitle": "\#(sub)", "description": "\#(desc)", "triggers": [\#(trig)], "#
            + #""skill": "skills/\#(track)/\#(slug)/SKILL.md", "spec": "skills/\#(track)/\#(slug)/spec.json", "html": "skills/\#(track)/\#(slug)/\#(slug).html", "#
            + #""sections": [], "scenes": 3, "est_seconds": 120}"#
    }

    private func deck() throws -> LearnDeck {
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LearnDeckFixture.catalogJSON.utf8)) as? [String: Any])
        let bands = String(decoding: try JSONSerialization.data(withJSONObject: j["bands"] ?? []), as: UTF8.self)
        let json = """
        {"version": "0.2.0", "bands": \(bands),
         "suits": [{"id": "spades", "symbol": "♠", "label": "Ideas", "tracks": ["infra", "rhythms", "vault"]}],
         "tracks": [{"id": "infra", "suit": "spades", "intro": "Dev", "name": "Dev environment", "question": "Repos, git, worktrees, planning.", "cards": ["worktree-lane"]},
                    {"id": "rhythms", "suit": "spades", "intro": "Daily", "cards": ["next-session-handoff", "done-when"]},
                    {"id": "vault", "suit": "spades", "intro": "Notes", "cards": ["knowledge-notes"]}],
         "cards": [\(card("worktree-lane", "infra", title: "Worktree lane", sub: "One unit of work per git worktree", desc: "Run parallel sessions without collisions.", triggers: ["parallel agents"])),
                   \(card("next-session-handoff", "rhythms", title: "Next-session handoff", sub: "Write the opening message", desc: "So a fresh session resumes cold.")),
                   \(card("done-when", "rhythms", title: "Done when", sub: "A goal with a stop condition", desc: "The check that proves it.")),
                   \(card("knowledge-notes", "vault", title: "Knowledge notes", sub: "Plain Markdown notes", desc: "Notes that publish themselves."))]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
    }

    // MARK: Routes into Learn

    func testDeckCardPageOpensItsStation() throws {
        let d = try deck()
        XCTAssertEqual(d.route("/deck/skills/infra/worktree-lane/worktree-lane.html", helpFolder: "/app/help"), .card("worktree-lane"))
    }

    /// Foundations › Skills and the palette's skills name the card's page or SKILL.md, possibly in another copy of the deck.
    func testSkillPathsFromElsewhereOpenTheCard() throws {
        let d = try deck()
        XCTAssertEqual(d.route("/other/skills/infra/worktree-lane/worktree-lane.html", helpFolder: nil), .card("worktree-lane"))
        XCTAssertEqual(d.route("/other/skills/rhythms/done-when/SKILL.md", helpFolder: nil), .card("done-when"))
        XCTAssertEqual(d.route("/other/skills/x/not-a-card/not-a-card.html", helpFolder: nil), .none)
    }

    /// One Roof Help → the window's Help page, at that page.
    func testHelpPageOpensTheHelpPage() throws {
        let d = try deck()
        XCTAssertEqual(d.route("/app/help/09_learn.md", helpFolder: "/app/help"), .help("/app/help/09_learn.md"))
        XCTAssertEqual(d.route("/app/help/09_learn.md", helpFolder: "/app/help/"), .help("/app/help/09_learn.md"))
        XCTAssertEqual(d.route("/app/helpers/x.md", helpFolder: "/app/help"), .none, "a sibling folder is not Help")
    }

    /// Field-manual pages: home → Radio; a track page → the band that plays the track, at the track.
    func testFieldManualPagesOpenRadioOrTheTrack() throws {
        let d = try deck()
        XCTAssertEqual(d.route("/deck/content/field-manual/home.html", helpFolder: nil), .radio)
        XCTAssertEqual(d.route("/deck/content/field-manual/vault.html", helpFolder: nil), .band("context", track: "vault"))
        XCTAssertEqual(d.route("/deck/content/field-manual/infra.html", helpFolder: nil), .band("procedure", track: "infra"))
    }

    /// The course and extra-folder pages have no home in the three views: Learn stays where it is.
    func testCourseAndExtraFolderPagesGoNowhere() throws {
        let d = try deck()
        XCTAssertEqual(d.route("/deck/content/course/01-start-here.md", helpFolder: "/app/help"), .none)
        XCTAssertEqual(d.route("/notes/page.md", helpFolder: "/app/help"), .none)
    }

    // MARK: How do I…

    func testHowDoILandsOnTheBestCard() throws {
        let d = try deck()
        XCTAssertEqual(d.bestCards(for: "how do I run two agents in parallel?", limit: 1), ["worktree-lane"])
        XCTAssertEqual(d.bestCards(for: "write a handoff for the next session").first, "next-session-handoff")
        XCTAssertEqual(d.bestCards(for: "stop condition").first, "done-when")
        XCTAssertEqual(d.bestCards(for: "worktrees").first, "worktree-lane", "stems match (worktrees → worktree)")
        XCTAssertEqual(d.bestCards(for: "how do I"), [], "only stop words: no card")
        XCTAssertEqual(d.bestCards(for: "zzz-nothing"), [])
        XCTAssertLessThanOrEqual(d.bestCards(for: "notes session", limit: 1).count, 1)
    }

    /// Every word in one card (the header search's rule) still counts when ranking finds nothing.
    func testHowDoIFallsBackToEveryWordSearch() throws {
        let d = try deck()
        XCTAssertEqual(LearnMatch.rank("mark", [LearnMatch.Doc(id: "k", title: "Knowledge notes", text: "Plain Markdown notes")]), [])
        XCTAssertEqual(d.bestCards(for: "mark"), ["knowledge-notes"], "a part of a word: found by the every-word search")
    }

    // MARK: LAB-1272 · the band dial's labels

    func testLabelsThatFitStayOnTheFirstRow() {
        let p = DialLabels.place([(0, 60), (100, 40), (200, 50)], total: 400, gap: 6)
        XCTAssertEqual(p.map(\.row), [0, 0, 0])
        XCTAssertEqual(p.map(\.width), [60, 40, 50])
        XCTAssertFalse(p.contains { $0.hidden || $0.truncated })
    }

    /// FOUNDATIONS (one card) then VAULT a step later: VAULT drops to the second row instead of printing over it.
    func testAShortTrackStaggersTheNextLabel() {
        let p = DialLabels.place([(0, 70), (40, 80), (60, 40), (200, 50)], total: 400, gap: 6)
        XCTAssertEqual(p[0].row, 0)
        XCTAssertEqual(p[1].row, 1, "overlaps the first: second row")
        XCTAssertTrue(p[2].hidden, "both rows taken at x = 60: hidden (the full name stays as a tooltip)")
        XCTAssertEqual(p[3].row, 0)
        // No two visible labels on the same row overlap.
        let vis = p.enumerated().filter { !$0.element.hidden }
        for a in vis { for b in vis where a.offset < b.offset && a.element.row == b.element.row {
            let xs: [Double] = [0, 40, 60, 200]
            XCTAssertLessThanOrEqual(xs[a.offset] + a.element.width, xs[b.offset])
        } }
    }

    func testALabelAtTheEndIsShortenedOrHidden() {
        let p = DialLabels.place([(0, 50), (360, 80)], total: 400, gap: 6, minWidth: 24)
        XCTAssertEqual(p[1].row, 0)
        XCTAssertEqual(p[1].width, 40)
        XCTAssertTrue(p[1].truncated)
        let q = DialLabels.place([(0, 50), (390, 80)], total: 400, gap: 6, minWidth: 24)
        XCTAssertTrue(q[1].hidden, "10 pt left: hidden")
    }
}
