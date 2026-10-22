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

    func test_LAB474_aSessionCarriesSeveralIssues() {
        var s = Session(name: "LAB-472 · shift", repoPath: "/r", workstream: "LAB-ROOFD", ticket: "LAB-472", ticketId: "x", ticketTeam: "LAB")
        XCTAssertTrue(Intake.attach(issue("LAB-474"), team: nil, project: "LAB-ONEROOF-BUGS", to: &s))
        XCTAssertTrue(Intake.attach(issue("LAB-475"), team: "LAB", project: nil, to: &s))
        XCTAssertEqual(s.name, "LAB-472 · shift")
        XCTAssertEqual(s.ticket, "LAB-472")
        XCTAssertEqual(s.allTickets.map(\.key), ["LAB-472", "LAB-474", "LAB-475"])
        XCTAssertEqual(s.moreTickets.first?.team, "LAB")
        XCTAssertEqual(s.workstream, "LAB-ROOFD")
        XCTAssertEqual(s.ticketChip, "LAB-472 +2")
        XCTAssertFalse(Intake.attach(issue("LAB-474"), team: nil, project: nil, to: &s), "same issue twice")
        XCTAssertEqual(s.allTickets.count, 3)
    }

    func test_LAB474_detachPromotesTheNextIssue() {
        var s = Session(name: "t", repoPath: "/r", ticket: "LAB-1", ticketId: "a", ticketTeam: "LAB")
        Intake.attach(issue("LAB-2"), team: "LAB", project: nil, to: &s)
        Intake.detach("LAB-1", from: &s)
        XCTAssertEqual(s.ticket, "LAB-2")
        XCTAssertEqual(s.ticketId, "id-LAB-2")
        XCTAssertTrue(s.moreTickets.isEmpty)
        Intake.detach("LAB-2", from: &s)
        XCTAssertNil(s.ticket)
        XCTAssertNil(s.ticketChip)
    }

    func test_LAB474_issuesSurviveSaveAndOldRowsLoad() throws {
        var s = Session(name: "t", repoPath: "/r", ticket: "LAB-1", ticketId: "a", ticketTeam: "LAB")
        Intake.attach(issue("LAB-2"), team: "LAB", project: nil, to: &s)
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.allTickets.map(\.key), ["LAB-1", "LAB-2"])
        let old = #"{"id":"o","name":"old","agent":"claude","repoPath":"/r","ticket":"LAB-9"}"#
        let o = try JSONDecoder().decode(Session.self, from: Data(old.utf8))
        XCTAssertEqual(o.allTickets.map(\.key), ["LAB-9"])
    }

    func test_LAB474_commitWithASecondIssueKeyFindsTheSession() {
        var s = Session(name: "t", repoPath: "/r", ticket: "LAB-1", ticketId: "a", ticketTeam: "LAB")
        Intake.attach(issue("LAB-2"), team: "LAB", project: nil, to: &s)
        XCTAssertEqual(Attributor.session(forCommitMessage: "LAB-2 · [lab-x] fix", sessions: [s])?.id, s.id)
    }

    func test_LAB474_attachMessageNamesKeyLinkAndCommitFormat() {
        let m = Intake.attachMessage(key: "LAB-474", title: "Attach me", url: "https://l/LAB-474", project: "LAB-ONEROOF-BUGS")
        XCTAssertTrue(m.contains("LAB-474: Attach me"))
        XCTAssertTrue(m.contains("https://l/LAB-474"))
        XCTAssertTrue(m.contains("`LAB-474 · [lab-oneroof-bugs] …`"))
    }

    /// LAB-284: Ask to fix and review comments refuse a working or waiting agent, with the reason.
    func test_LAB284_typingRefusedWhileWorkingOrWaiting() {
        XCTAssertEqual(SessionStatus.running.typingRefusal(name: "A"), "A is working; send when it is idle.")
        XCTAssertNotNil(SessionStatus.needsYou.typingRefusal(name: "A"))
        for s in [SessionStatus.idle, .done] { XCTAssertNil(s.typingRefusal(name: "A"), s.rawValue) }
    }

    /// LAB-487: a rename made elsewhere survives the plan panel's save; only fields edited in the panel are written.
    func test_LAB487_panelSaveWritesOnlyEditedFields() {
        var s = Session(name: "asds", agent: .shell, repoPath: "/p")
        let base = SessionEdits(s)
        s.name = "Renamed"                                   // Rename… while the panel is open
        var mine = base; mine.notes = "my note"              // the panel edits notes only
        mine = mine.rebased(from: base, onto: SessionEdits(s))
        XCTAssertEqual(mine.name, "Renamed", "the untouched name field follows the rename")
        XCTAssertTrue(mine.apply(over: SessionEdits(s), to: &s))
        XCTAssertEqual(s.name, "Renamed")
        XCTAssertEqual(s.notes, "my note")
        // Even without the rebase, a stale name is never written back.
        var t = Session(name: "old", agent: .shell, repoPath: "/p")
        let stale = SessionEdits(t)
        t.name = "new"
        var edit = stale; edit.objective = "x"
        edit.apply(over: stale, to: &t)
        XCTAssertEqual(t.name, "new")
        XCTAssertFalse(stale.apply(over: stale, to: &t), "nothing edited, nothing written")
        var w = stale; w.workstream = "lab-oneroof-v0.50"
        w.apply(over: stale, to: &t)
        XCTAssertEqual(t.workstream, "LAB-ONEROOF-v0.50")
    }
}
