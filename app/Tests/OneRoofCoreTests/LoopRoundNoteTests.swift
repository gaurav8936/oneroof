import XCTest
@testable import OneRoofCore

/// LAB-1940 · a loop round's session notifies only when it needs you or a command failed (owner, 10-31).
final class LoopRoundNoteTests: XCTestCase {
    func ev(_ k: NoteKind, exit: Int? = nil) -> NoteEvent { NoteEvent(kind: k, sessionId: "s", sessionName: "loop", exitCode: exit) }

    func test_needsYou_andFailures_notify() {
        XCTAssertTrue(NoteSignals.allowedForLoopRound(ev(.needsYou)))
        XCTAssertTrue(NoteSignals.allowedForLoopRound(ev(.longCommand, exit: 1)))
    }

    func test_successAndRoutine_stayQuiet() {
        XCTAssertFalse(NoteSignals.allowedForLoopRound(ev(.done)))
        XCTAssertFalse(NoteSignals.allowedForLoopRound(ev(.longCommand, exit: 0)))
        XCTAssertFalse(NoteSignals.allowedForLoopRound(ev(.longCommand)))
        XCTAssertFalse(NoteSignals.allowedForLoopRound(ev(.terminal)))
    }

    func test_loopRoundsAreTaggedSessions() {
        XCTAssertTrue(SessionScope.isLoop(Session(name: "r", agent: .claude, repoPath: "/tmp", tags: ["loop:nightly"])))
        XCTAssertFalse(SessionScope.isLoop(Session(name: "m", agent: .claude, repoPath: "/tmp")))
    }
}
