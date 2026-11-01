import AppKit
import SwiftUI
import OneRoofCore

/// LAB-EVALS: the Evals place. Catalog (LAB-1980/1981) · Runs (LAB-1982/1983) · Results (LAB-1984–1987) · Learn
/// (LAB-1988/1989). Everything comes from the eval engine (`roof_eval.py … --json`), called off the main thread.
final class EvalsBoard: ObservableObject {
    enum Tab: String, CaseIterable { case catalog = "Catalog", runs = "Runs", results = "Results", learn = "Learn" }
    @Published var tab: Tab = .catalog
    @Published private(set) var doctor: EvalDoctor?
    @Published private(set) var catalog: EvalCatalog?
    @Published private(set) var runs: [EvalRunRow] = []
    @Published private(set) var results: [EvalResult] = []
    @Published var error: String?
    @Published private(set) var busy: String?
    private var timer: Timer?
    private let io = DispatchQueue(label: "oneroof.evals.io")

    func start() {
        refreshDoctor()
        refreshRuns()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            guard let self, self.runs.contains(where: \.isActive) || self.tab == .runs else { return }
            self.refreshRuns()
        }
        timer?.tolerance = 0.5
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func call<T: Decodable>(_ args: [String], _ type: T.Type, label: String? = nil, timeout: TimeInterval = 600,
                                    done: @escaping (T) -> Void) {
        if let label { busy = label }
        io.async {
            let r = EvalEngine.decode(T.self, EvalEngine.run(args + ["--json"], timeout: timeout))
            DispatchQueue.main.async {
                if label != nil { self.busy = nil }
                switch r {
                case .success(let v): done(v); self.error = nil
                case .failure(let e): self.error = e.message
                }
            }
        }
    }

    func refreshDoctor() {
        call(["doctor"], EvalDoctor.self) { d in
            self.doctor = d
            if d.engine.ready && self.catalog == nil { self.refreshCatalog(force: false) }
        }
    }

    func setup() {
        call(["setup"], EvalDoctor.Engine.self, label: "Installing the eval engine (a minute or two the first time)…", timeout: 1800) { _ in
            self.refreshDoctor()
        }
    }

    func refreshCatalog(force: Bool) {
        call(["catalog"] + (force ? ["--refresh"] : []), EvalCatalog.self, label: "Reading the benchmarks…") { self.catalog = $0 }
    }

    func refreshRuns() {
        call(["status"], [EvalRunRow].self) { rows in
            let sorted = rows.sorted { ($0.created ?? $0.id) > ($1.created ?? $1.id) }
            let finishedNow = self.runs.contains { old in old.isActive && sorted.contains { $0.id == old.id && !$0.isActive } }
            if sorted != self.runs { self.runs = sorted }
            if finishedNow || self.results.isEmpty { self.refreshResults() }
        }
    }

    func refreshResults() { call(["results"], [EvalResult].self) { if $0 != self.results { self.results = $0 } } }

    func estimate(task: String, model: String, limit: Int, epochs: Int?, place: String = "local",
                  done: @escaping (Result<EvalEstimate, EvalError>) -> Void) {
        io.async {
            var a = ["estimate", task, "--model", model, "--limit", String(limit), "--where", place, "--json"]
            if let e = epochs { a += ["--epochs", String(e)] }
            let r = EvalEngine.decode(EvalEstimate.self, EvalEngine.run(a, timeout: 120))
            DispatchQueue.main.async { done(r) }
        }
    }

    struct Started: Decodable { var id: String }

    func start(_ plan: EvalRunPlan) {
        busy = "Starting \(plan.tasks.count * plan.models.count) run(s)…"
        io.async {
            var errors: [String] = []
            for task in plan.tasks { for model in plan.models {
                var a = ["run", task, "--model", model, "--limit", String(plan.limit), "--max-cost", String(plan.cap), "--background", "--json"]
                if let e = plan.epochs { a += ["--epochs", String(e)] }
                if let s = plan.seed { a += ["--seed", String(s)] }
                if let t = plan.temperature { a += ["--temperature", String(t)] }
                if !plan.taskArgs.isEmpty { a += ["--task-args", plan.taskArgs] }
                if plan.place != "local" { a += ["--where", plan.place] }
                if case .failure(let e) = EvalEngine.decode(Started.self, EvalEngine.run(a, timeout: 300)) {
                    errors.append("\(task) × \(model): \(e.message)")
                }
            } }
            DispatchQueue.main.async {
                self.busy = nil
                self.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
                self.tab = .runs
                self.refreshRuns()
            }
        }
    }

    func cancel(_ id: String) { io.async { _ = EvalEngine.run(["cancel", id]); DispatchQueue.main.async { self.refreshRuns() } } }
    func resume(_ id: String) { io.async { _ = EvalEngine.run(["resume", id]); DispatchQueue.main.async { self.refreshRuns() } } }

