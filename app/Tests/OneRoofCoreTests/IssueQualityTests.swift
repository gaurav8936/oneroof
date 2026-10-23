import XCTest
@testable import OneRoofCore

/// LAB-533: the issue quality bar — must-haves per type, bonus points, "not ready" with what is missing.
final class IssueQualityTests: XCTestCase {
    func issue(_ type: String?, _ title: String, _ body: String) -> LinearIssue {
        LinearIssue(id: "1", identifier: "LAB-1", title: title, description: body, state: "Backlog", stateType: "backlog",
                    type: type, milestoneId: nil, milestone: nil, url: "")
    }

    func testAGoodBugIsReadyWithBonusPoints() {
        let body = """
        ## Steps to reproduce
        1. Open One Roof 0.5.1 and start a Claude session
        2. Pop the session out (⌥⌘O)
        3. Close the pop-out window

        **Expected:** the terminal goes back to the main window.
        **Actual:** the pane stays blank until the row is clicked again.

        ![blank pane](https://uploads.linear.app/abc/def/blank.png)
        Probably `PopOutWindow.swift:61` (bringBack).
        """
        let r = IssueQuality.assess(issue("defect", "Pop-out close leaves a blank pane", body))
        XCTAssertTrue(r.ready, r.missingLine)
        XCTAssertEqual(r.kind, .bug)
        XCTAssertEqual(r.bonus, ["screenshot", "file:line"])
        XCTAssertEqual(r.score, 100)
        XCTAssertEqual(r.missingLine, "")
    }

    func testAThinBugIsNotReadyAndSaysWhatIsMissing() {
        let r = IssueQuality.assess(issue("defect", "Sidebar flickers", "The sidebar flickers sometimes. Annoying."))
        XCTAssertFalse(r.ready)
        XCTAssertEqual(r.missing, ["steps to reproduce", "expected vs actual", "where seen (version, build or screen)"])
        XCTAssertEqual(r.missingLine, "Missing: steps to reproduce, expected vs actual, where seen (version, build or screen)")
        XCTAssertEqual(r.score, 0)
        XCTAssertTrue(r.tooltip.contains("Bonus if added: screenshot, file:line"))
    }

    func testBugWithExpectedButNoActualIsStillMissingIt() {
        let body = """
        Steps to reproduce: open Settings › General and toggle the Dock badge off.
        It should clear the badge.
        """
        let r = IssueQuality.assess(issue("Bug", "Dock badge stays", body))
        XCTAssertEqual(r.missing, ["expected vs actual"])
        XCTAssertEqual(r.score, 53)
    }

    func testDeliverable() {
        let good = """
        Outcome: the owner sees a banner when an agent needs them, so that no session waits unseen.

        Scope: needs-you, ready and long-command notifications; Settings toggles. Out of scope: Slack.

        Done when:
        - [ ] a banner shows for a session that needs you while the app is in the background
        - [ ] clicking it opens the session
        """
        let r = IssueQuality.assess(issue("deliverable", "Desktop notifications", good))
        XCTAssertTrue(r.ready, r.missingLine)
        XCTAssertEqual(r.missingBonus, ["mockup or screenshot", "file:line"])
        XCTAssertEqual(r.score, 80)
        let thin = IssueQuality.assess(issue("deliverable", "Notifications", "Add desktop notifications."))
        XCTAssertEqual(thin.missing, ["outcome", "done when", "scope"])
    }

    func testTaskSpikeAndDecision() {
        let task = IssueQuality.assess(issue("chore", "Bump Ghostty",
            "Rebuild GhosttyKit from v1.3.2 with scripts/build-ghosttykit.sh and update the Vendor link. Done when swift build passes."))
        XCTAssertTrue(task.ready, task.missingLine)
        XCTAssertEqual(IssueQuality.assess(issue("Task", "Bump", "Bump it.")).missing, ["what to do", "done when"])

        let spike = IssueQuality.assess(issue("spike", "Can roofd run shell integration for bash?",
            "Find out whether Ghostty's bash integration works under roofd. Outcome: a short write-up with a yes/no. Timebox: 2 h."))
        XCTAssertTrue(spike.ready, spike.missingLine)
        XCTAssertEqual(spike.bonus, ["timebox"])
        XCTAssertEqual(IssueQuality.assess(issue("spike", "Look at bash", "Look into bash.")).missing,
                       ["question", "outcome (what the answer will be)"])

        let decision = """
        ## Context
        Notifications need a permission prompt.
        ## Options
        - Option A: ask at first launch
        - Option B: ask on the first notification
        ## Recommendation
        Option B: fewer prompts for people who never get one. Trade-off: the first banner is late.
        """
        let d = IssueQuality.assess(issue("decision", "When to ask for notification permission", decision))
        XCTAssertTrue(d.ready, d.missingLine)
        XCTAssertEqual(d.bonus, ["context (why now)", "trade-offs"])
        XCTAssertEqual(IssueQuality.assess(issue("decision", "Permission prompt", "We need to decide this.")).missing,
                       ["options", "recommendation"])
    }

    func testNoTypeIsNotReady() {
        let r = IssueQuality.assess(issue(nil, "Something", ""))
        XCTAssertFalse(r.ready)
        XCTAssertEqual(r.missing, ["a Type (Bug, Deliverable, Task, Spike or Decision)", "a description"])
        XCTAssertNil(IssueQuality.Kind(type: "workstream"))
        XCTAssertEqual(IssueQuality.Kind(type: "type:defect"), .bug)
        XCTAssertEqual(IssueQuality.Kind(type: "Task"), .task)
    }

    func testScreenshotDetection() {
        XCTAssertTrue(IssueQuality.Doc(title: "", body: "see https://uploads.linear.app/x/y").meets("screenshot", kind: .bug))
        XCTAssertTrue(IssueQuality.Doc(title: "", body: "![](a.png)").meets("screenshot", kind: .bug))
        XCTAssertFalse(IssueQuality.Doc(title: "", body: "no screenshot yet").meets("screenshot", kind: .bug))
    }
}
