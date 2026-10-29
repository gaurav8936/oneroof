import XCTest
@testable import OneRoofCore

final class SessionSearchTests: XCTestCase {
    private let docs = [
        SessionSearch.Doc(id: "a", title: "Bugs: Ongoing", meta: "labs/oneroof", lines: ["The terminal froze for a second on every resize.", "Fixed the hitch."]),
        SessionSearch.Doc(id: "b", title: "Pitch Deck: Energy Lab 2", meta: "labs-docs", lines: ["Slide 10 needs the engine run."]),
        SessionSearch.Doc(id: "c", title: "Release notes", meta: "", lines: Array(repeating: "release release release notes notes", count: 50)),
    ]

    /// LAB-1585: a session is found by what it worked on, and the hit says why.
    func test_LAB1585_findsByConversationWithSnippet() {
        let hits = SessionSearch.rank("screen freezing on resize", docs: docs)
        XCTAssertEqual(hits.first?.id, "a")
        XCTAssertTrue(hits.first!.snippet.contains("resize"))
    }

    /// LAB-1585: freeze, freezing and froze-adjacent forms meet; related words from the model widen the search.
    func test_LAB1585_stemsMeetAndRelatedWordsWiden() {
        XCTAssertEqual(SessionSearch.keys("freezing"), SessionSearch.keys("freezes"))
        XCTAssertTrue(SessionSearch.rank("stutter", docs: docs).isEmpty)
        XCTAssertEqual(SessionSearch.rank("stutter", extra: ["hitch"], docs: docs).first?.id, "a")
    }

    /// LAB-1585: the name counts most; a long conversation does not win by length alone.
    func test_LAB1585_titleBeatsLength() {
        XCTAssertEqual(SessionSearch.rank("pitch deck", docs: docs).first?.id, "b")
        let notes = [SessionSearch.Doc(id: "x", title: "Release notes", meta: "", lines: ["short"])] + docs.filter { $0.id != "c" }
            + [SessionSearch.Doc(id: "c", title: "Misc", meta: "", lines: Array(repeating: "release notes", count: 200))]
        XCTAssertEqual(SessionSearch.rank("release notes", docs: notes).first?.id, "x")
    }

    func test_LAB1585_parsesModelWords() {
        XCTAssertEqual(SessionSearch.parseExpansion("hangs, freezes, freezes, \"lag\"\n1. stutter, technical terms, ui_jank"),
                       ["hangs", "freezes", "lag", "stutter", "ui jank"])
    }
}

final class CatalogOrderTests: XCTestCase {
    private func entry(_ id: String, _ state: SessionCatalog.State, ago: TimeInterval) -> SessionCatalog.Entry {
        SessionCatalog.Entry(id: id, name: id, agent: "Claude", account: nil, repo: "r", ticket: nil, window: nil,
                             started: Date().addingTimeInterval(-ago), lastActive: nil, state: state, resume: .open)
    }

    /// LAB-1584: a row that changes state and date keeps its place, and stays listed under the filter it was found with.
    func test_LAB1584_rowsKeepTheirPlace() {
        let before = [entry("old", .history, ago: 500), entry("new", .history, ago: 100)]
        let order = SessionCatalog.order(of: SessionCatalog.groups(before))
        XCTAssertEqual(order, ["new": 0, "old": 1])
        let after = [entry("old", .working, ago: 0), entry("new", .history, ago: 100)]
        XCTAssertEqual(SessionCatalog.groups(after, order: order).flatMap(\.entries).map(\.id), ["new", "old"])
        XCTAssertEqual(SessionCatalog.groups(after, states: [.history], order: order).flatMap(\.entries).map(\.id), ["new"])
        XCTAssertEqual(SessionCatalog.groups(after, states: [.history], order: order, keep: ["old"]).flatMap(\.entries).map(\.id), ["new", "old"])
    }
}
