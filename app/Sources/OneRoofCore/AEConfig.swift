import Foundation

/// The Agentic Engineering kit's config (`ae.config.yaml`), read only for what One Roof shows about the kit's loops:
/// where the run journal lives (`journal.root`, LAB-2099) and each loop's workspace settings (`loops.settings.<loop>`,
/// LAB-2100). Found the kit's way: `$AE_CONFIG`, then `ae.config.yaml` in the projects or shared folder, then
/// `~/.config/ae/config.yaml`. One Roof never writes it. A small indentation reader, enough for block-style YAML (the
/// kit writes block style); anything it cannot read counts as not set.
public enum AEConfig {
    public static func candidates(environment: [String: String] = ProcessInfo.processInfo.environment,
                                  home: String = NSHomeDirectory(),
                                  projects: String = Workspace.projectsRoot, shared: String = Workspace.sharedRoot) -> [String] {
        var out: [String] = []
        if let e = environment["AE_CONFIG"], !e.isEmpty { out.append(expand(e, home: home)) }
        out += [projects + "/ae.config.yaml", shared + "/ae.config.yaml", home + "/.config/ae/config.yaml"]
        return out
    }

    /// The first config file that exists, if any.
    public static func find(_ candidates: [String] = AEConfig.candidates()) -> String? {
        candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    public static func expand(_ p: String, home: String) -> String {
        p == "~" ? home : p.hasPrefix("~/") ? home + String(p.dropFirst(1)) : p
    }

    // MARK: Reading block YAML

    struct Line { var indent: Int; var text: String }

    static func lines(_ yaml: String) -> [Line] {
        yaml.split(separator: "\n", omittingEmptySubsequences: false).compactMap { raw in
            let s = String(raw)
            let body = s.trimmingCharacters(in: .whitespaces)
            if body.isEmpty || body.hasPrefix("#") { return nil }
            return Line(indent: s.prefix { $0 == " " }.count, text: body)
        }
    }

    /// The value written after `key:` on its own line (comment and quotes stripped), and the lines under it.
    public struct Node: Equatable, Sendable {
        public var inline: String
        public var children: [String]
        /// Set to something: an inline value that is not empty/null/[]/{} , or anything under the key.
        public var isSet: Bool {
            let v = inline.trimmingCharacters(in: .whitespaces)
            if !v.isEmpty && !["[]", "{}", "null", "~", "''", "\"\""].contains(v) { return true }
            return !children.isEmpty
        }
    }

    /// The node at a key path (`["loops", "settings", "cost-watch", "limits"]`), or nil when the path is not there.
    public static func node(_ path: [String], in yaml: String) -> Node? {
        var scope = lines(yaml)[...]
        var indent = -1
        var found: Node?
        for (depth, key) in path.enumerated() {
            // The first line at this scope's child indent whose key is `key`.
            guard let childIndent = scope.first(where: { $0.indent > indent })?.indent else { return nil }
            guard let at = scope.firstIndex(where: { $0.indent == childIndent && keyOf($0.text) == key }) else { return nil }
            let line = scope[at]
            // Its block: following lines indented deeper, or list items at the same indent ("key:\n- a").
            var end = scope.index(after: at)
            while end < scope.endIndex, scope[end].indent > line.indent || (scope[end].indent == line.indent && scope[end].text.hasPrefix("- ")) {
                end = scope.index(after: end)
            }
            let block = scope[scope.index(after: at)..<end]
            if depth == path.count - 1 {
                found = Node(inline: inlineValue(line.text), children: block.map(\.text))
            }
            scope = block
            indent = line.indent
            if depth < path.count - 1, block.isEmpty { return nil }
        }
        return found
    }

    static func keyOf(_ text: String) -> String? {
        guard let colon = text.firstIndex(of: ":") else { return nil }
        let k = text[..<colon].trimmingCharacters(in: .whitespaces)
        if k.hasPrefix("- ") { return nil }
        return k.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    static func inlineValue(_ text: String) -> String {
        guard let colon = text.firstIndex(of: ":") else { return "" }
        var v = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        if let hash = v.range(of: " #") { v = String(v[..<hash.lowerBound]).trimmingCharacters(in: .whitespaces) }
        if v.count >= 2, let f = v.first, let l = v.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") { v = String(v.dropFirst().dropLast()) }
        return v
    }

    // MARK: The journal (LAB-2099)

    /// Where `journal:` links point: `journal.root` from the config, else `<shared>/journal`, else `~/.ae/journal`.
    public static func journalRoots(config: String?, home: String = NSHomeDirectory(), shared: String = Workspace.sharedRoot) -> [String] {
        var out: [String] = []
        if let c = config, let r = node(["journal", "root"], in: c)?.inline, !r.isEmpty { out.append(expand(r, home: home)) }
        out += [shared + "/journal", home + "/.ae/journal"]
        var seen = Set<String>()
        return out.filter { seen.insert($0).inserted }
    }

    /// The file a `journal:<relative path>` link names: the first root where it exists, else under the first root
    /// (the caller shows the folder when the file is missing).
    public static func resolveJournal(_ relative: String, roots: [String], exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        let rel = relative.hasPrefix("/") ? String(relative.dropFirst()) : relative
        guard !rel.isEmpty, !rel.split(separator: "/").contains("..") else { return nil }
        let all = roots.map { ($0 as NSString).appendingPathComponent(rel) }
        return all.first(where: exists) ?? all.first
    }
}

/// LAB-2100 · whether one of the kit's loops has what it needs to check anything. Switched on without it, a loop runs,
/// finds "no commands configured" and reports pass or dry: the card said Done/pass when nothing was checked. The card
/// now says "not configured" and the loop's page says what to set and where.
public enum LoopSetup {
    public enum Status: Equatable, Sendable {
        case ready
        case notConfigured([String])      // what is missing, one line each
    }

    public struct Need: Equatable, Sendable {
        public var setting: [String]?     // a key under loops.settings.<loop> that must be set
        public var tool: String?          // a program that must be installed
        public var missing: String        // the line shown when it is not
    }

    /// What each kit loop needs before a run checks anything (the kit's collectors: commands.py, cost_watch.py, and
    /// security-audit's osv-scanner command).
    public static func needs(_ loop: String) -> [Need] {
        func commands(_ what: String) -> Need {
            Need(setting: ["commands"], missing: "no commands: set loops.settings.\(loop).commands ([{name, run, severity}]) with the \(what) to check")
        }
        switch loop {
        case "fleet-sweep": return [commands("repo gates (one fast check per repo)")]
        case "site-prober": return [commands("sites and the one key action on each")]
        case "visual-diff": return [commands("pages to compare")]
        case "cost-watch":
            return [Need(setting: ["usd_per_mtok"], missing: "no price table: set loops.settings.cost-watch.usd_per_mtok from the provider's live price page"),
                    Need(setting: ["limits"], missing: "no spend limit: set loops.settings.cost-watch.limits (for example anthropic: 20)")]
        case "security-audit":
            return [Need(tool: "osv-scanner", missing: "osv-scanner is not installed (the dependency scan needs it; secret scan runs without it)")]
        default: return []
        }
    }

    /// The status from the config text and which tools are installed; nil for a loop with no known needs.
    public static func status(loop: String, config: String?, toolInstalled: (String) -> Bool) -> Status? {
        let ns = needs(loop)
        guard !ns.isEmpty else { return nil }
        var missing: [String] = []
        for n in ns {
            if let key = n.setting {
                let set = config.flatMap { AEConfig.node(["loops", "settings", loop] + key, in: $0) }?.isSet ?? false
                if !set { missing.append(n.missing) }
            }
            if let tool = n.tool, !toolInstalled(tool) { missing.append(n.missing) }
        }
        return missing.isEmpty ? .ready : .notConfigured(missing)
    }

    /// The loop card's result line: "not configured" in place of a pass, dry or done that checked nothing.
    public static func cardResult(_ last: String, status: Status?) -> String {
        if case .notConfigured = status { return "not configured" }
        return last
    }

    /// Where a program would be: PATH plus the usual install folders (the app's PATH from launchd is short).
    public static func toolDirs(environment: [String: String] = ProcessInfo.processInfo.environment, home: String = NSHomeDirectory()) -> [String] {
        let path = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        var seen = Set<String>()
        return (path + ["/opt/homebrew/bin", "/usr/local/bin", home + "/go/bin", home + "/.local/bin", home + "/bin"]).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public static func installed(_ tool: String, dirs: [String] = LoopSetup.toolDirs()) -> Bool {
        dirs.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + tool) }
    }

    /// The YAML to add under `loops: settings:` for a loop, as a starting point (comments say what to fill in).
    public static func snippet(_ loop: String) -> String? {
        switch loop {
        case "fleet-sweep", "site-prober", "visual-diff":
            let example: String
            switch loop {
            case "fleet-sweep": example = "      - name: web-tests\n        run: cd ~/code/web && npm test --silent\n        severity: high"
            case "site-prober": example = "      - name: home-page\n        run: curl -fsS https://example.com/ >/dev/null\n        severity: high\n        network: true"
            default: example = "      - name: pricing-page\n        run: <your screenshot compare command>\n        severity: medium"
            }
            return "loops:\n  settings:\n    \(loop):\n      commands:\n\(example)"
        case "cost-watch":
            return "loops:\n  settings:\n    cost-watch:\n      limits:\n        anthropic: 20          # dollars per day\n      usd_per_mtok:\n        <model id>: {input: 0, output: 0, cache_read: 0, cache_write: 0}   # from the live price page"
        case "security-audit":
            return "# Install osv-scanner (https://google.github.io/osv-scanner/), then the next run scans dependencies."
        default: return nil
        }
    }
}
