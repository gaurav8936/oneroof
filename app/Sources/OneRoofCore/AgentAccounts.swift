import Foundation

// LAB-1999 · more than one account per agent (Codex 1, 2 · Gemini 1, 2, 3 …), not only Claude1 / Claude2.
//
// An account is possible where the agent's CLI moves its whole home, sign-in included, to a folder named by one
// environment variable (checked against each CLI's docs, 10-31):
//   Claude  CLAUDE_CONFIG_DIR   first ~/.claude (variable unset)   then ~/.claude-N
//   Codex   CODEX_HOME          first ~/.codex  (unset)            then ~/.codex-N
//   Gemini  GEMINI_CLI_HOME     first ~         (unset)            then ~/.gemini-home-N (the CLI makes .gemini inside it)
//   Kimi    KIMI_CODE_HOME      first ~/.kimi-code (unset)         then ~/.kimi-code-N
// Antigravity and Goose have no such variable and OpenCode's OPENCODE_CONFIG_DIR does not move its sign-in: one account.
//
// The folder follows from the agent and the number, so a session's account id ("Codex2") is enough to launch it: the
// app, roofd's scheduler and loops (LaunchPlan) all get the same environment without reading the app's settings. The
// first account of every agent sets no variable at all (an EMPTY CLAUDE_CONFIG_DIR breaks Claude, gotcha 20261017).

/// One sign-in of one agent. `id` ("Claude2", "Codex2", "Gemini3") is what sessions store; `label` is the owner's name
/// for it (Settings › Seats & accounts › Rename), shown in Settings and in the New session sheet.
public struct AgentAccount: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var agent: AgentKind
    public var number: Int
    public var label: String

    public init(agent: AgentKind, number: Int, label: String? = nil) {
        self.agent = agent
        self.number = max(1, number)
        let l = (label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.label = l.isEmpty ? AgentAccounts.id(agent, self.number) : l
    }

    public var id: String { AgentAccounts.id(agent, number) }
    /// The account's home folder (the one its variable names; for a first account, the CLI's own default).
    public func folder(home: String = NSHomeDirectory()) -> String { AgentAccounts.folder(agent, number, home: home) }
    /// The badge and dock seat for this account.
    public var seat: SeatMark { SeatMark(agent: agent, number: number) }
    /// True for the label the app gave it (not renamed).
    public var hasDefaultLabel: Bool { label == id }
}

public enum AgentAccounts {
    /// The agents that can have accounts, in the order Settings and the bottom bar list them.
    public static let kinds: [AgentKind] = [.claude, .codex, .gemini, .kimi, .agy, .opencode, .goose]

    /// The environment variable that moves an agent's home (nil: one account only).
    public static func variable(_ k: AgentKind) -> String? {
        switch k {
        case .claude: return "CLAUDE_CONFIG_DIR"
        case .codex: return "CODEX_HOME"
        case .gemini: return "GEMINI_CLI_HOME"
        case .kimi: return "KIMI_CODE_HOME"
        default: return nil
        }
    }

    public static func canAdd(_ k: AgentKind) -> Bool { variable(k) != nil }

    /// Why "+ Add account" is off for an agent (its help text), or nil when it can have more accounts.
    public static func oneAccountReason(_ k: AgentKind) -> String? {
        switch k {
        case .agy: return "Antigravity has no setting that moves its sign-in to another folder, so it has one account."
        case .opencode: return "OpenCode's OPENCODE_CONFIG_DIR moves its settings but not its sign-in, so it has one account."
        case .goose: return "Goose has no setting that moves its sign-in to another folder, so it has one account."
        case .shell: return "A terminal has no account."
        default: return nil
        }
    }

    /// "Claude2", "Codex1", "Gemini3".
    public static func id(_ k: AgentKind, _ n: Int) -> String { k.displayName + "\(n)" }

    /// The account number in a session's account field: "Codex2" → 2; nil, "", "Codex" (the usage feed's name) or
    /// anything else → 1. Claude keeps its old rule for labels it did not write ("…2…" was the second account).
    public static func number(_ account: String?, agent: AgentKind) -> Int {
        guard let a = account, !a.isEmpty else { return 1 }
        let p = agent.displayName
        if a.hasPrefix(p), let n = Int(a.dropFirst(p.count)), n >= 1 { return canAdd(agent) ? n : 1 }
        if agent == .claude, a.contains("2") { return 2 }
        return 1
    }

