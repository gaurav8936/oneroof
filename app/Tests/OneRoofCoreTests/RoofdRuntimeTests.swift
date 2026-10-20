import XCTest
@testable import OneRoofCore

/// RoofdRuntime pieces that need no daemon: how a session is started and what it starts with.
final class RoofdRuntimeTests: XCTestCase {
    func runtime(resources: URL? = nil) -> RoofdRuntime { RoofdRuntime(roofdPath: "/x/roofd", dir: "/tmp/rd", resources: resources) }

    /// Q2: through the login shell, a shell left behind when the agent exits.
    func testAgentStartsThroughTheLoginShell() {
        let r = runtime()
        let spec = LaunchSpec(id: "roof-1", label: "x", cwd: "/p", agent: .claude, args: ["--model", "opus 5", "--resume"])
        XCTAssertEqual(r.argv(spec), ["/bin/zsh", "-l", "-i", "-c", "claude --model 'opus 5' --resume; exec /bin/zsh -l -i"])
        XCTAssertEqual(r.argv(LaunchSpec(id: "t", label: "t", cwd: "/p", agent: .shell)), ["/bin/zsh", "-l", "-i"])
    }

    func testShellQuote() {
        XCTAssertEqual(RoofdRuntime.shellQuote("plain-arg_1.2"), "plain-arg_1.2")
        XCTAssertEqual(RoofdRuntime.shellQuote("it's"), "'it'\\''s'")
        XCTAssertEqual(RoofdRuntime.shellQuote(""), "''")
        XCTAssertEqual(RoofdRuntime.shellQuote("a b;rm -rf"), "'a b;rm -rf'")
    }

    func testEnvironmentDropsAccountsAndAddsTheLaunchsOwn() {
        let env = runtime().environment(LaunchSpec(id: "r", label: "r", cwd: "/p", env: ["CLAUDE_CONFIG_DIR": "/c2"], agent: .claude))
        XCTAssertEqual(env["CLAUDE_CONFIG_DIR"], "/c2", "the launch's account wins")
        XCTAssertNil(env["CODEX_HOME"])
        XCTAssertEqual(env["TERM"], "xterm-256color", "no bundled terminfo here")
        XCTAssertNil(env["ZDOTDIR"].flatMap { $0.contains("shell-integration") ? $0 : nil })
    }

    func testGhosttyResourcesTurnOnTerminfoAndShellIntegration() throws {
        let res = FileManager.default.temporaryDirectory.appendingPathComponent("roofd-res-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: res.appendingPathComponent("ghostty/shell-integration/zsh"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: res.appendingPathComponent("terminfo"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: res) }
        let env = runtime(resources: res).environment(LaunchSpec(id: "r", label: "r", cwd: "/p", agent: .shell))
        XCTAssertEqual(env["TERM"], "xterm-ghostty")
        XCTAssertEqual(env["TERMINFO"], res.appendingPathComponent("terminfo").path)
        XCTAssertEqual(env["ZDOTDIR"], res.appendingPathComponent("ghostty").path + "/shell-integration/zsh")
    }

    func testOSC7PathAndAttachCommand() {
        XCTAssertEqual(RoofdRuntime.pathFromOSC7("file://host/Users/x/Projects"), "/Users/x/Projects")
        XCTAssertEqual(RoofdRuntime.pathFromOSC7("/abs"), "/abs")
        XCTAssertNil(RoofdRuntime.pathFromOSC7(""))
        XCTAssertEqual(runtime().attachCommand("roof-1"), "env ROOFD_DIR=/tmp/rd /x/roofd attach roof-1")
    }

    func testNotRunningIsAFailNotAHang() {
        let r = RoofdRuntime(roofdPath: "/nonexistent/roofd", dir: "/tmp/roofd-none-\(UUID().uuidString.prefix(6))")
        XCTAssertEqual(r.health().level, .fail)
        XCTAssertThrowsError(try r.snapshot())
    }
}
