import Foundation

// The decision builder (v2, ENGINES §3): when roofd reports an agent blocked, read the permission prompt off its
// terminal and turn it into one card with the command, the agent's own why, what it touches, the risk, what happens
// if you say no and how often you said yes before. Answers are data (keys to send); the app sends them via roofd.
// Nothing here answers on its own: humans stay in the loop.

public enum DecisionKind: String, Codable, CaseIterable, Sendable {
    case runCommand, editFile, approvePlan, network, install, push, other
}

public enum Risk: String, Codable, CaseIterable, Sendable {
    case low, plan, high
    public var label: String { switch self { case .low: return "Low"; case .plan: return "Plan"; case .high: return "High" } }
}

public enum Answer: String, Codable, CaseIterable, Sendable {
    case allowOnce, always, deny, reply
    public var isAllow: Bool { self == .allowOnce || self == .always }
}

public struct DecisionHistory: Codable, Equatable, Sendable {
    public var similarAllowed: Int
    public var similarDenied: Int
    /// "Always allow swift test in labs/oneroof", after 3 allows and no denies.
    public var ruleSuggestion: String?
    public init(similarAllowed: Int = 0, similarDenied: Int = 0, ruleSuggestion: String? = nil) {
        self.similarAllowed = similarAllowed; self.similarDenied = similarDenied; self.ruleSuggestion = ruleSuggestion
    }
}

public struct Decision: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var sessionId: String
    public var agent: AgentKind
    public var kind: DecisionKind
    public var command: String?
    public var path: String?
    public var planId: UUID?
    public var why: String
    public var whySource: CaptionSource
    /// True when the agent gave no reason: the card shows "The agent didn't say why. Ask it:" with Reply focused.
    public var whyMissing: Bool
    public var touches: String
    public var risk: Risk
    public var ifNo: String
    public var where_: String
    public var history: DecisionHistory
    /// The pattern history and rules match on, e.g. "swift test"; and the repo it ran in.
    public var pattern: String
    public var repo: String
    public var askedAt: Date
    public var answeredAt: Date?
    public var answer: Answer?
    public var replyText: String?

    public init(id: UUID = UUID(), sessionId: String, agent: AgentKind, kind: DecisionKind, command: String? = nil, path: String? = nil,
                planId: UUID? = nil, why: String, whySource: CaptionSource = .heuristic, whyMissing: Bool = false, touches: String,
                risk: Risk, ifNo: String, where_: String = "", history: DecisionHistory = DecisionHistory(), pattern: String,
                repo: String, askedAt: Date = Date(), answeredAt: Date? = nil, answer: Answer? = nil, replyText: String? = nil) {
        self.id = id; self.sessionId = sessionId; self.agent = agent; self.kind = kind; self.command = command; self.path = path
        self.planId = planId; self.why = why; self.whySource = whySource; self.whyMissing = whyMissing; self.touches = touches
        self.risk = risk; self.ifNo = ifNo; self.where_ = where_; self.history = history; self.pattern = pattern; self.repo = repo
        self.askedAt = askedAt; self.answeredAt = answeredAt; self.answer = answer; self.replyText = replyText
    }

    public var isOpen: Bool { answer == nil }

    /// "Claude wants to run swift test".
    public var title: String {
        let who = agent.displayName
        switch kind {
        case .approvePlan: return "\(who) wants you to approve a plan"
        case .editFile: return "\(who) wants to edit \(((path ?? "a file") as NSString).lastPathComponent)"
        case .push: return "\(who) wants to push"
        case .install: return "\(who) wants to install \(command.map(CommandAnalyzer.installTarget) ?? "a package")"
        case .network: return "\(who) wants to use the network"
        case .runCommand, .other: return "\(who) wants to run \(command.map(CaptionEngine.mainCommand) ?? "a command")"
        }
    }
}

/// An "Always allow <pattern> in <repo>" rule (also written to the agent's own allow-list where it has one, never silently).
public struct DecisionRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var pattern: String
    public var repo: String
    public var createdAt: Date
    public init(id: UUID = UUID(), pattern: String, repo: String, createdAt: Date = Date()) {
        self.id = id; self.pattern = pattern; self.repo = repo; self.createdAt = createdAt
    }
    public func matches(_ d: Decision) -> Bool { d.pattern == pattern && d.repo == repo }
}

// MARK: - Reading the prompt

/// A permission prompt read off an agent's terminal.
public struct PromptMatch: Equatable, Sendable {
    public enum Ask: String, Sendable { case command, edit, fetch, other }
    public struct Option: Equatable, Sendable {
        public var label: String
        /// What to type to pick it: the CLI's hotkey ("y", "a", "esc") or the option number.
        public var key: String
    }
    public var agent: AgentKind
    public var ask: Ask
    /// The question line ("Do you want to proceed?").
    public var question: String
    public var command: String?
    public var path: String?
    public var url: String?
    public var options: [Option]
    /// Index of the first prompt line in the text's lines (the why is read from above it).
    public var startLine: Int
}

public enum DecisionMatcher {
    /// Reads the most recent permission prompt from terminal text. Tries `agent`'s matcher first, then the others.
    public static func match(_ text: String, agent: AgentKind? = nil) -> PromptMatch? {
        let all = TerminalText.lines(text)
        let base = max(0, all.count - 80)
        let lines = Array(all[base...]).map(TerminalText.unboxed)
        let order: [AgentKind] = agent.map { a in [a] + [.claude, .codex, .kimi, .gemini, .agy].filter { $0 != a } }
            ?? [.claude, .codex, .kimi, .gemini, .agy]
        for k in order {
            if var m = matcher(k)(lines) { m.startLine += base; return m }
        }
        return nil
    }

    static func matcher(_ k: AgentKind) -> ([String]) -> PromptMatch? {
        switch k {
        case .claude: return claude
        case .codex: return codex
        case .kimi: return kimi
        case .gemini: return gemini
        case .agy: return antigravity
        case .shell: return { _ in nil }
        }
    }

