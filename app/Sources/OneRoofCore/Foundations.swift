import Foundation

/// The startup hygiene check: is every agent wired to the shared rules, skills, hooks, MCP list and
/// memory before a session starts? One Roof only READS the workspace and runs the workspace's own check scripts
/// (`ensure-doors.sh --check`, `sync-mcp.py --check`, `sync-skills.sh --dry-run`); it never keeps a copy of what
/// they manage (owner, 2026-10-17).
public enum CheckLevel: Int, Comparable, Sendable {
    case ok = 0, warn = 1, fail = 2
    public static func < (a: CheckLevel, b: CheckLevel) -> Bool { a.rawValue < b.rawValue }
}

public struct CheckResult: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var level: CheckLevel
    public var detail: String
    /// A workspace command that fixes it (run in a One Roof terminal so the owner sees the output).
    public var fix: String?

    public init(id: String, title: String, level: CheckLevel, detail: String, fix: String? = nil) {
        self.id = id; self.title = title; self.level = level; self.detail = detail; self.fix = fix
    }
}

public struct FoundationPaths: Sendable {
    public var home: String
    public var projects: String
    public var common: String
    public var agenticEngineering: String

    public init(home: String = NSHomeDirectory(), projects: String = Workspace.projectsRoot,
                common: String = Workspace.sharedRoot,
                agenticEngineering: String = AEFolder.resolve(setting: "").path) {
        self.home = home; self.projects = projects; self.common = common; self.agenticEngineering = agenticEngineering
    }

    public var claudeSettings: String { home + "/.claude/settings.json" }
    public var memoryFolder: String { home + "/.claude/projects/" + Workspace.mangle(projects) + "/memory" }
    public var handoffs: String { common + "/docs/next-session-handoff" }
    public var gotchas: String { common + "/docs/gotchas" }
    /// The shared folder is optional: checks and lists that need it stay quiet when it is missing.
    public var hasShared: Bool { Workspace.folderExists(common) }
    public var skills: String { agenticEngineering + "/skills" }
}

public enum Foundations {
    // MARK: Running workspace scripts

