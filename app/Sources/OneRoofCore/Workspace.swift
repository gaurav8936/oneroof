import Foundation

/// Facts about the workspace layout: <projects>/<domain>/<repo>, the shared folder, workstream ids, account homes.
/// The projects folder is a setting (Settings › Foundations): the app calls `configure(root:shared:)` at launch and
/// whenever the settings change, so every call site reads the folder in use.
public enum Workspace {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var configuredRoot: String?
    nonisolated(unsafe) private static var configuredShared: String?

    /// The projects folder in use (see `resolveProjects`). Before `configure` runs: ~/Projects if it exists, else home.
    public static var projectsRoot: String {
        lock.lock(); defer { lock.unlock() }
        return configuredRoot ?? defaultProjectsRoot()
    }

    /// The shared rules-and-docs folder in use (see `resolveShared`). It may not exist; callers check.
    public static var sharedRoot: String {
        lock.lock(); let r = configuredRoot, s = configuredShared; lock.unlock()
        return s ?? resolveShared(setting: "", projects: r ?? defaultProjectsRoot(), environment: [:])
    }

    /// Point every call site at a projects folder (and, optionally, a shared folder).
    public static func configure(root: String, shared: String? = nil) {
        lock.lock(); defer { lock.unlock() }
        configuredRoot = (expand(root) as NSString).standardizingPath
        configuredShared = shared.map { (expand($0) as NSString).standardizingPath }
    }

    /// ~/Projects when that folder exists, else the home folder.
    public static func defaultProjectsRoot(home: String = NSHomeDirectory()) -> String {
        let p = (home as NSString).appendingPathComponent("Projects")
        var dir: ObjCBool = false
        return FileManager.default.fileExists(atPath: p, isDirectory: &dir) && dir.boolValue ? p : home
    }

    /// `ONEROOF_PROJECTS` wins, then the Settings value, then `defaultProjectsRoot`. "" in Settings means the default.
    public static func resolveProjects(setting: String, environment: [String: String] = ProcessInfo.processInfo.environment,
                                       home: String = NSHomeDirectory()) -> String {
        if let e = environment["ONEROOF_PROJECTS"], !e.isEmpty { return (expand(e) as NSString).standardizingPath }
        if !setting.isEmpty { return (expand(setting) as NSString).standardizingPath }
        return defaultProjectsRoot(home: home)
    }

    /// `ONEROOF_SHARED` wins, then the Settings value, then `<projects>/_common`.
    public static func resolveShared(setting: String, projects: String,
                                     environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let e = environment["ONEROOF_SHARED"], !e.isEmpty { return (expand(e) as NSString).standardizingPath }
        if !setting.isEmpty { return (expand(setting) as NSString).standardizingPath }
        return (projects as NSString).appendingPathComponent("_common")
    }

    /// True when `path` is an existing folder.
    public static func folderExists(_ path: String) -> Bool {
        var dir: ObjCBool = false
        return !path.isEmpty && FileManager.default.fileExists(atPath: path, isDirectory: &dir) && dir.boolValue
    }

    /// One Roof's own data folder (~/Library/Application Support/One Roof).
    public static var appSupport: String {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Library/Application Support") + "/One Roof"
    }

    static func expand(_ p: String) -> String { (p as NSString).expandingTildeInPath }

    /// True when `path` is the projects folder or inside it (agents start only here).
    public static func isInsideProjects(_ path: String, root: String = projectsRoot) -> Bool {
        let p = (path as NSString).standardizingPath
        let r = (root as NSString).standardizingPath
        return p == r || p.hasPrefix(r + "/")
    }

    /// "domain/repo" for a path under the projects folder, "domain" for a domain folder, the folder itself (with ~)
    /// for the root, or the last path component for anything else.
    public static func repoLabel(for path: String, root: String = projectsRoot) -> String {
        let p = (path as NSString).standardizingPath
        let r = (root as NSString).standardizingPath
        guard isInsideProjects(p, root: r) else { return (p as NSString).lastPathComponent }
        if p == r { return (r as NSString).abbreviatingWithTildeInPath }
        let rel = String(p.dropFirst(r.count + 1))
        let parts = rel.split(separator: "/").map(String.init)
        // Worktrees live at <repo>/.worktrees/<unit>/: label them as the repo.
        let cut = parts.firstIndex(of: ".worktrees") ?? parts.count
        let useful = Array(parts.prefix(min(cut, 2)))
        return useful.joined(separator: "/")
    }

