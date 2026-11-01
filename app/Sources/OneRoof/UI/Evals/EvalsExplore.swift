import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2063 · Explore (Claude Design 1A-1 = HP E1.1): shelves and topics · benchmarks with what they are made of · one
/// benchmark's page with Anatomy · Questions · Scores · Your runs. Replaces Catalog: search, Start here, No Docker needed,
/// category and Rescan all stay (NO_REGRESSION).
struct EvalsExploreTab: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var filter = EvalExploreFilter(shelf: .start)
    @ObservedObject private var hf = HFAccount.shared   // LAB-2117: rows show Locked until the user's own sign-in
    @FocusState private var searchFocused: Bool
    @FocusState private var listFocused: Bool
    @State private var hintSeen = Prefs.viewState.bool(forKey: "evals.exploreHintSeen")

    var body: some View {
        if let c = board.catalog {
            let ran = Set(board.results.compactMap(\.task))
            let shown = filter.apply(c.benchmarks, ran: ran)
            HStack(alignment: .top, spacing: 0) {
                shelves(c.benchmarks, ran: ran).frame(width: 170)
                Rectangle().fill(t.separator.color).frame(width: 1).padding(.horizontal, 12)
                list(c, shown: shown, ran: ran).frame(width: 290)
                Rectangle().fill(t.separator.color).frame(width: 1).padding(.horizontal, 12)
                Group {
                    if filter.shelf == .judges {
                        Text("Your judges grade prose answers against your labels. Pick one to label answers and see how far to trust it.")
                            .ui(TypeScale.body).foregroundStyle(t.text2.color).frame(maxWidth: 460, alignment: .leading)
                    } else if let b = selected(c, shown) {
                        EvalsBenchmarkPage(board: board, nav: nav, benchmark: b).id(b.id)
                    } else {
                        Text("No benchmark matches these filters.").ui(TypeScale.body).foregroundStyle(t.text2.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).frame(width: 0, height: 0))
        } else {
            Text(board.busy ?? "Reading the benchmarks…").ui(TypeScale.body).foregroundStyle(t.text2.color)
        }
    }

    private func selected(_ c: EvalCatalog, _ shown: [EvalBenchmark]) -> EvalBenchmark? {
        if let id = nav.benchmark, let b = shown.first(where: { $0.id == id || $0.tasks.contains { $0.name == id } }) { return b }
        return shown.first
    }

    // MARK: Left: shelves, what it tests, graded by, checkboxes

    private func shelves(_ bs: [EvalBenchmark], ran: Set<String>) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                EvalsLabel("Shelves").padding(.bottom, 4)
                ForEach(EvalExploreFilter.Shelf.allCases, id: \.self) { s in
                    shelfRow(s.rawValue, count: s == .judges ? board.judges.count : EvalExploreFilter.count(bs, shelf: s),
                             on: filter.shelf == s && filter.topic == nil && filter.category == nil) {
                        filter.shelf = s; filter.topic = nil; filter.category = nil
                    }
                }
                EvalsLabel("What it tests").padding(.top, 12).padding(.bottom, 4)
                ForEach(EvalBenchmark.topics, id: \.self) { topic in
                    let n = EvalExploreFilter.count(bs, topic: topic)
                    if n > 0 {
                        shelfRow(topic, count: n, on: filter.topic == topic) { filter.topic = topic; filter.shelf = nil; filter.category = nil }
                    }
                }
                let more = EvalExploreFilter.otherCategories(bs)
                if !more.isEmpty {
                    FieldMenu(title: filter.category ?? "More topics", height: 26) {
                        ForEach(more, id: \.self) { cat in Button(cat) { filter.category = cat; filter.topic = nil; filter.shelf = nil } }
                    }
                    .padding(.top, 4)
                }
                EvalsLabel("Graded by").padding(.top, 12).padding(.bottom, 4)
                ForEach([("code", "Code / exact match"), ("judge", "Model judge"), ("tests", "Runs tests")], id: \.0) { key, label in
                    Toggle(label, isOn: Binding(get: { filter.gradedBy.contains(key) },
                                                set: { on in if on { filter.gradedBy.insert(key) } else { filter.gradedBy.remove(key) } }))
                        .toggleStyle(.checkbox).ui(TypeScale.small)
                }
                Rectangle().fill(t.separator.color).frame(height: 1).padding(.vertical, 8)
                Toggle("No Docker needed", isOn: $filter.noDocker).toggleStyle(.checkbox).ui(TypeScale.small)
                Toggle("I've run it", isOn: $filter.ranIt).toggleStyle(.checkbox).ui(TypeScale.small)
            }
        }
    }

    private func shelfRow(_ title: String, count: Int, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).ui(TypeScale.small, on ? .semibold : .regular).foregroundStyle(t.text.color)
                Spacer()
                Text("\(count)").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
            }
            .padding(.vertical, 4).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: 7, selected: on)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Middle: search and benchmarks

    private func list(_ c: EvalCatalog, shown: [EvalBenchmark], ran: Set<String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search benchmarks", text: $filter.search).textFieldStyle(.roundedBorder).focused($searchFocused)
                .accessibilityLabel("Search benchmarks (⌘F)")
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        if filter.shelf == .judges {
                            ForEach(board.judges) { j in judgeRow(j) }
                            if board.judges.isEmpty {
                                Text("No judges yet: make one in Your evals › A judge for prose answers.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                            }
                        } else {
                            ForEach(shown) { b in row(b, on: b.id == selected(c, shown)?.id, runs: runCount(b)).id(b.id) }
                        }
                        if !hintSeen {
                            HStack(alignment: .top) {
                                Text("The second line of each row says what the benchmark is made of: the question type and how it's graded.")
                                    .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                                Button("✕") { hintSeen = true; Prefs.viewState.set(true, forKey: "evals.exploreHintSeen") }
                                    .buttonStyle(.plain).foregroundStyle(t.text3.color).accessibilityLabel("Hide this hint")
                            }
                            .padding(.top, 10).padding(.horizontal, 8)
                        }
                    }
                }
                .focusable().focused($listFocused).focusEffectDisabled()
                .onKeyPress(.downArrow) { move(1, shown, proxy); return .handled }
                .onKeyPress(.upArrow) { move(-1, shown, proxy); return .handled }
                .onKeyPress(.return) { nav.exploreTab = .anatomy; return .handled }
            }
            Rectangle().fill(t.separator.color).frame(height: 1)
            HStack(spacing: 4) {
                Text(EvalCatalog.footer(shown: shown, total: c, ownShelf: filter.shelf == .own) + " · inspect-evals \(c.inspectEvals ?? "?") ·")
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                Button("Rescan benchmarks") { board.refreshCatalog(force: true) }.buttonStyle(.plain)
                    .font(.system(size: TypeScale.caption)).foregroundStyle(t.accentText.color)
            }
            .lineLimit(1).minimumScaleFactor(0.85)
            if let v = board.doctor?.engine.inspectAI {
                Text("Inspect \(v)").ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
        }
    }

    private func move(_ d: Int, _ shown: [EvalBenchmark], _ proxy: ScrollViewProxy) {
        guard !shown.isEmpty else { return }
        let i = shown.firstIndex { $0.id == (nav.benchmark ?? shown[0].id) } ?? 0
        let j = min(max(i + d, 0), shown.count - 1)
        nav.benchmark = shown[j].id
        proxy.scrollTo(shown[j].id)
    }

    private func runCount(_ b: EvalBenchmark) -> Int {
        let names = Set(b.tasks.map { EvalBenchmark.taskLabel($0.name) })
        return board.results.filter { names.contains($0.task ?? "") }.count
    }

    private func row(_ b: EvalBenchmark, on: Bool, runs: Int) -> some View {
        Button { nav.benchmark = b.id; nav.exploreTab = .anatomy } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(b.shortName).ui(TypeScale.row, on ? .semibold : .medium).foregroundStyle(t.text.color).lineLimit(1).help(b.name)
                    Spacer()
                    if let n = b.questionCount { Text(n.formatted()).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color) }
                }
                if let m = b.madeOf {
                    Text(m).ui(11.5).foregroundStyle(t.text2.color).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(b.category + (b.sandbox ? " · Docker" : "")).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                }
                let locked = hf.status(EvalSources.table[b.folder]).locked   // LAB-2117
                if b.isStarter || runs > 0 || b.sandbox || locked {
                    HStack(spacing: 6) {
                        if locked { EvalsChip(text: "Locked · Hugging Face") }
                        if b.isStarter { EvalsChip(text: "★ Start here") }
                        if runs > 0 { EvalsChip(text: "run \(runs)×", accent: true) }
                        if b.sandbox { EvalsChip(text: "Docker") }
                    }
                }
            }
            .padding(.vertical, 7).padding(.horizontal, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hoverHighlight(radius: Radius.row, selected: on)
        .accessibilityLabel("\(b.name), \(b.madeOf ?? b.category)" + (b.isStarter ? ", start here" : "") + (runs > 0 ? ", run \(runs) times" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func judgeRow(_ j: EvalJudgeList.Judge) -> some View {
        Button { nav.tab = .yourEvals; nav.route = .judge(name: j.name, first: nil) } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(j.name.replacingOccurrences(of: "_", with: " ") + " judge").ui(TypeScale.row, .medium).foregroundStyle(t.text.color)
                Text("\(j.items) answers · \(j.labelled) labelled by you").ui(11.5).foregroundStyle(t.text2.color)
            }
            .padding(.vertical, 7).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverHighlight()
    }
}

/// One benchmark's page: eyebrow, title, summary, Run this…, and its four sub-tabs.
struct EvalsBenchmarkPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let benchmark: EvalBenchmark
    @Environment(\.theme) private var t
    @State private var anatomy: EvalAnatomy?
    @State private var anatomyError: String?
    @State private var set: EvalSetDetail?
    @ObservedObject private var hf = HFAccount.shared

    /// LAB-2117: where the data comes from (nil for your own sets) and whether it is locked here.
    private var source: EvalDataSource? { EvalSources.source(folder: benchmark.folder, dataset: anatomy?.dataset, gated: anatomy?.gated ?? false) }

    var body: some View {
        let b = benchmark
        let runs = myRuns
        let src = source
        let gate = hf.status(src)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(anatomy?.eyebrow ?? b.category).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                        Text(b.name).ui(22, .bold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    if gate.locked {
                        RoofButton("Locked · how to unlock") { NotificationCenter.default.post(name: .openEvalsSettings, object: nil) }
                            .help(EvalSources.lockedLine)
                    } else {
                        RoofButton("Run this…", .primary) {
                            nav.run(EvalRunPlan(benchmark: b, tasks: [b.defaultTask], limit: b.firstRunLimit))
                        }
                        .help("Opens the run sheet with this benchmark; the cost shows before anything starts")
                    }
                }
                Text(b.description).ui(TypeScale.body).foregroundStyle(t.text.color).lineLimit(5).fixedSize(horizontal: false, vertical: true)
                if let src { EvalsSourceLine(source: src) }
                if let src, gate.locked { EvalsLockCard(name: b.name, source: src, status: gate) }
                EvalsTextTabs(options: tabs(runs: runs.count), selection: Binding(get: { nav.exploreTab }, set: { tab in
                    if tab == .questions { nav.route = .questions(benchmark: b.id, task: b.defaultTask) } else { nav.exploreTab = tab }
                }))
                Rectangle().fill(t.separator.color).frame(height: 1).padding(.top, -12)
                switch nav.exploreTab {
                case .scores: EvalsScoresView(board: board, benchmark: b, runs: runs)
                case .runs: yourRuns(runs)
                default: if b.isOwn { ownAnatomy } else { anatomyView(b, runs: runs) }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.bottom, 20)
        }
        .onAppear(perform: load)
    }

    private func tabs(runs: Int) -> [(EvalsNav.ExploreTab, String)] {
        var o: [(EvalsNav.ExploreTab, String)] = [(.anatomy, "Anatomy"),
                                                  (.questions, "Questions" + (benchmark.questionCount.map { " \($0.formatted())" } ?? ""))]
        if !benchmark.isOwn { o.append((.scores, "Scores")) }   // your own set has no published scores
        o.append((.runs, "Your runs \(runs)"))
        return o
    }

    private var myRuns: [EvalResult] {
        let names = Set(benchmark.tasks.map { EvalBenchmark.taskLabel($0.name) })
        return board.results.filter { names.contains($0.task ?? "") && $0.status == "done" }
    }

    private func load() {
        if benchmark.isOwn {
            let name = String(benchmark.folder.dropFirst(4))   // "own-<name>"
            board.ask(["evalset", "show", name], EvalSetDetail.self) { if case .success(let s) = $0 { set = s } }
        } else {
            board.ask(["anatomy", benchmark.folder], EvalAnatomy.self, timeout: 120) { r in
                switch r { case .success(let a): anatomy = a; case .failure(let e): anatomyError = e.message }
            }
        }
    }

    // MARK: Anatomy

    @ViewBuilder private func anatomyView(_ b: EvalBenchmark, runs: [EvalResult]) -> some View {
        if let a = anatomy {
            EvalsFactsStrip(facts: a.facts.map { f in
                (f.label, f.value, f.label == "Headroom" ? (a.headroom?.saturated == true ? t.needsText : t.diffAddText) : nil)
            }, hover: { label, value in   // LAB-2070: Chance and Headroom explain themselves
                label == "Chance" ? (.chance, EvalHover.chance(value))
                    : label == "Headroom" ? (.headroom, EvalHover.headroom(value, saturated: a.headroom?.saturated == true)) : nil
            })
            EvalsLabel("How one question is scored").padding(.top, 4)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(a.steps.enumerated()), id: \.offset) { i, s in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(i + 1) · \(s.title)").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                        Text(s.body).ui(11.5, mono: i == 1 && s.body.contains("ANSWER")).foregroundStyle(t.text2.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surface.color))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
                }
            }
            HStack(alignment: .top, spacing: 12) {
                onThisMac(runs).frame(maxWidth: .infinity, alignment: .topLeading)
                teaches(a).frame(maxWidth: .infinity, alignment: .topLeading)
            }
            footer(a, b)
            tasks(b)
        } else if let e = anatomyError {
            Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color)
        } else {
            Text("Reading what this benchmark is made of…").ui(TypeScale.small).foregroundStyle(t.text3.color)
        }
    }

    private func onThisMac(_ runs: [EvalResult]) -> some View {
        let latest = Array(runs.prefix(4))
        let pairs = latest.compactMap { r -> (Double, Int)? in
            guard let p = r.primary, let v = p.value, p.ciMethod == "wilson" else { return nil }
            return (v, p.n ?? 0)
        }
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                EvalsLabel("On this Mac so far")
                if latest.isEmpty {
                    Text("Not run here yet. Run this… shows the cost first.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
                ForEach(latest) { r in
                    Button { nav.openRun(r.id) } label: {
                        HStack(spacing: 10) {
                            Text(r.contestant?.name ?? EvalModels.short(r.model ?? "?")).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color)
                                .lineLimit(1).frame(width: 150, alignment: .leading)
                            if let p = r.primary, let v = p.value {
                                Text(evalFormat(v, p)).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 58, alignment: .trailing)
                                EvalIntervalBar(metric: p).frame(height: 6)
                                    .evalHoverIf(p.ciMethod == "wilson" ? (.range, EvalHover.range(score: v, n: p.n ?? 0, lo: p.ci95?.first ?? v, hi: p.ci95?.last ?? v)) : nil)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if let w = EvalRangeWarning.text(pairs.map { (score: $0.0, n: $0.1) }) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(w).ui(TypeScale.caption).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                        Button("Why ›") { nav.openLesson("range") }.buttonStyle(.plain).font(.system(size: TypeScale.caption))
                            .foregroundStyle(t.accentText.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func teaches(_ a: EvalAnatomy) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                EvalsLabel("What it teaches")
                Text(a.teaches ?? a.lesson ?? "—").ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                if let w = a.watchOut, !w.isEmpty {
                    EvalsLabel("Watch out").padding(.top, 4)
                    ForEach(w, id: \.self) { Text($0).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func footer(_ a: EvalAnatomy, _ b: EvalBenchmark) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Rectangle().fill(t.separator.color).frame(height: 1)
            HStack(alignment: .top, spacing: 16) {
                (Text("Needs ").bold() + Text((a.needs ?? []).joined(separator: " · ")))
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).frame(maxWidth: 260, alignment: .leading)
                EvalsCostLine(board: board, benchmark: b, judged: a.gradedBy == "judge").frame(maxWidth: .infinity, alignment: .leading)
                if let p = a.paper?.split(separator: ",").first, let url = URL(string: String(p)) {
                    Link("Paper ↗", destination: url).font(.system(size: TypeScale.small))
                }
            }
        }
    }

    /// Every task of the benchmark with its questions and the score people reach, where known (1.9.37's card kept).
    @ViewBuilder private func tasks(_ b: EvalBenchmark) -> some View {
        if b.tasks.count > 1 || b.tasks.contains(where: { $0.humanBaseline?.score != nil }) {
            VStack(alignment: .leading, spacing: 3) {
                EvalsLabel("Tasks")
                ForEach(b.tasks, id: \.name) { task in
                    HStack(spacing: 10) {
                        Text(EvalBenchmark.taskLabel(task.name)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color)
                        if let n = task.samples { Text("\(n.formatted()) questions").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                        if let h = task.humanBaseline, let sc = h.score {
                            Text("people: \(Int((sc * 100).rounded())) % \(h.metric ?? "")").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        }
                    }
                }
            }
        }
    }

    /// Your own set: what it is, its floor and best so far (no published scores for your work).
    @ViewBuilder private var ownAnatomy: some View {
        if let s = set {
            Text(s.description ?? "").ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            EvalsFactsStrip(facts: [("Cases", "\(s.count) · v\(s.version)", nil),
                                    ("No-model floor", "\(s.floor.right) of \(s.floor.of) · \(evalsPct(Double(s.floor.right) / Double(max(s.floor.of, 1))))", nil),
                                    ("Best so far", s.best.map { "\(evalsPct($0.score)) · \($0.contestant)" } ?? "not run yet", nil)],
                            hover: { label, _ in label == "No-model floor" ? (.floor, EvalHover.floor(share: nil, right: s.floor.right, of: s.floor.of)) : nil })
            RoofButton("Open in Your evals ›") { nav.set = s.name; nav.go(.yourEvals) }
        } else {
            Text("Reading your set…").ui(TypeScale.small).foregroundStyle(t.text3.color)
        }
    }

    private func yourRuns(_ runs: [EvalResult]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if runs.isEmpty { Text("No runs of this benchmark on this Mac yet.").ui(TypeScale.small).foregroundStyle(t.text3.color) }
            ForEach(runs) { r in
                Button { nav.openRun(r.id) } label: {
                    HStack(spacing: 12) {
                        Text(EvalModels.when(r.started)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color).frame(width: 90, alignment: .leading)
                        Text(r.contestant?.name ?? EvalModels.short(r.model ?? "?")).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color)
                            .lineLimit(1).frame(width: 200, alignment: .leading)
                        if let k = r.contestant?.kind { EvalsKindTag(kind: k) }
                        Text("n=\(r.primary?.n ?? r.samplesDone ?? 0)").ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).frame(width: 50, alignment: .leading)
                        if let p = r.primary, let v = p.value {
                            Text(evalFormat(v, p)).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 60, alignment: .trailing)
                            EvalIntervalBar(metric: p).frame(width: 140, height: 6)
                        }
                        Spacer()
                        Text(r.cost.map { $0 > 0 ? String(format: "$%.4f", $0) : "free" } ?? (r.isFree ? "free" : "–"))
                            .ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                    }
                    .padding(.vertical, 5).padding(.horizontal, 6).contentShape(Rectangle())
                }
                .buttonStyle(.plain).hoverHighlight()
            }
        }
    }
}

/// "50 questions: haiku $0.06 · sonnet $0.41 · gpt-5-mini $0.09 + judge $0.02" from the engine's estimate.
struct EvalsCostLine: View {
    @ObservedObject var board: EvalsBoard
    let benchmark: EvalBenchmark
    var judged = false
    @Environment(\.theme) private var t
    @State private var est: [String: EvalEstimate] = [:]
    private let models = ["anthropic/claude-haiku-5-5", "anthropic/claude-sonnet-5-5", "openai/gpt-5-mini"]
    var body: some View {
        let parts = models.map { m -> String in
            let short = EvalModels.short(m).replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: "-5-5", with: "")
            return short + " " + (est[m].flatMap { $0.modelUSD ?? $0.usd }.map { String(format: "$%.2f", $0) } ?? "…")
        }
        let grader = est.values.compactMap { $0.grader?.usd }.max()
        return (Text("\(benchmark.firstRunLimit) questions ").bold() + Text(parts.joined(separator: " · ")
                + (grader.map { $0 > 0 ? String(format: " · + judge $%.2f", $0) : "" } ?? "")))
            .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            .help("Prices from OpenRouter's public list; answer length is a guess until this Mac has run the benchmark.")
            .onAppear {
                for m in models {
                    board.estimate(task: benchmark.defaultTask, model: m, limit: benchmark.firstRunLimit, epochs: nil) { r in
                        if case .success(let e) = r { est[m] = e }
                    }
                }
            }
    }
}