    func samples(_ id: String, done: @escaping ([EvalSample]) -> Void) {
        call(["samples", id], [EvalSample].self, done: done)
    }

    func transcript(_ run: String, _ s: EvalSample, done: @escaping (EvalTranscript) -> Void) {
        call(["sample", run, s.sampleID, "--epoch", String(s.epoch)], EvalTranscript.self, done: done)
    }

    func export(format: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "one-roof-evals.\(format)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        io.async {
            let o = EvalEngine.run(["export", "--format", format, "--out", url.path])
            DispatchQueue.main.async { self.error = o.code == 0 ? nil : o.stderr }
        }
    }
}

/// What the run sheet starts: every task × every model, as background runs (they queue in the engine).
struct EvalRunPlan: Identifiable, Equatable {
    var id = UUID()
    var benchmark: EvalBenchmark?
    var tasks: [String]
    var models: [String] = ["mockllm/model"]
    var limit = 50
    var epochs: Int?
    var seed: Int? = 42
    var temperature: Double?
    var cap = 2.0
    var taskArgs = ""
    var place = "local"   // where code-running benchmarks execute (LAB-2000)
}

struct EvalsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @StateObject private var board = EvalsBoard()
    @Environment(\.theme) private var t
    @State private var plan: EvalRunPlan?

    var body: some View {
        FleetPage(title: "Evals", subtitle: subtitle) {
            HStack(spacing: 8) {
                Segmented(options: EvalsBoard.Tab.allCases.map { ($0, $0.rawValue) }, selection: $board.tab,
                          badge: { $0 == .runs ? board.runs.filter(\.isActive).count.nonZero : nil })
                if board.doctor?.engine.ready == true {
                    RoofButton("+ New run", .primary) { plan = EvalRunPlan(tasks: ["gsm8k"]) }
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                if let b = board.busy { Text(b).ui(TypeScale.small).foregroundStyle(t.text2.color) }
                if let e = board.error {
                    Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled)
                }
                if let d = board.doctor, !d.engine.ready {
                    EvalsSetupCard(doctor: d, board: board)
                } else if board.doctor == nil {
                    Text("Checking the eval engine…").ui(TypeScale.body).foregroundStyle(t.text2.color)
                } else {
                    switch board.tab {
                    case .catalog: EvalsCatalogTab(board: board) { b in plan = EvalRunPlan(benchmark: b, tasks: [b.defaultTask], limit: b.firstRunLimit) }
                    case .runs: EvalsRunsTab(board: board)
                    case .results: EvalsResultsTab(board: board)
                    case .learn: EvalsLearnTab(board: board) { plan = $0 }
                    }
                }
            }
        }
        .onAppear {
            board.start()
            // Self-test captures: ONEROOF_SELFTEST_EVALS_TAB=<catalog|runs|results|learn|sheet>.
            if let tab = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_EVALS_TAB"] {
                if tab == "sheet" { plan = EvalRunPlan(tasks: ["gsm8k"], models: ["mockllm/model", "anthropic/claude-haiku-5-5"]) }
                else if let t = EvalsBoard.Tab(rawValue: tab.capitalized) { board.tab = t }
            }
        }
        .onDisappear { board.stop() }
        .sheet(item: $plan) { p in
            EvalRunSheet(board: board, plan: p, providers: board.doctor?.readyProviders ?? [],
                         places: board.doctor?.places ?? ["local": true]) { final in
                plan = nil
                if let final { board.start(final) }
            }
            .themed(t.name)
        }
    }

    private var subtitle: String {
        guard let d = board.doctor else { return "Run any model on any benchmark and read what the numbers mean" }
        guard d.engine.ready else { return "The eval engine is not installed yet" }
        var parts: [String] = []
        if let c = board.catalog { parts.append("\(c.count) benchmarks") }
        let active = board.runs.filter(\.isActive).count
        if active > 0 { parts.append("\(active) running") }
        parts.append("\(board.results.filter { $0.status == "done" }.count) finished runs")
        if let v = d.engine.inspectAI { parts.append("Inspect \(v)") }
        return parts.joined(separator: " · ")
    }
}

private extension Int { var nonZero: String? { self > 0 ? String(self) : nil } }

// MARK: - Setup

struct EvalsSetupCard: View {
    let doctor: EvalDoctor
    @ObservedObject var board: EvalsBoard
    @Environment(\.theme) private var t
    var body: some View {
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Install the eval engine").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("One Roof runs evals with Inspect AI (MIT, UK AI Security Institute) and its collection of public benchmarks. It is installed into One Roof's own folder with uv, outside the app, and can be removed by deleting that folder.")
                    .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Text("uv: \(doctor.uv ?? "not found — install it once with  brew install uv")")
                    .ui(TypeScale.small, mono: true).foregroundStyle(doctor.uv == nil ? t.needsText.color : t.text2.color)
                Text("Docker: \(doctor.docker) (only benchmarks that run code need it)").ui(TypeScale.small).foregroundStyle(t.text2.color)
                RoofButton("Install", .primary) { board.setup() }.disabled(doctor.uv == nil || board.busy != nil)
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }
}

