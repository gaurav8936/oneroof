import Foundation
import OneRoofCore

/// LAB-2050 · ONEROOF_SELFTEST_PROJECTS=1 (with ONEROOF_SELFTEST_DEMO=1): the Projects page reads a fixture Linear
/// instead of the network. Six teams (API DOC LAB MOB OPS WEB) and 18 projects in every status (Backlog, Planned,
/// In progress, In progress whose open issues are all In Review, Completed, Canceled), with milestones and issues.
/// The fixture answers through `LinearClient.transport`, so the real parse path runs; it never reaches Linear, and
/// any write (a mutation) fails with "self-test fixture: read-only".
/// PROJECTSTATUSES=<comma list of chip ids, or "all"> · PROJECTSQUERY=<text> · PROJECTSFOLD=<team keys, or "all">
/// set the page's remembered filter and folds for this run (captures: default view, a team folded, In review only,
/// no match). Written to Prefs.viewState, a self-test suite emptied at launch: never the owner's settings.
enum SelfTestProjects {
    static var active: Bool { ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_PROJECTS"] == "1" }

    static func install(_ m: AppModel) {
        let c = LinearClient(key: "selftest-fixture")
        c.transport = { req in
            let body = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data())) as? [String: Any] ?? [:]
            let q = body["query"] as? String ?? ""
            let vars = body["variables"] as? [String: Any] ?? [:]
            let data: [String: Any]
            if q.contains("mutation") {
                return (200, try JSONSerialization.data(withJSONObject: ["errors": [["message": "self-test fixture: read-only"]]]))
            } else if q.contains("projects(") {
                data = ["projects": ["pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": projects.map(\.json)]]
            } else if q.contains("project(id") {
                let id = vars["id"] as? String ?? ""
                let nodes = projects.first { $0.id == id }?.issueJSON ?? []
                data = ["project": ["issues": ["pageInfo": ["hasNextPage": false, "endCursor": NSNull()], "nodes": nodes]]]
            } else if q.contains("teams(") {
                data = ["teams": ["nodes": teams.map { ["id": "t-" + $0.0, "key": $0.0, "name": $0.1] }]]
            } else {
                data = [:]
            }
            return (200, try JSONSerialization.data(withJSONObject: ["data": data]))
        }
        m.linear = c
        // A planned session on LAB-ONEROOF-BUGS / LAB-2040, so the project's live-session count and (before LAB-2051) its
        // Sessions block have something to show.
        let name = "Projects page hierarchy"
        if !m.items.contains(where: { $0.session.name == name }) {
            m.save(Session(name: name, agent: .claude, repoPath: Workspace.projectsRoot + "/acme/web", workstream: "LAB-ONEROOF-BUGS",
                           lifecycle: .planned, ticket: "LAB-2040", ticketTeam: "LAB"))
        }
        let env = ProcessInfo.processInfo.environment
        let d = Prefs.viewState   // a self-test suite, never the owner's settings
        if let s = env["ONEROOF_SELFTEST_PROJECTSTATUSES"] {
            d.set(s == "all" ? ProjectStatus.allCases.map(\.rawValue).joined(separator: ",") : s, forKey: "projects.statuses")
        }
        if let s = env["ONEROOF_SELFTEST_PROJECTSQUERY"] { d.set(s, forKey: "projects.query") }
        if let s = env["ONEROOF_SELFTEST_PROJECTSFOLD"] {
            d.set(s == "all" ? teams.map(\.0).joined(separator: ",") : s, forKey: "projects.foldedTeams")
        }
    }

    static let teams: [(String, String)] = [("API", "Platform"), ("DOC", "Docs"), ("LAB", "Labs"),
                                            ("MOB", "Mobile"), ("OPS", "Operations"), ("WEB", "Web")]

    struct Fixture {
        var id: String, name: String, team: String, type: String, statusName: String
        var working = false, reviewing = false
        var milestones: [String] = []
        var issues: [(String, String, String, Int?)] = []   // title, state name, state type, milestone index

        var json: [String: Any] {
            [
                "id": id, "name": name, "state": type, "status": ["name": statusName, "type": type],
                "url": "https://linear.app/fixture/project/\(id)", "teams": ["nodes": [["key": team]]],
                "projectMilestones": ["nodes": milestones.enumerated().map { ["id": "\(id)-m\($0.offset)", "name": $0.element, "sortOrder": Double($0.offset)] }],
                "working": ["nodes": working ? [["id": "w"]] : []],
                "reviewing": ["nodes": reviewing ? [["id": "r"]] : []],
            ]
        }
        var issueJSON: [[String: Any]] {
            issues.enumerated().map { k, i in
                var n: [String: Any] = [
                    "id": "\(id)-i\(k)", "identifier": "\(team)-\(2040 + k)", "title": i.0, "description": "", "url": "https://linear.app/fixture/issue/\(team)-\(2040 + k)",
                    "state": ["name": i.1, "type": i.2], "labels": ["nodes": [["name": k % 3 == 0 ? "Bug" : "Deliverable"]]],
                ]
                if let m = i.3 { n["projectMilestone"] = ["id": "\(id)-m\(m)", "name": milestones[m]] }
                return n
            }
        }
    }

    static let projects: [Fixture] = [
        Fixture(id: "p-bugs", name: "LAB-ONEROOF-BUGS · One Roof bugs and owner observations from daily use", team: "LAB",
                type: "started", statusName: "In Progress", working: true, reviewing: true,
                milestones: ["M5 · Projects page", "M6 · Resources"],
                issues: [("Projects list: team → project hierarchy, folding and status chips", "In Progress", "started", 0),
                         ("Project page: remove the Sessions section", "In Review", "started", 0),
                         ("Resources: Mac apps list", "Todo", "unstarted", 1),
                         ("Toolbar overlaps the title at 1280", "Done", "completed", 1),
                         ("Reload keeps the selected project", "Backlog", "backlog", nil)]),
        Fixture(id: "p-evals", name: "LAB-EVALS · Evals in One Roof: any model, any benchmark, the agent X-ray", team: "LAB",
                type: "started", statusName: "In Progress", reviewing: true,
                milestones: ["M8 · Judge"], issues: [("Judge model picker", "In Review", "started", 0)]),
        Fixture(id: "p-loops", name: "LAB-LOOPS · Loops that run themselves", team: "LAB", type: "started", statusName: "In Progress", reviewing: true),
        Fixture(id: "p-kit", name: "LAB-AE-KIT · Agentic Engineering gold-standard kit", team: "LAB", type: "started", statusName: "In Progress", working: true, reviewing: true),
        Fixture(id: "p-papers", name: "LAB-AE-PAPERS · Research papers track, narrated, with voice questions", team: "LAB", type: "planned", statusName: "Planned"),
        Fixture(id: "p-starter", name: "LAB-STARTER-KIT · Starter kit for a new machine", team: "LAB", type: "backlog", statusName: "Backlog"),
        Fixture(id: "p-pitch", name: "LAB-ENERGYLAB-EXPLAINED · Energy Lab pitch deck for regulatory affairs teams", team: "LAB", type: "completed", statusName: "Completed"),
        Fixture(id: "p-checkout", name: "WEB-CHECKOUT · New checkout with saved cards and wallets", team: "WEB", type: "started", statusName: "In Progress", working: true),
        Fixture(id: "p-a11y", name: "WEB-A11Y · Accessibility pass on every form", team: "WEB", type: "started", statusName: "In Progress", reviewing: true),
        Fixture(id: "p-dark", name: "WEB-DARK-MODE · Dark mode for the marketing site", team: "WEB", type: "backlog", statusName: "Backlog"),
        Fixture(id: "p-legacy", name: "WEB-LEGACY-CART · Legacy cart clean-up", team: "WEB", type: "completed", statusName: "Completed"),
        Fixture(id: "p-usage", name: "API-USAGE-EXPORT · Nightly usage export", team: "API", type: "started", statusName: "In Progress", working: true),
        Fixture(id: "p-rate", name: "API-RATE-LIMITS · Rate limits per key", team: "API", type: "planned", statusName: "Planned"),
        Fixture(id: "p-help", name: "DOC-HELP-MAP · Help map as a tree", team: "DOC", type: "started", statusName: "In Progress", working: true),
        Fixture(id: "p-wiki", name: "DOC-WIKI-MOVE · Move the wiki into the repo", team: "DOC", type: "canceled", statusName: "Canceled"),
        Fixture(id: "p-push", name: "MOB-PUSH · Push notifications on both platforms", team: "MOB", type: "planned", statusName: "Planned"),
        Fixture(id: "p-offline", name: "MOB-OFFLINE · Offline mode for the field app", team: "MOB", type: "paused", statusName: "Paused"),
        Fixture(id: "p-ops", name: "OPS-RUNNERS · Self-hosted build runners", team: "OPS", type: "backlog", statusName: "Backlog"),
    ]
}
