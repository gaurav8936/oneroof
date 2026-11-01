import XCTest
@testable import OneRoofCore

/// LAB-1999 · as many accounts per agent as the owner needs (Codex 1, 2 · Gemini 1, 2, 3 …), not only Claude1 / Claude2.
/// Every test uses a temp home; nothing is created in the real one.
final class AgentAccountsTests: XCTestCase {
    var home = ""

    override func setUpWithError() throws {
        home = NSTemporaryDirectory() + "lab1999-" + UUID().uuidString
        try FileManager.default.createDirectory(atPath: home, withIntermediateDirectories: true)
        AgentAccounts.use(stored: [], removed: [])
    }

    override func tearDownWithError() throws {
        AgentAccounts.use(stored: [], removed: [])
        try? FileManager.default.removeItem(atPath: home)
    }

    private func mkdir(_ rel: String) throws {
        try FileManager.default.createDirectory(atPath: home + "/" + rel, withIntermediateDirectories: true)
    }

    // MARK: Model

    func test_model_derived_firstAccountOfEveryAgent_andClaude2OnlyWhenItsFolderExists() throws {
        XCTAssertEqual(AgentAccounts.derived(home: home).map(\.id),
                       ["Claude1", "Codex1", "Gemini1", "Kimi1", "Antigravity1", "OpenCode1", "Goose1"])
        try mkdir(".claude-2")
        XCTAssertEqual(AgentAccounts.derived(home: home).filter { $0.agent == .claude }.map(\.id), ["Claude1", "Claude2"])
    }

    func test_model_folders_perAgent() {
        XCTAssertEqual(AgentAccounts.folder(.claude, 1, home: home), home + "/.claude")
        XCTAssertEqual(AgentAccounts.folder(.claude, 3, home: home), home + "/.claude-3")
        XCTAssertEqual(AgentAccounts.folder(.codex, 1, home: home), home + "/.codex")
        XCTAssertEqual(AgentAccounts.folder(.codex, 2, home: home), home + "/.codex-2")
        XCTAssertEqual(AgentAccounts.folder(.gemini, 1, home: home), home)
        XCTAssertEqual(AgentAccounts.folder(.gemini, 3, home: home), home + "/.gemini-home-3")
        XCTAssertEqual(AgentAccounts.folder(.kimi, 1, home: home), home + "/.kimi-code")
        XCTAssertEqual(AgentAccounts.folder(.kimi, 2, home: home), home + "/.kimi-code-2")
    }

    func test_model_nextNumber_isTheLowestFree_andOneAccountAgentsHaveNone() {
        var list = AgentAccounts.derived(home: home)
        XCTAssertEqual(AgentAccounts.next(.codex, in: list)?.id, "Codex2")
        list.append(AgentAccount(agent: .gemini, number: 3))
        XCTAssertEqual(AgentAccounts.next(.gemini, in: list)?.id, "Gemini2")
        for k in [AgentKind.agy, .opencode, .goose] {
            XCTAssertNil(AgentAccounts.next(k, in: list))
            XCTAssertFalse(AgentAccounts.canAdd(k))
            XCTAssertNotNil(AgentAccounts.oneAccountReason(k), "the disabled button says why")
        }
        XCTAssertTrue(AgentAccounts.oneAccountReason(.opencode)!.contains("OPENCODE_CONFIG_DIR"))
    }

    func test_model_accountNumber_fromSessionAccountField() {
        XCTAssertEqual(AgentAccounts.number(nil, agent: .codex), 1)
        XCTAssertEqual(AgentAccounts.number("Codex", agent: .codex), 1)
        XCTAssertEqual(AgentAccounts.number("Codex2", agent: .codex), 2)
        XCTAssertEqual(AgentAccounts.number("Gemini3", agent: .gemini), 3)
        XCTAssertEqual(AgentAccounts.number("Claude2", agent: .claude), 2)
        XCTAssertEqual(AgentAccounts.number("Antigravity2", agent: .agy), 1, "one account only")
    }

    // MARK: Migration

