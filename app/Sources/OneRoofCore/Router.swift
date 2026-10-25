import Foundation

/// How full a seat's usage windows are. Subscriptions are flat, so "cost" is the share of a window used.
public struct SeatUsage: Equatable, Sendable {
    public var seat: String               // Claude1, Claude2, Codex
    public var fiveHour: Double?          // percent used, 0–100
    public var fiveHourResets: Date?
    public var sevenDay: Double?
    public var sevenDayResets: Date?
    public var updated: Date

    /// The tighter of the two windows.
    public var worst: Double? { [fiveHour, sevenDay].compactMap { $0 }.max() }
    public var stale: Bool { Date().timeIntervalSince(updated) > 6 * 3600 }
}

public enum Usage {
    public static var dir: String {
        (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!.path) + "/One Roof/usage"
    }

    /// Claude seats from the files the workspace status line writes (`_common/hooks/statusline-lane.sh`).
    public static func claude(dir: String = Usage.dir, accounts: [String] = AccountResolver.claudeAccounts()) -> [SeatUsage] {
        accounts.compactMap { lane in
            guard let d = FileManager.default.contents(atPath: dir + "/" + lane + ".json"),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let rl = j["rate_limits"] as? [String: Any] else { return nil }
            func w(_ k: String) -> (Double?, Date?) {
                let o = rl[k] as? [String: Any] ?? [:]
                return ((o["used_percentage"] as? NSNumber)?.doubleValue,
                        (o["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
            }
            let (f, fr) = w("five_hour"), (s, sr) = w("seven_day")
            return SeatUsage(seat: lane, fiveHour: f, fiveHourResets: fr, sevenDay: s, sevenDayResets: sr,
                             updated: Date(timeIntervalSince1970: (j["updated"] as? NSNumber)?.doubleValue ?? 0))
        }
    }

    /// Codex from the newest session log that carries `rate_limits` (primary = 5 h window, secondary = 7 days).
    public static func codex(home: String = NSHomeDirectory() + "/.codex") -> SeatUsage? {
        let fm = FileManager.default
        let root = home + "/sessions"
        guard let e = fm.enumerator(atPath: root) else { return nil }
        var files: [(String, Date)] = []
        for case let rel as String in e where rel.hasSuffix(".jsonl") {
            let p = root + "/" + rel
            if let d = try? fm.attributesOfItem(atPath: p)[.modificationDate] as? Date { files.append((p, d)) }
        }
        for (p, date) in files.sorted(by: { $0.1 > $1.1 }).prefix(40) {
            guard let text = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
            for line in text.split(separator: "\n").reversed() where line.contains("\"rate_limits\":{") {
                guard let j = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      let rl = findKey("rate_limits", in: j) as? [String: Any] else { continue }
                func w(_ k: String) -> (Double?, Date?) {
                    let o = rl[k] as? [String: Any] ?? [:]
                    return ((o["used_percent"] as? NSNumber)?.doubleValue,
                            (o["resets_at"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) })
                }
                let (f, fr) = w("primary"), (s, sr) = w("secondary")
                return SeatUsage(seat: "Codex", fiveHour: f, fiveHourResets: fr, sevenDay: s, sevenDayResets: sr, updated: date)
            }
        }
        return nil
    }

    static func findKey(_ key: String, in obj: Any) -> Any? {
        if let d = obj as? [String: Any] {
            if let v = d[key], !(v is NSNull) { return v }
            for v in d.values { if let f = findKey(key, in: v) { return f } }
        } else if let a = obj as? [Any] {
            for v in a { if let f = findKey(key, in: v) { return f } }
        }
        return nil
    }

    public static func all() -> [SeatUsage] { claude() + [codex()].compactMap { $0 } }
}

/// Routing rules, read in place from the agentic-engineering folder (`skills/*/agent-routing/routing.json`, see AEFolder).
public struct RoutingPolicy: Sendable {
    public struct Choice: Equatable, Sendable { public var agent: AgentKind; public var model: String? }
    public var kinds: [String: [Choice]]
    public var skipFiveHour: Double
    public var skipSevenDay: Double

    public static let builtIn = RoutingPolicy(kinds: [
        "research": [.init(agent: .kimi), .init(agent: .agy), .init(agent: .claude, model: "sonnet")],
        "code": [.init(agent: .claude, model: "opus"), .init(agent: .codex), .init(agent: .claude, model: "sonnet")],
        "review": [.init(agent: .codex), .init(agent: .claude, model: "sonnet")],
        "docs": [.init(agent: .kimi), .init(agent: .claude, model: "sonnet")],
    ], skipFiveHour: 90, skipSevenDay: 95)

    public init(kinds: [String: [Choice]], skipFiveHour: Double, skipSevenDay: Double) {
        self.kinds = kinds; self.skipFiveHour = skipFiveHour; self.skipSevenDay = skipSevenDay
    }

    public static func load(agenticEngineering: String = AEFolder.resolve(setting: "").path) -> RoutingPolicy {
        guard let f = AEFolder.routingFile(agenticEngineering, "routing.json"),
              let d = FileManager.default.contents(atPath: f),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return builtIn }
        var kinds: [String: [Choice]] = [:]
        for (k, v) in j["kinds"] as? [String: Any] ?? [:] {
            kinds[k] = (v as? [[String: Any]] ?? []).compactMap { c in
                guard let a = (c["agent"] as? String).flatMap({ AgentKind(rawValue: $0) }) else { return nil }
                return Choice(agent: a, model: c["model"] as? String)
            }
        }
        let skip = j["skip_above"] as? [String: Any] ?? [:]
        return RoutingPolicy(kinds: kinds.isEmpty ? builtIn.kinds : kinds,
                             skipFiveHour: (skip["five_hour"] as? NSNumber)?.doubleValue ?? 90,
                             skipSevenDay: (skip["seven_day"] as? NSNumber)?.doubleValue ?? 95)
    }
}

/// A routing suggestion with the reason shown to the owner.
public struct RouteSuggestion: Equatable, Sendable {
    public var agent: AgentKind
    public var account: String?
    public var model: String?
    public var reason: String
}

public enum Router {
    /// Rules first (kind → ordered choices, reordered by budget), then capacity (skip seats near their limit; pick the
    /// emptier Claude seat). `avoid` keeps a review off the vendor family of the agent that wrote the code. `claudeSeats` are the Claude
    /// accounts on this Mac; a seat that does not exist is never suggested.
    public static func suggest(kind: String?, budget: String = "normal", usage: [SeatUsage], policy: RoutingPolicy,
                               avoid: AgentKind? = nil,
                               claudeSeats: [String] = AccountResolver.claudeAccounts()) -> RouteSuggestion {
        let k = (kind ?? "code").lowercased()
        var choices = policy.kinds[k] ?? policy.kinds["code"] ?? RoutingPolicy.builtIn.kinds["code"]!
        if budget == "light" {
            choices = choices.filter { !($0.agent == .claude && $0.model == "opus") } + choices.filter { $0.agent == .claude && $0.model == "opus" }
        } else if budget == "max", ["design", "code", "review"].contains(k) {
            choices = choices.filter { $0.agent == .claude && $0.model == "opus" } + choices.filter { !($0.agent == .claude && $0.model == "opus") }
            if !choices.contains(where: { $0.agent == .claude && $0.model == "opus" }) { choices.insert(.init(agent: .claude, model: "opus"), at: 0) }
        }
        func seat(_ name: String) -> SeatUsage? { usage.first { $0.seat == name && !$0.stale } }
        func full(_ u: SeatUsage?) -> Bool {
            guard let u else { return false }
            return (u.fiveHour ?? 0) >= policy.skipFiveHour || (u.sevenDay ?? 0) >= policy.skipSevenDay
        }
        var skipped: [String] = []
        for c in choices where avoid.map({ c.agent.vendorFamily != $0.vendorFamily }) ?? true {
            switch c.agent {
            case .claude:
                let available = claudeSeats.isEmpty ? ["Claude1"] : claudeSeats
                let seats = available.filter { !full(seat($0)) }
                guard !seats.isEmpty else {
                    skipped.append(available.count > 1 ? "both Claude seats near their limit" : "Claude near its limit"); continue
                }
                let pick = seats.min { (seat($0)?.fiveHour ?? 0) < (seat($1)?.fiveHour ?? 0) } ?? "Claude1"
                let use = seat(pick)?.fiveHour.map { " (\(Int($0))% of its 5-hour window)" } ?? ""
                return RouteSuggestion(agent: .claude, account: pick, model: c.model,
                                       reason: "\(k) → Claude\(c.model.map { " \($0)" } ?? "") on \(pick)\(use)" + note(skipped))
            case .codex where full(seat("Codex")):
                skipped.append("Codex near its limit"); continue
            default:
                let use = c.agent == .codex ? seat("Codex")?.fiveHour.map { " (\(Int($0))% of 5 h)" } ?? "" : ""
                return RouteSuggestion(agent: c.agent, account: nil, model: c.model,
                                       reason: "\(k) → \(c.agent.displayName)\(use)" + note(skipped))
            }
        }
        return RouteSuggestion(agent: .claude, account: "Claude1", model: nil, reason: "no rule fits \(k); default Claude1" + note(skipped))
    }

    static func note(_ skipped: [String]) -> String { skipped.isEmpty ? "" : " · skipped: " + skipped.joined(separator: ", ") }
}

/// A role: a skill plus the agent that should run it, read in place from the agentic-engineering folder
/// (`skills/*/agent-routing/roles.json`).
public struct Role: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var skill: String
    public var kind: String
    public var agent: AgentKind
    public var model: String?
    public var opening: String

    /// The opening message with {repo} and {workstream} filled in.
    public func opening(repo: String, workstream: String?) -> String {
        opening.replacingOccurrences(of: "{repo}", with: repo).replacingOccurrences(of: "{workstream}", with: workstream ?? "the current work")
    }

    public static func load(agenticEngineering: String = AEFolder.resolve(setting: "").path) -> [Role] {
        guard let f = AEFolder.routingFile(agenticEngineering, "roles.json"),
              let d = FileManager.default.contents(atPath: f),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return [] }
        return (j["roles"] as? [[String: Any]] ?? []).compactMap { r in
            guard let id = r["id"] as? String, let title = r["title"] as? String, let skill = r["skill"] as? String,
                  let agent = (r["agent"] as? String).flatMap({ AgentKind(rawValue: $0) }) else { return nil }
            return Role(id: id, title: title, skill: skill, kind: r["kind"] as? String ?? "code", agent: agent,
                        model: r["model"] as? String, opening: r["opening"] as? String ?? "Use the \(skill) skill.")
        }
    }
}

public extension AgentKind {
    /// The model vendor behind an agent; a review avoids the family that wrote the code. Gemini and Antigravity are
    /// one family (Google).
    var vendorFamily: String {
        switch self {
        case .claude: return "anthropic"
        case .codex: return "openai"
        case .gemini, .agy: return "google"
        case .kimi: return "moonshot"
        case .shell: return "shell"
        }
    }
}