// MARK: - Catalog (LAB-1980, LAB-1981)

struct EvalsCatalogTab: View {
    @ObservedObject var board: EvalsBoard
    var run: (EvalBenchmark) -> Void
    @Environment(\.theme) private var t
    @State private var filter = EvalCatalogFilter()
    @State private var selected: String?

    var body: some View {
        if let c = board.catalog {
            let shown = filter.apply(c.benchmarks)
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    TextField("Search benchmarks", text: $filter.search).textFieldStyle(.roundedBorder).frame(width: 240)
                    FieldMenu(title: filter.category ?? "All categories", expand: false) {
                        Button("All categories") { filter.category = nil }
                        Divider()
                        ForEach(c.allCategories, id: \.self) { cat in Button(cat) { filter.category = cat } }
                    }
                    Toggle("Start here", isOn: $filter.starterOnly).toggleStyle(.checkbox)
                    Toggle("No Docker needed", isOn: $filter.noSandbox).toggleStyle(.checkbox)
                    Spacer()
                    Text("\(shown.count) of \(c.count) · \(c.tasks) tasks · inspect-evals \(c.inspectEvals ?? "?")")
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    RoofButton("Rescan") { board.refreshCatalog(force: true) }
                }
                HStack(alignment: .top, spacing: 16) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            ForEach(shown) { b in row(b) }
                        }
                    }
                    .frame(width: 420)
                    if let b = c.benchmarks.first(where: { $0.id == (selected ?? shown.first?.id) }) {
                        ScrollView { EvalBenchmarkCard(benchmark: b, board: board, run: run) }.frame(maxWidth: .infinity)
                    }
                }
            }
        } else {
            Text(board.busy ?? "No catalog yet.").ui(TypeScale.body).foregroundStyle(t.text2.color)
        }
    }

    private func row(_ b: EvalBenchmark) -> some View {
        let on = (selected ?? board.catalog.flatMap { filter.apply($0.benchmarks).first?.id }) == b.id
        return Button { selected = b.id } label: {
            HStack(spacing: 8) {
                Text(b.isStarter ? "★" : " ").ui(TypeScale.small).foregroundStyle(t.accentText.color).frame(width: 12)
                VStack(alignment: .leading, spacing: 2) {
                    Text(b.name).ui(TypeScale.row, .medium).foregroundStyle(t.text.color).lineLimit(1)
                    Text(b.category + (b.sandbox ? " · Docker" : "") + (b.internet ? " · internet" : ""))
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
                }
                Spacer()
                if let n = b.tasks.first?.samples { Text("\(n)").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color) }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(b.name), \(b.category)")
    }
}

struct EvalBenchmarkCard: View {
    let benchmark: EvalBenchmark
    @ObservedObject var board: EvalsBoard
    var run: (EvalBenchmark) -> Void
    @Environment(\.theme) private var t
    @State private var estimates: [String: String] = [:]

