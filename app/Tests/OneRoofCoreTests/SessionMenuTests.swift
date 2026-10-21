import XCTest
@testable import OneRoofCore

/// LAB-300: the session menu shows stickers, colours, emoji and actions inline, with no Close button.
final class SessionMenuTests: XCTestCase {
    private func item(status: SessionStatus, live: Bool, adopted: Bool = false) -> BoardItem {
        let s = Session(name: "t", agent: .claude, repoPath: Workspace.projectsRoot, lifecycle: live ? .running : .planned)
        return BoardItem(id: s.id, session: s, status: status, liveAgent: live ? "a-t" : nil,
                         paneId: nil, workspaceId: nil, detectedAccount: nil, adopted: adopted, title: nil)
    }

    func test_LAB300_noCloseInQuickActions() {
        XCTAssertFalse(SessionQuickAction.allCases.map(\.rawValue).contains("close"))
        let live = SessionQuickAction.available(for: item(status: .idle, live: true))
        XCTAssertEqual(live, [.open, .next, .pin, .rename, .issue, .highlight, .doNotUse])
    }

    func test_LAB300_stoppedSessionsLaunchAndDelete() {
        XCTAssertEqual(SessionQuickAction.available(for: item(status: .planned, live: false)).first, .launch)
        XCTAssertEqual(SessionQuickAction.available(for: item(status: .exited, live: false)).first, .relaunch)
        XCTAssertEqual(SessionQuickAction.available(for: item(status: .exited, live: false)).last, .delete)
        XCTAssertFalse(SessionQuickAction.available(for: item(status: .doNotUse, live: false)).contains(.launch))
        XCTAssertFalse(SessionQuickAction.available(for: item(status: .exited, live: false, adopted: true)).contains(.delete))
    }

    func test_LAB300_pickableStickersSkipStatusOnesAndKeepCustoms() {
        let ids = Sticker.pickable(for: ["wip", "Deploy", "deploy", " "]).map(\.id)
        XCTAssertEqual(Array(ids.prefix(4)), ["wip", "important", "blocked", "review"])
        XCTAssertFalse(ids.contains("next"))
        XCTAssertFalse(ids.contains("dnu"))
        XCTAssertEqual(ids.filter { $0 == "deploy" }.count, 1)
        XCTAssertEqual(ids.filter { $0 == "wip" }.count, 1)
    }

    func test_LAB300_highlightIsTheImportantSticker() {
        XCTAssertTrue(Sticker.catalog.contains { $0.id == Sticker.highlightId && $0.builtIn })
        XCTAssertEqual(Set(Sticker.emojiChoices).count, Sticker.emojiChoices.count)
    }

    func test_LAB474_issueActionOnEverySessionButParkedOnes() {
        XCTAssertTrue(SessionQuickAction.available(for: item(status: .running, live: true)).contains(.issue))
        XCTAssertTrue(SessionQuickAction.available(for: item(status: .planned, live: false)).contains(.issue))
        XCTAssertFalse(SessionQuickAction.available(for: item(status: .doNotUse, live: false)).contains(.issue))
    }

    private func issue(_ key: String) -> LinearIssue {
        LinearIssue(id: "id-" + key, identifier: key, title: "Attach me", description: "", state: "Backlog",
                    stateType: "backlog", type: "deliverable", milestoneId: nil, milestone: nil, url: "https://linear.app/x/" + key)
    }

    func test_LAB474_attachNamesAPlainSessionAndSetsItsTicket() {
        var s = Session(name: "fix the panel", repoPath: "/r")
        Intake.attach(issue("LAB-474"), team: "LAB", project: "LAB-ONEROOF-BUGS", to: &s)
        XCTAssertEqual(s.name, "LAB-474 · fix the panel")
        XCTAssertEqual(s.ticket, "LAB-474")
        XCTAssertEqual(s.ticketId, "id-LAB-474")
        XCTAssertEqual(s.ticketTeam, "LAB")
        XCTAssertEqual(s.workstream, "LAB-ONEROOF-BUGS")
    }

    func test_LAB474_attachToASessionWithAnIssueKeepsNameAndProject() {
        var s = Session(name: "LAB-472 · shift", repoPath: "/r", workstream: "LAB-ROOFD", ticket: "LAB-472", ticketId: "x", ticketTeam: "LAB")
        Intake.attach(issue("LAB-474"), team: nil, project: "LAB-ONEROOF-BUGS", to: &s)
        XCTAssertEqual(s.name, "LAB-472 · shift")
        XCTAssertEqual(s.ticket, "LAB-474")
        XCTAssertEqual(s.ticketTeam, "LAB")
        XCTAssertEqual(s.workstream, "LAB-ROOFD")
    }

    func test_LAB474_attachMessageNamesKeyLinkAndCommitFormat() {
        let m = Intake.attachMessage(key: "LAB-474", title: "Attach me", url: "https://l/LAB-474", project: "LAB-ONEROOF-BUGS")
        XCTAssertTrue(m.contains("LAB-474: Attach me"))
        XCTAssertTrue(m.contains("https://l/LAB-474"))
        XCTAssertTrue(m.contains("`LAB-474 · [lab-oneroof-bugs] …`"))
    }
}
