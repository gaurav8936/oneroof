import SwiftUI
import OneRoofCore

/// LAB-2242 · E1.1 Overview, the tab Evals opens on: where do we stand? Two things only (v2 review §4):
/// 1. the inside / outside layer picture — the ONE coverage display — with the counts from `overview.layers` (CONTRACT §7:
///    our tasks vs public benchmarks, grader runs apart); before the 2.0.4 engine answers, the same counts from the run store;
/// 2. the three questions (Which setup does our work best · Did my last change help · What does real history say), each
///    with today's answer chosen by rule from real data (EvalsAQuestions), its evidence and "To answer it properly".
/// 2.0.3's scorecards live on in Compare and All results; "what changed" in Changes; "running now" in the queue (Running · N)
/// and question 1; the suggested next step under the cards; the How to walkthrough in Lessons › How to.
struct EvalsOverviewTab: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    @AppStorage(EvalsRealHistoryView.reposKey, store: Prefs.viewState) private var reposPref = ""
    @AppStorage(EvalsRealHistoryView.daysKey, store: Prefs.viewState) private var days = 60

    private var repos: [String] { EvalsRealHistoryView.repos(reposPref, board: board) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                layerCard
                questions
                if let s = board.overview?.suggestion {
                    Button { follow(s) } label: {
                        (Text("Also suggested: ").foregroundColor(t.text2.color) + Text(s.text + " ›").foregroundColor(t.accentText.color))
                            .ui(TypeScale.small).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
                if let e = board.overviewError {
                    Text("The overview could not be read: " + e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled)
                }
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .padding(.bottom, 20)
        }
        .onAppear(perform: refresh)
        .onChange(of: board.results) { _, _ in store.refreshBoards(board) }
        .onChange(of: board.sets) { _, _ in refresh() }
    }

    private func refresh() {
        store.refreshBoards(board)
        store.refreshChanges(board)
        store.refreshXRay(board, repos: repos, days: days)
    }

    // MARK: 1 · The layer picture

    private var layerData: (layers: [EvalOverviewLayer], graders: Int?, derived: Bool) {
        if let l = board.overview?.layers { return (l, board.overview?.graderRuns, false) }
        let bs = board.catalog?.benchmarks ?? []
        let d = EvalsALayers.derive(results: board.results, runs: board.runs, benchmarks: board.catalog?.count ?? bs.count,
                                    agentBenchmarks: EvalExploreFilter.count(bs, shelf: .agent))
        return (d.layers, d.graders, true)
    }

    private var layerCard: some View {
        let data = layerData
        let bands = EvalsALayers.bands(data.layers)
        return Card(padding: 16) {
            EvalsColumns(breakpoint: 980, side: 250) {
                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { g in
                        let half = g.size.width / 2
                        HStack(spacing: 0) {
                            Text("INSIDE · OUR OWN TASKS").ui(10.5, .semibold).tracking(0.6).foregroundStyle(t.accentText.color)
                                .frame(width: half - 12, alignment: .trailing)
                            Spacer().frame(width: 24)
                            Text("OUTSIDE · PUBLIC BENCHMARKS").ui(10.5, .semibold).tracking(0.6).foregroundStyle(t.text3.color)
                                .frame(width: half - 12, alignment: .leading)
                        }
                    }
                    .frame(height: 14)
                    ForEach(Array(bands.enumerated()), id: \.element.id) { i, b in
                        band(b, width: [0.56, 0.78, 1.0][i])
                    }
                    HStack(spacing: 12) {
                        if let g = EvalsALayers.graderLine(data.graders) { Text(g).ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                        if data.derived {
                            Text("Counted from the run store (the engine's own layer counts come with 2.0.4).").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                        }
                    }
                }
            } aside: {
                VStack(alignment: .leading, spacing: 8) {
                    Text("How to read Evals").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text("Each layer adds one thing to the one above it. Test the same tasks at each layer to see what each part adds.")
                    Text("Inside is what matters: our own bugs, our own work. Outside is context.")
                    Text("The three questions below read from this picture: Compare works on any layer; Changes and Real history work on the base.")
                    Button { nav.go(EvalsLegacyTab.howTo) } label: {
                        Text("Your first test, step by step ›").ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain)
                }
                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 12)
                .overlay(alignment: .leading) { Rectangle().fill(t.separator.color).frame(width: 1) }
            }
        }
    }

    private func band(_ b: EvalsALayerBand, width frac: CGFloat) -> some View {
        GeometryReader { g in
            let w = g.size.width * frac
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                HStack(alignment: .top, spacing: 0) {
                    Button { openInside(b.layer) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(b.kicker.uppercased()).ui(10, .semibold).tracking(0.5).foregroundStyle(t.text3.color)
                            Text(b.layer.title).ui(TypeScale.body, .bold).foregroundStyle(t.text.color)
                            Text(b.how).ui(TypeScale.caption).foregroundStyle(t.text2.color).lineLimit(1)
                            Text(b.inside).ui(TypeScale.small, .semibold).foregroundStyle(insideInk(b.insideTone).color).lineLimit(1)
                                .evalHover(.n, "\(b.layer.title), inside: \(b.inside). Tests on our own tasks; grader runs are counted apart.")
                            Text(b.insideNote).ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
                        }
                        .padding(10).frame(width: w / 2, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(b.layer == .full ? "Our tasks" : "Compare our tasks at this layer")
                    Rectangle().fill(t.separatorStrong.color).frame(width: 1)
                    Button { nav.go(.benchmarks) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Spacer(minLength: 0)
                            Text(b.outside).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                            Text(b.outsideNote).ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
                            Text("Open ›").ui(TypeScale.caption, .semibold).foregroundStyle(t.accentText.color)
                        }
                        .padding(10).frame(width: w / 2, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Public benchmarks, for context")
                }
                .frame(width: w)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.separator.color))
                Spacer(minLength: 0)
            }
        }
        .frame(height: 96)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(b.layer.title): inside \(b.inside); outside \(b.outside)")
    }

    private func insideInk(_ tone: EvalsALayerBand.Tone) -> RGB {
        switch tone { case .measured: return t.text; case .waiting: return t.evalsATone(.cantTell).ink; case .gap: return t.needsText }
    }

    private func openInside(_ l: EvalStamp.Layer) {
        if l == .full { nav.go(.ourTasks) } else { nav.go(.compare) }
    }

    // MARK: 2 · The three questions

    private var questions: some View {
        let boards = store.loaded(board)
        let q1 = EvalsAQuestions.whichSetup(boards)
        let changes: [EvalChange]? = { if case .success(let c)? = store.changes { return c }; return nil }()
        let q2 = EvalsAQuestions.didMyChangeHelp(boards, changes: changes)
        let xk = EvalsAStore.key(repos, days: days)
        let rows: [EvalHistoryRow]? = { if case .success(let x)? = store.xray[xk] { return EvalHistoryRow.from(x) }; return nil }()
        let xerr: String? = { if case .failure(let e)? = store.xray[xk] { return e.message }; return repos.isEmpty ? "Choose a repo in Real history to read its commits." : nil }()
        let q3 = EvalsAQuestions.realHistory(rows, repos: repos.count, days: days, error: xerr)
        return EvalsAFlow(breakpoint: 980) {
            card(1, "Which setup does our work best?", open: { nav.go(.compare) }) {
                EvalsAAnswerBlock(answer: boards.isEmpty && store.error(board) == nil && !board.sets.isEmpty
                                  ? EvalsAAnswer(tone: .reading, headline: "Reading our tasks…", body: "Reading every setup's latest test on our tasks.") : q1.answer)
                if let e = store.error(board), boards.isEmpty {
                    Text("The setups could not be read: " + e).ui(TypeScale.caption).foregroundStyle(t.needsText.color).lineLimit(3)
                }
                if !q1.bars.isEmpty {
                    EvalsLabel(q1.title)
                    ForEach(q1.bars) { b in
                        EvalsABarRow(bar: b, hover: b.value.map { v in (.score, EvalHover.score(score: v, n: boards.first?.n)) })
                    }
                }
            } fix: { q1Fix(boards) }
            card(2, "Did my last change help?", open: { nav.go(.changes) }) {
                EvalsAAnswerBlock(answer: q2)
                EvalsLabel("What a test records today")
                ForEach(EvalsAQuestions.records(boards)) { r in
                    HStack {
                        Text(r.label).ui(TypeScale.small).foregroundStyle(t.text.color)
                        Spacer()
                        Text(r.state.rawValue).ui(TypeScale.small, .semibold)
                            .foregroundStyle(r.state == .yes ? t.diffAddText.color : r.state == .partly ? t.evalsATone(.cantTell).ink.color : t.needsText.color)
                    }
                }
            } fix: {
                fix("LAB-2240 stamps every new test with agent · model · CLI version · rules on/off @ version. Then test the same setup before and after a change.",
                    "Open Changes") { nav.go(.changes) }
            }
            card(3, "What does real history say?", open: { nav.go(.realHistory) }) {
                EvalsAAnswerBlock(answer: q3.answer)
                if !q3.bars.isEmpty {
                    EvalsLabel(repos.map { ($0 as NSString).lastPathComponent }.joined(separator: " · ") + " · \(days) days · followed by a fix")
                    ForEach(q3.bars) { b in
                        EvalsABarRow(bar: b)
                            .evalsALesson(EvalXRay.definitions["Followed by a fix"] ?? "", lesson: "golden-sets", nav: nav)
                    }
                }
            } fix: {
                fix("Sessions One Roof starts sign their commits (LAB-2241), so other agents can be read too. The model per commit needs LAB-2240.",
                    "Open Real history") { nav.go(.realHistory) }
            }
        }
    }

    @ViewBuilder private func q1Fix(_ boards: [EvalSetupLeaderboard]) -> some View {
        if let main = boards.first(where: { $0.rows.contains(where: \.isDone) }) ?? boards.first {
            let agents = EvalsACompare.untested(main, others: []).filter { $0.agent != nil }
            let waiting = main.rows.filter { $0.isActive && $0.layer != .model }
            let title = main.title ?? main.task
            if !agents.isEmpty, let file = EvalsCompareView.taskFile(main, board: board) {
                let names = EvalsAWords.list(agents.map { $0.label.components(separatedBy: ",").first ?? $0.label })
                fix("Run \(names) on “\(title)” (\(main.n ?? main.cases.count) bugs). On your seats: no API cost.",
                    agents.count > 1 ? "Run both agents" : "Run \(agents[0].label.components(separatedBy: ",").first ?? "it")") {
                    nav.test(EvalsACompare.plan(agents, taskFile: file, cases: main.n ?? main.cases.count))
                }
            } else if let w = waiting.first {
                fix("\(w.label) is waiting (\(w.statusNote ?? w.status)). Open the queue and press Run anyway, or cancel it.", "Open the queue") { nav.sheet = .setup }
            } else {
                fix("Pick two setups in Compare: the paired verdict says whether the gap is real.", "Open Compare") { nav.go(.compare) }
            }
        } else {
            fix("Build a task from your repo's fixed bugs, then test setups on it.", "Our tasks") { nav.go(.ourTasks) }
        }
    }

    private func fix(_ text: String, _ button: String, _ action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EvalsLabel("To answer it properly")
            Text(text).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            RoofButton(button, .primary, action: action)
        }
    }

    private func card<Body: View, Fix: View>(_ n: Int, _ title: String, open: @escaping () -> Void,
                                             @ViewBuilder _ content: () -> Body, @ViewBuilder fix: () -> Fix) -> some View {
        let body = content(), fixView = fix()
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text("QUESTION \(n)").ui(10.5, .semibold).tracking(0.6).foregroundStyle(t.accentText.color)
                Button(action: open) {
                    Text(title).ui(TypeScale.title, .bold).foregroundStyle(t.text.color).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .buttonStyle(.plain).help("Open the tab that answers it")
                body
                Spacer(minLength: 0)
                Divider()
                fixView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// 2.0.3's suggested next step, kept (its home is under the cards).
    private func follow(_ s: EvalOverview.Suggestion) {
        let tg = s.target
        switch tg.tab {
        case "your-evals":
            if let j = tg.judge { nav.openGrader(j) } else { nav.set = tg.set; nav.openBuild = tg.set != nil; nav.go(.ourTasks) }
        case "run": nav.test(EvalRunPlan(tasks: [tg.task ?? "gsm8k"], models: [], limit: tg.limit ?? 20, epochs: tg.epochs))
        case "learn": nav.go(EvalsLegacyTab.learn)
        default: break
        }
    }
}

/// Side by side with equal heights when wide; stacked under `breakpoint` (no clipping at 1280).
struct EvalsAFlow<Content: View>: View {
    var breakpoint: CGFloat = 980
    @ViewBuilder var content: () -> Content
    @State private var width: CGFloat = 1200
    var body: some View {
        Group {
            if width >= breakpoint {
                HStack(alignment: .top, spacing: 14) { content() }.fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: 14) { content() }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    }
}
