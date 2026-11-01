import Foundation

/// Linear, read and written from One Roof (owner, 2026-10-17: "I shouldn't need to go to Linear … one place").
/// Projects are Linear projects, named "CODE · title" (TEAM-TOPIC[-NN]; older ones WS-…); tickets are issues with one
/// Type label (Deliverable · Bug · Task · Spike · Decision; older workspaces `type:*`). Uses the API key already on this
/// Mac for the commit hook. (The Swift names still say "workstream": stored sessions keep that field.)
public struct LinearWorkstream: Identifiable, Equatable, Sendable {
    public var id: String           // Linear project id
    public var name: String         // "WS-WEB-12 · New checkout"
    public var state: String        // the status type: backlog / planned / started / paused / completed / canceled
    public var url: String
    public var team: String         // CMN, GBL, HYP, AGM
    public var milestones: [LinearMilestone]
    /// LAB-2050: the project status's name ("In Progress"; a status named "In Review" counts as In review).
    public var statusName: String = ""
    /// LAB-2050: it has an open issue In Progress (`working`) / In Review (`reviewing`), read with the project list.
    public var working: Bool = false
    public var reviewing: Bool = false

    public init(id: String, name: String, state: String, url: String, team: String, milestones: [LinearMilestone],
                statusName: String = "", working: Bool = false, reviewing: Bool = false) {
        self.id = id; self.name = name; self.state = state; self.url = url; self.team = team; self.milestones = milestones
        self.statusName = statusName; self.working = working; self.reviewing = reviewing
    }

    /// The Projects page status (chip and pill): In review is worked out from the issues (ProjectList.swift).
    public var status: ProjectStatus { ProjectStatus.of(type: state, name: statusName, working: working, reviewing: reviewing) }

    /// The project code at the start of the name (TEAM-TOPIC, or an older WS- id).
    public var wsId: String? { Workspace.projectCode(name: name) }
    public var title: String {
        guard let r = name.range(of: " · ") else { return name }
        return String(name[r.upperBound...])
    }
    /// The status words the Projects page uses for its chip and pill (LAB-2050: "Completed", never "Shipped").
    public var stateLabel: String { status.label }
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
    public var createdAt: Date? = nil
    public var updatedAt: Date? = nil

    /// The number after the team key (LAB-547: "LAB-90" sorts before "LAB-547").
    public var number: Int { Int(identifier.split(separator: "-").last ?? "") ?? 0 }
    /// Sort keys for the picker's columns (a table sorts on Comparable values; a missing date sorts oldest).
    public var created: Date { createdAt ?? .distantPast }
    public var updated: Date { updatedAt ?? createdAt ?? .distantPast }

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
            case .noKey: return "Linear is not connected: connect it in Settings › Linear (the key is saved to ~/.config/oneroof/linear-api-key), or set LINEAR_API_KEY"
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

    /// LAB-2102: how this workspace's state and label names map to One Roof's (Settings › Linear).
    public let mapping: LinearMapping

    public init(key: String? = LinearClient.findKey(), mapping: LinearMapping = .standard) { self.key = key; self.mapping = mapping }

