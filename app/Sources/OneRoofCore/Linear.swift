import Foundation

/// Linear, read and written from One Roof (owner, 2026-10-17: "I shouldn't need to go to Linear … one place").
/// Projects are Linear projects, named "CODE · title" (TEAM-TOPIC[-NN]; older ones WS-…); tickets are issues with one
/// Type label (Deliverable · Bug · Task · Spike · Decision; older workspaces `type:*`). Uses the API key already on this
/// Mac for the commit hook. (The Swift names still say "workstream": stored sessions keep that field.)
public struct LinearWorkstream: Identifiable, Equatable, Sendable {
    public var id: String           // Linear project id
    public var name: String         // "WS-WEB-12 · New checkout"
    public var state: String        // planned / started / completed / …
    public var url: String
    public var team: String         // CMN, GBL, HYP, AGM
    public var milestones: [LinearMilestone]

    /// The project code at the start of the name (TEAM-TOPIC, or an older WS- id).
    public var wsId: String? { Workspace.projectCode(name: name) }
    public var title: String {
        guard let r = name.range(of: " · ") else { return name }
        return String(name[r.upperBound...])
    }
    public var stateLabel: String {
        switch state {
        case "started": return "In progress"
        case "completed": return "Shipped"
        case "planned": return "Planned"
        case "backlog": return "Backlog"
        case "canceled": return "Canceled"
        case "paused": return "Paused"
        default: return state.capitalized
        }
    }
}

public struct LinearMilestone: Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var sortOrder: Double
}

public struct LinearIssue: Identifiable, Equatable, Sendable {
    public var id: String
    public var identifier: String   // ENG-281
    public var title: String
    public var description: String
    public var state: String        // "In Progress"
    public var stateType: String    // backlog / unstarted / started / completed / canceled
    public var type: String?        // deliverable / defect / spike / decision / chore
    public var milestoneId: String?
    public var milestone: String?
    public var url: String

    /// The ticket title without a "[code] " prefix (older tickets carry one).
    public var shortTitle: String {
        title.replacingOccurrences(of: #"^\[[a-z][a-z0-9]*-[a-z0-9-]+\]\s*"#, with: "", options: .regularExpression)
    }
}

/// A team as listed for the pickers (key + name), before its states and labels are loaded.
public struct LinearTeamRef: Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var key: String
    public var name: String
    public init(id: String, key: String, name: String) { self.id = id; self.key = key; self.name = name }
}

public struct LinearTeam: Equatable, Sendable {
    public var id: String
    public var key: String
    public var states: [(id: String, name: String, type: String)]
    public var labels: [String: String]   // name → id
    public static func == (a: LinearTeam, b: LinearTeam) -> Bool { a.id == b.id }
}

public final class LinearClient: @unchecked Sendable {
    public enum Failure: Error, CustomStringConvertible {
        case noKey, http(Int, String), api(String)
        public var description: String {
            switch self {
            case .noKey: return "Linear is not connected: set LINEAR_API_KEY or save a key to ~/.config/oneroof/linear-api-key (One Roof › Setup…)"
            case .http(let c, let b): return "Linear HTTP \(c): \(b.prefix(200))"
            case .api(let m): return "Linear: \(m.prefix(300))"
            }
        }
    }

    /// Where One Roof saves a Linear key (Setup…), readable only by you.
    public static var keyPath: String { NSHomeDirectory() + "/.config/oneroof/linear-api-key" }
    let key: String?
    public var hasKey: Bool { key.map { !$0.isEmpty } ?? false }

