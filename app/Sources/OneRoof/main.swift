import AppKit
import OneRoofCore

// One Roof — native Mac command center for the agent fleet.

// 1.8.1: a self-test or fresh-profile run never shares the owner's roofd. Without its own ROOFD_DIR such a run talked
// to the installed daemon, asked it to "upgrade" to the (newer) test binary and registered the test bundle as the
// background item, so the owner's sessions ended up served from a worktree build.
if (SelfTest.isActive || Prefs.freshProfile), ProcessInfo.processInfo.environment["ROOFD_DIR"] == nil {
    let dir = "/tmp/oneroof-roofd-" + String(UUID().uuidString.prefix(8))
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    setenv("ROOFD_DIR", dir, 1)
}

// Command-line modes read the folders from the saved settings (no migration, nothing written).
if ["--check", "--linear", "--route"].contains(where: CommandLine.arguments.contains) {
    AppModel.applyFolders(Prefs.loadSettings(migrate: false))
}

// `OneRoof --check`: run the foundations check in the terminal and exit (1 if anything is red).
if CommandLine.arguments.contains("--check") {
    let st = Prefs.loadSettings(migrate: false)
    let results = Foundations.runAll(FoundationPaths(common: st.sharedFolder, agenticEngineering: st.agenticEngineering.path),
                                     runtime: Runtimes.make())
    for r in results {
        let mark = r.level == .ok ? "✓" : r.level == .warn ? "!" : "✗"
        print("\(mark) \(r.title): \(r.detail)" + (r.fix.map { "   fix: \($0)" } ?? ""))
    }
    exit(Foundations.overall(results) == .fail ? 1 : 0)
}

// `OneRoof --linear`: list workstreams and the first one's tickets (connection check).
if CommandLine.arguments.contains("--linear") {
    let c = LinearClient()
    do {
        let ws = try c.workstreams()
        let teams = try c.teams()
        print("\(teams.count) teams: " + teams.map { "\($0.key) \($0.name)" }.joined(separator: " · "))
        print("\(ws.count) projects")
        for w in ws.prefix(8) { print("  \(w.team) \(w.stateLabel.padding(toLength: 11, withPad: " ", startingAt: 0)) \(w.wsId ?? "-")  \(w.name)  [\(w.milestones.count) milestones]") }
        // `--linear-roundtrip <TEAM>`: create a project with two milestones and a Bug ticket in it, print what Linear
        // stored, then delete both (LAB-238 check; they land in Linear's trash).
        if let i = CommandLine.arguments.firstIndex(of: "--linear-roundtrip"), i + 1 < CommandLine.arguments.count,
           let team = teams.first(where: { $0.key == CommandLine.arguments[i + 1] }) {
            let p = try c.createProject(team: team, code: team.key + "-SELFTEST", title: "One Roof self-test (delete me)",
                                        summary: "Round-trip check.", milestones: ["P0 First", "P1 Second"])
            print("created project: \(p.name) code=\(p.wsId ?? "-") team=\(p.team) milestones=\(p.milestones.map(\.name))")
            let t = try c.team(key: team.key)
            let issue = try c.createIssue(team: t, workstream: p, milestone: p.milestones.first?.id, title: "Self-test bug",
                                          description: "Round-trip check.", type: WorkKind.defect.rawValue)
            let back = try c.issues(project: p.id)
            print("created issue: \(issue.identifier) title=\(issue.title); read back: " +
                  back.map { "\($0.identifier) type=\($0.type ?? "-") milestone=\($0.milestone ?? "-") title=\($0.shortTitle)" }.joined(separator: ", "))
            _ = try c.gql("mutation($id: String!) { issueDelete(id: $id) { success } }", ["id": issue.id])
            _ = try c.gql("mutation($id: String!) { projectDelete(id: $id) { success } }", ["id": p.id])
            print("deleted both")
        }
        if let first = ws.first {
            let iss = try c.issues(project: first.id)
            print("\(first.name): \(iss.count) tickets; last: \(iss.last.map { "\($0.identifier) \($0.state) \($0.shortTitle)" } ?? "-")")
        }
    } catch { print("error: \(error)"); exit(1) }
    exit(0)
}

// `OneRoof --route "<task>"`: on-device model → kind → router suggestion (and stop the model server after).
if let i = CommandLine.arguments.firstIndex(of: "--route"), i + 1 < CommandLine.arguments.count {
    let text = CommandLine.arguments[i + 1]
    let t0 = Date()
    let kind = LocalModel.shared.classify(text, kinds: RoutingPolicy.kindDescriptions())
    let r = Router.suggest(kind: kind, usage: Usage.all(), policy: RoutingPolicy.load())
    print("kind: \(kind ?? "-") (\(Int(Date().timeIntervalSince(t0) * 1000)) ms incl. model start)")
    print("→ \(r.agent.displayName)\(r.account.map { " · \($0)" } ?? "")\(r.model.map { " · \($0)" } ?? ""): \(r.reason)")
    LocalModel.shared.stop()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
