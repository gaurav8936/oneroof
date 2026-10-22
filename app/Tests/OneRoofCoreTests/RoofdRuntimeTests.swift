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

    /// Found in the visual pass: One Roof opened from a terminal inside Claude Code passed Claude's child-session
    /// markers on, and Claude in the session turned transcript saving off.
    func testInheritedAgentMarkersAreDropped() {
        for k in ["CLAUDECODE", "CLAUDE_CODE_CHILD_SESSION", "CLAUDE_CODE_SESSION_ID", "CLAUDE_CODE_MESSAGING_TOKEN", "CLAUDE_PID", "AI_AGENT"] {
            XCTAssertTrue(RoofdRuntime.inheritedAgentMarker(k), k)
        }
        XCTAssertFalse(RoofdRuntime.inheritedAgentMarker("CLAUDE_CONFIG_DIR"), "the account variable is the launch's own")
        XCTAssertFalse(RoofdRuntime.inheritedAgentMarker("PATH"))
    }

    /// LAB-255: a session opened by a self-test run carried ONEROOF_SELFTEST_* and ONEROOF_STORE; One Roof started
    /// from that session came up as a self-test on a scratch store and quit.
    func testAppTestVariablesAreDropped() {
        for k in ["ONEROOF_SELFTEST_LAUNCH", "ONEROOF_SELFTEST_QUIT", "ONEROOF_SELFTEST_OUT", "ONEROOF_STORE", "ONEROOF_BUNDLE_OUT"] {
            XCTAssertTrue(RoofdRuntime.appTestVariable(k), k)
        }
        XCTAssertFalse(RoofdRuntime.appTestVariable("ONEROOF_SESSION"), "the launch sets its own session id")
        XCTAssertFalse(RoofdRuntime.appTestVariable("ONEROOF_ROOFD"))
    }

    /// LAB-529: One Roof opened from a terminal inside a session carries that session's holder variables; a new session
    /// must not inherit them (its agents called the other session's, older, roofd).
    func testInheritedHolderVariablesAreDropped() {
        for k in RoofdRuntime.holderVariables { setenv(k, "/old/\(k)", 1) }
        defer { for k in RoofdRuntime.holderVariables { unsetenv(k) } }
        let env = runtime().environment(LaunchSpec(id: "r", label: "r", cwd: "/p", agent: .claude))
        for k in ["ONEROOF_SESSION", "ONEROOF_ROOFD", "ONEROOF_ROOFD_BIN"] { XCTAssertNil(env[k], k) }
    }

    func testSessionsGetACertificateBundleUnlessOneIsSet() throws {
        var env: [String: String] = [:]
        RoofdRuntime.addCertificateDefault(&env, bundle: "/etc/hosts")
        XCTAssertEqual(env["SSL_CERT_FILE"], "/etc/hosts")
        var mine = ["SSL_CERT_FILE": "/my/certs.pem"]
        RoofdRuntime.addCertificateDefault(&mine, bundle: "/etc/hosts")
        XCTAssertEqual(mine["SSL_CERT_FILE"], "/my/certs.pem", "the owner's own setting wins")
        var none: [String: String] = [:]
        RoofdRuntime.addCertificateDefault(&none, bundle: "/nonexistent.pem")
        XCTAssertNil(none["SSL_CERT_FILE"])
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

    func testListEntryCarriesWhenTheSessionWasLastActive() {
        // LAB-258: roofd's holders outlive the app, so the age shown after a restart comes from them.
        let at = Date(timeIntervalSince1970: 1_800_000_000)
        let agent = RoofdRuntime.sessionState(["id": "a", "agent": "claude", "status": "idle", "active": at.timeIntervalSince1970])
        XCTAssertEqual(agent?.activeAt, at)
        XCTAssertEqual(RoofdRuntime.sessionState(["id": "s", "active": at.timeIntervalSince1970])?.activeAt, at)
        XCTAssertNil(RoofdRuntime.sessionState(["id": "old"])?.activeAt, "an older holder does not say")
        XCTAssertNil(RoofdRuntime.sessionState(["id": "x", "exited": 1.0]))
    }
}
