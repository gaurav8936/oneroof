import XCTest
@testable import OneRoofCore

/// LAB-1362: after Claude exits in a One Roof terminal, Resume continues that conversation in the same terminal.
final class ClaudeResumeTests: XCTestCase {
    let id = "3f2a9c1e-7b4d-4e8a-9c0f-1a2b3c4d5e6f"

    func test_LAB1362_sessionIdFromClaudesExitLine() {
        let screen = """
        > /exit
        Total cost: $1.20
        Resume this session with:
        claude --resume \(id)
        user@mac ~/Projects %
        """
        XCTAssertEqual(ClaudeResume.sessionId(fromScreen: screen), id)
        XCTAssertNil(ClaudeResume.sessionId(fromScreen: "no hint here"))
        // Two exits in the same terminal: the last one is the conversation that just ended.
        let other = "11111111-2222-3333-4444-555555555555"
        XCTAssertEqual(ClaudeResume.sessionId(fromScreen: "claude --resume \(other)\n…\nclaude --resume \(id)\n"), id)
    }

    func test_LAB1362_sessionIdFromTranscriptPath() {
        XCTAssertEqual(ClaudeResume.sessionId(transcriptPath: "/u/.claude/projects/-Users-x-Projects/\(id).jsonl"), id)
        XCTAssertNil(ClaudeResume.sessionId(transcriptPath: "/u/.claude/projects/x/notes.txt"))
    }

    func test_LAB1362_commandKeepsModelAndDropsOldResume() {
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["--model", "opus"], sessionId: id),
                       "claude --model opus --resume \(id)")
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["--resume", "old-id", "--model", "sonnet", "-c"], sessionId: id),
                       "claude --model sonnet --resume \(id)")
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["-r", "old", "--session-id", "x", "--continue"], sessionId: id),
                       "claude --resume \(id)")
        XCTAssertEqual(ClaudeResume.command(launchArgs: ["--append-system-prompt", "be brief"], sessionId: id),
                       "claude --append-system-prompt 'be brief' --resume \(id)")
        // A new launch (terminal gone) gets the arguments themselves: a value with a space stays one argument.
        XCTAssertEqual(ClaudeResume.args(["--resume", "old", "--append-system-prompt", "be brief"], sessionId: id),
                       ["--append-system-prompt", "be brief", "--resume", id])
    }
}
