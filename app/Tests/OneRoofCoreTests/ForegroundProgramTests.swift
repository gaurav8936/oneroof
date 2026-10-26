import XCTest
@testable import OneRoofCore

final class ForegroundProgramTests: XCTestCase {
    typealias P = RuntimeProcesses.Proc

    func testShellAtItsPromptShowsNothing() {
        XCTAssertNil(ForegroundProgram.label(.init(shellPid: 10, foreground: [P(pid: 10, name: "zsh", argv: ["-zsh"])]), agentShown: false))
        // shell pid unknown, but the group is only a shell
        XCTAssertNil(ForegroundProgram.label(.init(shellPid: nil, foreground: [P(pid: 10, name: "bash", argv: ["/bin/bash"])]), agentShown: false))
        XCTAssertNil(ForegroundProgram.label(.init(shellPid: 10, foreground: []), agentShown: false))
    }

    func testAProgramInTheForegroundIsNamedByItsLeader() {
        let p = RuntimeProcesses(shellPid: 10, foreground: [P(pid: 22, name: "node", argv: ["/usr/local/bin/node", "server.js"]),
                                                          P(pid: 21, name: "npm", argv: ["/opt/homebrew/bin/npm", "run", "dev"])])
        XCTAssertEqual(ForegroundProgram.label(p, agentShown: false), "npm run dev")
        XCTAssertEqual(ForegroundProgram.label(.init(shellPid: 10, foreground: [P(pid: 30, name: "python3.12", argv: ["python3", "-m", "http.server", "8000"])]), agentShown: true),
                       "python3 -m http.server 8000")
    }

    func testTheSessionsOwnAgentIsNotFlagged() {
        let claude = RuntimeProcesses(shellPid: 10, foreground: [P(pid: 40, name: "claude", argv: ["claude", "--model", "opus"])])
        XCTAssertNil(ForegroundProgram.label(claude, agentShown: true))
        let gemini = RuntimeProcesses(shellPid: 10, foreground: [P(pid: 41, name: "node", argv: ["node", "/opt/homebrew/bin/gemini"])])
        XCTAssertNil(ForegroundProgram.label(gemini, agentShown: true))
        // in a plain terminal that does not show an agent, a running agent is still a program the keys go to
        XCTAssertEqual(ForegroundProgram.label(claude, agentShown: false), "claude --model opus")
    }

    func testLongCommandsAreShortened() {
        let p = P(pid: 1, name: "node", argv: ["/a/b/node", String(repeating: "x", count: 100)])
        let s = ForegroundProgram.command(p, max: 20)
        XCTAssertEqual(s.count, 20)
        XCTAssertTrue(s.hasPrefix("node xxx"))
        XCTAssertTrue(s.hasSuffix("…"))
    }
}