    /// The account's home folder. First accounts: the CLI's default (~/.claude, ~/.codex, ~ for Gemini, ~/.kimi-code).
    public static func folder(_ k: AgentKind, _ n: Int, home: String = NSHomeDirectory()) -> String {
        switch (k, n) {
        case (.claude, 1): return home + "/.claude"
        case (.claude, _): return home + "/.claude-\(n)"
        case (.codex, 1): return home + "/.codex"
        case (.codex, _): return home + "/.codex-\(n)"
        case (.gemini, 1): return home
        case (.gemini, _): return home + "/.gemini-home-\(n)"
        case (.kimi, 1): return home + "/.kimi-code"
        case (.kimi, _): return home + "/.kimi-code-\(n)"
        case (.agy, _): return home + "/.gemini"
        case (.opencode, _), (.goose, _), (.shell, _): return home   // one account, in the CLI's own folders
        }
    }

    /// The variables that start `agent` on account number `n`: nothing for a first account, else the folder.
    public static func env(_ k: AgentKind, _ n: Int, home: String = NSHomeDirectory()) -> [String: String] {
        guard n >= 2, let v = variable(k) else { return [:] }
        return [v: folder(k, n, home: home)]
    }

    /// `/Users/x/.codex-2` → `~/.codex-2`.
    public static func short(_ path: String, home: String = NSHomeDirectory()) -> String {
        path == home ? "~" : path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    /// The one-time sign-in, typed in Terminal: `CODEX_HOME=~/.codex-2 codex login`.
    public static func signInCommand(_ a: AgentAccount, home: String = NSHomeDirectory()) -> String {
        let prefix = env(a.agent, a.number, home: home).map { "\($0.key)=\(short($0.value, home: home)) " }.first ?? ""
        switch a.agent {
        case .codex: return prefix + "codex login"
        default: return prefix + a.agent.cliName
        }
    }

    /// What to do once the sign-in command runs.
    public static func signInHint(_ k: AgentKind) -> String {
        switch k {
        case .claude: return "Claude asks you to sign in when it starts (or type /login)."
        case .codex: return "Codex opens the browser to sign in."
        case .gemini: return "Pick a sign-in when Gemini asks; with a Gemini API key, set GEMINI_API_KEY first."
        case .kimi: return "Type /login when Kimi opens."
        default: return ""
        }
    }

    /// Signed in, as far as a file check of the agent's own folder tells (nil: not knowable without asking the CLI).
    public static func signedIn(_ a: AgentAccount, home: String = NSHomeDirectory()) -> Bool? {
        let fm = FileManager.default
        switch a.agent {
        case .claude: return AccountResolver.claudeEmail(AccountResolver.claudeConfigFile(a.id, home: home)) != nil
        case .codex: return fm.fileExists(atPath: a.folder(home: home) + "/auth.json")
        case .gemini: return fm.fileExists(atPath: a.folder(home: home) + "/.gemini/oauth_creds.json") ? true : nil
        case .kimi: return fm.fileExists(atPath: a.folder(home: home) + "/credentials")
        default: return nil
        }
    }

    // MARK: The list

    /// The accounts with no settings at all: the first account of every agent, and Claude2 when ~/.claude-2 exists
    /// (the behaviour before LAB-1999).
    public static func derived(home: String = NSHomeDirectory()) -> [AgentAccount] {
        var out = kinds.map { AgentAccount(agent: $0, number: 1) }
        if Workspace.folderExists(home + "/.claude-2") { out.append(AgentAccount(agent: .claude, number: 2)) }
        return sorted(out)
    }

    /// The list Settings shows: the derived accounts, plus the owner's added ones (`stored` also carries renames),
    /// minus the ones removed. A first account can't be removed.
    public static func effective(stored: [AgentAccount], removed: [String], home: String = NSHomeDirectory()) -> [AgentAccount] {
        var byID: [String: AgentAccount] = [:]
        for a in derived(home: home) where a.number == 1 || !removed.contains(a.id) { byID[a.id] = a }
        for a in stored where kinds.contains(a.agent) && (a.number == 1 || canAdd(a.agent)) && (a.number == 1 || !removed.contains(a.id)) {
            byID[a.id] = a
        }
        return sorted(Array(byID.values))
    }

    static func sorted(_ l: [AgentAccount]) -> [AgentAccount] {
        l.sorted { (kinds.firstIndex(of: $0.agent) ?? 99, $0.number) < (kinds.firstIndex(of: $1.agent) ?? 99, $1.number) }
    }

    /// The next account to add for `k` (the lowest free number from 2), or nil when it can have only one.
    public static func next(_ k: AgentKind, in list: [AgentAccount]) -> AgentAccount? {
        guard canAdd(k) else { return nil }
        let used = Set(list.filter { $0.agent == k }.map(\.number))
        var n = 2
        while used.contains(n) { n += 1 }
        return AgentAccount(agent: k, number: n)
    }

    // MARK: The list in use (set by the app from its settings; roofd and tests see the derived list)

    private static let lock = NSLock()
    nonisolated(unsafe) private static var current: (stored: [AgentAccount], removed: [String]) = ([], [])

    /// The app calls this whenever its settings change, so code without the settings (AccountResolver, Usage, the
    /// router) reads the same list.
    public static func use(stored: [AgentAccount], removed: [String]) {
        lock.lock(); current = (stored, removed); lock.unlock()
    }

    public static func list(home: String = NSHomeDirectory()) -> [AgentAccount] {
        lock.lock(); let c = current; lock.unlock()
        return effective(stored: c.stored, removed: c.removed, home: home)
    }

    public static func accounts(for k: AgentKind, home: String = NSHomeDirectory()) -> [AgentAccount] {
        list(home: home).filter { $0.agent == k }
    }

    /// The owner's name for a session's account ("Codex2" → "Work Codex"), or the id when it was never renamed.
    public static func label(of account: String?, agent: AgentKind, home: String = NSHomeDirectory()) -> String {
        let n = number(account, agent: agent)
        return list(home: home).first { $0.agent == agent && $0.number == n }?.label ?? id(agent, n)
    }
}

// MARK: - Settings

public extension AppSettings {
    /// LAB-1999: every account per agent, as Settings › Seats & accounts lists them.
    func agentAccounts(home: String = NSHomeDirectory()) -> [AgentAccount] {
        AgentAccounts.effective(stored: accounts, removed: removedAccounts, home: home)
    }

