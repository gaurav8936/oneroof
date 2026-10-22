import XCTest
@testable import OneRoofCore

/// LAB-511: issues a session mentions but has not attached.
final class IssueMentionTests: XCTestCase {
    func testBareNumbersAfterBugTakeTheSessionsTeam() {
        let s = Session(name: "Bugs 298 and 460", agent: .claude, repoPath: "/p", workstream: "LAB-ONEROOF-BUGS",
                        openingMessage: "I want you to work on bugs 298 and 460 from Linear for Labs.")
        XCTAssertEqual(IssueMentions.team(of: s), "LAB")
        XCTAssertEqual(IssueMentions.keys(in: IssueMentions.texts(s), team: IssueMentions.team(of: s)), ["LAB-298", "LAB-460"])
    }

    func testFullKeysInOrderWithoutDuplicatesOrOwnIssues() {
        let texts = ["LAB-472 · The moment…", "Fixed LAB-474 and LAB-472; see UTF-8 and SHA-256", "[live 1a2b] LAB-490 · [lab-oneroof-bugs] x"]
        XCTAssertEqual(IssueMentions.keys(in: texts, team: nil, teams: ["LAB", "ENG"], excluding: ["lab-472"]), ["LAB-474", "LAB-490"])
        XCTAssertEqual(IssueMentions.keys(in: ["see UTF-8"], team: nil), ["UTF-8"], "with no team list any KEY-n counts")
        XCTAssertEqual(IssueMentions.keys(in: ["issues 12, 13 & #14; ticket 9 is too short"], team: "eng"), ["ENG-12", "ENG-13", "ENG-14"])
        XCTAssertEqual(IssueMentions.keys(in: ["LAB-ONEROOF-BUGS and LAB-0"], team: nil), [], "project codes and 0 are not issues")
    }

    func testTeamFromTicketFirst() {
        var s = Session(name: "x", agent: .claude, repoPath: "/p", workstream: "GBL-HELP")
        XCTAssertEqual(IssueMentions.team(of: s), "GBL")
        s.ticketTeam = "lab"
        XCTAssertEqual(IssueMentions.team(of: s), "LAB")
    }
}
