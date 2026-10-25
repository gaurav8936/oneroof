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

    /// LAB-528: the owner wrote above the list after picking 3, then picked 17 more; the message still named 3.
    func testEditedOpeningKeepsTheOwnersWordsAndFollowsThePicks() {
        let three = (1...3).map { PickedIssue(key: "LAB-\($0)", title: "Fix \($0)", state: "Backlog") }
        let twenty = (1...20).map { PickedIssue(key: "LAB-\($0)", title: "Fix \($0)", state: "Backlog") }
        let edited = "Invoke where are we first.\n\n" + Intake.multiTicketOpening(three, project: "LAB-X") + "\n\nNOTE: also LAB-99"
        let synced = Intake.syncIssueBlock(edited, issues: twenty, project: "LAB-X")
        XCTAssertTrue(synced.hasPrefix("Invoke where are we first.\n\nThis session works on 20 issues in project LAB-X:"), synced)
        XCTAssertTrue(synced.contains("- LAB-20: Fix 20 (Backlog)"))
        XCTAssertTrue(synced.contains("Only these 20 issues can be updated"))
        XCTAssertFalse(synced.contains("3 issues"))
        XCTAssertTrue(synced.hasSuffix("NOTE: also LAB-99"), "words after the list stay too")
        XCTAssertEqual(synced.components(separatedBy: "This session works on").count, 2, "one list, not two")

        let one = Intake.syncIssueBlock(synced, issues: [three[0]], project: "LAB-X")
        XCTAssertTrue(one.contains("Work on LAB-1 in project LAB-X: Fix 1."), one)
        XCTAssertFalse(one.contains("This session works on"))
        XCTAssertEqual(Intake.syncIssueBlock(one, issues: [], project: "LAB-X"), "Invoke where are we first.\n\nNOTE: also LAB-99")
    }

    func testOwnWordsOnlyGetTheListAppended() {
        let picks = [PickedIssue(key: "LAB-1", title: "A", state: "Todo"), PickedIssue(key: "LAB-2", title: "B", state: "Todo")]
        let s = Intake.syncIssueBlock("Please be careful.", issues: picks, project: nil)
        XCTAssertTrue(s.hasPrefix("Please be careful.\n\nThis session works on 2 issues:"), s)
        XCTAssertEqual(Intake.syncIssueBlock("Please be careful.", issues: [], project: nil), "Please be careful.")
        let placeholder = Intake.ticketOpening(key: Intake.newIssueKey, title: "t", project: "LAB-X")
        XCTAssertEqual(Intake.syncIssueBlock(placeholder, issues: [], project: "LAB-X"), placeholder, "a new issue's placeholder line stays for LAB-248")
    }

    /// LAB-491: openings start with Where Are We, anchored in the team and project; never twice, never on nothing.
    func testOpeningIsAnchoredOnce() {
        let a = Intake.anchored("Work on LAB-1.", team: "LAB", project: "LAB-ONEROOF-BUGS")
        XCTAssertTrue(a.hasPrefix("Invoke the \"Where Are We\" skill from agentic engineering (no transcript needed). Anchor yourself in project LAB-ONEROOF-BUGS (team LAB) and do not switch to another team in this session."), a)
        XCTAssertTrue(a.hasSuffix("this is what I would like you to do next:\n\nWork on LAB-1."))
        XCTAssertEqual(Intake.anchored(a, team: "LAB", project: "LAB-ONEROOF-BUGS"), a, "not twice")
        XCTAssertEqual(Intake.anchored("I want you to invoke where are we first.", team: "LAB", project: nil), "I want you to invoke where are we first.")
        XCTAssertEqual(Intake.anchored("", team: "LAB", project: nil), "")
        XCTAssertTrue(Intake.anchored("x", team: nil, project: nil).contains("Anchor yourself in this repo. Once"))
        // The issue block still follows the picks under the anchor (LAB-528).
        let picks = [PickedIssue(key: "LAB-1", title: "A", state: "Todo"), PickedIssue(key: "LAB-2", title: "B", state: "Todo")]
        let opening = Intake.anchored(Intake.multiTicketOpening(picks, project: "P-X"), team: "P", project: "P-X")
        let synced = Intake.syncIssueBlock(opening, issues: picks + [PickedIssue(key: "LAB-3", title: "C", state: "Todo")], project: "P-X")
        XCTAssertTrue(synced.hasPrefix("Invoke the \"Where Are We\""))
        XCTAssertTrue(synced.contains("This session works on 3 issues"))
    }

    func testOnlyASingleIssueSessionStartsItsIssueOnLaunch() {
        XCTAssertEqual(session(["LAB-1"]).ticketsToStartOnLaunch.map(\.key), ["LAB-1"])
        XCTAssertEqual(session(["LAB-1", "LAB-2"]).ticketsToStartOnLaunch, [], "the agent moves each when it starts on it")
        XCTAssertEqual(session([]).ticketsToStartOnLaunch, [])
    }
}