    var body: some View {
        let b = benchmark
        Card(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(b.name).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                        Text([b.category, b.group].compactMap { $0 }.uniqued().joined(separator: " · ") + (b.isStarter ? " · Start here" : ""))
                            .ui(TypeScale.small).foregroundStyle(t.text2.color)
                    }
                    Spacer()
                    RoofButton("Run this…", .primary) { run(b) }
                }
                Text(b.description).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                ForEach(b.starter, id: \.task) { s in
                    Text("What it teaches: " + s.teaches + (s.milestone.map { " (coding agents: \($0))" } ?? ""))
                        .ui(TypeScale.body, .medium).foregroundStyle(t.accentText.color).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                    ForEach(b.tasks, id: \.name) { task in
                        HStack(spacing: 10) {
                            Text(EvalBenchmark.taskLabel(task.name)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color)
                            if let n = task.samples { Text("\(n) questions").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                            if let h = task.humanBaseline, let s = h.score {
                                Text("people: \(Int((s * 100).rounded())) % \(h.metric ?? "")").ui(TypeScale.small).foregroundStyle(t.text2.color)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Needs").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                    Text(needs(b)).ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Estimated cost for \(benchmark.firstRunLimit) questions").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                    ForEach(costModels, id: \.self) { m in
                        HStack {
                            Text(EvalModels.short(m)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).frame(width: 220, alignment: .leading)
                            Text(estimates[m] ?? "…").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        }
                    }
                    Text("Prices from OpenRouter's public list; answer length is a guess until this Mac has run the benchmark.")
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
                if let a = b.arxiv, let url = URL(string: a) {
                    Link("Paper ↗", destination: url).font(.system(size: TypeScale.small))
                }
            }
        }
        .onAppear(perform: estimate)
        .onChange(of: benchmark.id) { _, _ in estimates = [:]; estimate() }
    }

    private var costModels: [String] { ["anthropic/claude-haiku-5-5", "anthropic/claude-sonnet-5-5", "openai/gpt-5-mini", "openrouter/qwen/qwen3-coder"] }

    private func estimate() {
        let task = benchmark.defaultTask
        for m in costModels {
            board.estimate(task: task, model: m, limit: benchmark.firstRunLimit, epochs: nil) { r in
                switch r {
                case .success(let e): estimates[m] = e.usd.map { String(format: "$%.3f · %d calls", $0, e.calls) } ?? "price unknown"
                case .failure: estimates[m] = "price unknown"
                }
            }
        }
    }

    private func needs(_ b: EvalBenchmark) -> String {
        var n: [String] = []
        if b.sandbox { n.append("Docker running: it executes code" + (b.supportsK8s ? " (also runs on Kubernetes)" : "")) }
        if b.internet { n.append("internet access during the run") }
        if let x = b.extra { n.append("an extra package (installed on first run: \(x))") }
        if b.tasks.contains(where: { ["hle", "livecodebench_pro", "gaia", "gaia_level1", "xstest"].contains($0.name) }) {
            n.append("a Hugging Face sign-in with the dataset's terms accepted")
        }
        return n.isEmpty ? "Nothing extra: a small question file and the model's API." : n.joined(separator: " · ")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] { var seen = Set<Element>(); return filter { seen.insert($0).inserted } }
}

// MARK: - Run sheet (LAB-1982)

struct EvalRunSheet: View {
    @ObservedObject var board: EvalsBoard
    @State var plan: EvalRunPlan
    let providers: [String]
    var places: [String: Bool] = ["local": true]
    var done: (EvalRunPlan?) -> Void
    @Environment(\.theme) private var t
    @State private var customModel = ""
    @State private var estimates: [String: EvalEstimate] = [:]
    @State private var estimateErrors: [String: String] = [:]
    @State private var epochsText = ""
    @State private var temperatureText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New eval run").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            if let b = plan.benchmark, b.tasks.count > 1 {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tasks in \(b.name)").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                    ForEach(b.tasks, id: \.name) { task in
                        Toggle(task.name + (task.samples.map { " · \($0) questions" } ?? ""), isOn: Binding(
                            get: { plan.tasks.contains(task.name) },
                            set: { on in plan.tasks = on ? plan.tasks + [task.name] : plan.tasks.filter { $0 != task.name }; refresh() }))
                        .toggleStyle(.checkbox)
                    }
                }
            } else {
                HStack {
                    Text("Benchmark task").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color).frame(width: 130, alignment: .leading)
                    if let task = plan.tasks.first, task.hasSuffix(".py") {   // your own eval set: its task file, not typed
                        Text(EvalBenchmark.taskLabel(task)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color)
                    } else {
                        TextField("gsm8k", text: Binding(get: { plan.tasks.first ?? "" }, set: { plan.tasks = [$0] }))
                            .textFieldStyle(.roundedBorder).frame(width: 260).onSubmit(refresh)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Models").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(EvalModels.suggestions, id: \.group) { g in
                            Text(g.group + keyNote(g.models.first ?? "")).ui(TypeScale.caption, .semibold).foregroundStyle(t.text3.color).padding(.top, 4)
                            ForEach(g.models, id: \.self) { m in modelRow(m) }
                        }
                        ForEach(plan.models.filter { m in !EvalModels.suggestions.contains { $0.models.contains(m) } }, id: \.self) { m in modelRow(m) }
                    }
                }
                .frame(height: 210)
                HStack {
                    TextField("any model, e.g. fireworks/accounts/fireworks/models/…", text: $customModel).textFieldStyle(.roundedBorder)
                    RoofButton("Add") {
                        let m = customModel.trimmingCharacters(in: .whitespaces)
                        if m.contains("/") && !plan.models.contains(m) { plan.models.append(m); refresh() }
                        customModel = ""
                    }
                }
            }
            HStack(spacing: 16) {
                Stepper("Questions: \(plan.limit)", value: $plan.limit, in: 1...5000, step: plan.limit < 20 ? 1 : 10)
                    .onChange(of: plan.limit) { _, _ in refresh() }
                labeled("Attempts each", $epochsText, "default").onSubmit(refresh)
                labeled("Temperature", $temperatureText, "default")
                Stepper(String(format: "Spending cap: $%.2f", plan.cap), value: $plan.cap, in: 0...500, step: plan.cap < 5 ? 0.5 : 5)
            }
            .ui(TypeScale.small)
            if plan.benchmark?.sandbox == true {
                HStack(spacing: 8) {
                    Text("Where its code runs").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                    Segmented(options: EvalDoctor.placeOrder.map { ($0, EvalDoctor.placeTitle($0) + ((places[$0] ?? false) ? "" : " · not set up")) },
                              selection: $plan.place)
                        .onChange(of: plan.place) { _, _ in refresh() }
                }
                if !(places[plan.place] ?? false) {
                    Text(plan.place == "modal" ? "Sign in once in a terminal: python3 -m modal setup"
                         : plan.place == "local" ? "Start Docker first." : "Add a key file: roof eval providers set \(plan.place) --key-file PATH")
                        .ui(TypeScale.caption).foregroundStyle(t.needsText.color)
                }
                Text("Cloud sandboxes bill per second of sandbox time; the estimate includes it (1 vCPU + 2 GiB, prices checked 2026-10-31).")
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
            estimatesView
            HStack {
                Text("Runs start in the background and queue (two at a time); closing One Roof does not stop them.")
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                Spacer()
                RoofButton("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                RoofButton("Start \(plan.tasks.count * plan.models.count) run(s)", .primary) {
                    var p = plan
                    p.epochs = Int(epochsText)
                    p.temperature = Double(temperatureText)
                    done(p)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan.tasks.isEmpty || plan.models.isEmpty || overCap || (plan.benchmark?.sandbox == true && !(places[plan.place] ?? false)))
            }
        }
        .padding(22)
        .frame(width: 760)
        .background(t.surface.color)
        .onAppear(perform: refresh)
    }

    private func keyNote(_ m: String) -> String {
        let p = EvalModels.provider(m)
        if EvalModels.isFree(m) { return "" }
        return providers.contains(p) ? "" : "  (no key yet: roof eval providers set \(p) --key-file …)"
    }

    private func modelRow(_ m: String) -> some View {
        Toggle(isOn: Binding(get: { plan.models.contains(m) },
                             set: { on in plan.models = on ? plan.models + [m] : plan.models.filter { $0 != m }; refresh() })) {
            Text(m).ui(TypeScale.small, mono: true)
        }
        .toggleStyle(.checkbox)
    }

    private func labeled(_ title: String, _ text: Binding<String>, _ placeholder: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
            TextField(placeholder, text: text).textFieldStyle(.roundedBorder).frame(width: 70)
        }
    }

    private var total: Double? {
        let all = plan.models.flatMap { m in plan.tasks.map { "\($0)|\(m)" } }
        let vals = all.compactMap { estimates[$0]?.usd }
        return vals.count == all.count ? vals.reduce(0, +) : nil
    }

    /// Checked as the engine does: grader cost padded ×1.5, since grading is not stopped mid-run (LAB-2012).
    private var overCap: Bool { plan.models.flatMap { m in plan.tasks.map { k -> Double in let e = estimates["\(k)|\(m)"]; return e?.capCheckUSD ?? e?.usd ?? 0 } }.contains { $0 > plan.cap } }

    private var estimatesView: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cost before you start").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
            ForEach(plan.tasks, id: \.self) { task in
                ForEach(plan.models, id: \.self) { m in
                    let k = "\(task)|\(m)"
                    HStack {
                        Text("\(EvalBenchmark.taskLabel(task)) × \(EvalModels.short(m))").ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).frame(width: 330, alignment: .leading)
                        if let e = estimates[k] {
                            Text(e.usd.map { String(format: "$%.4f", $0) } ?? "price unknown")
                                .ui(TypeScale.small, .semibold).foregroundStyle((e.usd ?? 0) > plan.cap ? t.needsText.color : t.text.color)
                            Text("· \(e.calls) calls · \(e.breakdown) · ~\(e.tokensPerSample.input) in / \(e.tokensPerSample.output) out each (\(e.tokenBasis))")
                                .ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
                                .help(e.grader.map { "Grader: \($0.basis)" } ?? "")
                        } else {
                            Text(estimateErrors[k] ?? "…").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                        }
                    }
                }
            }
            if let tot = total { Text(String(format: "Total estimate $%.4f · each run is capped at $%.2f", tot, plan.cap)).ui(TypeScale.small).foregroundStyle(t.text2.color) }
            if overCap { Text("A run is over its cap: lower the questions or raise the cap.").ui(TypeScale.small).foregroundStyle(t.needsText.color) }
        }
    }

    private func refresh() {
        for task in plan.tasks { for m in plan.models {
            let k = "\(task)|\(m)"
            board.estimate(task: task, model: m, limit: plan.limit, epochs: Int(epochsText), place: plan.place) { r in
                switch r {
                case .success(let e): estimates[k] = e; estimateErrors[k] = nil
                case .failure(let err): estimates[k] = nil; estimateErrors[k] = err.message
                }
            }
        } }
    }
}