    /// Run a command with a timeout; returns (exit code, combined output). Never uses a shell.
    public static func run(_ exe: String, _ args: [String], cwd: String? = nil, timeout: TimeInterval = 20) -> (Int32, String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return (127, "\(error)") }
        var data = Data()
        let reader = DispatchQueue(label: "oneroof.check.read")
        let done = DispatchSemaphore(value: 0)
        reader.async { data = pipe.fileHandleForReading.readDataToEndOfFile(); done.signal() }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return (124, "timed out after \(Int(timeout)) s") }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    static func lastLine(_ s: String) -> String {
        s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.last { !$0.isEmpty } ?? ""
    }

    // MARK: Checks

    public static func runAll(_ p: FoundationPaths = FoundationPaths(), runtime: SessionRuntime? = nil) -> [CheckResult] {
        var out: [CheckResult] = []
        out.append(runtimeCheck(runtime))
        out.append(contentsOf: claudeSettingsChecks(p))
        out.append(doorsCheck(p))
        out.append(skillsCheck(p))
        out.append(mcpCheck(p))
        out.append(contentsOf: agentChecks(p))
        out.append(agenticEngineeringCheck(p))
        let lm = LocalModel.shared
        out.append(CheckResult(id: "localmodel", title: "On-device router model (optional)", level: lm.installed() ? .ok : .warn,
                               detail: lm.status(), fix: lm.serverBinary == nil ? "brew install llama.cpp" : nil))
        return p.hasShared ? out : softenWithoutShared(out)
    }

    /// Without a shared folder there are no workspace conventions to enforce: the memory pin, launch guard and skill
    /// links are advice (warn), not blockers.
    public static func softenWithoutShared(_ r: [CheckResult]) -> [CheckResult] {
        r.map { c in
            guard c.level == .fail, ["memory", "guard", "skills"].contains(c.id) else { return c }
            var w = c; w.level = .warn; return w
        }
    }

    /// The session runtime row. Its id stays "herdr" so saved check state and the Setup page keep matching.
    public static func runtimeCheck(_ r: SessionRuntime?) -> CheckResult {
        let title = r?.kind.displayName ?? "herdr"
        guard let r else { return CheckResult(id: "herdr", title: title, level: .warn, detail: "not checked") }
        let h = r.health()
        return CheckResult(id: "herdr", title: title, level: h.level, detail: h.detail, fix: h.fix)
    }

    /// Memory pin, launch-folder hook and the hooks' scripts, from ~/.claude/settings.json (shared by both Claude homes).
    public static func claudeSettingsChecks(_ p: FoundationPaths) -> [CheckResult] {
        guard let data = FileManager.default.contents(atPath: p.claudeSettings),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [CheckResult(id: "memory", title: "Memory pin", level: .fail, detail: "~/.claude/settings.json missing or unreadable")]
        }
        var out: [CheckResult] = []
        let pin = (json["autoMemoryDirectory"] as? String).map { ($0 as NSString).expandingTildeInPath }
        let memIndex = p.memoryFolder + "/MEMORY.md"
        if pin == nil {
            out.append(CheckResult(id: "memory", title: "Memory pin", level: .fail,
                                   detail: "autoMemoryDirectory not set: a session started outside the projects folder writes a second memory"))
        } else if pin != p.memoryFolder {
            out.append(CheckResult(id: "memory", title: "Memory pin", level: .fail, detail: "points at \(pin!), expected \(p.memoryFolder)"))
        } else if let text = try? String(contentsOfFile: memIndex, encoding: .utf8) {
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            out.append(CheckResult(id: "memory", title: "Memory pin", level: lines > 200 ? .warn : .ok,
                                   detail: "one memory · MEMORY.md \(lines) lines" + (lines > 200 ? " (only the first 200 load)" : "")))
        } else {
            out.append(CheckResult(id: "memory", title: "Memory pin", level: .warn, detail: "pinned, but MEMORY.md not found"))
        }

        let hooks = parseHooks(json)
        let missing = hooks.filter { !$0.scriptExists }
        let guardHook = hooks.contains { $0.event == "UserPromptSubmit" }
        out.append(CheckResult(id: "guard", title: "Launch-folder guard", level: guardHook ? .ok : .fail,
                               detail: guardHook ? "Claude hook blocks prompts outside the projects folder" : "no UserPromptSubmit hook in ~/.claude/settings.json"))
        out.append(CheckResult(id: "hooks", title: "Hooks", level: missing.isEmpty ? .ok : .warn,
                               detail: missing.isEmpty ? "\(hooks.count) hooks, every script present"
                                   : "missing script: " + missing.map { ($0.script as NSString).lastPathComponent }.joined(separator: ", ")))
        return out
    }

    static func noShared(_ id: String, _ title: String, _ p: FoundationPaths) -> CheckResult {
        CheckResult(id: id, title: title, level: .warn,
                    detail: "skipped: no shared folder at \(p.common.replacingOccurrences(of: p.home, with: "~")) (Settings › Foundations)")
    }

    public static func doorsCheck(_ p: FoundationPaths) -> CheckResult {
        guard p.hasShared else { return CheckResult(id: "doors", title: "Doors", level: .ok, detail: "optional: needs a shared folder") }
        let script = p.common + "/scripts/doors/ensure-doors.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            return CheckResult(id: "doors", title: "Doors", level: .ok, detail: "optional: not set up (no scripts/doors/ensure-doors.sh in the shared folder)")
        }
        let (rc, outText) = run("/bin/bash", [script, "--check"], cwd: p.projects)
        return CheckResult(id: "doors", title: "Doors", level: rc == 0 ? .ok : .fail, detail: lastLine(outText),
                           fix: rc == 0 ? nil : "bash \(script)")
    }

    public static func mcpCheck(_ p: FoundationPaths) -> CheckResult {
        guard p.hasShared else { return CheckResult(id: "mcp", title: "MCP servers", level: .ok, detail: "optional: needs a shared folder") }
        let script = p.common + "/scripts/mcp/sync-mcp.py"
        guard FileManager.default.fileExists(atPath: script) else {
            return CheckResult(id: "mcp", title: "MCP servers", level: .ok, detail: "optional: not set up (no scripts/mcp/sync-mcp.py in the shared folder)")
        }
        // An app started from Finder has a bare PATH, where python3 is the system 3.9 (no tomllib); use one that has it.
        guard let py = python3(home: p.home) else {
            return CheckResult(id: "mcp", title: "MCP servers", level: .warn, detail: "no Python 3.11 or newer found for sync-mcp.py",
                               fix: "brew install python@3.12")
        }
        let (rc, outText) = run(py, [script, "--check"], cwd: p.projects)
        return CheckResult(id: "mcp", title: "MCP servers", level: rc == 0 ? .ok : .fail, detail: lastLine(outText),
                           fix: rc == 0 ? nil : "\(py) \(script)")
    }

    /// The first python3 that can import tomllib (3.11+), from the usual install places.
    public static func python3(home: String = NSHomeDirectory()) -> String? {
        let candidates = ["/opt/homebrew/bin/python3", "/usr/local/bin/python3",
                          "/Library/Frameworks/Python.framework/Versions/Current/bin/python3",
                          home + "/opt/anaconda3/bin/python3", home + "/miniconda3/bin/python3", "/usr/bin/python3"]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) && run($0, ["-c", "import tomllib"], timeout: 5).0 == 0 }
    }

    /// Every link `sync-skills.sh --dry-run` says should exist, checked on disk (read-only).
    public static func skillsCheck(_ p: FoundationPaths) -> CheckResult {
        let script = p.agenticEngineering + "/scripts/sync-skills.sh"
        guard FileManager.default.fileExists(atPath: script) else {
            return CheckResult(id: "skills", title: "Skills", level: .fail, detail: "agentic-engineering sync-skills.sh not found at \(script)")
        }
        let (rc, outText) = run("/bin/bash", [script, "--dry-run"], cwd: p.agenticEngineering, timeout: 30)
        guard rc == 0 else { return CheckResult(id: "skills", title: "Skills", level: .warn, detail: "dry run failed: " + lastLine(outText)) }
        let links = expectedLinks(outText)
        var bad: [String: Int] = [:]
        for l in links where (try? FileManager.default.destinationOfSymbolicLink(atPath: l.dest)) != l.source {
            bad[homeLabel(l.dest, home: p.home), default: 0] += 1
        }
        let skills = Set(links.map { ($0.source as NSString).lastPathComponent }).count
        let homes = Set(links.map { homeLabel($0.dest, home: p.home) }).sorted()
        if bad.isEmpty {
            return CheckResult(id: "skills", title: "Skills", level: .ok,
                               detail: "\(skills) skills linked into \(homes.count) agent homes (\(homes.joined(separator: ", ")))")
        }
        let summary = bad.sorted { $0.key < $1.key }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
        return CheckResult(id: "skills", title: "Skills", level: .fail, detail: "links missing or stale: \(summary)",
                           fix: "bash \(script)")
    }

    public struct SkillLink: Equatable, Sendable { public var source: String; public var dest: String }

    /// Parse `[DRY] ln -sfn <source> <dest>` lines.
    public static func expectedLinks(_ text: String) -> [SkillLink] {
        text.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("[DRY] ln -sfn ") else { return nil }
            let parts = line.dropFirst("[DRY] ln -sfn ".count).split(separator: " ")
            guard parts.count == 2 else { return nil }
            return SkillLink(source: String(parts[0]), dest: String(parts[1]))
        }
    }

    /// "~/.claude/skills/x" → "Claude"; "~/.codex/skills/x" → "Codex"; …
    public static func homeLabel(_ dest: String, home: String) -> String {
        let rel = dest.hasPrefix(home) ? String(dest.dropFirst(home.count)) : dest
        if rel.hasPrefix("/.claude") { return "Claude" }
        if rel.hasPrefix("/.codex") { return "Codex" }
        if rel.hasPrefix("/.kimi") { return "Kimi" }
        if rel.hasPrefix("/.gemini") { return "Gemini/agy" }
        return (rel as NSString).deletingLastPathComponent
    }

    /// Each agent: installed, and signed in (Claude: the account email from its own config). One Claude account is
    /// enough; a second (~/.claude-2) is checked only when it exists.
    public static func agentChecks(_ p: FoundationPaths) -> [CheckResult] {
        let fm = FileManager.default
        var out: [CheckResult] = []
        let accounts = AccountResolver.claudeAccounts(home: p.home)
        let emails = accounts.map { ($0, AccountResolver.claudeEmail(AccountResolver.claudeConfigFile($0, home: p.home))) }
        out.append(CheckResult(id: "claude", title: accounts.joined(separator: " · "),
                               level: emails.allSatisfy { $0.1 != nil } ? .ok : .warn,
                               detail: emails.map { "\($0.0) \($0.1 ?? "not signed in")" }.joined(separator: " · ")))
        let others: [(String, String, String)] = [
            ("codex", "Codex", p.home + "/.codex/auth.json"),
            ("kimi", "Kimi", p.home + "/.kimi-code/credentials"),
            ("agy", "Antigravity", p.home + "/.gemini"),
        ]
        for (cmd, title, login) in others {
            let installed = AccountResolver.installed(cmd, home: p.home)
            let signed = fm.fileExists(atPath: login)
            out.append(CheckResult(id: cmd, title: title, level: installed && signed ? .ok : .warn,
                                   detail: !installed ? "\(cmd) not found on PATH" : signed ? "installed · signed in" : "installed · no login found (\(login))"))
        }
        return out
    }

    /// Tools One Roof itself needs: herdr (runs every session) and git (diffs, branches, review). `run` is injectable
    /// for tests. Missing tools are reported, never blocking.
    public static func requiredTools(home: String = NSHomeDirectory(),
                                     installed: (String) -> Bool = { AccountResolver.installed($0) },
                                     run: (String, [String]) -> Int32 = { Foundations.run($0, $1, timeout: 10).0 }) -> [CheckResult] {
        let herdr = installed("herdr")
        let git = run("/usr/bin/git", ["--version"]) == 0
        return [
            CheckResult(id: "tool-herdr", title: "herdr", level: herdr ? .ok : .fail,
                        detail: herdr ? "found" : "not found: sessions need herdr. Install with `brew install herdr`",
                        fix: herdr ? nil : "brew install herdr"),
            CheckResult(id: "tool-git", title: "git", level: git ? .ok : .fail,
                        detail: git ? "found" : "not working: install the Xcode Command Line Tools: `xcode-select --install`",
                        fix: git ? nil : "xcode-select --install"),
        ]
    }

    public static func agenticEngineeringCheck(_ p: FoundationPaths) -> CheckResult {
        guard FileManager.default.fileExists(atPath: p.skills) else {
            return CheckResult(id: "ae", title: "Agentic engineering", level: .fail, detail: "not found at \(p.agenticEngineering)")
        }
        let shown = p.agenticEngineering.replacingOccurrences(of: p.home, with: "~")
        let (rc, head) = run("/usr/bin/git", ["-C", p.agenticEngineering, "log", "-1", "--format=%h %cr", "--", "."], timeout: 5)
        guard rc == 0, !head.isEmpty else {
            // The bundled copy inside the app is not a git checkout.
            return CheckResult(id: "ae", title: "Agentic engineering", level: .ok, detail: "read from \(shown) · \(skills(p).count) skills")
        }
        let (_, dirty) = run("/usr/bin/git", ["-C", p.agenticEngineering, "status", "--porcelain", "--", "."], timeout: 5)
        let n = dirty.split(separator: "\n").count
        return CheckResult(id: "ae", title: "Agentic engineering", level: .ok,
                           detail: "read from \(shown) · \(lastLine(head))" + (n > 0 ? " · \(n) uncommitted" : ""))
    }

    public static func overall(_ r: [CheckResult]) -> CheckLevel { r.map(\.level).max() ?? .ok }

    // MARK: Hooks

    public struct Hook: Identifiable, Equatable, Sendable {
        public var id: String { event + ":" + command }
        public var event: String
        public var matcher: String?
        public var command: String
        /// The script the command runs (first path-looking word), if any.
        public var script: String
        public var scriptExists: Bool
    }

    public static func parseHooks(_ settings: [String: Any]) -> [Hook] {
        guard let hooks = settings["hooks"] as? [String: Any] else { return [] }
        var out: [Hook] = []
        for (event, value) in hooks.sorted(by: { $0.key < $1.key }) {
            for group in value as? [[String: Any]] ?? [] {
                for h in group["hooks"] as? [[String: Any]] ?? [] {
                    guard let cmd = h["command"] as? String else { continue }
                    let script = cmd.split(separator: " ").map(String.init)
                        .first { $0.contains("/") && !$0.hasPrefix("-") }
                        .map { ($0.replacingOccurrences(of: "\"", with: "") as NSString).expandingTildeInPath } ?? ""
                    let exists = script.isEmpty || FileManager.default.fileExists(atPath: script)
                    out.append(Hook(event: event, matcher: group["matcher"] as? String, command: cmd, script: script, scriptExists: exists))
                }
            }
        }
        return out
    }

    public static func hooks(_ p: FoundationPaths = FoundationPaths()) -> [Hook] {
        guard let d = FileManager.default.contents(atPath: p.claudeSettings),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return parseHooks(j)
    }

    // MARK: Skills index (read from the agentic-engineering repo, never copied)

    public struct SkillInfo: Identifiable, Equatable, Sendable {
        public var id: String { track + "/" + name }
        public var name: String
        public var track: String
        public var description: String
        public var path: String
        /// Agent homes that have this skill linked (Claude, Codex, Kimi, Gemini/agy).
        public var linkedIn: [String]
    }

    public static func skills(_ p: FoundationPaths = FoundationPaths()) -> [SkillInfo] {
        let fm = FileManager.default
        let homes: [(String, String)] = [("Claude", p.home + "/.claude/skills"), ("Codex", p.home + "/.codex/skills"),
                                         ("Kimi", p.home + "/.kimi-code/skills"), ("Gemini/agy", p.home + "/.gemini/config/skills")]
        var out: [SkillInfo] = []
        for track in ((try? fm.contentsOfDirectory(atPath: p.skills)) ?? []).sorted() where !track.hasPrefix(".") {
            let tdir = p.skills + "/" + track
            for slug in ((try? fm.contentsOfDirectory(atPath: tdir)) ?? []).sorted() {
                let file = tdir + "/" + slug + "/SKILL.md"
                guard let text = try? String(contentsOfFile: file, encoding: .utf8) else { continue }
                let fm1 = frontmatter(text)
                let linked = homes.filter { fm.fileExists(atPath: $0.1 + "/" + slug) }.map(\.0)
                out.append(SkillInfo(name: fm1["name"] ?? slug, track: track, description: fm1["description"] ?? "",
                                     path: tdir + "/" + slug, linkedIn: linked))
            }
        }
        return out
    }

    /// `key: value` lines of a `---` frontmatter block (quotes stripped).
    public static func frontmatter(_ text: String) -> [String: String] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return [:] }
        var out: [String: String] = [:]
        for l in lines.dropFirst() {
            if l.trimmingCharacters(in: .whitespaces) == "---" { break }
            guard let i = l.firstIndex(of: ":"), !l.hasPrefix(" ") else { continue }
            let k = String(l[..<i]).trimmingCharacters(in: .whitespaces)
            var v = String(l[l.index(after: i)...]).trimmingCharacters(in: .whitespaces)
            if v.count >= 2, v.first == "\"", v.last == "\"" { v = String(v.dropFirst().dropLast()) }
            out[k] = v
        }
        return out
    }

    // MARK: Handoffs and gotchas (the shared record)

    public struct DocFile: Identifiable, Equatable, Sendable {
        public var id: String { path }
        public var path: String
        public var title: String
        public var workstream: String?
        public var modified: Date
    }

    /// Newest handoffs first, at most one per workstream unless `all`.
    public static func handoffs(_ p: FoundationPaths = FoundationPaths(), all: Bool = false, limit: Int = 40) -> [DocFile] {
        var files = listDocs(p.handoffs).filter { $0.path.hasSuffix(".txt") || $0.path.hasSuffix(".md") }
        files.sort { $0.title > $1.title }   // names start with the date and time
        guard !all else { return Array(files.prefix(limit)) }
        var seen = Set<String>(), out: [DocFile] = []
        for f in files {
            let key = f.workstream ?? f.title
            if seen.insert(key).inserted { out.append(f) }
            if out.count >= limit { break }
        }
        return out
    }

    public static func gotchas(_ p: FoundationPaths = FoundationPaths(), limit: Int = 30) -> [DocFile] {
        Array(listDocs(p.gotchas).filter { $0.path.hasSuffix(".md") && !$0.path.hasSuffix("_INDEX.md") }
            .sorted { $0.title > $1.title }.prefix(limit))
    }

    static func listDocs(_ dir: String) -> [DocFile] {
        let fm = FileManager.default
        return ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).compactMap { name in
            let path = dir + "/" + name
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir), !isDir.boolValue, !name.hasPrefix(".") else { return nil }
            let date = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
            let ws = Workspace.workstream(in: name.replacingOccurrences(of: "_", with: " "))
            return DocFile(path: path, title: (name as NSString).deletingPathExtension, workstream: ws, modified: date)
        }
    }
}

public extension Workspace {
    /// Claude's folder naming: every non-alphanumeric character becomes "-".
    static func mangle(_ path: String) -> String { String(path.map { $0.isLetter || $0.isNumber ? $0 : "-" }) }
}