/// LAB-638: the New session opening message is built from what is picked now: Where Are We, the focus (team,
/// project, issues by key and title), the owner's own words, done when, then the issue steps.
final class SessionOpeningTests: XCTestCase {
    func test_LAB638_openingFollowsTeamProjectIssuesAndKeepsTheOwnersWords() {
        let one = Intake.sessionOpening(OpeningFocus(team: "LAB", teamName: "Labs", project: "LAB-ONEROOF-BUGS", projectTitle: "One Roof bugs",
                                                     issues: [PickedIssue(key: "LAB-591", title: "Feed is reversed", state: "Backlog")],
                                                     ask: "Fix the feed order first", doneWhen: "newest is on top"))
        XCTAssertTrue(one.hasPrefix("Invoke the \"Where Are We\" skill from agentic engineering (no transcript needed)."))
        XCTAssertTrue(one.contains("- Team: LAB · Labs"))
        XCTAssertTrue(one.contains("- Project: LAB-ONEROOF-BUGS · One Roof bugs"))
        XCTAssertTrue(one.contains("- Issue: LAB-591 · Feed is reversed"))
        XCTAssertTrue(one.contains("What I would like you to do:\nFix the feed order first"), "the owner's words are kept when an issue is picked")
        XCTAssertTrue(one.contains("Done when: newest is on top"))
        XCTAssertTrue(one.contains("Work on LAB-591 in project LAB-ONEROOF-BUGS: Feed is reversed."))
        XCTAssertFalse(one.contains("Anchor yourself"))

        // Another team and project: nothing of the first one is left.
        let other = Intake.sessionOpening(OpeningFocus(team: "ZIB", project: "ZIB-AWS-COST", ask: "Check the bill"))
        XCTAssertTrue(other.contains("- Team: ZIB") && other.contains("- Project: ZIB-AWS-COST"))
        XCTAssertFalse(other.contains("LAB"))
        XCTAssertFalse(other.contains("- Issue"))

        // Several issues: keys in the focus, one plan for all of them; no words typed → a plain ask.
        let picks = [PickedIssue(key: "LAB-1", title: "a", state: "Backlog"), PickedIssue(key: "LAB-2", title: "b", state: "Todo")]
        let many = Intake.sessionOpening(OpeningFocus(team: "LAB", project: "LAB-X", issues: picks))
        XCTAssertTrue(many.contains("- Issues (2, listed with their titles below): LAB-1, LAB-2"))
        XCTAssertTrue(many.contains("Resolve these 2 issues."))
        XCTAssertTrue(many.contains("This session works on 2 issues in project LAB-X:"))

        XCTAssertEqual(Intake.sessionOpening(OpeningFocus()), "", "nothing picked, nothing typed: no message")
    }

    /// LAB-638: an edited message keeps the owner's words; its focus and issue list follow new picks.
    func test_LAB638_editedOpeningKeepsWordsAndFollowsThePicks() {
        let start = Intake.sessionOpening(OpeningFocus(team: "LAB", project: "LAB-X", issues: [PickedIssue(key: "LAB-1", title: "a", state: "Backlog")], ask: "go"))
        let edited = start + "\n\nPS: be brief."
        let synced = Intake.syncOpening(edited, focus: OpeningFocus(team: "LAB", project: "LAB-X",
                                                                    issues: [PickedIssue(key: "LAB-1", title: "a", state: "Backlog"), PickedIssue(key: "LAB-2", title: "b", state: "Backlog")], ask: "go"))
        XCTAssertTrue(synced.contains("PS: be brief."))
        XCTAssertTrue(synced.contains("- Issues (2, listed with their titles below): LAB-1, LAB-2"))
        XCTAssertFalse(synced.contains("- Issue: LAB-1 · a"))
        XCTAssertTrue(synced.contains("This session works on 2 issues"))
    }
}
