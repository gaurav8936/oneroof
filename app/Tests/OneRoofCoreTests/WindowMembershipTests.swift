import XCTest
@testable import OneRoofCore

/// LAB-705..708: which window lists a session, moving one, and which windows come back after a quit.
final class WindowMembershipTests: XCTestCase {
    let w1 = "W1", w2 = "W2", w3 = "W3"

    // LAB-705: a session made in window 3 is listed in window 3 only.
    func testSessionIsListedOnlyInItsOwnWindow() {
        let assigned = ["s2": w2, "s3": w3]
        let open = [w1, w2, w3], all: Set = [w1, w2, w3]
        XCTAssertEqual(WindowMembership.sessions(in: w2, ["s2", "s3"], assigned: assigned, open: open, existing: all), ["s2"])
        XCTAssertEqual(WindowMembership.sessions(in: w3, ["s2", "s3"], assigned: assigned, open: open, existing: all), ["s3"])
        XCTAssertEqual(WindowMembership.sessions(in: w1, ["s2", "s3"], assigned: assigned, open: open, existing: all), [])
    }

    // LAB-705: a closed window's sessions wait for it; they never spill into the first open window.
    func testClosedWindowsSessionsDoNotShowInAnotherWindow() {
        let assigned = ["s3": w3]
        let open = [w2], all: Set = [w1, w2, w3]
        XCTAssertEqual(WindowMembership.home(of: "s3", assigned: assigned, open: open, existing: all), w3)
        XCTAssertEqual(WindowMembership.sessions(in: w2, ["s3"], assigned: assigned, open: open, existing: all), [])
    }

    // Only a session with no window (started outside One Roof, or its workspace deleted) is the first open window's.
    func testSessionWithoutAWindowGoesToTheFirstOpenWindow() {
        let all: Set = [w1, w2]
        XCTAssertEqual(WindowMembership.home(of: "herdr:x", assigned: [:], open: [w2, w1], existing: all), w2)
        XCTAssertEqual(WindowMembership.home(of: "s", assigned: ["s": "gone"], open: [w1, w2], existing: all), w1)
        XCTAssertNil(WindowMembership.home(of: "s", assigned: [:], open: [], existing: all))
    }

    // LAB-707: after a move the session is listed in the new window and not the old one.
    func testMoveChangesTheListingWindow() {
        var assigned = ["s": w1]
        let open = [w1, w2], all: Set = [w1, w2]
        assigned["s"] = w2
        XCTAssertEqual(WindowMembership.sessions(in: w2, ["s"], assigned: assigned, open: open, existing: all), ["s"])
        XCTAssertEqual(WindowMembership.sessions(in: w1, ["s"], assigned: assigned, open: open, existing: all), [])
    }

    // LAB-706: AppKit closes every window while the app quits; none of those closes is remembered, so all come back.
    func testQuittingKeepsEveryWindowForTheNextLaunch() {
        var open: [String: Bool] = [w1: true, w2: true, w3: true]
        var remaining = 3
        for id in [w1, w2, w3] {
            remaining -= 1
            if WindowMembership.remembersClosed(quitting: true, otherOpenWindows: remaining) { open[id] = false }
        }
        XCTAssertEqual(WindowMembership.toRestore([w1, w2, w3].map { ($0, open[$0]!) }), [w1, w2, w3])
    }

    func testClosingAWindowYourselfIsRemembered() {
        XCTAssertTrue(WindowMembership.remembersClosed(quitting: false, otherOpenWindows: 2))
        XCTAssertFalse(WindowMembership.remembersClosed(quitting: false, otherOpenWindows: 0), "the last window comes back")
        XCTAssertEqual(WindowMembership.toRestore([(w1, true), (w2, false), (w3, true)]), [w1, w3])
        XCTAssertEqual(WindowMembership.toRestore([(w1, false), (w2, false)]), [w1], "never zero windows")
    }

    // Window list, names, colours and session assignments survive a relaunch (the store is reopened).
    func testWorkspacesAndAssignmentsSurviveReopeningTheStore() throws {
        let path = NSTemporaryDirectory() + "wm-\(UUID().uuidString).sqlite"
        defer { try? FileManager.default.removeItem(atPath: path) }
        let a = RoofWorkspace(name: "Infra Costs", colour: "blue", order: 1, layout: #"{"open":true}"#)
        let b = RoofWorkspace(name: "Blogs", colour: nil, order: 2, layout: #"{"open":true}"#)
        do {
            let s = try SessionStore(path: path)
            s.save(a); s.save(b)
            s.move(session: "s2", to: a.id)
            s.move(session: "s3", to: b.id)
        }
        let s = try SessionStore(path: path)
        let names = s.allWorkspaces().map(\.name)
        XCTAssertTrue(names.contains("Infra Costs") && names.contains("Blogs"))
        XCTAssertEqual(s.allWorkspaces().first { $0.id == a.id }?.colour, "blue")
        XCTAssertEqual(s.sessionWorkspaces()["s2"], a.id)
        XCTAssertEqual(s.sessionWorkspaces()["s3"], b.id)
    }

    // LAB-708: a pop-out's attach refused at once is retried, then reported; one that ran a while just closes.
    func testPopOutRetriesARefusedAttach() {
        XCTAssertEqual(PopOutAttach.next(attempt: 1, ranFor: 0.2, max: 4), .retry)
        XCTAssertEqual(PopOutAttach.next(attempt: 3, ranFor: 0.2, max: 4), .retry)
        XCTAssertEqual(PopOutAttach.next(attempt: 4, ranFor: 0.2, max: 4), .giveUp)
        XCTAssertEqual(PopOutAttach.next(attempt: 1, ranFor: 60, max: 4), .ended)
    }
}
