import XCTest
@testable import OneRoofCore

/// LAB-1668 · People (Influences) grouped by the catalog's themes, with each person's photo or initials and profile.
final class LearnPeopleTests: XCTestCase {
    private func deck() throws -> LearnDeck {
        func person(_ s: String, _ name: String, _ theme: String, photo: String?) -> String {
            let ph = photo.map { "\"\($0)\"" } ?? "null"
            return """
            {"slug": "\(s)", "track": "influences", "title": "\(name)", "html": "skills/influences/\(s)/\(s).html", "sections": [], "scenes": 4,
             "person": "\(name)", "tagline": "Tagline \(s)", "theme": "\(theme)", "role": "Role \(s)", "photo": \(ph),
             "monogram": \(photo == nil ? "\"ZZ\"" : "null"), "sources": 5}
            """
        }
        let json = """
        {"version": "0.2.4",
         "bands": [{"id": "context", "n": "01", "title": "Context", "tracks": ["intro", "influences"], "start_here": ["four-bands"]},
                   {"id": "loops", "n": "02", "title": "Loops", "tracks": ["goals"], "start_here": ["g1"]}],
         "tracks": [{"id": "intro", "cards": ["four-bands"]}, {"id": "influences", "cards": ["amodei", "willison", "karpathy", "zed"]},
                    {"id": "goals", "cards": ["g1"]}],
         "themes": [{"id": "labs", "title": "Labs and research", "question": "Who builds the models?", "track": "influences", "cards": ["amodei", "karpathy"]},
                    {"id": "practitioners", "title": "Practitioners in the open", "question": "Who shows the work?", "track": "influences", "cards": ["willison", "ghost"]}],
         "cards": [{"slug": "four-bands", "track": "intro", "title": "The four bands", "html": "a.html", "sections": [], "scenes": 3},
                   \(person("amodei", "Dario Amodei", "labs", photo: "skills/influences/amodei/photo.webp")),
                   \(person("karpathy", "Andrej Karpathy", "labs", photo: "skills/influences/karpathy/photo.webp")),
                   \(person("willison", "Simon Willison (simonw)", "practitioners", photo: nil)),
                   \(person("zed", "Zed Unthemed", "", photo: nil)),
                   {"slug": "g1", "track": "goals", "title": "G1", "html": "g.html", "sections": [], "scenes": 3}]}
        """
        return try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
    }

    func testThemesAreReadInOrderWithOnlyKnownCards() throws {
        let d = try deck()
        XCTAssertEqual(d.themes.map(\.id), ["labs", "practitioners"])
        XCTAssertEqual(d.themes[1].cards, ["willison"])                  // "ghost" is not in the deck
        XCTAssertEqual(d.themes(ofTrack: "influences").count, 2)
        XCTAssertTrue(d.themes(ofTrack: "intro").isEmpty)
    }

    func testThemedTrackPlaysInThemeOrderThenTheRest() throws {
        let d = try deck()
        XCTAssertEqual(d.tracks["influences"]?.cards, ["amodei", "karpathy", "willison", "zed"])
        XCTAssertEqual(d.lists["context"], ["four-bands", "amodei", "karpathy", "willison", "zed"])
        XCTAssertEqual(LearnRollover.next(after: "karpathy", in: d), "willison")   // ⏭ and the roll-over follow the themes
        XCTAssertEqual(LearnRollover.previous(before: "willison", in: d), "karpathy")
    }

    func testPersonFieldsPhotoOrInitials() throws {
        let d = try deck()
        let a = try XCTUnwrap(d.cards["amodei"]?.person)
        XCTAssertEqual(a.display, "Dario Amodei")
        XCTAssertEqual(a.tagline, "Tagline amodei")
        XCTAssertEqual(a.theme, "labs")
        XCTAssertEqual(a.photo, "skills/influences/amodei/photo.webp")
        XCTAssertEqual(a.sources, 5)
        let w = try XCTUnwrap(d.cards["willison"]?.person)
        XCTAssertNil(w.photo)
        XCTAssertEqual(w.initials, "ZZ")                                   // the catalog's monogram wins
        XCTAssertEqual(DeckPerson(display: "Simon Willison (simonw)", tagline: "", theme: "", role: "", photo: nil, monogram: "", sources: 0).initials, "SW")
        XCTAssertNil(d.cards["four-bands"]?.person)
    }

    func testOlderDeckHasNoThemes() throws {
        let json = #"{"version": "0.2.2", "tracks": [{"id": "t", "cards": ["a"]}], "cards": [{"slug": "a", "track": "t", "title": "A", "html": "a.html", "sections": [], "scenes": 1}]}"#
        let d = try XCTUnwrap(LearnDeck.parse(Data(json.utf8), root: "/deck"))
        XCTAssertTrue(d.themes.isEmpty)
        XCTAssertNil(d.cards["a"]?.person)
    }

    func testProfileFromSpec() throws {
        let spec = """
        {"title": "x", "sections": [],
         "profile": {"name": "Andrej Karpathy", "display": "Andrej Karpathy", "role": "Researcher", "tagline": "Software 3.0",
                     "bio": ["One.", "Two.", "Three."], "big_idea": "LLMs are computers.",
                     "photos": [{"file": "photo.webp", "name": "Andrej Karpathy", "photo_credit": "Someone, via Wikimedia Commons", "photo_licence": "CC BY 3.0", "photo_source": "https://commons.example/x"}],
                     "start_here": {"title": "Software Is Changing", "url": "https://example.com/talk", "type": "talk", "year": 2025},
                     "publishes": [{"label": "karpathy.ai", "url": "https://karpathy.ai"}], "related": ["simonw"], "checked": "2026-10-29"},
         "sources": [{"title": "Vibe coding", "type": "essay", "year": 2025, "url": "https://example.com/v", "line": "Naming it."},
                     {"title": "no url", "type": "essay"}],
         "deeper": [{"title": "2025 LLM Year in Review", "url": "https://example.com/y"}]}
        """
        let p = try XCTUnwrap(DeckProfile.parse(Data(spec.utf8)))
        XCTAssertEqual(p.display, "Andrej Karpathy")
        XCTAssertEqual(p.bio.count, 3)
        XCTAssertEqual(p.startHere?.url, "https://example.com/talk")
        XCTAssertEqual(DeckProfile.meta(try XCTUnwrap(p.startHere)), "talk · 2025")
        XCTAssertEqual(p.publishes.map(\.title), ["karpathy.ai"])
        XCTAssertEqual(p.sources.map(\.title), ["Vibe coding"])            // a source without a link is left out
        XCTAssertEqual(p.photos.first?.licence, "CC BY 3.0")
        XCTAssertEqual(p.deeper, ["2025 LLM Year in Review"])
        XCTAssertNil(DeckProfile.parse(Data(#"{"title": "not a person"}"#.utf8)))
    }
}