    // Claude Code:  Bash command / <cmd> / <description> / Do you want to proceed? / ❯ 1. Yes / 2. Yes, and don't ask…
    static func claude(_ lines: [String]) -> PromptMatch? {
        guard let q = lines.lastIndex(where: { $0.hasPrefix("Do you want to") }) else { return nil }
        let opts = options(after: q, in: lines)
        guard !opts.isEmpty else { return nil }
        let header = lines[..<q].lastIndex { ["Bash command", "Edit file", "Create file", "Write file", "Fetch", "Read file", "Web fetch", "Tool use"].contains($0) }
        let start = header ?? q
        let body = header.map { lines[($0 + 1)..<q].filter { !$0.isEmpty && !TerminalText.isChrome($0) } } ?? []
        var m = PromptMatch(agent: .claude, ask: .other, question: lines[q], options: opts, startLine: start)
        let question = lines[q]
        switch header.map({ lines[$0] }) {
        case "Bash command"?:
            m.ask = .command; m.command = body.first
        case "Edit file"?, "Create file"?, "Write file"?:
            m.ask = .edit; m.path = body.first(where: { $0.contains("/") || $0.contains(".") })
        case "Fetch"?, "Web fetch"?:
            m.ask = .fetch; m.url = body.first(where: { $0.hasPrefix("http") })
        default:
            if let r = question.range(of: "make this edit to ") {
                m.ask = .edit; m.path = String(question[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            } else if question.hasPrefix("Do you want to create ") {
                m.ask = .edit; m.path = String(question.dropFirst("Do you want to create ".count)).trimmingCharacters(in: CharacterSet(charactersIn: "? "))
            }
        }
        return m
    }

    // Codex: "Allow command?" or "Would you like to run the following command?" / $ cmd / › 1. Yes, proceed (y) …
    static func codex(_ lines: [String]) -> PromptMatch? {
        guard let q = lines.lastIndex(where: {
            $0.hasPrefix("Would you like to run the following command") || $0.hasPrefix("Allow command?")
                || $0.hasPrefix("Would you like to make the following edits") || $0.hasPrefix("Allow edits?")
        }) else { return nil }
        let opts = options(after: q, in: lines)
        guard !opts.isEmpty else { return nil }
        var m = PromptMatch(agent: .codex, ask: lines[q].contains("edit") ? .edit : .command, question: lines[q], options: opts, startLine: q)
        let region = lines[(q + 1)...].prefix { !isOption($0) }
        if m.ask == .command {
            m.command = region.first(where: { $0.hasPrefix("$ ") }).map { String($0.dropFirst(2)) }
        } else {
            m.path = region.compactMap { l -> String? in
                let s = l.replacingOccurrences(of: #"^[└•]\s*(Edit|Edited|Add|Added|Update|Updated)?\s*"#, with: "", options: .regularExpression)
                let p = s.replacingOccurrences(of: #"\s*\(\+\d+ -\d+\)$"#, with: "", options: .regularExpression)
                return p.contains("/") || p.contains(".") ? p : nil
            }.first
        }
        return m
    }

    // Kimi Code (2026-10, captured from a live pane): "▶ Run this command?" / "cwd: …" / "$ <cmd>" (wrapped lines indented)
    // / "▶ 1. Approve once" · "2. Approve for this session" · "3. Reject" · "4. Reject with feedback".
    static func kimiPanel(_ lines: [String]) -> PromptMatch? {
        let trimmed = lines.map { $0.trimmingCharacters(in: .whitespaces) }
        guard let q = trimmed.lastIndex(where: { $0.range(of: #"^(▶\s*)?(Run|Edit|Write|Apply|Fetch|Approve) this[^?]{0,60}\?$"#, options: .regularExpression) != nil }) else { return nil }
        let question = trimmed[q].replacingOccurrences(of: #"^▶\s*"#, with: "", options: .regularExpression)
        var opts: [PromptMatch.Option] = []
        var cmd: [String] = []
        var path: String?
        var i = q + 1
        while i < trimmed.count {
            let l = trimmed[i]
            if let r = l.range(of: #"^(▶\s*)?(\d)\.\s+"#, options: .regularExpression) {
                let num = l[r].filter(\.isNumber)
                opts.append(.init(label: String(l[r.upperBound...]), key: String(num)))
            } else if l.hasPrefix("$ ") {
                cmd.append(String(l.dropFirst(2)))
            } else if !cmd.isEmpty && opts.isEmpty && !l.isEmpty && !l.hasPrefix("cwd:") {
                cmd.append(l)
            } else if l.hasPrefix("path:") || l.hasPrefix("file:") {
                path = l.split(separator: ":", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
            }
            i += 1
        }
        guard opts.count >= 2 else { return nil }
        var m = PromptMatch(agent: .kimi, ask: .other, question: question, options: opts, startLine: q)
        if !cmd.isEmpty { m.ask = .command; m.command = cmd.joined(separator: " ") }
        else if let path { m.ask = .edit; m.path = path }
        return m
    }

    // Kimi: "Shell: <cmd>" or "WriteFile: <path>" / Allow? / options
    static func kimi(_ lines: [String]) -> PromptMatch? {
        if let m = kimiPanel(lines) { return m }
        guard let q = lines.lastIndex(where: { $0 == "Allow?" || $0.hasPrefix("Allow? ") }) else { return nil }
        var opts = options(after: q, in: lines)
        if opts.isEmpty { opts = inlineOptions(lines[q]) }
        guard !opts.isEmpty else { return nil }
        var m = PromptMatch(agent: .kimi, ask: .other, question: "Allow?", options: opts, startLine: q)
        // "Shell: cmd" on one line, or "Shell is requesting approval to run command:" with the command below it.
        func value(_ i: Int, after r: Range<String.Index>) -> String {
            let rest = String(lines[i][r.upperBound...]).trimmingCharacters(in: .whitespaces)
            return rest.isEmpty ? (lines[(i + 1)..<q].first { !$0.isEmpty } ?? "") : rest
        }
        for i in stride(from: q - 1, through: max(0, q - 8), by: -1) {
            let l = lines[i]
            if let r = l.range(of: #"^(Shell|Bash)( is requesting approval to run command)?:\s*"#, options: .regularExpression) {
                m.ask = .command; m.command = value(i, after: r); m.startLine = i; break
            }
            if let r = l.range(of: #"^(WriteFile|StrReplaceFile|PatchFile|Edit)( is requesting approval to edit)?:\s*"#, options: .regularExpression) {
                m.ask = .edit; m.path = value(i, after: r); m.startLine = i; break
            }
            if let r = l.range(of: #"^(FetchURL|SearchWeb):\s*"#, options: .regularExpression) {
                m.ask = .fetch; m.url = value(i, after: r); m.startLine = i; break
            }
        }
        if m.command == nil, m.ask == .other, q > 0 {
            // "Approval required" box with the command on its own line above "Allow?"
            if let c = lines[..<q].last(where: { !$0.isEmpty && !TerminalText.isChrome($0) && !$0.hasPrefix("Approval") }) {
                m.ask = .command; m.command = c
            }
        }
        return m
    }

    // Gemini CLI: "?  Shell <cmd> (<desc>)" / <cmd> / "Allow execution of: 'rm'?" / ● 1. Yes, allow once …
    static func gemini(_ lines: [String]) -> PromptMatch? {
        guard let q = lines.lastIndex(where: {
            $0.hasPrefix("Allow execution") || $0.hasPrefix("Apply this change?")
        }) else { return nil }
        let opts = options(after: q, in: lines)
        guard !opts.isEmpty else { return nil }
        let head = lines[..<q].lastIndex { $0.hasPrefix("?") }
        var m = PromptMatch(agent: .gemini, ask: lines[q].hasPrefix("Apply") ? .edit : .command, question: lines[q], options: opts, startLine: head ?? q)
        if let h = head {
            let s = lines[h].dropFirst().trimmingCharacters(in: .whitespaces)
            let tool = s.prefix { !$0.isWhitespace }
            var arg = s.dropFirst(tool.count).trimmingCharacters(in: .whitespaces)
            arg = arg.replacingOccurrences(of: #"\s+\([^()]*\)$"#, with: "", options: .regularExpression)
            if m.ask == .command { m.command = arg } else { m.path = arg }
        }
        return m
    }

    // Antigravity CLI: "Antigravity wants to run a command:" / `cmd` / "Run this command? (y)es / (a)lways / (n)o"
    static func antigravity(_ lines: [String]) -> PromptMatch? {
        guard let q = lines.lastIndex(where: { $0.hasPrefix("Run this command?") || $0.hasPrefix("Apply these edits?") }) else { return nil }
        var opts = options(after: q, in: lines)
        if opts.isEmpty { opts = inlineOptions(lines[q]) }
        guard !opts.isEmpty else { return nil }
        let head = lines[..<q].lastIndex { $0.hasPrefix("Antigravity wants to") }
        var m = PromptMatch(agent: .agy, ask: lines[q].hasPrefix("Apply") ? .edit : .command,
                            question: String(lines[q].prefix { $0 != "?" }) + "?", options: opts, startLine: head ?? q)
        let body = lines[((head ?? q - 1) + 1)..<q].filter { !$0.isEmpty }
        let first = body.first?.trimmingCharacters(in: CharacterSet(charactersIn: "` "))
        if m.ask == .command { m.command = first } else { m.path = first }
        return m
    }

    static func isOption(_ l: String) -> Bool {
        l.range(of: #"^[❯›>●▸]?\s*\d+\.\s+\S"#, options: .regularExpression) != nil
    }

    /// Numbered options under the question: "❯ 1. Yes", "2. Yes, and don't ask again (a)", "3. No … (esc)".
    static func options(after q: Int, in lines: [String]) -> [PromptMatch.Option] {
        var out: [PromptMatch.Option] = []
        for l in lines[(q + 1)...] {
            if l.isEmpty && out.isEmpty { continue }
            guard isOption(l) else { if out.isEmpty { continue } else { break } }
            let s = l.replacingOccurrences(of: #"^[❯›>●▸]?\s*"#, with: "", options: .regularExpression)
            let num = String(s.prefix { $0.isNumber })
            var label = s.drop { $0.isNumber || $0 == "." }.trimmingCharacters(in: .whitespaces)
            var key = num
            if let r = label.range(of: #"\((y|a|n|p|esc|shift\+tab)\)$"#, options: .regularExpression) {
                let hk = label[r].dropFirst().dropLast()
                if hk != "shift+tab" { key = hk == "esc" ? "\u{1B}" : String(hk) }
                label = label[..<r.lowerBound].trimmingCharacters(in: .whitespaces)
            }
            out.append(.init(label: label, key: key))
        }
        return out
    }

    /// "Allow? [y]es / [a]lways / [n]o" or "(y)es / (a)lways / (n)o" on one line.
    static func inlineOptions(_ l: String) -> [PromptMatch.Option] {
        guard let re = try? NSRegularExpression(pattern: #"[\[\(]([a-z])[\]\)]([a-z ]*)"#) else { return [] }
        return re.matches(in: l, range: NSRange(l.startIndex..., in: l)).compactMap { m in
            guard let k = Range(m.range(at: 1), in: l), let rest = Range(m.range(at: 2), in: l) else { return nil }
            let key = String(l[k])
            return .init(label: (key + l[rest]).trimmingCharacters(in: .whitespaces), key: key)
        }
    }
}

// MARK: - What a command touches

public struct Touches: Equatable, Sendable {
    public enum Class: String, CaseIterable, Sendable {
        case readOnly, writesRepo, writesOutside, network, installs, deletes, secrets, gitChanges, unknown
    }
    public var classes: Set<Class>
    /// Folders a build/test writes to (".build/", "target/").
    public var buildOutputs: [String]
    public var writePaths: [String]
    public var hosts: [String]
    public var sentence: String
    public var isTest: Bool
    public var isPush: Bool
}

public enum CommandAnalyzer {
    static let readOnly: Set<String> = ["ls", "cat", "head", "tail", "less", "grep", "rg", "ag", "wc", "pwd", "echo", "which", "file",
                                        "stat", "du", "df", "tree", "diff", "jq", "sort", "uniq", "date", "whoami", "true", "test", "type"]
    static let networkTools: Set<String> = ["curl", "wget", "ssh", "scp", "gh", "glab", "kubectl", "helm", "nc", "http", "aws", "gcloud", "az", "ping"]
    static let deleteTools: Set<String> = ["rm", "rmdir", "unlink", "shred", "truncate"]
    static let writeTools: Set<String> = ["cp", "mv", "mkdir", "touch", "ln", "chmod", "chown", "tee", "patch", "install"]
    static let secretTools: Set<String> = ["env", "printenv", "security", "bw", "op", "pass", "gpg"]
    static let secretHints = [".env", ".ssh/", ".aws/", ".netrc", "id_rsa", "id_ed25519", ".pem", ".key", "credentials", "secret", "token", "keychain"]

    /// Static analysis of a shell command run in `repo` (absolute path; nil = unknown).
    public static func analyze(_ command: String, repo: String?) -> Touches {
        var t = Touches(classes: [], buildOutputs: [], writePaths: [], hosts: [], sentence: "", isTest: false, isPush: false)
        var gitWhat: [String] = [], installs: [String] = [], deletes: [String] = [], secrets: [String] = []
        var unknown: [String] = []

        for seg in segments(command) {
            var words = Session.parseArgs(seg.text)
            while let f = words.first, f.contains("="), !f.hasPrefix("-") { words.removeFirst() }   // FOO=1 cmd
            if words.first == "sudo" { words.removeFirst(); t.classes.insert(.writesOutside) }
            guard let prog0 = words.first else { continue }
            let prog = (prog0 as NSString).lastPathComponent
            let args = prog == "git" ? Self.withoutGitGlobals(Array(words.dropFirst())) : Array(words.dropFirst())
            let sub = args.first { !$0.hasPrefix("-") } ?? ""

            for target in seg.redirects { write(target, repo: repo, into: &t) }
            if words.contains(where: { w in secretHints.contains { w.lowercased().contains($0) } }) { secrets.append(words.joined(separator: " ")) }

            switch prog {
            case "cd", "export", "set", "source", ".":
                if prog == "export", args.contains(where: { $0.uppercased().contains("TOKEN") || $0.uppercased().contains("KEY") || $0.uppercased().contains("SECRET") }) {
                    secrets.append("an exported secret")
                }
            case _ where readOnly.contains(prog):
                t.classes.insert(.readOnly)
            case "find":
                t.classes.insert(.readOnly)
                if args.contains("-delete") || args.contains("-exec") && args.contains("rm") { deletes.append("files found by find") }
            case "sed", "perl":
                if args.contains(where: { $0.hasPrefix("-i") }) { args.filter { !$0.hasPrefix("-") }.dropFirst().forEach { write($0, repo: repo, into: &t) } }
                else { t.classes.insert(.readOnly) }
            case "git":
                switch sub {
                case "status", "diff", "log", "show", "blame", "rev-parse", "ls-files", "grep", "describe", "shortlog", "reflog": t.classes.insert(.readOnly)
                case "branch", "tag", "remote", "stash":
                    if args.count == 1 { t.classes.insert(.readOnly) } else { gitWhat.append("git " + sub) }
                case "push": t.classes.insert(.network); t.isPush = true; gitWhat.append("pushes"); t.hosts.append("the git remote")
                case "pull", "fetch", "clone": t.classes.insert(.network); t.hosts.append("the git remote")
                    if sub == "pull" { gitWhat.append("merges from the remote") }
                case "reset" where args.contains("--hard"): deletes.append("uncommitted changes (git reset --hard)"); gitWhat.append("resets the branch")
                case "clean": deletes.append("untracked files (git clean)")
                case "checkout" where args.contains("--"), "restore": deletes.append("uncommitted changes to files")
                default: gitWhat.append(sub.isEmpty ? "changes git" : "git " + sub)
                }
            case "swift", "xcodebuild", "cargo", "go", "make", "gradle", "./gradlew", "gradlew", "mvn", "dotnet", "tsc", "bazel":
                if ["install", "get"].contains(sub) { installs.append(args.dropFirst().first ?? sub); t.classes.insert(.network) }
                else if prog == "swift", sub == "package", args.contains(where: { ["update", "resolve"].contains($0) }) { t.classes.insert(.network); t.hosts.append("package registries") }
                else {
                    t.isTest = t.isTest || sub == "test" || args.contains("test")
                    let out = ["swift": ".build/", "cargo": "target/", "go": "", "xcodebuild": "DerivedData", "gradle": "build/", "mvn": "target/"][prog] ?? ""
                    if !out.isEmpty { t.buildOutputs.append(out) }
                    t.classes.insert(.readOnly)
                }
            case "pytest", "jest", "vitest", "ruff", "swiftlint", "mypy", "eslint", "prettier", "black":
                t.isTest = t.isTest || ["pytest", "jest", "vitest"].contains(prog)
                if args.contains("--fix") || args.contains("--write") || (prog == "black") || (prog == "ruff" && sub == "format") { t.classes.insert(.writesRepo); t.writePaths.append("source files (formatter)") }
                else { t.classes.insert(.readOnly) }
            case "python", "python3", "node", "ruby", "bash", "sh", "zsh", "deno":
                if args.first == "-m", let mod = args.dropFirst().first {
                    if mod == "pytest" || mod == "unittest" { t.isTest = true; t.classes.insert(.readOnly) }
                    else if mod == "pip", args.contains("install") { installs.append(args.last ?? "packages"); t.classes.insert(.network); t.hosts.append("PyPI") }
                    else { unknown.append(prog + " -m " + mod) }
                } else if prog == "bash" || prog == "sh" || prog == "zsh", args.first == "-c" || args.first == "-lc", let inner = args.dropFirst().first {
                    let sub = analyze(inner, repo: repo)
                    t.classes.formUnion(sub.classes); t.buildOutputs += sub.buildOutputs; t.writePaths += sub.writePaths; t.hosts += sub.hosts
                    t.isTest = t.isTest || sub.isTest; t.isPush = t.isPush || sub.isPush
                } else {
                    unknown.append(([prog] + args.prefix(1)).joined(separator: " "))
                }
            case "pip", "pip3", "uv", "poetry", "pipx":
                if ["install", "add", "sync"].contains(sub) || args.contains("install") {
                    installs.append(args.last(where: { !$0.hasPrefix("-") && !["install", "add", "pip", "sync"].contains($0) }) ?? "packages")
                    t.classes.insert(.network); t.hosts.append("PyPI")
                } else if sub == "run", args.contains("pytest") { t.isTest = true; t.classes.insert(.readOnly) }
                else { t.classes.insert(.readOnly) }
            case "npm", "yarn", "pnpm", "bun":
                switch sub {
                case "install", "i", "ci", "add", "update", "upgrade":
                    let pkgs = args.dropFirst().filter { !$0.hasPrefix("-") }
                    installs.append(pkgs.isEmpty ? "the project's dependencies" : pkgs.joined(separator: " "))
                    t.classes.insert(.network); t.hosts.append("npm")
                    if args.contains("-g") || args.contains("--global") { t.classes.insert(.writesOutside) } else { t.buildOutputs.append("node_modules/") }
                case "test", "t": t.isTest = true; t.classes.insert(.readOnly)
                case "run":
                    let script = args.dropFirst().first ?? ""
                    if script.contains("test") { t.isTest = true; t.classes.insert(.readOnly) }
                    else if ["build", "lint", "typecheck", "check"].contains(script) { t.classes.insert(.readOnly); t.buildOutputs.append("dist/") }
                    else { unknown.append("npm run " + script) }
                case "publish": t.classes.insert(.network); t.isPush = true; t.hosts.append("npm"); gitWhat.append("publishes a package")
                default: unknown.append(prog + " " + sub)
                }
            case "brew", "apt", "apt-get", "gem", "port":
                if ["install", "upgrade", "reinstall", "tap"].contains(sub) { installs.append(args.dropFirst().first ?? "packages"); t.classes.insert(.network); t.classes.insert(.writesOutside); t.hosts.append(prog == "brew" ? "Homebrew" : prog) }
                else if ["uninstall", "remove"].contains(sub) { deletes.append(args.dropFirst().first ?? "a package") ; t.classes.insert(.writesOutside) }
                else { t.classes.insert(.readOnly) }
            case "docker":
                if ["pull", "push", "login", "run", "build"].contains(sub) { t.classes.insert(.network); t.hosts.append("a container registry") }
                if sub == "push" { t.isPush = true }
                if ["ps", "images", "logs", "inspect"].contains(sub) { t.classes.insert(.readOnly) }
            case "rsync":
                if args.contains(where: { $0.contains(":") }) { t.classes.insert(.network); t.hosts.append(args.first { $0.contains(":") }.map { String($0.prefix { $0 != ":" }) } ?? "a remote host") }
                args.filter { !$0.hasPrefix("-") }.last.map { write($0, repo: repo, into: &t) }
                if args.contains("--delete") { deletes.append("files missing from the source (rsync --delete)") }
            case _ where networkTools.contains(prog):
                t.classes.insert(.network)
                if let u = args.first(where: { $0.hasPrefix("http") }), let h = URL(string: u)?.host { t.hosts.append(h) } else { t.hosts.append(prog) }
                if prog == "gh", sub == "auth", args.contains("token") { secrets.append("your GitHub token") }
                if let o = args.firstIndex(where: { $0 == "-o" || $0 == "--output" }), o + 1 < args.count { write(args[o + 1], repo: repo, into: &t) }
            case _ where deleteTools.contains(prog):
                let targets = args.filter { !$0.hasPrefix("-") }
                deletes.append(targets.isEmpty ? "files" : targets.joined(separator: " "))
                targets.forEach { if !inside($0, repo: repo) { t.classes.insert(.writesOutside); t.writePaths.append($0) } }
            case _ where secretTools.contains(prog):
                if prog == "env", args.contains(where: { !$0.hasPrefix("-") && !$0.contains("=") }) { unknown.append(args.first { !$0.hasPrefix("-") && !$0.contains("=") }!) }
                else { secrets.append(prog == "security" ? "the keychain" : prog == "env" || prog == "printenv" ? "environment variables" : prog) }
            case _ where writeTools.contains(prog):
                let targets = args.filter { !$0.hasPrefix("-") }
                if let dest = prog == "mkdir" || prog == "touch" || prog == "chmod" ? nil : targets.last { write(dest, repo: repo, into: &t) }
                else { targets.forEach { write($0, repo: repo, into: &t) } }
            default:
                unknown.append(prog)
            }
        }

        if !installs.isEmpty { t.classes.insert(.installs) }
        if !deletes.isEmpty { t.classes.insert(.deletes) }
        if !secrets.isEmpty { t.classes.insert(.secrets) }
        if !gitWhat.isEmpty { t.classes.insert(.gitChanges) }
        if !unknown.isEmpty { t.classes.insert(.unknown) }
        if t.classes.isEmpty { t.classes.insert(.readOnly) }
        t.buildOutputs = unique(t.buildOutputs); t.hosts = unique(t.hosts); t.writePaths = unique(t.writePaths)
        if !t.writePaths.isEmpty || !t.classes.isDisjoint(with: [.writesOutside, .writesRepo, .deletes, .installs, .gitChanges, .unknown]) {
            t.classes.remove(.readOnly)
        }
        t.sentence = sentence(t, installs: installs, deletes: deletes, secrets: secrets, git: gitWhat, unknown: unknown)
        return t
    }

    /// The human sentence: "Reads the repo, writes only to .build/. No network. No git changes."
    static func sentence(_ t: Touches, installs: [String], deletes: [String], secrets: [String], git: [String], unknown: [String]) -> String {
        var parts: [String] = []
        if t.classes.contains(.writesOutside) {
            let w = t.writePaths.filter { $0.hasPrefix("/") || $0.hasPrefix("~") }
            parts.append("Writes outside the repo" + (w.isEmpty ? "." : " (\(w.prefix(2).joined(separator: ", ")))."))
        } else if t.classes.contains(.writesRepo) {
            parts.append("Writes inside the repo" + (t.writePaths.isEmpty ? "." : " (\(t.writePaths.prefix(3).joined(separator: ", ")))."))
        } else if !t.buildOutputs.isEmpty {
            parts.append("Reads the repo, writes only to \(t.buildOutputs.joined(separator: " and ")).")
        } else if unknown.isEmpty {
            parts.append("Reads the repo, writes nothing.")
        }
        if !unknown.isEmpty { parts.append("Runs \(unique(unknown).prefix(2).joined(separator: ", ")), which One Roof can't read; it could do anything.") }
        if !deletes.isEmpty { parts.append("Deletes \(deletes.prefix(2).joined(separator: "; ")).") }
        if !installs.isEmpty { parts.append("Installs \(installs.prefix(2).joined(separator: ", "))" + (t.hosts.isEmpty ? "." : " from \(t.hosts[0]).")) }
        if !secrets.isEmpty { parts.append("Reads secrets (\(unique(secrets).prefix(2).joined(separator: ", "))).") }
        if t.classes.contains(.network) {
            if installs.isEmpty { parts.append("Uses the network" + (t.hosts.isEmpty ? "." : " (\(t.hosts.prefix(2).joined(separator: ", "))).")) }
        } else {
            parts.append("No network.")
        }
        parts.append(git.isEmpty ? "No git changes." : "Git: \(unique(git).joined(separator: ", ")).")
        return parts.joined(separator: " ")
    }

    struct Segment { var text: String; var redirects: [String] }

    /// Split on && || ; | and pull out `> file` / `>> file` redirections.
    static func segments(_ command: String) -> [Segment] {
        var out: [Segment] = []
        var cur = "", quote: Character? = nil
        let chars = Array(command.replacingOccurrences(of: "\n", with: " ; "))
        var i = 0
        func push() {
            var text = cur.trimmingCharacters(in: .whitespaces), redirects: [String] = []
            if let re = try? NSRegularExpression(pattern: #"\d?>>?\s*([^\s;&|]+)"#) {
                for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
                    if let r = Range(m.range(at: 1), in: text) {
                        let target = String(text[r])
                        if !target.hasPrefix("&") && target != "/dev/null" { redirects.append(target) }
                    }
                    if let all = Range(m.range, in: text) { text.removeSubrange(all) }
                }
            }
            if !text.trimmingCharacters(in: .whitespaces).isEmpty || !redirects.isEmpty { out.append(Segment(text: text, redirects: redirects)) }
            cur = ""
        }
        while i < chars.count {
            let c = chars[i]
            if let q = quote { if c == q { quote = nil }; cur.append(c); i += 1; continue }
            if c == "\"" || c == "'" { quote = c; cur.append(c); i += 1; continue }
            if c == ";" || c == "|" || (c == "&" && i + 1 < chars.count && chars[i + 1] == "&") {
                if c == "&" || (c == "|" && i + 1 < chars.count && chars[i + 1] == "|") { i += 1 }
                push(); i += 1; continue
            }
            cur.append(c); i += 1
        }
        push()
        return out
    }

    static func inside(_ path: String, repo: String?) -> Bool {
        if path.hasPrefix("~") || path.hasPrefix("$HOME") { return repo.map { (path as NSString).expandingTildeInPath.hasPrefix($0 + "/") } ?? false }
        guard path.hasPrefix("/") else { return !path.hasPrefix("..") }
        guard let repo else { return false }
        let p = (path as NSString).standardizingPath
        return p == repo || p.hasPrefix(repo + "/")
    }

    static func write(_ path: String, repo: String?, into t: inout Touches) {
        t.writePaths.append(path)
        t.classes.insert(inside(path, repo: repo) ? .writesRepo : .writesOutside)
    }

    /// `git -C dir -c k=v push` → `push`.
    static func withoutGitGlobals(_ args: [String]) -> [String] {
        var out: [String] = [], skip = false
        for a in args {
            if skip { skip = false; continue }
            if a == "-C" || a == "-c" { skip = true; continue }
            out.append(a)
        }
        return out
    }

    static func unique(_ a: [String]) -> [String] { var s = Set<String>(); return a.filter { s.insert($0).inserted } }

    /// "npm install left-pad" → "left-pad".
    public static func installTarget(_ command: String) -> String {
        let w = Session.parseArgs(CaptionEngine.mainCommand(command))
        guard let i = w.firstIndex(where: { ["install", "add", "i"].contains($0) }) else { return "a package" }
        return w[(i + 1)...].first { !$0.hasPrefix("-") } ?? "the project's dependencies"
    }

    /// The pattern history and rules match on: program + subcommand ("swift test", "git push", "ls").
    public static func pattern(for command: String) -> String {
        var w = Session.parseArgs(CaptionEngine.mainCommand(command))
        guard let p0 = w.first else { return command }
        let prog = (p0 as NSString).lastPathComponent
        if prog == "git" { w = [p0] + withoutGitGlobals(Array(w.dropFirst())) }
        let withSub: Set<String> = ["git", "swift", "npm", "yarn", "pnpm", "cargo", "go", "docker", "kubectl", "gh", "pip", "pip3", "brew",
                                    "make", "uv", "xcodebuild", "helm", "poetry", "bun", "apt", "apt-get", "gem"]
        if prog == "python" || prog == "python3", w.count > 2, w[1] == "-m" { return "\(prog) -m \(w[2])" }
        if withSub.contains(prog), let sub = w.dropFirst().first(where: { !$0.hasPrefix("-") }) {
            if (prog == "npm" || prog == "yarn" || prog == "pnpm"), sub == "run", let s = w.drop(while: { $0 != "run" }).dropFirst().first { return "\(prog) run \(s)" }
            return "\(prog) \(sub)"
        }
        return prog
    }
}

// MARK: - Building the card

public struct DecisionContext: Sendable {
    public var sessionId: String
    public var agent: AgentKind
    /// The session's terminal text (the prompt plus what came before it).
    public var terminalText: String
    /// Absolute repo/worktree path the agent works in.
    public var repoPath: String
    public var objective: String?
    public var ticket: String?
    public var step: Int?
    public var steps: Int?
    public var added: Int?
    public var removed: Int?
    /// Earlier decisions (any session), for history.
    public var past: [Decision]
    public var now: Date
    /// For the repo label ("labs/oneroof").
    public var projectsRoot: String

    public init(sessionId: String, agent: AgentKind, terminalText: String, repoPath: String, objective: String? = nil, ticket: String? = nil,
                step: Int? = nil, steps: Int? = nil, added: Int? = nil, removed: Int? = nil, past: [Decision] = [], now: Date = Date(),
                projectsRoot: String = Workspace.projectsRoot) {
        self.sessionId = sessionId; self.agent = agent; self.terminalText = terminalText; self.repoPath = repoPath
        self.objective = objective; self.ticket = ticket; self.step = step; self.steps = steps; self.added = added; self.removed = removed
        self.past = past; self.now = now; self.projectsRoot = projectsRoot
    }
}

public enum DecisionBuilder {
    public static let noWhy = "The agent didn't say why. Ask it:"
    /// LAB-716: what the card says when no matcher recognises the prompt (was "One Roof could not read what this
    /// prompt does. Open the session to see it.").
    public static let unreadPrompt = "One Roof does not recognise this prompt, so it cannot tell what Allow or Deny will press. Check the prompt's own options in the terminal; you can also answer there by typing."

    /// LAB-716: the question of a prompt no matcher recognises: the last line with a "?", in full (it was cut to 80
    /// characters, which dropped the end of Claude's "Is this a project you created or one you trust? (Like your own
    /// code, …)"), else the last line; at most 400 characters.
    public static func fallbackQuestion(_ text: String) -> String {
        let lines = TerminalText.lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !TerminalText.isChrome($0) }
        let q = lines.last { $0.contains("?") } ?? lines.last ?? "The agent is waiting for you"
        return String(q.prefix(400))
    }

    /// A decision from a blocked session's terminal, or nil when no prompt can be read.
    public static func build(_ c: DecisionContext) -> Decision? {
        guard let m = DecisionMatcher.match(c.terminalText, agent: c.agent) else { return nil }
        let lines = TerminalText.lines(c.terminalText)
        let before = Array(lines[..<min(m.startLine, lines.count)])
        let why = whyText(before)

        var kind: DecisionKind
        var touches: Touches?
        var touchText: String
        var pattern: String
        switch m.ask {
        case .command:
            let cmd = m.command ?? ""
            let t = CommandAnalyzer.analyze(cmd, repo: c.repoPath)
            touches = t; touchText = t.sentence; pattern = CommandAnalyzer.pattern(for: cmd)
            kind = t.isPush ? .push : t.classes.contains(.installs) ? .install : t.classes.contains(.network) ? .network : .runCommand
        case .edit:
            let p = m.path ?? "a file"
            let abs = p.hasPrefix("/") ? p : c.repoPath + "/" + p
            let inRepo = CommandAnalyzer.inside(abs, repo: c.repoPath)
            touchText = inRepo ? "Edits \(p) inside the repo. No network. No git changes." : "Edits \(p), outside the repo. No network. No git changes."
            pattern = "edit " + ((p as NSString).deletingLastPathComponent.isEmpty ? "files" : (p as NSString).deletingLastPathComponent + "/")
            kind = .editFile
            touches = Touches(classes: [inRepo ? .writesRepo : .writesOutside], buildOutputs: [], writePaths: [p], hosts: [], sentence: touchText, isTest: false, isPush: false)
        case .fetch:
            let host = m.url.flatMap { URL(string: $0)?.host } ?? "the web"
            touchText = "Fetches \(host). Writes nothing. No git changes."
            pattern = "fetch " + host; kind = .network
            touches = Touches(classes: [.network], buildOutputs: [], writePaths: [], hosts: [host], sentence: touchText, isTest: false, isPush: false)
        case .other:
            touchText = "One Roof can't tell what this touches; read the prompt in the terminal."
            pattern = m.question; kind = .other
        }

        let repo = Workspace.repoLabel(for: c.repoPath, root: c.projectsRoot)
        return Decision(sessionId: c.sessionId, agent: c.agent, kind: kind, command: m.command, path: m.path, why: why ?? noWhy,
                        whySource: .heuristic, whyMissing: why == nil, touches: touchText, risk: risk(kind: kind, touches: touches),
                        ifNo: ifNo(kind: kind, isTest: touches?.isTest ?? false, step: c.step, agent: c.agent),
                        where_: whereText(c), history: history(c.past, pattern: pattern, repo: repo, now: c.now),
                        pattern: pattern, repo: repo, askedAt: c.now)
    }

    /// A plan approval from the objectives runner.
    public static func planApproval(sessionId: String, agent: AgentKind, planId: UUID, plan: Plan, objective: String, repoPath: String,
                                    why: String? = nil, past: [Decision] = [], now: Date = Date(),
                                    projectsRoot: String = Workspace.projectsRoot) -> Decision {
        let repo = Workspace.repoLabel(for: repoPath, root: projectsRoot)
        let agents = Set(plan.steps.map { $0.agentKind.displayName }).sorted().joined(separator: ", ")
        return Decision(sessionId: sessionId, agent: agent, kind: .approvePlan, planId: planId, why: why ?? plan.objective ?? objective,
                        whySource: .heuristic, whyMissing: false,
                        touches: "\(plan.steps.count) steps by \(agents). Nothing runs until you approve.", risk: .plan,
                        ifNo: ifNo(kind: .approvePlan, isTest: false, step: nil, agent: agent), where_: objective,
                        history: history(past, pattern: "approve plan", repo: repo, now: now), pattern: "approve plan", repo: repo, askedAt: now)
    }

    /// The agent's own words before the prompt, at most the last 2 sentences.
    public static func whyText(_ linesBefore: [String]) -> String? {
        guard let msg = CaptionEngine.assistantMessages(in: linesBefore).last else { return nil }
        let s = CaptionEngine.sentences(msg)
        let text = s.suffix(2).joined(separator: " ")
        return text.isEmpty ? nil : text
    }

    /// The question for the model when the agent said nothing (marked whySource = .model).
    public static func whyModelPrompt(command: String) -> String {
        "In the agent's words, why does it want to run \(command)? Quote it if possible."
    }

    public static func risk(kind: DecisionKind, touches: Touches?) -> Risk {
        if kind == .approvePlan { return .plan }
        if [.push, .install, .network].contains(kind) { return .high }
        guard let t = touches else { return .high }
        let dangerous: Set<Touches.Class> = [.network, .installs, .deletes, .writesOutside, .secrets, .unknown]
        return t.classes.isDisjoint(with: dangerous) && !t.isPush ? .low : .high
    }

    public static func ifNo(kind: DecisionKind, isTest: Bool, step: Int?, agent: AgentKind) -> String {
        let base: String
        switch kind {
        case .approvePlan: base = "nothing runs; the planner waits for edits"
        case .push: base = "commits stay local"
        case .install: base = "the step stops; you'll be asked how to continue"
        case .editFile: base = "the file stays as it is; the agent asks how to continue"
        case .network: base = "nothing is fetched; the agent carries on without it or asks you"
        case .runCommand, .other:
            base = isTest ? "skips the tests, marks step \(step.map(String.init) ?? "this step") not verified"
                          : "the command doesn't run; the agent tries another way or asks you"
        }
        switch agent {
        case .codex where kind != .approvePlan: return base + " (Codex ends its turn and waits)"
        default: return base
        }
    }

    /// "ENG-312 · step 3 of 4 · +42 −7".
    public static func whereText(_ c: DecisionContext) -> String {
        var parts: [String] = []
        if let t = c.ticket, !t.isEmpty { parts.append(t) } else if let o = c.objective, !o.isEmpty { parts.append(CaptionEngine.clip(o, 48)) }
        if let s = c.step, let n = c.steps { parts.append("step \(s) of \(n)") }
        if let a = c.added, let r = c.removed { parts.append("+\(a) −\(r)") }
        return parts.joined(separator: " · ")
    }

    /// Same pattern in the same repo, last 7 days; suggest a rule after 3 allows and no denies.
    public static func history(_ past: [Decision], pattern: String, repo: String, now: Date) -> DecisionHistory {
        let since = now.addingTimeInterval(-7 * 86_400)
        let same = past.filter { $0.pattern == pattern && $0.repo == repo && $0.askedAt >= since && $0.answer != nil }
        let allowed = same.filter { $0.answer?.isAllow == true }.count
        let denied = same.count - allowed
        let suggest = allowed >= 3 && denied == 0 ? "Always allow \(pattern) in \(repo)" : nil
        return DecisionHistory(similarAllowed: allowed, similarDenied: denied, ruleSuggestion: suggest)
    }
}

// MARK: - Answering

/// What to send to the agent's pane for an answer (the app sends each string in order through the runtime).
public struct AnswerKeys: Equatable, Sendable {
    public var sends: [String]
    /// False when the agent has no "always" option: the app sends allow-once and keeps the rule on its side.
    public var exact: Bool

    public static let escape = "\u{1B}"

    public static func keys(for answer: Answer, prompt: PromptMatch?, agent: AgentKind, reply: String? = nil) -> AnswerKeys {
        let opts = prompt?.options ?? []
        func find(_ test: (String) -> Bool) -> String? { opts.first { test($0.label.lowercased()) }?.key }
        let alwaysWords = ["don't ask again", "always", "allow all", "for this session", "auto-accept"]
        let allow = find { l in (l.hasPrefix("yes") || l.hasPrefix("allow") || l.hasPrefix("approve") || l.hasPrefix("y")) && !alwaysWords.contains { l.contains($0) } }
        let always = find { l in alwaysWords.contains { l.contains($0) } }
        let deny = find { l in l.hasPrefix("no") || l.hasPrefix("deny") || l.hasPrefix("reject") || l.hasPrefix("n") && l.count < 4 }
        let d = defaults(agent)
        switch answer {
        case .allowOnce: return AnswerKeys(sends: [allow ?? d.allow], exact: true)
        case .always:
            if let a = always ?? (opts.isEmpty ? d.always : nil) { return AnswerKeys(sends: [a], exact: true) }
            return AnswerKeys(sends: [allow ?? d.allow], exact: false)
        case .deny: return AnswerKeys(sends: [deny ?? d.deny], exact: true)
        case .reply:
            // Deny first, then the instructions as the next message (Claude: Esc then text).
            let first = agent == .claude ? escape : (deny ?? d.deny)
            let text = (reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return AnswerKeys(sends: text.isEmpty ? [first] : [first, text, "\r"], exact: true)
        }
    }

    /// Per-agent keys when the prompt's options could not be read.
    static func defaults(_ agent: AgentKind) -> (allow: String, always: String?, deny: String) {
        switch agent {
        case .claude: return ("1", "2", escape)
        case .codex: return ("y", "a", escape)
        case .kimi: return ("1", "2", "3")
        case .gemini: return ("1", "2", escape)
        case .agy: return ("y", "a", "n")
        case .shell: return ("y", nil, "n")
        }
    }

    /// The agent's interrupt: Esc for Claude, Ctrl-C otherwise.
    public static func interrupt(_ agent: AgentKind) -> String { agent == .claude ? escape : "\u{03}" }
}
