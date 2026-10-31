import Foundation

/// LAB-1843 · your own `ae` loops (`<loops>/<name>.loop.yaml`, the kit's format) in One Roof's Loops area, as Mine.
///
/// One folder holds every loop of yours: One Roof's `<shared>/loops/<id>/loop.json` and the kit's `*.loop.yaml`
/// (`loops.user_dir` points there), so a loop made with `ae loops new` shows here and one made here shows in
/// `ae loops list`. The kit owns a `.loop.yaml` file and its schedule (`ae loops on` · launchd): One Roof reads it,
/// shows it, and runs it on Run now (`python3 -m ae.loops run <name> --no-agent` in its own worktree, like a Built-in
/// loop), but never starts it on its own (that would run it twice) and never rewrites the file.
public enum LoopFiles {
    /// Every `*.loop.yaml` in `folder` as a Loop (origin Mine; unreadable or invalid files are skipped).
    public static func load(folder: String, repoPath: @autoclosure () -> String = LoopBuiltIns.defaultRepoPath()) -> [Loop] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".loop.yaml") }.sorted()
        guard !names.isEmpty else { return [] }
        let repo = repoPath()
        return names.compactMap { n in
            let path = (folder as NSString).appendingPathComponent(n)
            guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
            return loop(fromYAML: text, path: path, repoPath: repo)
        }
    }

    /// One kit loop file as a Loop. nil when it has no valid `name`.
    public static func loop(fromYAML text: String, path: String, repoPath: String) -> Loop? {
        let y = MiniYAML.parse(text)
        guard let name = y.string("name"), Loop.validId(name) else { return nil }
        let goal = y.string("goal") ?? name
        let stop = y.map("stop")
        let maxRounds = Int(stop["max_iterations"] ?? "") ?? 1
        let maxMinutes = Int(stop["max_minutes"] ?? "") ?? 15
        var l = Loop(id: name, name: name, title: y.string("title"), origin: .mine, goal: goal,
                     check: "python3 -m ae.loops run \(name) --no-agent", repoPath: repoPath, agent: .claude,
                     trigger: .untilDone(everyMinutes: 0),
                     limits: LoopLimits(maxRounds: max(1, maxRounds), maxDuration: TimeInterval(max(1, maxMinutes) * 60), sameFailureStop: 2),
                     pinned: false, state: .stopped, createdAt: LoopBuiltIns.referenceDate)
        l.specFile = path
        l.kind = y.string("kind")
        l.act = y.map("act")["by"]
        l.externalSchedule = schedule(y)
        return l
    }

    /// "cron 0 17 * * 5", "when quiet", "on linear.issue.created", "manual".
    static func schedule(_ y: MiniYAML) -> String {
        let trig = y.map("trigger")
        switch trig["when"] {
        case "quiet": return "when quiet (after the cron, waits up to \(trig["max_wait_minutes"] ?? "60") min)"
        case "event": return "on " + (trig["event"] ?? "an event")
        default: break
        }
        let sched = y.map("schedule")
        if let c = sched["cron"], !c.isEmpty { return "cron " + c }
        return "manual"
    }
}

extension Loop {
    /// A `.loop.yaml` loop: `ae` owns its file and schedule.
    public var isKitFile: Bool { specFile != nil }
}

/// The small part of YAML the kit's loop files use: top-level `key: value` (plain, quoted, folded onto indented
/// lines, or a `|` / `>` block), one level of nested `key: value`, and `- item` lists. Enough to read a loop file;
/// not a general YAML reader.
public struct MiniYAML {
    public var scalars: [String: String] = [:]
    public var maps: [String: [String: String]] = [:]
    public var lists: [String: [String]] = [:]

    public func string(_ k: String) -> String? { scalars[k].flatMap { $0.isEmpty ? nil : $0 } }
    public func map(_ k: String) -> [String: String] { maps[k] ?? [:] }

    public static func parse(_ text: String) -> MiniYAML {
        var y = MiniYAML()
        var key: String?
        var mode = 0          // 0 none · 1 folded scalar · 2 block (| or >) · 3 nested map or list
        var block: [String] = []
        var literal = false
        func flush() {
            if let k = key, mode == 2 { y.scalars[k] = (literal ? block.joined(separator: "\n") : block.joined(separator: " ")).trimmingCharacters(in: .whitespacesAndNewlines) }
            block = []
        }
        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { if mode == 2 { block.append("") }; continue }
            if trimmed.hasPrefix("#") && mode != 2 { continue }
            let indent = raw.prefix(while: { $0 == " " }).count
            if indent == 0 && !trimmed.hasPrefix("- ") && trimmed != "-" {
                flush()
                guard let colon = trimmed.firstIndex(of: ":") else { key = nil; mode = 0; continue }
                let k = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                key = k
                if v == "|" || v == "|-" || v == ">" || v == ">-" { mode = 2; literal = v.hasPrefix("|") }
                else if v.isEmpty { mode = 3 }
                else { y.scalars[k] = unquote(stripComment(v)); mode = 1 }
                continue
            }
            guard let k = key else { continue }
            switch mode {
            case 1: y.scalars[k] = ((y.scalars[k] ?? "") + " " + trimmed).trimmingCharacters(in: .whitespaces)
            case 2: block.append(String(raw.dropFirst(min(indent, 2))))
            case 3:
                if trimmed.hasPrefix("- ") || trimmed == "-" {
                    y.lists[k, default: []].append(unquote(stripComment(String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces))))
                } else if let colon = trimmed.firstIndex(of: ":") {
                    let sk = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                    let sv = String(trimmed[trimmed.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                    y.maps[k, default: [:]][sk] = unquote(stripComment(sv))
                }
            default: break
            }
        }
        flush()
        return y
    }

    static func stripComment(_ v: String) -> String {
        if let q = v.first, q == "\"" || q == "'" {
            if let end = v.dropFirst().firstIndex(of: q) { return String(v[...end]) }
            return v
        }
        if let r = v.range(of: " #") { return String(v[..<r.lowerBound]).trimmingCharacters(in: .whitespaces) }
        return v
    }

    static func unquote(_ v: String) -> String {
        if v.count >= 2, let f = v.first, let l = v.last, (f == "\"" && l == "\"") || (f == "'" && l == "'") { return String(v.dropFirst().dropLast()) }
        return v
    }
}