/// Scores (blend addition, LAB-2063 / EVO-3): published best scores, one official source, each with its date, beside
/// this Mac's latest run of the same model when there is one.
struct EvalsScoresView: View {
    @ObservedObject var board: EvalsBoard
    let benchmark: EvalBenchmark
    let runs: [EvalResult]
    @Environment(\.theme) private var t
    @State private var scores: EvalPublishedScores?
    @State private var error: String?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let s = scores {
                HStack {
                    EvalsLabel("Published best scores")
                    Spacer()
                    if s.hasSource {
                        Button(checking ? "Checking…" : "Check now") { refresh() }.buttonStyle(.plain).disabled(checking)
                            .font(.system(size: TypeScale.caption)).foregroundStyle(t.accentText.color)
                    }
                }
                if let f = s.failed {
                    Text("Last check failed on \(f.date): \(f.reason)" + (s.rows.isEmpty ? "" : " Showing the last good values."))
                        .ui(TypeScale.caption).foregroundStyle(t.needsText.color)
                }
                if s.rows.isEmpty {
                    Text(s.hasSource ? "No published score yet. The weekly check looks at: \(s.source?.name ?? "")."
                                     : "No published score yet: no official source is listed for this benchmark.")
                        .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                } else {
                    table(s)
                    Text("Published numbers use their own prompts and settings; compare with care. Checked automatically every week.")
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
            } else if let e = error {
                Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color)
            } else {
                Text("Reading the published scores…").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
        }
        .onAppear { load(auto: true) }
    }

    private func table(_ s: EvalPublishedScores) -> some View {
        // QA (stage 1): the last column had no room left and its label wrapped letter by letter, opening a tall gap above
        // the first row. Setting is the one flexible column now; the labels never wrap.
        let widths: [CGFloat?] = [210, 64, nil, 112, 84]
        func cols(_ v: [AnyView]) -> some View {
            HStack(alignment: .top, spacing: 12) {
                ForEach(Array(v.enumerated()), id: \.offset) { i, c in
                    if let w = widths[i] { c.frame(width: w, alignment: .leading) } else { c.frame(minWidth: 90, maxWidth: .infinity, alignment: .leading) }
                }
            }
        }
        return VStack(alignment: .leading, spacing: 8) {
            cols(["Model or agent", "Score", "Setting", "Source", "This Mac"].map { AnyView(EvalsLabel($0).lineLimit(1).fixedSize()) })
            ForEach(s.ordered) { r in
                let old = r.stale == true
                cols([
                    AnyView(VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(r.contestant).ui(TypeScale.small).foregroundStyle((old ? t.text3 : t.text).color).lineLimit(2)
                            if r.kind == "agent" { EvalsKindTag(kind: .agent) }
                        }
                        if let p = r.published { Text("published \(p)").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                    }),
                    AnyView(Text(evalsPct(r.score) + (r.plusMinus.map { " ±" + String(format: "%.0f", $0 * 100) } ?? ""))
                        .ui(TypeScale.small, .semibold, mono: true).foregroundStyle((old ? t.text3 : t.text).color)),
                    AnyView(Text(r.setting ?? "–").ui(TypeScale.caption).foregroundStyle(t.text2.color).lineLimit(3)),
                    AnyView(VStack(alignment: .leading, spacing: 2) {
                        if let u = URL(string: r.sourceUrl) { Link("source ↗", destination: u).font(.system(size: TypeScale.caption)).help(r.sourceName) }
                        Text("checked \(r.checked)" + (old ? " · may be out of date" : "")).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    }),
                    AnyView(Text(thisMac(r.contestant)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color))])
                .accessibilityElement(children: .combine)
            }
            if let src = s.source { Text("Source: \(src.name)").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
        }
    }

    /// The latest run here of a model whose name matches the published one, with its range; "–" when none.
    private func thisMac(_ name: String) -> String {
        let key = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard key.count >= 4 else { return "–" }
        let hit = runs.first { r in
            let m = EvalModels.short(r.model ?? "").lowercased().filter { $0.isLetter || $0.isNumber }
            return !m.isEmpty && (key.contains(m) || m.contains(key))
        }
        guard let r = hit, let p = r.primary, let v = p.value else { return "–" }
        return evalFormat(v, p) + (p.ci95.map { String(format: " (%.0f–%.0f)", $0[0] * 100, $0[1] * 100) } ?? "")
    }

    private func load(auto: Bool) {
        board.ask(["scores", "show", benchmark.defaultTask] + (auto ? ["--auto"] : []), EvalPublishedScores.self, timeout: 120) { r in
            switch r { case .success(let s): scores = s; error = nil; case .failure(let e): error = e.message }
        }
    }

    private func refresh() {
        checking = true
        board.ask(["scores", "refresh", "--only", benchmark.folder], EvalRefreshAck.self, timeout: 120) { _ in
            checking = false
            load(auto: false)
        }
    }
}

private struct EvalRefreshAck: Decodable { var checked: String? }