// MARK: - Runs (LAB-1983)

struct EvalsRunsTab: View {
    @ObservedObject var board: EvalsBoard
    @Environment(\.theme) private var t
    var body: some View {
        if board.runs.isEmpty {
            Text("No runs yet. Pick a benchmark in Catalog and choose Run this…, or try the free guided run in Learn.")
                .ui(TypeScale.body).foregroundStyle(t.text2.color)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(board.runs) { r in
                        Card(padding: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("\(r.task ?? "?") × \(r.model ?? "?")  ·  \(EvalModels.when(r.created))").ui(TypeScale.row, .medium).foregroundStyle(t.text.color)
                                    Text("\(r.id) · \(r.limit ?? 0) questions" + (r.epochs.map { " × \($0)" } ?? ""))
                                        .ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                                }
                                Spacer()
                                if let f = r.fraction, r.isActive { ProgressView(value: f).frame(width: 140) }
                                Text(r.progress).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                                Text(r.status ?? "").ui(TypeScale.small, .semibold).foregroundStyle(color(r.status))
                                    .frame(width: 84, alignment: .trailing)
                                if r.isActive { RoofButton("Cancel") { board.cancel(r.id) } }
                                if r.canResume { RoofButton("Resume") { board.resume(r.id) } }
                                if r.status == "done" || r.status == "failed" { RoofButton("Results") { board.tab = .results } }
                            }
                        }
                    }
                }
            }
        }
    }
    private func color(_ s: String?) -> Color {
        switch s {
        case "done": return t.diffAddText.color
        case "failed", "interrupted": return t.needsText.color
        default: return t.text2.color
        }
    }
}