    private static let wsRegex = try! NSRegularExpression(
        pattern: #"\bWS-[A-Z]{2,6}(?:-[A-Z0-9]{2,8})?-\d{2,4}\b"#, options: [.caseInsensitive])

    /// The first workstream id (WS-<CODE>-<TOPIC>-<NN> or WS-<CODE>-<NN>) in `text`, upper-cased.
    public static func workstream(in text: String) -> String? {
        let range = NSRange(text.startIndex..., in: text)
        guard let m = wsRegex.firstMatch(in: text, range: range),
              let r = Range(m.range, in: text) else { return nil }
        return String(text[r]).uppercased()
    }

    /// Repos under the projects folder (two levels: domain/repo that contain .git), for the "new session" picker.
    public static func listRepos(root: String = projectsRoot) -> [String] {
        let fm = FileManager.default
        var out: [String] = []
        guard let domains = try? fm.contentsOfDirectory(atPath: root) else { return [] }
        for d in domains.sorted() where !d.hasPrefix(".") {
            let dp = (root as NSString).appendingPathComponent(d)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dp, isDirectory: &isDir), isDir.boolValue else { continue }
            if fm.fileExists(atPath: (dp as NSString).appendingPathComponent(".git")) { out.append(dp) }
            guard let repos = try? fm.contentsOfDirectory(atPath: dp) else { continue }
            for r in repos.sorted() where !r.hasPrefix(".") && !r.hasPrefix("_") {
                let rp = (dp as NSString).appendingPathComponent(r)
                if fm.fileExists(atPath: (rp as NSString).appendingPathComponent(".git")) { out.append(rp) }
            }
        }
        return out
    }
}

/// Turns an agent process's environment into an account label.
public enum AccountResolver {
    /// Known Claude homes → labels: ~/.claude is "Claude1", ~/.claude-2 (a second account, if you have one) "Claude2".
    public static func claudeLabel(configDir: String?, home: String = NSHomeDirectory()) -> String {
        guard let dir = configDir, !dir.isEmpty else { return "Claude1" }
        let d = (dir as NSString).standardizingPath
        let h = (home as NSString).standardizingPath
        if d == h + "/.claude" { return "Claude1" }
        if d == h + "/.claude-2" { return "Claude2" }
        return (d as NSString).lastPathComponent
    }

    /// The account label for `agent`, given its environment. Nil when there is nothing to say.
    public static func label(agent: AgentKind, env: [String: String], home: String = NSHomeDirectory()) -> String? {
        switch agent {
        case .claude:
            return claudeLabel(configDir: env["CLAUDE_CONFIG_DIR"], home: home)
        case .codex:
            guard let c = env["CODEX_HOME"], !c.isEmpty else { return "Codex" }
            return (c as NSString).lastPathComponent
        case .gemini, .agy:
            return nil
        case .kimi, .shell:
            return nil
        }
    }

    /// Environment to launch `agent` on the account `label` (the inverse of `label`).
    /// Claude1 sets nothing: an EMPTY CLAUDE_CONFIG_DIR is not "unset" — Claude then uses the current folder as its
    /// config folder (gotcha 20261017). The herdr server must therefore not carry account variables itself;
    /// One Roof checks that before launching (`HerdrClient.serverLeaks`).
    public static func launchEnv(agent: AgentKind, account: String?, home: String = NSHomeDirectory()) -> [String: String] {
        guard agent == .claude, account == "Claude2" else { return [:] }
        return ["CLAUDE_CONFIG_DIR": home + "/.claude-2"]
    }

    /// Account variables removed from herdr's environment when One Roof starts the server.
    public static let accountVariables = ["CLAUDE_CONFIG_DIR", "CODEX_HOME", "KIMI_HOME", "GEMINI_HOME"]

    /// The Claude accounts on this Mac: "Claude1" (~/.claude) always, "Claude2" only when ~/.claude-2 exists.
    public static func claudeAccounts(home: String = NSHomeDirectory()) -> [String] {
        Workspace.folderExists(home + "/.claude-2") ? ["Claude1", "Claude2"] : ["Claude1"]
    }

    /// The account choices offered for an agent in the "new session" sheet.
    public static func choices(for agent: AgentKind, home: String = NSHomeDirectory()) -> [String] {
        switch agent {
        case .claude: return claudeAccounts(home: home)
        default: return []
        }
    }

    /// True when `command` is found in the usual install folders or on the login shell's PATH.
    public static func installed(_ command: String, home: String = NSHomeDirectory()) -> Bool {
        let fm = FileManager.default
        for dir in ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", home + "/.npm-global/bin", home + "/bin"]
        where fm.isExecutableFile(atPath: dir + "/" + command) { return true }
        guard command.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return false }
        return Foundations.run("/bin/zsh", ["-lc", "command -v \(command)"], timeout: 5).0 == 0
    }

    /// The signed-in email in a Claude config file (`~/.claude.json`, `~/.claude-2/.claude.json`), if any.
    public static func claudeEmail(_ file: String) -> String? {
        // Demo mode (screenshots for the public help) never shows a real account.
        if ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_DEMO"] == "1" {
            return FileManager.default.fileExists(atPath: file) ? "you@example.com" : nil
        }
        guard let d = FileManager.default.contents(atPath: file),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
              let acct = j["oauthAccount"] as? [String: Any] else { return nil }
        return acct["emailAddress"] as? String
    }

    /// The config file holding a Claude account's sign-in.
    public static func claudeConfigFile(_ account: String, home: String = NSHomeDirectory()) -> String {
        account == "Claude2" ? home + "/.claude-2/.claude.json" : home + "/.claude.json"
    }
}