    /// Adds the next account for `k` to the list (the folder is the caller's to create, after the owner confirms).
    @discardableResult
    mutating func addAccount(_ k: AgentKind, home: String = NSHomeDirectory()) -> AgentAccount? {
        guard let a = AgentAccounts.next(k, in: agentAccounts(home: home)) else { return nil }
        removedAccounts.removeAll { $0 == a.id }
        accounts.removeAll { $0.id == a.id }
        accounts.append(a)
        return a
    }

    /// Renames an account; an empty name puts the default back.
    mutating func renameAccount(_ id: String, to name: String, home: String = NSHomeDirectory()) {
        guard var a = agentAccounts(home: home).first(where: { $0.id == id }) else { return }
        a = AgentAccount(agent: a.agent, number: a.number, label: name)
        accounts.removeAll { $0.id == id }
        accounts.append(a)
    }

    /// Takes an account out of One Roof. Its folder (and sign-in) stays on disk. A first account can't be removed.
    /// Defaults and the bottom bar that pointed at it go back to the agent's first account.
    @discardableResult
    mutating func removeAccount(_ id: String, home: String = NSHomeDirectory()) -> Bool {
        guard let a = agentAccounts(home: home).first(where: { $0.id == id }), a.number > 1 else { return false }
        accounts.removeAll { $0.id == id }
        if !removedAccounts.contains(id) { removedAccounts.append(id) }
        dockHidden.removeAll { $0 == a.seat.rawValue }
        if var d = agents[a.agent.rawValue], d.account == id {
            d.account = a.agent == .claude ? AgentAccounts.id(.claude, 1) : nil
            agents[a.agent.rawValue] = d
        }
        return true
    }
}

// MARK: - Badge / seat

/// LAB-1999 · an agent mark on one account: the badge monogram and the bottom bar's seat. `AgentMark` stays the agent
/// kind (colour, ~20 call sites, C1/C2 for Claude's first two accounts); this adds the account number, so added
/// accounts get their own monogram ("X2", "G3", "K2", "C3") in the agent's colour. The first accounts keep the marks
/// they always had (C1 · C2 · CX · GM · KM · AG · OC · GS), and `rawValue` stays the AgentMark raw value for them, so
/// saved settings (Settings › Bottom bar) read the same.
public struct SeatMark: Hashable, Sendable {
    public let mark: AgentMark
    public let number: Int

    public init(_ mark: AgentMark, number: Int? = nil) {
        self.mark = mark
        self.number = number ?? (mark == .claude2 ? 2 : 1)
    }

    public init(agent: AgentKind, number: Int) {
        let n = AgentAccounts.canAdd(agent) ? max(1, number) : 1
        switch agent {
        case .claude: self.init(n == 2 ? .claude2 : .claude1, number: n)
        default: self.init(AgentMark(agent: agent, account: nil), number: n)
        }
    }

    /// The seat for a session's agent and account ("Codex2" → X2).
    public init(agent: AgentKind, account: String?) {
        self.init(agent: agent, number: AgentAccounts.number(account, agent: agent))
    }

    public static let claude1 = SeatMark(.claude1), claude2 = SeatMark(.claude2), codex = SeatMark(.codex),
                      kimi = SeatMark(.kimi), gemini = SeatMark(.gemini), antigravity = SeatMark(.antigravity),
                      opencode = SeatMark(.opencode), goose = SeatMark(.goose), shell = SeatMark(.shell)