// MARK: - Results (LAB-1984 matrix, LAB-1985 compare, LAB-1986 drill-down, LAB-1987 cost + export)

struct EvalsResultsTab: View {
    @ObservedObject var board: EvalsBoard
    @Environment(\.theme) private var t
    @State private var open: EvalResult?
    @State private var compareA: String?
    @State private var compareB: String?

    var body: some View {
        if let r = open {
            EvalRunDetail(board: board, result: r) { open = nil }
        } else if board.results.isEmpty {
            Text("No results yet.").ui(TypeScale.body).foregroundStyle(t.text2.color)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Latest finished run per model and task. The number is the main score; the bar shows its 95 % range. Dashed: fewer than 30 questions.")
                            .ui(TypeScale.small).foregroundStyle(t.text2.color)
                        Spacer()
                        RoofButton("Export CSV") { board.export(format: "csv") }
                        RoofButton("Export JSON") { board.export(format: "json") }
                    }
                    matrix
                    EvalCompareCard(board: board, a: $compareA, b: $compareB)
                    Text("Every run").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    ForEach(board.results) { r in runRow(r) }
                }
            }
        }
    }

    private var matrix: some View {
        let m = EvalStats.matrix(board.results)
        let models = m.keys.sorted()
        let tasks = Array(Set(m.values.flatMap(\.keys))).sorted()
        return ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("").frame(width: 220)
                    ForEach(tasks, id: \.self) { Text($0).ui(TypeScale.caption, .semibold, mono: true).foregroundStyle(t.text2.color).frame(width: 130) }
                }
                ForEach(models, id: \.self) { model in
                    GridRow {
                        Text(EvalModels.short(model)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).frame(width: 220, alignment: .leading).lineLimit(1)
                        ForEach(tasks, id: \.self) { task in cell(m[model]?[task]) }
                    }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ r: EvalResult?) -> some View {
        if let r, let p = r.primary, let v = p.value {
            Button { open = r } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(format(v, p)).ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color)
                    EvalIntervalBar(metric: p).frame(height: 6)
                    Text("n=\(p.n ?? 0)" + ((r.cost ?? 0) > 0 ? String(format: " · $%.3f", r.cost!) : (r.isFree ? " · free" : "")))
                        .ui(TypeScale.micro, mono: true).foregroundStyle(t.text3.color)
                    if let j = r.judgeAgreement {   // a judged score: how far to trust it (LAB-1996)
                        Text(j.short).ui(TypeScale.micro).foregroundStyle(j.trustworthy ? t.text2.color : t.needsText.color)
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8).frame(width: 130, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(t.separator.color, style: StrokeStyle(lineWidth: 1, dash: EvalStats.isSmall(p.n) ? [4, 3] : [])))
            }
            .buttonStyle(.plain)
            .help("\(p.label) · 95 % \(p.ci95.map { String(format: "%.3f to %.3f", $0[0], $0[1]) } ?? "n/a") · open the run")
        } else {
            Text("–").ui(TypeScale.small).foregroundStyle(t.text3.color).frame(width: 130)
        }
    }

    private func runRow(_ r: EvalResult) -> some View {
        Button { open = r } label: {
            HStack(spacing: 10) {
                Text("\(r.task ?? "?") × \(EvalModels.short(r.model ?? "?"))").ui(TypeScale.small, .medium).foregroundStyle(t.text.color).frame(width: 330, alignment: .leading)
                Text(r.status ?? "").ui(TypeScale.small).foregroundStyle(r.status == "done" ? t.text2.color : t.needsText.color).frame(width: 70, alignment: .leading)
                if let p = r.primary, let v = p.value { Text("\(p.metric) \(format(v, p))").ui(TypeScale.small, mono: true).foregroundStyle(t.text.color) }
                if let j = r.judgeAgreement {
                    Text(j.short).ui(TypeScale.caption).foregroundStyle(j.trustworthy ? t.text2.color : t.needsText.color).lineLimit(1)
                }
                Spacer()
                Text(EvalModels.when(r.started)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

func evalFormat(_ v: Double, _ p: EvalMetric) -> String { p.ciMethod == "wilson" ? String(format: "%.1f %%", v * 100) : String(format: "%.3f", v) }
private func format(_ v: Double, _ p: EvalMetric) -> String { evalFormat(v, p) }

/// The 95 % range drawn on 0…1 (proportions) or around the value (others).
struct EvalIntervalBar: View {
    let metric: EvalMetric
    @Environment(\.theme) private var t
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let (lo, hi, v) = scaled
            ZStack(alignment: .leading) {
                Capsule().fill(t.control.color).frame(height: 4)
                Capsule().fill(t.accent.color.opacity(0.35)).frame(width: max((hi - lo) * w, 2), height: 4).offset(x: lo * w)
                Circle().fill(t.accent.color).frame(width: 6, height: 6).offset(x: v * w - 3)
            }
        }
        .accessibilityLabel("95 percent range")
    }
    private var scaled: (Double, Double, Double) {
        guard let v = metric.value else { return (0, 0, 0) }
        let ci = metric.ci95 ?? [v, v]
        if metric.ciMethod == "wilson" { return (ci[0], ci[1], v) }
        let span = max(abs(ci[1] - ci[0]), 1e-9) * 2
        let base = v - span / 2
        return ((ci[0] - base) / span, (ci[1] - base) / span, 0.5)
    }
}

struct EvalCompareCard: View {
    @ObservedObject var board: EvalsBoard
    @Binding var a: String?
    @Binding var b: String?
    @Environment(\.theme) private var t
    @State private var result: EvalStats.Comparison?
    @State private var working = false

    var body: some View {
        let done = board.results.filter { $0.status == "done" }
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Compare two runs").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                HStack {
                    pick("A", $a, done)
                    pick("B", $b, done)
                    RoofButton(working ? "Comparing…" : "Compare", .primary, action: compare).disabled(a == nil || b == nil || a == b || working)
                }
                if let c = result {
                    Text("\(c.verdict.rawValue): difference \(String(format: "%+.3f", c.diff)), 95 % range \(String(format: "%+.3f to %+.3f", c.lo, c.hi)) over \(c.n) \(c.paired ? "shared questions (paired)" : "questions (unpaired: the runs share no questions)")")
                        .ui(TypeScale.body, .medium).foregroundStyle(c.verdict == .noise ? t.text2.color : t.text.color)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(EvalGlossary.entry("compare")?.body ?? "").ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func pick(_ label: String, _ sel: Binding<String?>, _ runs: [EvalResult]) -> some View {
        let cur = runs.first { $0.id == sel.wrappedValue }
        return FieldMenu(title: "\(label): " + (cur.map { "\($0.task ?? "?") × \(EvalModels.short($0.model ?? "?"))" } ?? "choose a run"), expand: false) {
            ForEach(runs) { r in Button("\(r.task ?? "?") × \(r.model ?? "?") · \(r.id)") { sel.wrappedValue = r.id; result = nil } }
        }
    }

    private func compare() {
        guard let a, let b else { return }
        working = true
        board.samples(a) { sa in
            board.samples(b) { sb in
                result = EvalStats.compare(sa, sb)
                working = false
            }
        }
    }
}

struct EvalRunDetail: View {
    @ObservedObject var board: EvalsBoard
    let result: EvalResult
    var back: () -> Void
    @Environment(\.theme) private var t
    @State private var samples: [EvalSample] = []
    @State private var onlyWrong = false
    @State private var transcript: (EvalSample, EvalTranscript)?

    var body: some View {
        let r = result
        VStack(alignment: .leading, spacing: 12) {
            Button(action: back) { Text("‹ Results").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain).keyboardShortcut("[", modifiers: .command)
            Text("\(r.task ?? "?") × \(r.model ?? "?")").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            Text(facts(r)).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            if let e = r.error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled) }
            ForEach(Array(r.metrics.enumerated()), id: \.offset) { _, m in
                HStack(spacing: 12) {
                    Text(m.label).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).frame(width: 300, alignment: .leading)
                    if let v = m.value {
                        Text(evalFormat(v, m)).ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 80, alignment: .leading)
                        EvalIntervalBar(metric: m).frame(width: 160, height: 6)
                        Text(m.ci95.map { "95 % " + (m.ciMethod == "wilson" ? String(format: "%.1f–%.1f %%", $0[0] * 100, $0[1] * 100) : String(format: "%.3f–%.3f", $0[0], $0[1])) } ?? "")
                            .ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                    } else {
                        Text("n/a — \(m.note ?? "")").ui(TypeScale.small).foregroundStyle(t.text3.color)
                    }
                }
            }
            HStack {
                Text("Questions").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Toggle("Only the ones it got wrong", isOn: $onlyWrong).toggleStyle(.checkbox)
                Spacer()
                Text("\(samples.count) answers").ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
            HStack(alignment: .top, spacing: 14) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(samples.filter { !onlyWrong || ($0.score ?? 0) < 1 }) { s in
                            Button { board.transcript(r.id, s) { transcript = (s, $0) } } label: {
                                HStack(spacing: 8) {
                                    Text((s.score ?? 0) >= 1 ? "✓" : "✕").ui(TypeScale.small, .semibold)
                                        .foregroundStyle((s.score ?? 0) >= 1 ? t.diffAddText.color : t.diffDelText.color)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(s.input ?? s.sampleID).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(2)
                                        Text("answer \(s.answer ?? "–") · expected \(s.target ?? "–")" + (s.epoch > 1 ? " · attempt \(s.epoch)" : ""))
                                            .ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
                                    }
                                }
                                .padding(6).frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                                    .fill(transcript?.0.id == s.id ? t.selection.color : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(width: 440)
                if let (s, tr) = transcript {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Question \(s.sampleID)" + (s.epoch > 1 ? " · attempt \(s.epoch)" : "")).ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                            ForEach(Array(tr.messages.enumerated()), id: \.offset) { _, m in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(m.role).ui(TypeScale.caption, .semibold, mono: true).foregroundStyle(t.text3.color)
                                    Text(m.text).ui(TypeScale.small).foregroundStyle(t.text.color).textSelection(.enabled)
                                    ForEach(Array(m.toolCalls.enumerated()), id: \.offset) { _, c in
                                        Text("→ \(c.function)(\(c.arguments))").ui(TypeScale.caption, mono: true).foregroundStyle(t.accentText.color)
                                    }
                                }
                            }
                            Text("Expected: \(tr.target ?? "–")").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                            ForEach(tr.scores.keys.sorted(), id: \.self) { k in
                                let sc = tr.scores[k]!
                                Text("Scorer \(k): \(sc.value)" + (sc.explanation.map { $0.isEmpty ? "" : " — \($0)" } ?? ""))
                                    .ui(TypeScale.small).foregroundStyle(t.text2.color).textSelection(.enabled)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { board.samples(result.id) { samples = $0 } }
    }

    private func facts(_ r: EvalResult) -> String {
        var f = ["\(r.status ?? "?")", "\(r.samplesDone ?? 0) answers"]
        if let i = r.inputTokens, let o = r.outputTokens { f.append("\(i.formatted()) in / \(o.formatted()) out tokens") }
        if let c = r.cost, c > 0 { f.append(String(format: "$%.4f", c) + (r.isFree ? " (the benchmark's grader)" : "")) }
        else if r.isFree { f.append("free") } else { f.append("cost unknown") }
        if let c = r.costPerCorrect { f.append(String(format: "$%.4f per correct answer", c)) }
        if let d = r.duration { f.append(String(format: "%.0f s", d)) }
        if let s = r.seed { f.append("seed \(s)") }
        if let v = r.inspectEvals { f.append("inspect-evals \(v)") }
        return f.joined(separator: " · ")
    }
}

// MARK: - Learn (LAB-1988 explainers, LAB-1989 guided first run)

struct EvalsLearnTab: View {
    @ObservedObject var board: EvalsBoard
    var run: (EvalRunPlan) -> Void
    @Environment(\.theme) private var t
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your first eval, free").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                        Text("1. Run 5 GSM8K math questions on the stand-in model (it always gives the same wrong answer, and costs nothing). 2. Open Results: the score is 0 %, but the 95 % range goes up to 43 % — five questions say very little. 3. Open a question to see the prompt, the answer and how it was scored. 4. Then run the same 5 questions on a real, cheap model and compare the two runs.")
                            .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            RoofButton("Step 1: run it free", .primary) {
                                run(EvalRunPlan(tasks: ["gsm8k"], models: ["mockllm/model"], limit: 5, cap: 0))
                            }
                            RoofButton("Step 4: same questions on a cheap model") {
                                run(EvalRunPlan(tasks: ["gsm8k"], models: ["anthropic/claude-haiku-5-5"], limit: 5, cap: 0.05))
                            }
                        }
                    }
                }
                ForEach(EvalGlossary.all) { e in
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(e.title).ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                            Text(e.body).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                            Text("Example: " + e.example).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}
