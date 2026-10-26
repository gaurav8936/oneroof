import XCTest
@testable import OneRoofCore

/// LAB-1233 · Learn Radio's reading of the deck: bands, dial order, search, scenes, skill files and posts.
final class LearnDeckTests: XCTestCase {
    private func card(_ slug: String, _ track: String, secs: Int = 120, title: String? = nil) -> String {
        #"{"slug": "\#(slug)", "track": "\#(track)", "title": "\#(title ?? "")", "subtitle": "sub \#(slug)", "description": "about \#(slug)", "triggers": ["say \#(slug)"], "#
            + #""skill": "skills/\#(track)/\#(slug)/SKILL.md", "spec": "skills/\#(track)/\#(slug)/spec.json", "html": "skills/\#(track)/\#(slug)/\#(slug).html", "#
            + #""sections": [{"title": "One", "scenes": 2}, {"title": "Two", "scenes": 1}], "scenes": 3, "est_seconds": \#(secs)}"#
    }

    /// The catalog's `bands` (LAB-1257: the deck repository's manual.yaml), as JSON to splice into a test catalog.
    private func bandsJSON() throws -> String {
        let j = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(LearnDeckFixture.catalogJSON.utf8)) as? [String: Any])
        return String(decoding: try JSONSerialization.data(withJSONObject: j["bands"] ?? []), as: UTF8.self)
    }

    private func deck() throws -> LearnDeck {
        let json = """
        {"version": "0.2.0", "bands": \(try bandsJSON()),
         "suits": [{"id": "spades", "symbol": "♠", "label": "Ideas", "tracks": ["foundations", "rhythms", "ship"]}],
         "tracks": [{"id": "foundations", "suit": "spades", "intro": "Big", "cards": ["loops-first", "context-as-structure", "zeta"]},
                    {"id": "rhythms", "suit": "spades", "intro": "Daily", "cards": ["done-when", "nightly"]},
                    {"id": "ship", "suit": "spades", "intro": "Ship", "cards": ["smoke-prod"]}],
         "paths": [{"id": "p", "title": "Path", "tag": "T", "why": "Why", "slugs": ["done-when", "missing", "smoke-prod"]}],
         "cards": [\(card("loops-first", "foundations", title: "Loops First")), \(card("context-as-structure", "foundations")), \(card("zeta", "foundations")),
                   \(card("done-when", "rhythms")), \(card("nightly", "rhythms", secs: 30)), \(card("smoke-prod", "ship"))]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
    }

    func testBandsPutStartHereCardsFirstThenTracksInCatalogOrder() throws {
        let d = try deck()
        XCTAssertEqual(d.version, "0.2.0")
        XCTAssertEqual(d.count, 6)
        // loops-first is a foundations card but a Loops start-here card: it belongs to Loops.
        XCTAssertEqual(d.partOf["loops-first"], "loops")
        XCTAssertEqual(d.lists["context"], ["context-as-structure", "zeta"])
        XCTAssertEqual(d.lists["loops"], ["loops-first", "done-when", "nightly"])
        XCTAssertEqual(d.lists["evidence"], ["smoke-prod"])
        XCTAssertEqual(d.lists["procedure"], [])
        XCTAssertEqual(d.dial, ["context-as-structure", "zeta", "loops-first", "done-when", "nightly", "smoke-prod"])
        XCTAssertEqual(d.band(of: "smoke-prod").title, "Evidence")
        XCTAssertEqual(d.cards["zeta"]?.title, "Zeta", "an empty title falls back to the slug")
        XCTAssertEqual(d.htmlPath("done-when"), "/deck/skills/rhythms/done-when/done-when.html")
        XCTAssertEqual(d.slug(forPage: "/deck/skills/rhythms/done-when/done-when.html"), "done-when")
        XCTAssertNil(d.slug(forPage: "/elsewhere/done-when.html"))
        XCTAssertEqual(d.paths.first?.slugs.filter { d.cards[$0] != nil }, ["done-when", "smoke-prod"])
    }

    /// LAB-1257 · the bands, plain track names and By-kind groups read from the catalog the deck repository builds are
    /// exactly the constants One Roof 1.8.2 hard-coded.
    func testCatalogBandsNamesAndKindsEqualThe182Constants() throws {
        let d = try XCTUnwrap(LearnDeck.parse(Data(LearnDeckFixture.catalogJSON.utf8), root: "/deck"))
        XCTAssertEqual(d.bands, LearnDeckFixture.bands)
        XCTAssertEqual(d.trackNames.mapValues { [$0.name, $0.question] }, LearnDeckFixture.trackNames.mapValues { [$0.name, $0.question] })
        XCTAssertEqual(d.kinds.map { [$0.title, $0.sub] + $0.tracks }, LearnDeckFixture.kinds.map { [$0.title, $0.sub] + $0.tracks })
        XCTAssertEqual(d.band(id: "nope").id, "loops", "an unknown band falls back to Loops, as before")
    }

    /// An older deck without bands shows a neutral Learn: no bands, no dial, nothing invented, nothing crashes.
    func testDeckWithoutBandsIsNeutral() throws {
        let json = #"{"version": "0.1.0", "tracks": [{"id": "ship", "cards": ["smoke-prod"]}], "cards": [{"slug": "smoke-prod", "track": "ship"}]}"#
        let d = try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
        XCTAssertTrue(d.bands.isEmpty)
        XCTAssertTrue(d.trackNames.isEmpty)
        XCTAssertTrue(d.kinds.isEmpty)
        XCTAssertEqual(d.dial, [])
        XCTAssertEqual(d.band(of: "smoke-prod").id, "")
        XCTAssertEqual(d.count, 1)
    }

    /// `load` makes the deck the one the static accessors (used by the Learn views) describe.
    func testLoadPublishesTheDecksBands() throws {
        let dir = NSTemporaryDirectory() + "deckload-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir + "/content", withIntermediateDirectories: true)
        try LearnDeckFixture.catalogJSON.write(toFile: dir + "/content/catalog.json", atomically: true, encoding: .utf8)
        let d = try XCTUnwrap(LearnDeck.load(deck: dir))
        XCTAssertEqual(LearnDeck.bands, d.bands)
        XCTAssertEqual(LearnDeck.bands.map(\.title), ["Context", "Loops", "Evidence", "Procedure"])
        XCTAssertEqual(LearnDeck.trackNames["vault"]?.name, "Notes & memory")
        XCTAssertEqual(LearnDeck.kinds.count, 4)
        XCTAssertEqual(LearnDeck.fallbackBand.id, "loops")
    }

    func testSearchMatchesEveryWordInDialOrder() throws {
        let d = try deck()
        XCTAssertEqual(d.search("about done"), ["done-when"])
        XCTAssertEqual(d.search("say"), d.dial)
        XCTAssertEqual(d.search("  "), [])
        XCTAssertEqual(d.search("nothing-like-this"), [])
    }

    func testFormatting() {
        XCTAssertEqual(LearnDeck.label("model-craft"), "Model craft")
        XCTAssertEqual(LearnDeck.minutes(383), "6 min")
        XCTAssertEqual(LearnDeck.minutes(10), "1 min")
        XCTAssertEqual(LearnDeck.clock(325), "5:25")
        XCTAssertEqual(DeckSpec.clean("🧭 The reframe  now"), "The reframe now")
    }

    func testScenesFromSpecWithSectionDiagramAndFallback() throws {
        let dir = NSTemporaryDirectory() + "deck-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let spec = #"{"sections": [{"title": "🔁 The loop", "diagram": {"nodes": [{"id": "a", "title": "Ask", "sub": "first"}, {"id": "b", "title": "Do"}]}, "#
            + #""scenes": [{"kicker": "Step 1", "heading": "Open", "lede": "L", "points": ["p1", "p2"], "highlight": ["a"], "narration": "Say this."}]},"#
            + #" {"title": "Recap", "scenes": [{"heading": "Done", "narration": ""}]}]}"#
        try spec.write(toFile: dir + "/spec.json", atomically: true, encoding: .utf8)
        let s = DeckSpec.scenes(path: dir + "/spec.json")
        XCTAssertEqual(s.count, 2)
        XCTAssertEqual(s[0].section, "The loop")
        XCTAssertEqual(s[0].nodes.map(\.title), ["Ask", "Do"])
        XCTAssertEqual(s[0].highlight, ["a"])
        XCTAssertEqual(s[0].points, ["p1", "p2"])
        XCTAssertEqual(s[0].narration, "Say this.")
        XCTAssertEqual(s[1].sectionIndex, 1)
        XCTAssertTrue(s[1].nodes.isEmpty)
        let d = try deck()
        let fallback = DeckSpec.scenes(path: dir + "/missing.json", fallback: d.cards["zeta"])
        XCTAssertEqual(fallback.map(\.section), ["One", "One", "Two"])
        XCTAssertTrue(fallback.allSatisfy { $0.narration.isEmpty })
    }

    func testSkillFileFrontmatterListsAndBody() {
        let text = """
        ---
        name: loops-first
        description: Agents close loops.
        runtime: [shared, nightly]
        dependencies:
          - done-when
          - evidence-check
        triggers:
          - loops-first
          - agents close loops
        metadata:
          type: skill
        ---

        # Loops First

        Body.
        """
        let s = DeckSkill.parse(text)
        XCTAssertEqual(s.front.map(\.key), ["name", "description", "runtime", "dependencies", "triggers"])
        XCTAssertEqual(s.front.first { $0.key == "triggers" }?.value, "loops-first, agents close loops")
        XCTAssertEqual(s.front.first { $0.key == "runtime" }?.value, "[shared, nightly]")
        XCTAssertEqual(s.dependencies, ["done-when", "evidence-check"])
        XCTAssertTrue(s.body.hasPrefix("# Loops First"))
        XCTAssertEqual(DeckSkill.parse("no frontmatter").body, "no frontmatter")
    }

    func testPostsFromLearnFoldersAndScheduleStates() throws {
        let root = NSTemporaryDirectory() + "posts-\(UUID().uuidString)"
        func post(_ folder: String, _ fm: String, _ body: String = "Hello world.\n\n## First\n\ntext\n\n## Links\n") throws {
            try FileManager.default.createDirectory(atPath: root + "/" + folder, withIntermediateDirectories: true)
            try ("---\n" + fm + "\n---\n\n" + body).write(toFile: root + "/" + folder + "/index.md", atomically: true, encoding: .utf8)
        }
        try post("20261024_loops-with-a-stop-condition", "title: \"Loops\"\ndate: 2026-10-24\nstatus: published\nseries: Agentic engineering\ntags: [a, b]")
        try post("20261101_next-one", "title: Next\ndate: 2026-11-01\nstatus: scheduled")
        try post("20261108_later", "title: Later\ndate: 2026-11-08\nstatus: scheduled")
        try post("notes", "title: No date")
        let posts = LearnPosts.scan([root])
        XCTAssertEqual(posts.map(\.slug), ["loops-with-a-stop-condition", "next-one", "later"])
        XCTAssertEqual(posts[0].sections, ["First"])
        XCTAssertEqual(posts[0].tags, ["a", "b"])
        XCTAssertEqual(posts[0].minutes, 1)
        XCTAssertEqual(LearnPosts.state(posts[0], in: posts, today: "2026-10-26").label, "AIRED")
        XCTAssertEqual(LearnPosts.state(posts[1], in: posts, today: "2026-10-26").label, "NEXT · 6 DAYS")
        XCTAssertEqual(LearnPosts.state(posts[2], in: posts, today: "2026-10-26").label, "SCHEDULED")
        XCTAssertEqual(LearnPosts.scan([root + "/missing"]), [])
    }

    func testDisplayTokensStayDarkInEveryLook() {
        for n in ThemeName.allCases {
            let d = n.tokens.display
            XCTAssertLessThan(d.fill.luminance, 0.05, "\(n)")
            XCTAssertGreaterThan(RGB.contrast(d.text, d.fill), 7, "\(n)")
            XCTAssertGreaterThan(RGB.contrast(d.accent, d.fill), 4.5, "\(n)")
        }
    }
}