    func test_migration_oldSettingsDecodeUnchanged_andClaude2StaysClaude2() throws {
        try mkdir(".claude-2")
        var old = AppSettings()
        old.agents["claude"] = AgentDefaults(account: "Claude2")
        old.dockHidden = ["claude2"]
        var j = try JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as! [String: Any]
        j.removeValue(forKey: "accounts"); j.removeValue(forKey: "removedAccounts")   // as 1.9.34 saved it
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONSerialization.data(withJSONObject: j))
        XCTAssertEqual(back.accounts, [])
        XCTAssertEqual(back.removedAccounts, [])
        XCTAssertEqual(back.defaults(for: .claude).account, "Claude2")
        XCTAssertEqual(back.dockHidden, ["claude2"])
        XCTAssertEqual(back.agentAccounts(home: home).filter { $0.agent == .claude }.map(\.id), ["Claude1", "Claude2"])
        XCTAssertEqual(AccountResolver.claudeAccounts(home: home), ["Claude1", "Claude2"])
        XCTAssertEqual(AccountResolver.launchEnv(agent: .claude, account: "Claude2", home: home), ["CLAUDE_CONFIG_DIR": home + "/.claude-2"])
    }

    func test_migration_addedAccountsRoundTrip() throws {
        var s = AppSettings()
        s.addAccount(.codex, home: home)
        s.renameAccount("Codex2", to: "Work Codex", home: home)
        let back = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(s))
        XCTAssertEqual(back.agentAccounts(home: home).first { $0.id == "Codex2" }?.label, "Work Codex")
    }

    // MARK: Launch env per agent

    func test_launchEnv_firstAccountsSetNothing_neverAnEmptyClaudeConfigDir() {
        for (k, a) in [(AgentKind.claude, "Claude1"), (.claude, nil), (.claude, ""), (.codex, "Codex"), (.codex, "Codex1"), (.codex, nil),
                       (.gemini, "Gemini1"), (.kimi, nil), (.agy, nil), (.opencode, nil), (.goose, nil)] as [(AgentKind, String?)] {
            XCTAssertEqual(AccountResolver.launchEnv(agent: k, account: a, home: home), [:], "\(k) \(a ?? "nil")")
        }
        for n in 2...5 {
            let v = AccountResolver.launchEnv(agent: .claude, account: "Claude\(n)", home: home)["CLAUDE_CONFIG_DIR"]
            XCTAssertEqual(v, home + "/.claude-\(n)")
            XCTAssertFalse(v?.isEmpty ?? true)
        }
    }

    func test_launchEnv_addedAccounts_perAgent_andLabelRoundTrip() {
        let cases: [(AgentKind, String, String, String)] = [
            (.claude, "Claude3", "CLAUDE_CONFIG_DIR", "/.claude-3"),
            (.codex, "Codex2", "CODEX_HOME", "/.codex-2"),
            (.gemini, "Gemini2", "GEMINI_CLI_HOME", "/.gemini-home-2"),
            (.gemini, "Gemini3", "GEMINI_CLI_HOME", "/.gemini-home-3"),
            (.kimi, "Kimi2", "KIMI_CODE_HOME", "/.kimi-code-2"),
        ]
        for (k, id, v, f) in cases {
            let env = AccountResolver.launchEnv(agent: k, account: id, home: home)
            XCTAssertEqual(env, [v: home + f], id)
            XCTAssertEqual(AccountResolver.label(agent: k, env: env, home: home), id, "a running \(id) session is recognised")
        }
        XCTAssertEqual(AccountResolver.launchEnv(agent: .agy, account: "Antigravity2", home: home), [:])
    }

    func test_launchPlan_usesTheAccountsFolder() throws {
        let root = Workspace.projectsRoot
        let s = Session(name: "x", agent: .codex, account: "Codex2", repoPath: root)
        guard case .success(let spec) = LaunchPlan.spec(s, stored: []) else { return XCTFail("refused") }
        XCTAssertEqual(spec.env["CODEX_HOME"], NSHomeDirectory() + "/.codex-2")
    }

    // MARK: accountVariables

    func test_accountVariables_stripTheNamesTheCLIsRead() {
        for k in ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "GEMINI_CLI_HOME", "KIMI_CODE_HOME", "GEMINI_HOME", "KIMI_HOME"] {
            XCTAssertTrue(AccountResolver.accountVariables.contains(k), k)
        }
    }

    // MARK: Badges / seats

    func test_seatMark_monogramsAndRawValues() {
        XCTAssertEqual([SeatMark.claude1, .claude2, .codex, .gemini, .kimi].map(\.mono), ["C1", "C2", "CX", "GM", "KM"])
        XCTAssertEqual(SeatMark(agent: .codex, number: 2).mono, "X2")
        XCTAssertEqual(SeatMark(agent: .gemini, number: 3).mono, "G3")
        XCTAssertEqual(SeatMark(agent: .kimi, number: 2).mono, "K2")
        XCTAssertEqual(SeatMark(agent: .claude, number: 3).mono, "C3")
        XCTAssertEqual(SeatMark(agent: .codex, number: 2).fill, AgentMark.codex.fill, "the agent's colour")
        XCTAssertEqual(SeatMark.claude2.rawValue, "claude2")
        XCTAssertEqual(SeatMark(agent: .codex, number: 2).rawValue, "codex2")
        for m in [SeatMark.claude1, .claude2, .codex, SeatMark(agent: .gemini, number: 3), SeatMark(agent: .claude, number: 4)] {
            XCTAssertEqual(SeatMark(rawValue: m.rawValue), m)
        }
        XCTAssertEqual(SeatMark(agent: .codex, account: "Codex2"), SeatMark(agent: .codex, number: 2))
        XCTAssertEqual(SeatMark(agent: .claude, account: "Claude2"), .claude2)
    }

    // MARK: DockSeats with added accounts

    func test_dockSeats_addedAccountsFollowTheirAgent() {
        let accounts = AgentAccounts.derived(home: home) + [AgentAccount(agent: .codex, number: 2), AgentAccount(agent: .gemini, number: 2),
                                                            AgentAccount(agent: .claude, number: 3)]
        let f = DockSeats.Facts(claudeAccounts: ["Claude1", "Claude2", "Claude3"], installed: [.claude, .codex, .gemini, .kimi],
                                hostedReady: [], accounts: accounts)
        XCTAssertEqual(DockSeats.shown(f, hidden: []).map(\.mono), ["C1", "C2", "C3", "CX", "X2", "GM", "G2", "KM"])
        XCTAssertEqual(DockSeats.shown(f, hidden: ["codex2"]).map(\.mono), ["C1", "C2", "C3", "CX", "GM", "G2", "KM"])
        XCTAssertEqual(DockSeats.usageName(SeatMark(agent: .codex, number: 2)), "Codex2")
        XCTAssertEqual(DockSeats.usageName(.codex), "Codex")
    }

    func test_dockSeats_addedAccountOfAnAgentNotInstalled_staysOut() {
        let f = DockSeats.Facts(claudeAccounts: ["Claude1"], installed: [.claude], hostedReady: [],
                                accounts: [AgentAccount(agent: .codex, number: 2)])
        XCTAssertEqual(DockSeats.shown(f, hidden: []).map(\.mono), ["C1"])
        XCTAssertEqual(DockSeats.shown(f, hidden: [], usageSeats: ["Codex2"]).map(\.mono), ["C1", "X2"], "usage means set up")
    }

    func test_dockSeats_factsCarryTheSettingsAccounts() {
        var s = AppSettings()
        s.addAccount(.kimi, home: home)
        XCTAssertTrue(DockSeats.facts(settings: s, home: home).accounts.contains { $0.id == "Kimi2" })
    }

    // MARK: Settings logic

    func test_settings_add_rename_remove() throws {
        var s = AppSettings()
        XCTAssertEqual(s.addAccount(.codex, home: home)?.id, "Codex2")
        XCTAssertEqual(s.addAccount(.gemini, home: home)?.id, "Gemini2")
        XCTAssertEqual(s.addAccount(.gemini, home: home)?.id, "Gemini3")
        XCTAssertNil(s.addAccount(.goose, home: home))
        XCTAssertEqual(s.agentAccounts(home: home).filter { $0.agent == .gemini }.map(\.id), ["Gemini1", "Gemini2", "Gemini3"])
        s.renameAccount("Gemini2", to: "  Lab Gemini ", home: home)
        XCTAssertEqual(s.agentAccounts(home: home).first { $0.id == "Gemini2" }?.label, "Lab Gemini")
        s.renameAccount("Gemini2", to: "", home: home)
        XCTAssertEqual(s.agentAccounts(home: home).first { $0.id == "Gemini2" }?.label, "Gemini2", "empty puts the default back")
        // Remove: defaults and the bottom bar that pointed at it go back; the first account can't be removed.
        s.agents["codex"] = AgentDefaults(account: "Codex2")
        s.dockHidden = ["codex2"]
        XCTAssertFalse(s.removeAccount("Codex1", home: home))
        XCTAssertTrue(s.removeAccount("Codex2", home: home))
        XCTAssertFalse(s.agentAccounts(home: home).contains { $0.id == "Codex2" })
        XCTAssertNil(s.defaults(for: .codex).account)
        XCTAssertEqual(s.dockHidden, [])
        XCTAssertEqual(s.addAccount(.codex, home: home)?.id, "Codex2", "adding again brings it back")
    }

    func test_settings_removeNeverDeletesTheFolder_andAutoFoundClaude2StaysRemoved() throws {
        try mkdir(".claude-2")
        var s = AppSettings()
        XCTAssertTrue(s.removeAccount("Claude2", home: home))
        XCTAssertTrue(Workspace.folderExists(home + "/.claude-2"))
        XCTAssertEqual(s.agentAccounts(home: home).filter { $0.agent == .claude }.map(\.id), ["Claude1"])
        XCTAssertTrue(AccountsPane.removeConfirm(AgentAccount(agent: .claude, number: 2), home: home).message.contains("nothing is deleted"))
    }

    func test_settings_globalListFollowsTheApp() {
        var s = AppSettings()
        s.addAccount(.codex, home: home)
        AgentAccounts.use(stored: s.accounts, removed: s.removedAccounts)
        XCTAssertEqual(AccountResolver.choices(for: .codex, home: home), ["Codex1", "Codex2"])
        XCTAssertEqual(AccountResolver.choices(for: .gemini, home: home), [], "one account: no picker, as before")
        XCTAssertEqual(AccountResolver.choices(for: .claude, home: home), ["Claude1"])
    }

    func test_pane_rows_addConfirm_andSignInCommand() throws {
        let list = AgentAccounts.derived(home: home) + [AgentAccount(agent: .codex, number: 2, label: "Work")]
        let rows = AccountsPane.rows(list, agent: .codex, home: home, signedIn: { $0.number == 1 })
        XCTAssertEqual(rows.map(\.label), ["Codex1", "Work"])
        XCTAssertEqual(rows[1].idNote, "Codex2")
        XCTAssertEqual(rows[0].folder, "~/.codex (default)")
        XCTAssertEqual(rows[1].folder, "~/.codex-2")
        XCTAssertEqual(rows.map(\.status), ["signed in", "not signed in"])
        XCTAssertEqual(rows.map(\.canRemove), [false, true])
        XCTAssertEqual(rows[1].signInCommand, "CODEX_HOME=~/.codex-2 codex login")
        XCTAssertNil(AccountsPane.rows(list, agent: .goose, home: home, signedIn: { _ in nil })[0].folder)
        XCTAssertEqual(AgentAccounts.signInCommand(AgentAccount(agent: .gemini, number: 2), home: home), "GEMINI_CLI_HOME=~/.gemini-home-2 gemini")
        XCTAssertEqual(AgentAccounts.signInCommand(AgentAccount(agent: .claude, number: 3), home: home), "CLAUDE_CONFIG_DIR=~/.claude-3 claude")
        XCTAssertEqual(AgentAccounts.signInCommand(AgentAccount(agent: .kimi, number: 2), home: home), "KIMI_CODE_HOME=~/.kimi-code-2 kimi")
        let c = AccountsPane.addConfirm(AgentAccount(agent: .codex, number: 2), home: home, folderExists: false)
        XCTAssertEqual(c.title, "Add Codex2?")
        XCTAssertTrue(c.message.contains("creates the folder ~/.codex-2"))
        XCTAssertTrue(c.message.contains("CODEX_HOME=~/.codex-2 codex login"))
        XCTAssertEqual(c.button, "Create Folder and Add")
        XCTAssertEqual(AccountsPane.addConfirm(AgentAccount(agent: .codex, number: 2), home: home, folderExists: true).button, "Add Account")
        XCTAssertFalse(Workspace.folderExists(home + "/.codex-2"), "the pane's logic never creates folders")
    }

    func test_signedIn_readsOnlyTheAccountsOwnFolder() throws {
        let codex2 = AgentAccount(agent: .codex, number: 2)
        XCTAssertEqual(AgentAccounts.signedIn(codex2, home: home), false)
        try mkdir(".codex-2")
        FileManager.default.createFile(atPath: home + "/.codex-2/auth.json", contents: Data("{}".utf8))
        XCTAssertEqual(AgentAccounts.signedIn(codex2, home: home), true)
        XCTAssertNil(AgentAccounts.signedIn(AgentAccount(agent: .gemini, number: 2), home: home), "Gemini may use an API key")
    }

    // MARK: Usage

    func test_usage_eachCodexAccountIsItsOwnSeat() throws {
        try mkdir(".codex-2/sessions/2026")
        let line = #"{"payload":{"rate_limits":{"primary":{"used_percent":42},"secondary":{"used_percent":7}}}}"#
        FileManager.default.createFile(atPath: home + "/.codex-2/sessions/2026/a.jsonl", contents: Data(line.utf8))
        AgentAccounts.use(stored: [AgentAccount(agent: .codex, number: 2)], removed: [])
        let u = Usage.all(home: home).first { $0.seat == "Codex2" }
        XCTAssertEqual(u?.fiveHour, 42)
    }
}
