import XCTest
@testable import OneRoofCore

/// LAB-1485: the close-window sheet says what the window holds.
final class WindowCloseTextTests: XCTestCase {
    typealias R = WindowCloseText.Row

    func test_LAB1485_emptyWindow() {
        XCTAssertEqual(WindowCloseText.detail([]), "This window has no sessions. Reopen the window from Window \u{25B8} Workspaces.")
    }

    func test_LAB1485_onlySavedRows() {
        let t = WindowCloseText.detail([R(name: "a", kind: .saved), R(name: "b", kind: .saved)])
        XCTAssertTrue(t.hasPrefix("Nothing is running here: 2 saved sessions stay in the list."), t)
    }

    func test_LAB1485_mixIsCountedAndNamedWorkingFirst() {
        let t = WindowCloseText.detail([
            R(name: "Pitch Deck", kind: .finishedShell), R(name: "Bug Fixes", kind: .finishedShell),
            R(name: "Data", kind: .working), R(name: "old", kind: .saved),
        ])
        XCTAssertTrue(t.contains("3 sessions keep running in the background: 1 agent working, 2 finished sessions (agent ended, shell still open)."), t)
        XCTAssertTrue(t.contains("Data, Pitch Deck, Bug Fixes."), t)
        XCTAssertTrue(t.contains("1 saved session stays in the list."), t)
        XCTAssertFalse(t.contains("roofd"))
    }

    func test_LAB1485_longListIsCut() {
        let rows = (1...7).map { R(name: "s\($0)", kind: .finishedShell) }
        XCTAssertTrue(WindowCloseText.detail(rows).contains("s1, s2, s3, s4 and 3 more."))
    }

    func test_LAB1485_kinds() {
        XCTAssertEqual(WindowCloseText.kind(liveAgent: true, endedShell: false, status: .running), .working)
        XCTAssertEqual(WindowCloseText.kind(liveAgent: true, endedShell: false, status: .idle), .waiting)
        XCTAssertEqual(WindowCloseText.kind(liveAgent: false, endedShell: true, status: .exited), .finishedShell)
        XCTAssertEqual(WindowCloseText.kind(liveAgent: false, endedShell: false, status: .exited), .saved)
    }
}
