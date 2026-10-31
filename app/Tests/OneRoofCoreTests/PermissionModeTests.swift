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
        for a in AgentKind.allCases where a.isAgent {
            XCTAssertEqual(s.permissionMode(for: a), a.isHosted ? .manual : (a == .agy ? .full : .auto), a.rawValue)   // LAB-1935
        }
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
                // LAB-1935: Gemini's Full is its Auto flag (yolo), so it reads as Auto.
                let expected: PermissionMode = (a == .gemini && m == .full) ? .auto : m
                XCTAssertEqual(PermissionMode.detect(m.args(for: a), agent: a), expected, "\(a.rawValue) \(m.rawValue)")
                XCTAssertTrue(PermissionMode.hasExplicit(m.args(for: a), agent: a), "\(a.rawValue) \(m.rawValue)")
            }
        }
    }

    // LAB-1935 (owner 10-31): Full = each CLI's real never-ask flag (checked against --help 10-31).
    func test_LAB1935_fullFlagsPerAgent() {
        XCTAssertEqual(PermissionMode.full.args(for: .claude), ["--dangerously-skip-permissions"])
        XCTAssertEqual(PermissionMode.full.args(for: .codex), ["--dangerously-bypass-approvals-and-sandbox"])
        XCTAssertEqual(PermissionMode.full.args(for: .kimi), ["--auto"])
        XCTAssertEqual(PermissionMode.full.args(for: .gemini), ["--approval-mode", "yolo"])
        XCTAssertEqual(PermissionMode.full.args(for: .agy), ["--dangerously-skip-permissions"])
        XCTAssertEqual(PermissionMode.full.args(for: .opencode), [])
        XCTAssertEqual(PermissionMode.full.label, "Full")
        // Every Full flag is one the app recognises as setting a mode, so a session's own copy is never doubled.
        for a in AgentKind.allCases where a.isAgent && !a.isHosted {
            XCTAssertTrue(PermissionMode.hasExplicit(PermissionMode.full.args(for: a), agent: a), a.rawValue)
        }
        XCTAssertEqual(PermissionMode.detect(["--dangerously-skip-permissions"], agent: .agy), .full)
        XCTAssertEqual(PermissionMode.detect(["--auto"], agent: .kimi), .full)
        XCTAssertEqual(PermissionMode.detect(["--approval-mode", "yolo"], agent: .gemini), .auto)
    }

    func test_LAB1935_antigravityStartsInFullAndLaunchesWithoutPrompts() {
        let s = AppSettings()
        XCTAssertEqual(s.permissionMode(for: .agy), .full)
        var row = Session(name: "x", agent: .agy, repoPath: "/tmp")
        row.permissionMode = s.permissionMode(for: .agy)
        XCTAssertEqual(row.launchArgs, ["--dangerously-skip-permissions"])
    }

    func test_LAB1935_savedAutoForAntigravityMovesToFullOnceThenStaysTheOwnersChoice() throws {
        let old = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"permissionModes":{"agy":"auto","claude":"manual"}}"#.utf8))
        XCTAssertEqual(old.permissionMode(for: .agy), .full)
        XCTAssertEqual(old.permissionMode(for: .claude), .manual)
        var s = old
        s.permissionModes["agy"] = .auto                      // the owner switches it back
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.permissionMode(for: .agy), .auto)  // and it stays
        let plan = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"permissionModes":{"agy":"plan"}}"#.utf8))
        XCTAssertEqual(plan.permissionMode(for: .agy), .plan)  // a deliberate non-Auto choice is kept
    }

    func test_LAB1935_ownersFlagsReplaceTheModesFlagsAndRoundTrip() throws {
        var s = AppSettings()
        XCTAssertNil(s.permissionFlags(for: .agy, mode: .full))
        s.permissionFlags["agy.full"] = "--dangerously-skip-permissions --mode accept-edits"
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.permissionFlags(for: .agy, mode: .full), ["--dangerously-skip-permissions", "--mode", "accept-edits"])
        XCTAssertEqual(back.effectiveFlags(for: .agy, mode: .auto), ["--mode", "auto"])
        var row = Session(name: "x", agent: .agy, repoPath: "/tmp")
        row.permissionMode = .full
        row.permissionFlags = back.permissionFlags(for: .agy, mode: .full)
        XCTAssertEqual(row.launchArgs, ["--dangerously-skip-permissions", "--mode", "accept-edits"])
        let saved = try JSONDecoder().decode(Session.self, from: JSONEncoder().encode(row))
        XCTAssertEqual(saved.launchArgs, row.launchArgs)
        s.permissionFlags["agy.full"] = "   "
        XCTAssertNil(s.permissionFlags(for: .agy, mode: .full))   // blank = standard flags
    }
}
