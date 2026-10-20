import AppKit
import OneRoofCore

// One Roof — native Mac command center for the agent fleet.

// Command-line modes read the folders from the saved settings (no migration, nothing written).
if ["--check", "--linear", "--route"].contains(where: CommandLine.arguments.contains) {
    AppModel.applyFolders(Prefs.loadSettings(migrate: false))
}

// `OneRoof --check`: run the foundations check in the terminal and exit (1 if anything is red).
if CommandLine.arguments.contains("--check") {
    let st = Prefs.loadSettings(migrate: false)
    let results = Foundations.runAll(FoundationPaths(common: st.sharedFolder, agenticEngineering: st.agenticEngineering.path),
                                     runtime: HerdrRuntime())
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
        print("\(ws.count) workstreams")
        for w in ws.prefix(8) { print("  \(w.team) \(w.stateLabel.padding(toLength: 11, withPad: " ", startingAt: 0)) \(w.name)  [\(w.milestones.count) phases]") }
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
