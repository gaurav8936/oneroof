import XCTest
@testable import OneRoofCore

/// LAB-518: one session on several issues, and its agent updating each issue through One Roof.
final class IssueUpdateTests: XCTestCase {
    func session(_ keys: [String], linked: Bool = true) -> Session {
        var s = Session(name: "s", repoPath: "/p", lifecycle: .idle)
        if let first = keys.first { s.ticket = first; s.ticketId = linked ? "id-" + first : nil; s.ticketTeam = linked ? "LAB" : nil }
        s.moreTickets = keys.dropFirst().map { SessionIssue(key: $0, id: linked ? "id-" + $0 : nil, team: linked ? "LAB" : nil) }
        return s
    }

    // MARK: What an agent may change

    func testAgentMayMoveItsOwnIssueToInProgressOrInReview() {
        let s = session(["LAB-1", "LAB-2"])
        XCTAssertEqual(try? IssueRequest(seq: 1, key: "LAB-2", state: "In Progress").check(against: s).get().key, "LAB-2")
        XCTAssertEqual(try? IssueRequest(seq: 2, key: "lab-1", state: "in review").check(against: s).get().key, "LAB-1",
                       "key and state are matched without case")
        XCTAssertEqual(IssueRequest(seq: 2, key: "LAB-1", state: "in review").canonicalState, "In Review")
        XCTAssertEqual(try? IssueRequest(seq: 3, key: "LAB-1", comment: "plan").check(against: s).get().key, "LAB-1", "a comment alone")
    }

    func testAgentMayNotTouchOtherIssuesOrCloseThem() {
        let s = session(["LAB-1", "LAB-2"])
        XCTAssertEqual(IssueRequest(seq: 1, key: "LAB-9", state: "In Progress").check(against: s),
                       .failure(.notOnSession("LAB-9", ["LAB-1", "LAB-2"])))
        XCTAssertEqual(IssueRequest(seq: 1, key: "LAB-1", state: "Done").check(against: s), .failure(.stateNotAllowed("Done")))
        XCTAssertEqual(IssueRequest(seq: 1, key: "LAB-1", state: "Canceled").check(against: s), .failure(.stateNotAllowed("Canceled")))
        XCTAssertEqual(IssueRequest(seq: 1, key: "LAB-1").check(against: s), .failure(.nothingToDo))
        XCTAssertEqual(IssueRequest(seq: 1, key: "LAB-1", state: "In Review").check(against: session(["LAB-1"], linked: false)),
                       .failure(.notLinked("LAB-1")))
        XCTAssertTrue(IssueRequestError.notOnSession("LAB-9", []).description.contains("no issues"))
        XCTAssertTrue(IssueRequestError.stateNotAllowed("Done").description.contains("owner"))
    }

    func testRequestsAreReadFromRoofdList() {
        let st = RoofdRuntime.sessionState(["id": "roof-a", "agent": "claude", "status": "working", "issues": [
            ["seq": 1, "key": "LAB-1", "state": "In Progress"],
            ["seq": 2, "key": "LAB-2", "comment": "  "],          // blank comment, no state: kept, the app refuses it
            ["key": "LAB-3"],                                       // no seq: dropped
        ]])
        XCTAssertEqual(st?.issueRequests, [IssueRequest(seq: 1, key: "LAB-1", state: "In Progress"), IssueRequest(seq: 2, key: "LAB-2")])
        XCTAssertEqual(RoofdRuntime.sessionState(["id": "old"])?.issueRequests, [], "an older holder has none")
    }

    // MARK: Naming, opening, launch

    func testSessionNameCarriesEveryKey() {
        XCTAssertEqual(Intake.sessionName(keys: ["LAB-1", "LAB-2", "LAB-3"], title: "Tidy Resources"), "LAB-1, LAB-2, LAB-3 · Tidy Resources")
        XCTAssertEqual(Intake.sessionName(keys: ["LAB-1", "LAB-2"], title: " "), "LAB-1, LAB-2 · 2 issues")
        XCTAssertEqual(Intake.sessionName(keys: ["LAB-1"], title: "One"), "LAB-1 · One", "one key: the usual name")
    }

    func testOpeningListsEveryIssueAndAsksForOnePlanThenUpdates() {
        let o = Intake.multiTicketOpening([
            PickedIssue(key: "LAB-1", title: "Fix A", state: "Backlog", url: "https://linear.app/x/LAB-1"),
            PickedIssue(key: "LAB-2", title: "Fix B", state: "In Progress"),
        ], project: "LAB-ONEROOF-BUGS")
        XCTAssertTrue(o.contains("- LAB-1: Fix A (Backlog) — https://linear.app/x/LAB-1"))
        XCTAssertTrue(o.contains("- LAB-2: Fix B (In Progress)"))
        XCTAssertTrue(o.contains("ONE plan"))
        XCTAssertTrue(o.contains("\"$ONEROOF_ROOFD_BIN\" issue <KEY> --state \"In Progress\""))
        XCTAssertTrue(o.contains("--state \"In Review\" --comment"))
        XCTAssertTrue(o.contains("`<KEY> · [lab-oneroof-bugs] …`"))
        XCTAssertTrue(o.contains("Done stays with me"))
    }

    func testOnlyASingleIssueSessionStartsItsIssueOnLaunch() {
        XCTAssertEqual(session(["LAB-1"]).ticketsToStartOnLaunch.map(\.key), ["LAB-1"])
        XCTAssertEqual(session(["LAB-1", "LAB-2"]).ticketsToStartOnLaunch, [], "the agent moves each when it starts on it")
        XCTAssertEqual(session([]).ticketsToStartOnLaunch, [])
    }
}