    /// The key: env `LINEAR_API_KEY`, then `keyPath`, then the legacy key file (`LegacyMigration.linearKeyPath`).
    public static func findKey(environment: [String: String] = ProcessInfo.processInfo.environment,
                               files: [String] = [LinearClient.keyPath, LegacyMigration.linearKeyPath]) -> String? {
        if let e = environment["LINEAR_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !e.isEmpty { return e }
        for f in files {
            if let k = (try? String(contentsOfFile: f, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines), !k.isEmpty { return k }
        }
        return nil
    }

    public init(key: String? = LinearClient.findKey()) { self.key = key }

    public convenience init(keyPath: String) {
        self.init(key: (try? String(contentsOfFile: keyPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Save `key` to `path` (folder created, file mode 0600).
    public static func saveKey(_ key: String, to path: String = LinearClient.keyPath) throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true,
                               attributes: [.posixPermissions: 0o700])
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fm.createFile(atPath: path, contents: Data((k + "\n").utf8), attributes: [.posixPermissions: 0o600]) else {
            throw Failure.api("could not write \(path)")
        }
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// One GraphQL request (synchronous; call off the main thread).
    public func gql(_ query: String, _ vars: [String: Any] = [:]) throws -> [String: Any] {
        guard let key, !key.isEmpty else { throw Failure.noKey }
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": vars])
        let sem = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error> = .failure(Failure.api("no response"))
        URLSession.shared.dataTask(with: req) { d, r, e in
            if let e { result = .failure(e) } else { result = .success(((r as? HTTPURLResponse)?.statusCode ?? 0, d ?? Data())) }
            sem.signal()
        }.resume()
        sem.wait()
        let (code, data) = try result.get()
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
            throw Failure.api(errs.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
        guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        return json["data"] as? [String: Any] ?? [:]
    }

    /// Every project, with its team and milestones (LAB-236: not only WS- names; the owner's are TEAM-TOPIC).
    public func workstreams() throws -> [LinearWorkstream] {
        var out: [LinearWorkstream] = []
        var after: String?
        repeat {
            let d = try gql("""
            query($after: String) { projects(first: 50, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes { id name state url teams(first: 1) { nodes { key } } projectMilestones(first: 20) { nodes { id name sortOrder } } } } }
            """, after.map { ["after": $0] } ?? [:])
            let p = d["projects"] as? [String: Any] ?? [:]
            for n in p["nodes"] as? [[String: Any]] ?? [] {
                let ms = ((n["projectMilestones"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).map {
                    LinearMilestone(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", sortOrder: $0["sortOrder"] as? Double ?? 0)
                }.sorted { $0.sortOrder < $1.sortOrder }
                let team = (((n["teams"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["key"] as? String) ?? ""
                out.append(LinearWorkstream(id: n["id"] as? String ?? "", name: n["name"] as? String ?? "", state: n["state"] as? String ?? "",
                                            url: n["url"] as? String ?? "", team: team, milestones: ms))
            }
            let info = p["pageInfo"] as? [String: Any] ?? [:]
            after = (info["hasNextPage"] as? Bool ?? false) ? info["endCursor"] as? String : nil
        } while after != nil
        return out.sorted { $0.name < $1.name }
    }

    /// The tickets of one workstream.
    public func issues(project: String) throws -> [LinearIssue] {
        let d = try gql("""
        query($id: String!) { project(id: $id) { issues(first: 150) { nodes {
          id identifier title description url state { name type } projectMilestone { id name } labels(first: 6) { nodes { name } } } } } }
        """, ["id": project])
        let nodes = ((d["project"] as? [String: Any])?["issues"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []
        return nodes.map { n in
            let st = n["state"] as? [String: Any] ?? [:]
            let ms = n["projectMilestone"] as? [String: Any]
            let labels = ((n["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let type = labels.lazy.compactMap(WorkKind.fromLabel).first?.rawValue
            return LinearIssue(id: n["id"] as? String ?? "", identifier: n["identifier"] as? String ?? "", title: n["title"] as? String ?? "",
                               description: n["description"] as? String ?? "", state: st["name"] as? String ?? "",
                               stateType: st["type"] as? String ?? "", type: type, milestoneId: ms?["id"] as? String,
                               milestone: ms?["name"] as? String, url: n["url"] as? String ?? "")
        }.sorted { a, b in
            let na = Int(a.identifier.split(separator: "-").last ?? "") ?? 0, nb = Int(b.identifier.split(separator: "-").last ?? "") ?? 0
            return na < nb
        }
    }

    public func team(key: String) throws -> LinearTeam {
        let d = try gql("""
        query($k: String!) { teams(filter: { key: { eq: $k } }) { nodes { id key states { nodes { id name type } } labels(first: 100) { nodes { id name } } } } }
        """, ["k": key])
        guard let n = ((d["teams"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first else { throw Failure.api("team \(key) not found") }
        let states = ((n["states"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).map {
            (id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", type: $0["type"] as? String ?? "")
        }
        var labels: [String: String] = [:]
        for l in (n["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [] {
            if let name = l["name"] as? String, let id = l["id"] as? String { labels[name] = id }
        }
        return LinearTeam(id: n["id"] as? String ?? "", key: key, states: states, labels: labels)
    }

    /// Every team (key + name), for the team picker (LAB-237).
    public func teams() throws -> [LinearTeamRef] {
        let d = try gql("query { teams(first: 100) { nodes { id key name } } }")
        return ((d["teams"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).map {
            LinearTeamRef(id: $0["id"] as? String ?? "", key: $0["key"] as? String ?? "", name: $0["name"] as? String ?? "")
        }.sorted { $0.key < $1.key }
    }

    /// Create a project in a team, named "CODE · title", with its milestones in order (LAB-238).
    public func createProject(team: LinearTeamRef, code: String, title: String, summary: String,
                              milestones: [String]) throws -> LinearWorkstream {
        let name = code.isEmpty ? title : "\(code) · \(title)"
        var input: [String: Any] = ["teamIds": [team.id], "name": name, "state": "planned"]
        if !summary.isEmpty { input["description"] = summary + "\n\nCreated from One Roof." }
        let d = try gql("mutation($i: ProjectCreateInput!) { projectCreate(input: $i) { project { id name state url } } }", ["i": input])
        guard let n = (d["projectCreate"] as? [String: Any])?["project"] as? [String: Any], let pid = n["id"] as? String else {
            throw Failure.api("projectCreate returned nothing")
        }
        var ms: [LinearMilestone] = []
        for (i, m) in milestones.enumerated() where !m.trimmingCharacters(in: .whitespaces).isEmpty {
            let r = try gql("mutation($i: ProjectMilestoneCreateInput!) { projectMilestoneCreate(input: $i) { projectMilestone { id name sortOrder } } }",
                            ["i": ["projectId": pid, "name": m.trimmingCharacters(in: .whitespaces), "sortOrder": Double(i)]])
            if let x = (r["projectMilestoneCreate"] as? [String: Any])?["projectMilestone"] as? [String: Any] {
                ms.append(LinearMilestone(id: x["id"] as? String ?? "", name: x["name"] as? String ?? m, sortOrder: x["sortOrder"] as? Double ?? Double(i)))
            }
        }
        return LinearWorkstream(id: pid, name: n["name"] as? String ?? name, state: n["state"] as? String ?? "planned",
                                url: n["url"] as? String ?? "", team: team.key, milestones: ms)
    }

    /// Create a ticket in a project (or, with no project, in the team only). Old WS- projects keep their
    /// `[ws-…]` title prefix; TEAM-TOPIC projects need none (the commit carries the tag).
    public func createIssue(team: LinearTeam, workstream: LinearWorkstream?, milestone: String?, title: String,
                            description: String, type: String) throws -> LinearIssue {
        let prefix = workstream?.wsId.flatMap { $0.hasPrefix("WS-") ? "[\($0.lowercased())] " : nil } ?? ""
        var input: [String: Any] = [
            "teamId": team.id, "title": prefix + title,
            "description": description + "\n\nCreated from One Roof.",
        ]
        if let workstream { input["projectId"] = workstream.id }
        if let milestone { input["projectMilestoneId"] = milestone }
        if let kind = WorkKind(rawValue: type), let l = kind.labelNames.lazy.compactMap({ team.labels[$0] }).first { input["labelIds"] = [l] }
        if let backlog = team.states.first(where: { $0.type == "backlog" }) { input["stateId"] = backlog.id }
        let d = try gql("""
        mutation($i: IssueCreateInput!) { issueCreate(input: $i) { issue { id identifier title url state { name type } } } }
        """, ["i": input])
        guard let n = ((d["issueCreate"] as? [String: Any])?["issue"]) as? [String: Any] else { throw Failure.api("issueCreate returned nothing") }
        let st = n["state"] as? [String: Any] ?? [:]
        return LinearIssue(id: n["id"] as? String ?? "", identifier: n["identifier"] as? String ?? "", title: n["title"] as? String ?? "",
                           description: description, state: st["name"] as? String ?? "", stateType: st["type"] as? String ?? "",
                           type: type, milestoneId: milestone, milestone: nil, url: n["url"] as? String ?? "")
    }

    /// Move a ticket to the team state with this exact name ("In Review", "Done", …).
    public func setState(issue: String, team: LinearTeam, named name: String) throws {
        guard let s = team.states.first(where: { $0.name == name }) else { throw Failure.api("no state \(name) in \(team.key)") }
        _ = try gql("mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: { stateId: $s }) { success } }", ["id": issue, "s": s.id])
    }

    public func comment(issue: String, body: String) throws {
        _ = try gql("mutation($i: CommentCreateInput!) { commentCreate(input: $i) { success } }", ["i": ["issueId": issue, "body": body]])
    }

    /// One ticket's current state (for the plan panel).
    public func issueState(_ id: String) throws -> (name: String, type: String, url: String) {
        let d = try gql("query($id: String!) { issue(id: $id) { url state { name type } } }", ["id": id])
        let i = d["issue"] as? [String: Any] ?? [:], st = i["state"] as? [String: Any] ?? [:]
        return (st["name"] as? String ?? "", st["type"] as? String ?? "", i["url"] as? String ?? "")
    }

    /// Move a ticket to the team's first state of a type ("started" = In Progress).
    public func setState(issue: String, team: LinearTeam, type: String) throws {
        guard let s = team.states.first(where: { $0.type == type }) else { return }
        _ = try gql("mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: { stateId: $s }) { success } }", ["id": issue, "s": s.id])
    }
}

/// The intake filter (owner, 2026-10-17): before anything is created, decide what it is, so tab names, the
/// tracker and Linear stop drifting apart. Rules first; the on-device model refines this later.
public enum WorkKind: String, CaseIterable, Identifiable, Sendable {
    case workstream, deliverable, defect, spike, decision, chore, session
    public var id: String { rawValue }

    /// The Linear Type label for this kind, newest name first (then the older `type:*` name).
    public var labelNames: [String] {
        switch self {
        case .deliverable: return ["Deliverable", "type:deliverable"]
        case .defect: return ["Bug", "type:defect"]
        case .spike: return ["Spike", "type:spike"]
        case .decision: return ["Decision", "type:decision"]
        case .chore: return ["Task", "type:chore"]
        case .workstream, .session: return []
        }
    }

    /// The kind a Linear label names, if it is a Type label.
    public static func fromLabel(_ label: String) -> WorkKind? {
        allCases.first { $0.labelNames.contains(label) }
    }

    public var label: String {
        switch self {
        case .workstream: return "Project"
        case .deliverable: return "Ticket · deliverable"
        case .defect: return "Ticket · defect"
        case .spike: return "Ticket · spike"
        case .decision: return "Ticket · decision"
        case .chore: return "Ticket · chore"
        case .session: return "Just a session"
        }
    }

    public var meaning: String {
        switch self {
        case .workstream: return "An outcome that needs several sessions and more than one deliverable. Gets a WS id, a tracker pane, a docs folder and a Linear project."
        case .deliverable: return "One thing to build or write, done in one to three sessions, inside a project."
        case .defect: return "Something is broken or wrong and needs fixing."
        case .spike: return "Find something out (try, measure, research) before deciding or building."
        case .decision: return "A question with options that someone has to settle."
        case .chore: return "Housekeeping: upgrades, cleanup, renames."
        case .session: return "A quick one-off: no ticket, nothing to track."
        }
    }

    public var isTicket: Bool { ![.workstream, .session].contains(self) }
}

public enum Intake {
    /// Suggest a kind from the words used. The owner always confirms.
    public static func suggest(_ text: String) -> WorkKind {
        let t = " " + text.lowercased() + " "
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has([" bug", "broken", " fails", "failing", " error", " crash", "regression", "doesn't work", "does not work", " fix "]) { return .defect }
        if has(["decide", "decision", "should we", " vs ", " or not", "choose ", "pick between"]) { return .decision }
        if has(["investigate", "spike", "research", "explore", "find out", "evaluate", "compare", "prototype"]) { return .spike }
        if has(["workstream", "new project", "initiative", "programme", "program ", "platform", "end-to-end", "e2e", "migration", "redesign", " v2", "phases"]) { return .workstream }
        if has(["upgrade", "bump", "cleanup", "clean up", "rename", "tidy", "chore"]) { return .chore }
        if has(["quick", "just check", "look at", "ask ", "where are we", "status"]) { return .session }
        return .deliverable
    }

    /// Workstreams whose name shares the most words with the text (for the parent picker).
    public static func rankWorkstreams(_ text: String, _ all: [LinearWorkstream]) -> [LinearWorkstream] {
        let words = Set(text.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 })
        guard !words.isEmpty else { return all }
        func score(_ w: LinearWorkstream) -> Int {
            Set(w.name.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)).intersection(words).count
        }
        return all.sorted { (score($0), $1.name) > (score($1), $0.name) }
    }

    /// Existing tickets that look like the same thing (shared significant words), best first.
    public static func similar(_ title: String, in issues: [LinearIssue], limit: Int = 3) -> [LinearIssue] {
        let stop: Set<String> = ["with", "from", "into", "that", "this", "the", "and", "for", "add", "make"]
        func words(_ s: String) -> Set<String> {
            Set(s.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 2 && !stop.contains($0) })
        }
        let w = words(title)
        guard w.count >= 2 else { return [] }
        let scored = issues.map { ($0, Double(words($0.shortTitle).intersection(w).count) / Double(w.count)) }
        return scored.filter { $0.1 >= 0.5 }.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}

/// The master-tracker pane for a workstream, if one exists (read-only scan of the trackers).
public enum Trackers {
    /// `<projects>/_MASTER-TRACKER.html`, `<projects>/*/_MASTER-TRACKER.html` and `<shared>/_MASTER-TRACKER.html`
    /// that exist.
    public static func files(projects: String = Workspace.projectsRoot, shared: String = Workspace.sharedRoot) -> [String] {
        let fm = FileManager.default
        let name = "_MASTER-TRACKER.html"
        var out = [projects + "/" + name]
        for d in ((try? fm.contentsOfDirectory(atPath: projects)) ?? []).sorted() where !d.hasPrefix(".") {
            out.append(projects + "/" + d + "/" + name)
        }
        out.append(shared + "/" + name)
        var seen = Set<String>()
        return out.map { ($0 as NSString).standardizingPath }.filter { fm.fileExists(atPath: $0) && seen.insert($0).inserted }
    }

    public static func pane(for wsId: String) -> URL? {
        let anchor = "id=\"\(wsId.lowercased())\""
        for f in files() {
            guard let text = try? String(contentsOfFile: f, encoding: .utf8), text.contains(anchor) else { continue }
            return URL(string: "file://" + f + "#" + wsId.lowercased())
        }
        return nil
    }

    /// The workstream's docs folder, first that exists: `<shared>/docs/workstreams/<id>`, then
    /// `<projects>/*/*-docs/workstreams/<id>` (a docs-only repo), then `<projects>/*/*/docs/workstreams/<id>`.
    public static func docsFolder(for wsId: String, root: String = Workspace.projectsRoot,
                                  shared: String? = nil) -> String? {
        let id = wsId.lowercased()
        let fm = FileManager.default
        let sharedDir = shared ?? (root == Workspace.projectsRoot ? Workspace.sharedRoot
                                   : Workspace.resolveShared(setting: "", projects: root, environment: [:]))
        // Older ids live in workstreams/<id>, project codes in projects/<code> (LAB-235).
        let kinds = ["workstreams", "projects"]
        for k in kinds where fm.fileExists(atPath: "\(sharedDir)/docs/\(k)/\(id)") { return "\(sharedDir)/docs/\(k)/\(id)" }
        let domains = ((try? fm.contentsOfDirectory(atPath: root)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        func repos(_ d: String) -> [String] {
            ((try? fm.contentsOfDirectory(atPath: root + "/" + d)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        }
        for k in kinds {
            for d in domains {
                for r in repos(d) where r.hasSuffix("-docs") {
                    let path = "\(root)/\(d)/\(r)/\(k)/\(id)"
                    if fm.fileExists(atPath: path) { return path }
                }
            }
            for d in domains {
                for r in repos(d) {
                    let path = "\(root)/\(d)/\(r)/docs/\(k)/\(id)"
                    if fm.fileExists(atPath: path) { return path }
                }
            }
        }
        return nil
    }
}
