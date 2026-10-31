import XCTest
@testable import OneRoofCore

final class HostedPromptTests: XCTestCase {
    let goose = """
      ▸ shell
        command: pwd
    ◆ Goose would like to call the above tool, do you allow?
    │  ● Allow (Allow the tool call once)
    │  ○ Always Allow
    │  ○ Deny
    │  ○ Cancel
    └
    """
    let opencode = """
    ┃  △ Permission required
    ┃    # Shell command
    ┃
    ┃  $ pwd
    ┃
    ┃   Allow once   Allow always   Reject     ctrl+f fullscreen  ⇆ select  enter confirm
    """

    func testPinnedGooseSelectionProducesRelativeNativeKeysAndBlockedStatus() throws {
        let prompt = try XCTUnwrap(DecisionMatcher.match(goose, agent: .goose))
        XCTAssertEqual(prompt.command, "pwd")
        XCTAssertEqual(AnswerKeys.keys(for: .deny, prompt: prompt, agent: .goose).sends, ["\u{1b}[B\u{1b}[B\r"])
        XCTAssertEqual(AnswerKeys.keys(for: .allowOnce, prompt: prompt, agent: .goose).sends, ["\r"])
        assertBlocked(goose, agent: .goose)
    }

    func testOpenCodeDenyIsDeterministicButInvisibleApprovalSelectionStaysManual() throws {
        let prompt = try XCTUnwrap(DecisionMatcher.match(opencode, agent: .opencode))
        XCTAssertEqual(prompt.command, "pwd")
        XCTAssertEqual(AnswerKeys.keys(for: .deny, prompt: prompt, agent: .opencode).sends, [AnswerKeys.escape])
        XCTAssertTrue(AnswerKeys.keys(for: .allowOnce, prompt: prompt, agent: .opencode).sends.isEmpty)
        XCTAssertTrue(AnswerKeys.keys(for: .always, prompt: prompt, agent: .opencode).sends.isEmpty)
        assertBlocked(opencode, agent: .opencode)
    }

    func testTallEditDiffStillBlocksAndGooseUsesTheActualRequest() throws {
        let tall = opencode.replacingOccurrences(of: "$ pwd", with: Array(repeating: "2 - return a-b\n2 + return a+b", count: 8).joined(separator: "\n"))
        assertBlocked(tall, agent: .opencode)
        let request = "command: wrong-preview\ncommand: another-preview\nTool approval request\n{\"tool_name\":\"shell\",\"arguments\":{\"command\":\"pwd\"}}\n◆" + goose.components(separatedBy: "◆").last!
        XCTAssertEqual(DecisionMatcher.match(request, agent: .goose)?.command, "pwd")
    }

    func testUnknownHostedPromptsNeverBorrowAnotherAgentsApprovalKeys() {
        XCTAssertNil(DecisionMatcher.match("Do you want to proceed?\n❯ 1. Yes\n2. No", agent: .goose))
        XCTAssertNil(DecisionMatcher.match(goose.replacingOccurrences(of: "Always Allow", with: "Changed option"), agent: .goose))
        XCTAssertTrue(AnswerKeys.keys(for: .deny, prompt: nil, agent: .opencode).sends.isEmpty)
    }

    private func assertBlocked(_ text: String, agent: AgentKind, file: StaticString = #filePath, line: UInt = #line) {
        var engine = StatusEngine(); let now = Date()
        _ = engine.evaluate(.init(now: now, agent: agent, lastOutput: now, screen: text))
        XCTAssertEqual(engine.evaluate(.init(now: now.addingTimeInterval(5), agent: agent, lastOutput: now, screen: text)), .blocked, file: file, line: line)
    }
}
