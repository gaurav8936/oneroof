import XCTest
@testable import OneRoofCore

/// LAB-1600: one permission mode per agent, set once in Settings, Auto by default, mapped to each CLI's real flags.
final class PermissionModeTests: XCTestCase {
    func test_LAB1600_claudeFlags() {
        XCTAssertEqual(PermissionMode.manual.args(for: .claude), ["--permission-mode", "manual"])
        XCTAssertEqual(PermissionMode.plan.args(for: .claude), ["--permission-mode", "plan"])
        XCTAssertEqual(PermissionMode.auto.args(for: .claude), ["--permission-mode", "auto"])
    }

    func test_LAB1600_codexFlags() {
        XCTAssertEqual(PermissionMode.manual.args(for: .codex), ["--ask-for-approval", "on-request"])
        XCTAssertEqual(PermissionMode.plan.args(for: .codex), ["--sandbox", "read-only", "--ask-for-approval", "on-request"])
        XCTAssertEqual(PermissionMode.auto.args(for: .codex), ["--approve-for-me"])
        XCTAssertEqual(PermissionMode.plan.label(for: .codex), "Read only")
    }

    func test_LAB1600_kimiGeminiAntigravityFlags() {
        XCTAssertEqual(PermissionMode.manual.args(for: .kimi), [])
        XCTAssertEqual(PermissionMode.plan.args(for: .kimi), ["--plan"])
        XCTAssertEqual(PermissionMode.auto.args(for: .kimi), ["--yolo"])
        XCTAssertEqual(PermissionMode.manual.args(for: .gemini), ["--approval-mode", "default"])
        XCTAssertEqual(PermissionMode.plan.args(for: .gemini), ["--approval-mode", "plan"])
        XCTAssertEqual(PermissionMode.auto.args(for: .gemini), ["--approval-mode", "yolo"])
        XCTAssertEqual(PermissionMode.manual.args(for: .agy), [])
        XCTAssertEqual(PermissionMode.plan.args(for: .agy), ["--mode", "plan"])
        XCTAssertEqual(PermissionMode.auto.args(for: .agy), ["--mode", "auto"])
        for m in PermissionMode.allCases { XCTAssertEqual(m.args(for: .shell), []) }
    }

    func test_LAB1600_subscriptionDefaultsStayAutoAndHostedDefaultsAreSupervised() {
        let s = AppSettings()
        for a in AgentKind.allCases where a.isAgent { XCTAssertEqual(s.permissionMode(for: a), a.isHosted ? .manual : .auto, a.rawValue) }
        // Settings saved before LAB-1600 (no key) decode to Auto too.
        let old = try! JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(old.permissionMode(for: .claude), .auto)
    }

    func test_LAB1600_choiceRoundTripsThroughSettings() throws {
        var s = AppSettings()
        s.permissionModes["codex"] = .manual
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.permissionMode(for: .codex), .manual)
        XCTAssertEqual(back.permissionMode(for: .claude), .auto)
    }

    func test_LAB1600_sessionLaunchesWithItsMode() {
        var s = Session(name: "x", agent: .claude, repoPath: "/tmp", model: "opus")
        s.permissionMode = .auto
        XCTAssertEqual(s.launchArgs, ["--model", "opus", "--permission-mode", "auto"])
        s.agent = .gemini
        XCTAssertEqual(s.launchArgs, ["--model", "opus", "--approval-mode", "yolo"])
    }

    func test_LAB1600_explicitArgsAreNotDoubled() {
        var s = Session(name: "x", agent: .claude, repoPath: "/tmp", agentArgs: ["--permission-mode", "plan"])
        s.permissionMode = .auto
        XCTAssertEqual(s.launchArgs, ["--permission-mode", "plan"])
        s.agentArgs = ["--permission-mode=acceptEdits"]
        XCTAssertEqual(s.launchArgs, ["--permission-mode=acceptEdits"])
        s.agentArgs = ["--dangerously-skip-permissions"]
        XCTAssertEqual(s.launchArgs, ["--dangerously-skip-permissions"])
        XCTAssertTrue(PermissionMode.hasExplicit(["-a", "never"], agent: .codex))
        XCTAssertTrue(PermissionMode.hasExplicit(["--yolo"], agent: .kimi))
        XCTAssertTrue(PermissionMode.hasExplicit(["--approval-mode=auto_edit"], agent: .gemini))
        XCTAssertTrue(PermissionMode.hasExplicit(["--mode", "accept-edits"], agent: .agy))
        XCTAssertFalse(PermissionMode.hasExplicit(["--resume", "abc"], agent: .claude))
        // Unrelated arguments stay and the mode follows them; a resume keeps the mode.
        s.agentArgs = ClaudeResume.args(["--verbose"], sessionId: "abc")
        XCTAssertEqual(s.launchArgs, ["--verbose", "--resume", "abc", "--permission-mode", "auto"])
    }

    func test_LAB1600_olderRowsLaunchUnchanged() throws {
        let json = #"{"id":"1","name":"old","agent":"claude","repoPath":"/tmp","agentArgs":["--resume","r"]}"#
        let s = try JSONDecoder().decode(Session.self, from: Data(json.utf8))
        XCTAssertNil(s.permissionMode)
        XCTAssertEqual(s.launchArgs, ["--resume", "r"])
        XCTAssertNil(PermissionBadge.label(for: s))
    }

    func test_LAB1600_sessionRoundTripsItsMode() throws {
        var s = Session(name: "x", agent: .kimi, repoPath: "/tmp")
        s.permissionMode = .plan
        let back = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.permissionMode, .plan)
        XCTAssertEqual(back.launchArgs, ["--plan"])
    }

    func test_LAB1600_badgeShowsTheModeInUse() {
        var s = Session(name: "x", agent: .codex, repoPath: "/tmp")
        s.permissionMode = .auto
        XCTAssertEqual(PermissionBadge.label(for: s), "Auto")
        s.agentArgs = ["--sandbox", "read-only", "--ask-for-approval", "on-request"]
        XCTAssertEqual(PermissionBadge.label(for: s), "Read only")
        s.agentArgs = ["-a", "never"]
        XCTAssertEqual(PermissionBadge.label(for: s), "Custom")
        var c = Session(name: "y", agent: .claude, repoPath: "/tmp", agentArgs: ["--permission-mode", "plan"])
        XCTAssertEqual(PermissionBadge.label(for: c), "Plan")
        c.agent = .shell
        XCTAssertNil(PermissionBadge.label(for: c))
    }

    func test_LAB1600_detectMatchesEachMode() {
        for a in AgentKind.allCases where a.isAgent {
            for m in PermissionMode.allCases where !m.args(for: a).isEmpty {
                XCTAssertEqual(PermissionMode.detect(m.args(for: a), agent: a), m, "\(a.rawValue) \(m.rawValue)")
                XCTAssertTrue(PermissionMode.hasExplicit(m.args(for: a), agent: a), "\(a.rawValue) \(m.rawValue)")
            }
        }
    }
}