    public var agent: AgentKind { DockSeats.agent(mark) }
    public var isFirst: Bool { number == 1 || (mark == .claude2 && number == 2) }

    /// Saved in Settings (bottom bar): the AgentMark raw value for the first accounts, "codex2", "gemini3", "claude3".
    public var rawValue: String {
        if isFirst { return mark.rawValue }
        return (mark == .claude1 || mark == .claude2 ? "claude" : mark.rawValue) + "\(number)"
    }

    public init?(rawValue: String) {
        if let m = AgentMark(rawValue: rawValue) { self.init(m); return }
        let letters = rawValue.prefix { $0.isLetter }
        guard let n = Int(rawValue.dropFirst(letters.count)), n >= 1 else { return nil }
        let kind: AgentKind?
        switch String(letters) {
        case "claude": kind = .claude
        case "codex": kind = .codex
        case "gemini": kind = .gemini
        case "kimi": kind = .kimi
        default: kind = nil
        }
        guard let k = kind else { return nil }
        self.init(agent: k, number: n)
    }

    /// Two characters, like the first accounts': C1 · C2 · CX · X2 · GM · G3 · KM · K2 · C3.
    public var mono: String {
        if isFirst { return mark.mono }
        switch mark {
        case .claude1, .claude2: return "C\(number)"
        case .codex: return "X\(number)"
        case .gemini: return "G\(number)"
        case .kimi: return "K\(number)"
        default: return mark.mono
        }
    }

    public var fill: RGB { mark.fill }
    public func fill(dark: Bool) -> RGB { mark.fill(dark: dark) }
    public func ink(dark: Bool) -> RGB { mark.ink(dark: dark) }

    /// The account id sessions store ("Claude1", "Codex2"); nil for a terminal.
    public var accountID: String? { mark == .shell ? nil : AgentAccounts.id(agent, number) }
}

// MARK: - Settings › Seats & accounts (the pane's words and rules, kept here so they are tested)

public enum AccountsPane {
    public struct Row: Equatable, Sendable, Identifiable {
        public var id: String
        public var seat: SeatMark
        public var label: String
        /// The id when the account was renamed ("Codex2"), else nil.
        public var idNote: String?
        /// "~/.codex-2", "~/.claude (default)"; nil for agents whose folders One Roof does not move.
        public var folder: String?
        public var status: String
        public var signedIn: Bool?
        public var canRemove: Bool
        public var signInCommand: String?
    }

    public static func status(_ signedIn: Bool?, agent: AgentKind) -> String {
        switch signedIn {
        case true?: return "signed in"
        case false?: return "not signed in"
        case nil: return agent == .gemini ? "no sign-in file (API key?)" : "sign-in not checked"
        }
    }

    public static func rows(_ list: [AgentAccount], agent: AgentKind, home: String = NSHomeDirectory(),
                            signedIn: (AgentAccount) -> Bool? = { AgentAccounts.signedIn($0) }) -> [Row] {
        list.filter { $0.agent == agent }.map { a in
            let movable = AgentAccounts.canAdd(agent)
            let f = AgentAccounts.short(a.folder(home: home), home: home)
            let s = signedIn(a)
            return Row(id: a.id, seat: a.seat, label: a.label, idNote: a.hasDefaultLabel ? nil : a.id,
                       folder: movable ? (a.number == 1 ? f + " (default)" : f) : nil,
                       status: status(s, agent: agent), signedIn: s, canRemove: a.number > 1,
                       signInCommand: movable ? AgentAccounts.signInCommand(a, home: home) : nil)
        }
    }

    /// The confirm before "+ Add account" creates anything.
    public static func addConfirm(_ a: AgentAccount, home: String = NSHomeDirectory(), folderExists: Bool) -> (title: String, message: String, button: String) {
        let f = AgentAccounts.short(a.folder(home: home), home: home)
        let v = AgentAccounts.variable(a.agent) ?? ""
        let what = folderExists ? "uses the folder \(f), which is already on this Mac," : "creates the folder \(f)"
        return ("Add \(a.id)?",
                "One Roof \(what) as \(a.agent.displayName)'s home for this account (\(v)) and starts \(a.id) sessions there. "
                + "Sign in once in Terminal afterwards:\n\n\(AgentAccounts.signInCommand(a, home: home))",
                folderExists ? "Add Account" : "Create Folder and Add")
    }

    /// The confirm before Remove; the folder is never deleted.
    public static func removeConfirm(_ a: AgentAccount, home: String = NSHomeDirectory()) -> (title: String, message: String) {
        let f = AgentAccounts.short(a.folder(home: home), home: home)
        return ("Remove \(a.label) from One Roof?",
                "One Roof stops offering \(a.id). The folder \(f) and its sign-in stay on this Mac; nothing is deleted. "
                + "Add the account again to use it.")
    }
}