    public convenience init(keyPath: String) {
        self.init(key: (try? String(contentsOfFile: keyPath, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The same connection with another mapping (a new client, so a fetch already running keeps its own).
    public func with(mapping: LinearMapping) -> LinearClient {
        let c = LinearClient(key: key, mapping: mapping)
        c.transport = transport
        return c
    }

    /// LAB-2102 · Settings › Linear › Test connection: who the key belongs to, the workspace, and how many teams it sees.
    public func testConnection() throws -> (user: String, workspace: String, teams: Int) {
        let d = try gql("query { viewer { name } organization { name } teams(first: 100) { nodes { id } } }")
        let user = (d["viewer"] as? [String: Any])?["name"] as? String ?? "?"
        let org = (d["organization"] as? [String: Any])?["name"] as? String ?? "?"
        let n = ((d["teams"] as? [String: Any])?["nodes"] as? [Any])?.count ?? 0
        return (user, org, n)
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

    /// Replaces the network in tests (no real Linear calls): returns the status code and body for a request.
    public var transport: ((URLRequest) throws -> (Int, Data))?

    /// One HTTP request, synchronous (call off the main thread).
    func send(_ req: URLRequest) throws -> (Int, Data) {
        if let transport { return try transport(req) }
        let sem = DispatchSemaphore(value: 0)
        var result: Result<(Int, Data), Error> = .failure(Failure.api("no response"))
        URLSession.shared.dataTask(with: req) { d, r, e in
            if let e { result = .failure(e) } else { result = .success(((r as? HTTPURLResponse)?.statusCode ?? 0, d ?? Data())) }
            sem.signal()
        }.resume()
        sem.wait()
        return try result.get()
    }

    /// Upload a file to Linear's storage (LAB-462) and return its asset URL, for `![name](url)` in a description:
    /// `fileUpload` gives a signed URL and headers, then the bytes go there with a PUT.
    public func uploadFile(_ data: Data, filename: String, contentType: String) throws -> String {
        let d = try gql("""
        mutation($ct: String!, $fn: String!, $size: Int!) {
          fileUpload(contentType: $ct, filename: $fn, size: $size) { success uploadFile { uploadUrl assetUrl headers { key value } } }
        }
        """, ["ct": contentType, "fn": filename, "size": data.count])
        guard let f = (d["fileUpload"] as? [String: Any])?["uploadFile"] as? [String: Any],
              let upload = (f["uploadUrl"] as? String).flatMap(URL.init(string:)), let asset = f["assetUrl"] as? String else {
            throw Failure.api("fileUpload returned nothing")
        }
        var req = URLRequest(url: upload, timeoutInterval: 60)
        req.httpMethod = "PUT"
        req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        req.setValue("public, max-age=31536000", forHTTPHeaderField: "Cache-Control")
        for h in f["headers"] as? [[String: Any]] ?? [] {
            if let k = h["key"] as? String, let v = h["value"] as? String { req.setValue(v, forHTTPHeaderField: k) }
        }
        req.httpBody = data
        let (code, body) = try send(req)
        guard (200..<300).contains(code) else { throw Failure.http(code, String(decoding: body, as: UTF8.self)) }
        return asset
    }

    /// Upload each image (LAB-462); one that cannot be read or uploaded keeps only its local path.
    public func uploadImages(_ paths: [String]) -> [ImageAttachments.Upload] {
        paths.map { p in
            guard let data = FileManager.default.contents(atPath: p) else { return .init(path: p, url: nil) }
            let url = try? uploadFile(data, filename: (p as NSString).lastPathComponent, contentType: ImageAttachments.contentType(for: p))
            return .init(path: p, url: url)
        }
    }

    /// One GraphQL request (synchronous; call off the main thread).
    public func gql(_ query: String, _ vars: [String: Any] = [:]) throws -> [String: Any] {
        guard let key, !key.isEmpty else { throw Failure.noKey }
        var req = URLRequest(url: URL(string: "https://api.linear.app/graphql")!, timeoutInterval: 20)
        req.httpMethod = "POST"
        req.setValue(key, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": vars])
        let (code, data) = try send(req)
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        if let errs = json["errors"] as? [[String: Any]], !errs.isEmpty {
            throw Failure.api(errs.compactMap { $0["message"] as? String }.joined(separator: "; "))
        }
        guard code == 200 else { throw Failure.http(code, String(decoding: data, as: UTF8.self)) }
        return json["data"] as? [String: Any] ?? [:]
    }

    /// Whether a cached Linear list should be fetched again (LAB-546 issues, LAB-1255 projects): never loaded, asked
    /// for (`force`), or older than `maxAge` seconds.
    public static func isStale(loaded: Bool, fetchedAt: Date?, force: Bool = false, maxAge: TimeInterval, now: Date = Date()) -> Bool {
        if force || !loaded { return true }
        guard let fetchedAt else { return true }
        return now.timeIntervalSince(fetchedAt) >= maxAge
    }

    /// Every project, with its team and milestones (LAB-236: not only WS- names; the owner's are TEAM-TOPIC).
    public func workstreams() throws -> [LinearWorkstream] {
        var out: [LinearWorkstream] = []
        var after: String?
        repeat {
            let d = try gql("""
            query($after: String, $review: String!) { projects(first: 50, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes { id name state status { name type } url teams(first: 1) { nodes { key } } projectMilestones(first: 20) { nodes { id name sortOrder } }
                working: issues(first: 1, filter: { state: { type: { eq: "started" }, name: { neqIgnoreCase: $review } } }) { nodes { id } }
                reviewing: issues(first: 1, filter: { state: { name: { eqIgnoreCase: $review } } }) { nodes { id } } } } }
            """, after.map { ["after": $0, "review": mapping.reviewState] } ?? ["review": mapping.reviewState])
            let p = d["projects"] as? [String: Any] ?? [:]
            for n in p["nodes"] as? [[String: Any]] ?? [] {
                let ms = ((n["projectMilestones"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).map {
                    LinearMilestone(id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", sortOrder: $0["sortOrder"] as? Double ?? 0)
                }.sorted { $0.sortOrder < $1.sortOrder }
                let team = (((n["teams"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first?["key"] as? String) ?? ""
                // LAB-2050: `status { name type }` (the deprecated `state` is the fallback), and whether any open issue is
                // In Progress / In Review (In review is worked out from those).
                let status = n["status"] as? [String: Any]
                func has(_ k: String) -> Bool { !(((n[k] as? [String: Any])?["nodes"] as? [Any]) ?? []).isEmpty }
                out.append(LinearWorkstream(id: n["id"] as? String ?? "", name: n["name"] as? String ?? "",
                                            state: status?["type"] as? String ?? n["state"] as? String ?? "",
                                            url: n["url"] as? String ?? "", team: team, milestones: ms,
                                            statusName: status?["name"] as? String ?? "", working: has("working"), reviewing: has("reviewing")))
            }
            let info = p["pageInfo"] as? [String: Any] ?? [:]
            after = (info["hasNextPage"] as? Bool ?? false) ? info["endCursor"] as? String : nil
        } while after != nil
        return out.sorted { $0.name < $1.name }
    }

    /// Linear's ISO 8601 timestamps ("2026-10-22T22:47:26.859Z").
    static func date(_ v: Any?) -> Date? {
        guard let s = v as? String else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// The most issues one project fetch reads (LAB-1255): pages of `issuesPage` until Linear says there are no more,
    /// or this many. A project the owner works in can hold 300+ issues; 1.9.2 read the first 150 only.
    public static let issuesCap = 1000
    public static let issuesPage = 100

    /// The tickets of one workstream, every page (pageInfo / endCursor), up to `cap`.
    public func issues(project: String, cap: Int = LinearClient.issuesCap) throws -> [LinearIssue] {
        var nodes: [[String: Any]] = []
        var after: String?
        repeat {
            var vars: [String: Any] = ["id": project, "first": min(Self.issuesPage, max(1, cap - nodes.count))]
            if let after { vars["after"] = after }
            let d = try gql("""
            query($id: String!, $first: Int!, $after: String) { project(id: $id) { issues(first: $first, after: $after) {
              pageInfo { hasNextPage endCursor }
              nodes {
              id identifier title description url createdAt updatedAt state { name type } projectMilestone { id name } labels(first: 6) { nodes { name } } } } } }
            """, vars)
            let page = (d["project"] as? [String: Any])?["issues"] as? [String: Any] ?? [:]
            let got = page["nodes"] as? [[String: Any]] ?? []
            nodes += got
            let info = page["pageInfo"] as? [String: Any] ?? [:]
            let next = (info["hasNextPage"] as? Bool ?? false) ? info["endCursor"] as? String : nil
            // Stop on the cap, on a page with no cursor or no nodes, or on a cursor that does not move (never loop).
            after = (next == nil || next == after || got.isEmpty || nodes.count >= cap) ? nil : next
        } while after != nil
        var seen = Set<String>()
        return nodes.prefix(cap).compactMap { n -> LinearIssue? in
            let id = n["id"] as? String ?? ""
            guard seen.insert(id).inserted else { return nil }
            let st = n["state"] as? [String: Any] ?? [:]
            let ms = n["projectMilestone"] as? [String: Any]
            let labels = ((n["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let type = labels.lazy.compactMap(self.mapping.kind(fromLabel:)).first?.rawValue
            return LinearIssue(id: id, identifier: n["identifier"] as? String ?? "", title: n["title"] as? String ?? "",
                               description: n["description"] as? String ?? "", state: st["name"] as? String ?? "",
                               stateType: st["type"] as? String ?? "", type: type, milestoneId: ms?["id"] as? String,
                               milestone: ms?["name"] as? String, url: n["url"] as? String ?? "",
                               createdAt: Self.date(n["createdAt"]), updatedAt: Self.date(n["updatedAt"]))
        }.sorted { $0.number < $1.number }
    }

    public func team(key: String) throws -> LinearTeam {
        let d = try gql("""
        query($k: String!) { teams(filter: { key: { eq: $k } }) { nodes { id key states { nodes { id name type position } } labels(first: 100) { nodes { id name } } } } }
        """, ["k": key])
        guard let n = ((d["teams"] as? [String: Any])?["nodes"] as? [[String: Any]])?.first else { throw Failure.api("team \(key) not found") }
        // Board order: the API lists In Review (started, position 1002) before In Progress (started, 2), so an
        // unsorted `first(where: type == "started")` moved new tickets straight to In Review (LAB-247).
        let states = ((n["states"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? [])
            .sorted { ($0["position"] as? Double ?? 0) < ($1["position"] as? Double ?? 0) }
            .map { (id: $0["id"] as? String ?? "", name: $0["name"] as? String ?? "", type: $0["type"] as? String ?? "") }
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
        if let kind = WorkKind(rawValue: type), let l = mapping.labelNames(kind).lazy.compactMap({ team.labels[$0] }).first { input["labelIds"] = [l] }
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

    /// Move a ticket to a state by One Roof's name ("In Review", "Done", …), through the mapping (LAB-2102: the team's
    /// own name, then the same name in any case, then the state of that type); any other name must match exactly.
    public func setState(issue: String, team: LinearTeam, named name: String) throws {
        let found = mapping.resolveState(name, in: team.states) ?? team.states.first(where: { $0.name == name }).map { ($0.id, $0.name) }
        guard let s = found else { throw Failure.api("no state \(mapping.stateName(name)) in \(team.key) (Settings › Linear maps state names)") }
        _ = try gql("mutation($id: String!, $s: String!) { issueUpdate(id: $id, input: { stateId: $s }) { success } }", ["id": issue, "s": s.id])
    }

    public func comment(issue: String, body: String) throws {
        _ = try gql("mutation($i: CommentCreateInput!) { commentCreate(input: $i) { success } }", ["i": ["issueId": issue, "body": body]])
    }

    /// One issue by its key ("LAB-298"), with its team key and project code (LAB-511: attach what a session mentions).
    public func issue(key: String) throws -> (issue: LinearIssue, team: String, project: String?)? {
        let d = try gql("""
        query($id: String!) { issue(id: $id) { id identifier title description url state { name type } team { key } project { name } labels(first: 6) { nodes { name } } } }
        """, ["id": key])
        guard let n = d["issue"] as? [String: Any], let id = n["id"] as? String else { return nil }
        let st = n["state"] as? [String: Any] ?? [:]
        // The Type label too (LAB-533: the Ticket tab's quality line needs it).
        let labels = ((n["labels"] as? [String: Any])?["nodes"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let i = LinearIssue(id: id, identifier: n["identifier"] as? String ?? key, title: n["title"] as? String ?? "",
                            description: n["description"] as? String ?? "", state: st["name"] as? String ?? "",
                            stateType: st["type"] as? String ?? "", type: labels.lazy.compactMap(mapping.kind(fromLabel:)).first?.rawValue,
                            milestoneId: nil, milestone: nil, url: n["url"] as? String ?? "")
        let project = ((n["project"] as? [String: Any])?["name"] as? String).flatMap { Workspace.projectCode(name: $0) }
        return (i, (n["team"] as? [String: Any])?["key"] as? String ?? "", project)
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
    /// Stands in for the key of an issue not created yet; replaced by the real one once Linear assigns it (LAB-248).
    public static let newIssueKey = "<new issue key>"

    /// The opening message for a session on an issue: the issue's own key (never the project code), its link, and the
    /// commit format (LAB-248: "Work on the new ticket (TEAM-PROJECT)" read as if the project code were the ticket).
    public static func ticketOpening(key: String, title: String, url: String? = nil, project: String?) -> String {
        let where_ = project.map { " in project \($0)" } ?? ""
        let read = url.map { "Read the ticket (\($0))" } ?? "Read the ticket"
        let tag = project.map { " · [\(Workspace.commitTag($0))]" } ?? ""
        return "Work on \(key)\(where_): \(title). \(read)\(project == nil ? "" : " and the project docs") first; commit as `\(key)\(tag) …`."
    }

    /// What a running agent is told when an issue is attached to its session (LAB-474).
    public static func attachMessage(key: String, title: String, url: String? = nil, project: String?) -> String {
        let read = url.map { "Read it (\($0))" } ?? "Read it"
        let tag = project.map { " · [\(Workspace.commitTag($0))]" } ?? ""
        return "This session now also works on \(key): \(title). \(read) when you reach a good stopping point; commit that work as `\(key)\(tag) …`."
    }

    /// Add an issue to an existing session (LAB-474). A session can resolve several: the first becomes its ticket (and
    /// "KEY · title" its name), later ones join `moreTickets`; one already on the session is left alone. A session with no
    /// project takes the issue's. Returns false when the issue was already attached.
    @discardableResult
    public static func attach(_ issue: LinearIssue, team: String?, project: String?, to s: inout Session) -> Bool {
        guard !s.hasTicket(issue.identifier) else { return false }
        if s.ticket == nil {
            s.name = sessionName(key: issue.identifier, title: s.name)
            s.ticket = issue.identifier
            s.ticketId = issue.id
            s.ticketTeam = team ?? s.ticketTeam
        } else {
            s.moreTickets.append(SessionIssue(key: issue.identifier, id: issue.id, team: team ?? s.ticketTeam))
        }
        if (s.workstream ?? "").isEmpty, let project, !project.isEmpty { s.workstream = project }
        return true
    }

    /// Take an issue off a session (it stays in Linear). Removing the first one promotes the next (LAB-474).
    public static func detach(_ key: String, from s: inout Session) {
        if s.ticket?.caseInsensitiveCompare(key) == .orderedSame {
            if s.moreTickets.isEmpty {
                s.ticket = nil; s.ticketId = nil
            } else {
                let next = s.moreTickets.removeFirst()
                s.ticket = next.key; s.ticketId = next.id; s.ticketTeam = next.team ?? s.ticketTeam
            }
        } else {
            s.moreTickets.removeAll { $0.key.caseInsensitiveCompare(key) == .orderedSame }
        }
    }

    /// A session on an issue is named after it, Linear's way: "KEY · title" (LAB-248).
    public static func sessionName(key: String, title: String) -> String {
        title.hasPrefix(key) ? title : "\(key) · \(title)"
    }

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
