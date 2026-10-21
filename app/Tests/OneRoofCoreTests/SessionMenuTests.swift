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
        XCTAssertEqual(live, [.open, .next, .pin, .rename, .highlight, .doNotUse])
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
}
