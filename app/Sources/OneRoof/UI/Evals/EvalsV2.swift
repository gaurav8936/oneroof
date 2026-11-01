import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2061 · the Evals place, redesigned (Claude Design "Evals v1.0" handover, blended with the owner's Overview):
/// How to (LAB-2113) · Overview · Your evals · Explore · Run · Results · Learn. Behind `Settings.evalsRedesign` (on in 2.0.0); off shows the
/// 1.9.37 Evals. Stage 1 (M9): the shell, Overview, Explore and Your evals; Run, Results and Learn show today's run
/// sheet + queue, results and lessons until stage 2/3 replaces them, so nothing is lost at any commit.
struct EvalsPlace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var body: some View {
        if model.settings.evalsRedesign { EvalsViewV2(model: model, win: win) } else { EvalsView(model: model, win: win) }
    }
}

/// Drill-downs replace the header with a breadcrumb row (⌘[ goes back).
enum EvalsRoute: Equatable {
    case questions(benchmark: String, task: String)   // E1.2
    case judge(name: String, first: String?)          // E2.2
    /// E4.2 one run; `only`: the cases to list (Compare's "See the N cases"), `other`: B's run, its answer alongside.
    case runDetail(run: String, sample: String?, only: [String]?, other: String?)
}

final class EvalsNav: ObservableObject {
    @Published var tab: EvalsTabV2 = .overview
    @Published var route: EvalsRoute?
    /// Run, pre-filled by Run this… / Run… / Run just this one / Run again / a suggestion (the cost shows first).
    @Published var draft: EvalRunPlan?
    /// What Run shows, kept while you visit other tabs.
    var workPlan: EvalRunPlan?
    /// Results: the eval shown (set@vN or a task), its view, and Compare's A (one run's "Compare with…").
    @Published var resultsKey: String?
    @Published var resultsMode: ResultsMode = .byEval
    @Published var compareA: String?
    /// Explore: the benchmark shown and its sub-tab; Your evals: the set shown.
    @Published var benchmark: String?
    @Published var exploreTab: ExploreTab = .anatomy
    @Published var set: String?
    /// Your evals › Build v2 opened from the Overview's suggestion.
    @Published var openBuild = false
    /// Learn: the lesson shown (LAB-2070); every number's hover and every "Why ›" opens one.
    @Published var lesson: String?

    enum ExploreTab: String, CaseIterable { case anatomy = "Anatomy", questions = "Questions", scores = "Scores", runs = "Your runs" }
    enum ResultsMode: String, CaseIterable { case byEval = "By eval", allByAll = "All × all", xray = "X-ray" }

    /// Every way into Run goes through here (HP: `EvalsNav.run(plan)` is the only prefill).
    func run(_ plan: EvalRunPlan) { route = nil; draft = plan; tab = .run }
    func back() { route = nil }
    /// Any score or run date opens that run, question by question (E4.2); Back lands on Results.
    func openRun(_ id: String, sample: String? = nil, only: [String]? = nil, other: String? = nil) {
        tab = .results
        route = .runDetail(run: id, sample: sample, only: only, other: other)
    }
    func showResults(key: String, compareA: String? = nil) {
        route = nil; resultsMode = .byEval; resultsKey = key; self.compareA = compareA; tab = .results
    }
    func go(_ t: EvalsTabV2) { route = nil; tab = t }
    func openLesson(_ id: String) { route = nil; lesson = id; tab = .learn }
}

// MARK: - Engine calls the redesign adds (same queue and style as EvalsBoard's own)

extension EvalsBoard {
    /// The new commands answer in snake_case; decoded with EvalEngine.decodeSnake. Errors come back as the message.
    func ask<T: Decodable>(_ args: [String], _ type: T.Type, timeout: TimeInterval = 600, done: @escaping (Result<T, EvalError>) -> Void) {
        io.async {
            let r = EvalEngine.decodeSnake(T.self, EvalEngine.run(args + ["--json"], timeout: timeout))
            DispatchQueue.main.async { done(r) }
        }
    }

    func refreshOwn() {
        ask(["evalset", "list"], EvalSetList.self) { if case .success(let l) = $0, l.sets != self.sets { self.sets = l.sets } }
        ask(["judge", "list"], EvalJudgeList.self) { if case .success(let l) = $0, l.judges != self.judges { self.judges = l.judges } }
    }

    func refreshOverview() {
        ask(["overview"], EvalOverview.self, timeout: 300) { r in
            switch r {
            case .success(let o): if o != self.overview { self.overview = o }; self.overviewError = nil
            case .failure(let e): self.overviewError = e.message
            }
        }
    }
}

struct EvalsViewV2: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @StateObject private var board = EvalsBoard()
    @StateObject private var nav = EvalsNav()
    @StateObject private var hover = EvalHoverCenter()
    @Environment(\.theme) private var t
    @AppStorage(EvalsLearnStore.doneKey, store: Prefs.viewState) private var lessonsDone = ""

    var body: some View {
        Group {
            if let route = nav.route { drill(route) } else { page }
        }
        .environment(\.evalHover, hover)
        .coordinateSpace(name: EvalHoverCenter.space)
        .overlay { EvalHoverLayer(center: hover) }
        .background(shortcuts)
        .onAppear {
            hover.openLesson = { [weak nav] in nav?.openLesson($0) }
            board.start()
            board.refreshOwn()
            board.refreshOverview()
            // LAB-2113: the first visit to Evals opens How to; later visits open Overview.
            if !Prefs.viewState.bool(forKey: EvalsHowTo.seenKey) { Prefs.viewState.set(true, forKey: EvalsHowTo.seenKey); nav.tab = .howTo }
            selfTest()
        }
        .onDisappear { board.stop() }
        .onChange(of: nav.tab) { _, tab in
            board.tab = tab == .run ? .runs : tab == .results ? .results : tab == .learn ? .learn : .catalog   // 3 s polling on Run
            if tab == .overview { board.refreshOverview() }
            if tab == .results { EvalsLearnStore.note(EvalsLearnStore.resultsKey) }   // first eval, step 2
            hover.hide()
        }
        .onChange(of: nav.route) { _, r in
            hover.hide()
            if case .runDetail = r { EvalsLearnStore.note(EvalsLearnStore.questionKey) }   // first eval, step 3
        }
        .onChange(of: board.started) { _, _ in nav.go(.run) }        // a started run shows in Run's queue
        .onChange(of: board.results) { _, _ in board.refreshOverview(); board.refreshOwn() }
    }

    // MARK: Page (header + tabs) and drill-downs (breadcrumb row)

    private var page: some View {
        FleetPage(title: "Evals", subtitle: subtitle) {
            HStack(spacing: 8) {
                Segmented(options: EvalsTabV2.allCases.map { ($0, $0.title) }, selection: $nav.tab,
                          badge: { $0 == .run ? board.runs.filter(\.isActive).count.nonZeroText : nil })
                    .accessibilityLabel("Evals tabs")
                if board.doctor?.engine.ready == true && nav.tab != .run {
                    RoofButton("+ New run", .primary) { nav.go(.run) }
                        .help("Choose what to run and on whom; the cost shows before anything starts")
                }
            }
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                lines
                if nav.tab == .howTo {
                    tab   // LAB-2113: How to reads without the engine (a new user starts here)
                } else if let d = board.doctor, !d.engine.ready {
                    EvalsSetupCard(doctor: d, board: board)
                } else if board.doctor == nil {
                    Text("Checking the eval engine…").ui(TypeScale.body).foregroundStyle(t.text2.color)
                } else {
                    tab
                }
            }
        }
    }

    /// The Draft banner (LAB-2072) on every tab, and the busy and error lines under the header (as 1.9.37).
    @ViewBuilder private var lines: some View {
        if EvalsDraft.isDraft { EvalsDraftBanner() }
        if let b = board.busy { Text(b).ui(TypeScale.small).foregroundStyle(t.text2.color) }
        if let e = board.error {
            Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled).lineLimit(4)
        }
    }

    @ViewBuilder private var tab: some View {
        switch nav.tab {
        case .howTo: EvalsHowToTab(nav: nav, model: model)   // LAB-2113
        case .overview: EvalsOverviewTab(board: board, nav: nav)
        case .yourEvals: EvalsYourEvalsTab(board: board, nav: nav)
        case .explore: EvalsExploreTab(board: board, nav: nav)
        case .run: EvalsRunTab(board: board, nav: nav)
        case .results: EvalsResultsV2(board: board, nav: nav)
        case .learn: EvalsLearnV2(board: board, nav: nav)   // LAB-2070; today's walkthrough and glossary live on in it
        }
    }

    @ViewBuilder private func drill(_ r: EvalsRoute) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if EvalsDraft.isDraft {   // LAB-2072: the banner on every Evals page, drill-downs too
                EvalsDraftBanner().padding(.horizontal, 20).padding(.top, 10)
            }
            switch r {
            case .questions(let b, let task): EvalsQuestionsPage(board: board, nav: nav, benchmark: b, task: task)
            case .judge(let name, let first): EvalsJudgePage(board: board, nav: nav, name: name, first: first)
            case .runDetail(let run, let sample, let only, let other):
                EvalsRunDetailPage(board: board, nav: nav, runID: run, start: sample, only: only, other: other).id(run + (only?.joined() ?? ""))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
    }

    private var subtitle: String {
        guard let d = board.doctor else { return "Measure your agents and models on your own work, and learn what the numbers mean" }
        guard d.engine.ready else { return "The eval engine is not installed yet" }
        let running = board.runs.filter { $0.status == "running" || $0.status == "waiting" }.count
        if nav.tab == .run {   // HP E3.1
            return "\(running) running · \(board.runs.filter { $0.status == "queued" }.count) queued · runs keep going if One Roof closes"
        }
        if nav.tab == .learn, let b = EvalsLearnStore.book {   // HP E5.1
            return b.subtitle(done: Set(lessonsDone.split(separator: ",").map(String.init)))
        }
        if nav.tab == .results {   // HP E4.1
            let entries = EvalResultsEntry.from(board.results).filter { $0.runs > 0 }
            let n = board.results.filter { $0.status == "done" }.count
            return "\(n) finished run\(n == 1 ? "" : "s") across \(entries.count) eval\(entries.count == 1 ? "" : "s")"
        }
        return EvalsSubtitle.text(benchmarks: board.catalog.map(\.benchmarkCount), ownEvals: board.sets.count,
                                  judges: board.judges.count, finished: board.results.filter { $0.status == "done" }.count,
                                  running: board.runs.filter(\.isActive).count)
    }

    /// ⌃⌥1…⌃⌥6 switch tabs (scoped to Evals: the buttons exist only while it shows); ⌘[ goes back from a drill-down.
    private var shortcuts: some View {
        ZStack {
            ForEach(EvalsTabV2.allCases) { tb in
                Button("") { nav.go(tb) }.keyboardShortcut(KeyEquivalent(tb.keyDigit), modifiers: [.control, .option])
            }
            if nav.route != nil { Button("") { nav.back() }.keyboardShortcut("[", modifiers: .command) }
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// ONEROOF_SELFTEST_EVALS_TAB=<overview|your-evals|judge|explore|question|scores|your-runs|run|sheet|results|learn>;
    /// EVALS_LESSON=<lesson id> and EVALS_DONE=<id,id> for Learn; EVALS_HOVER=<EvalHover.Kind> shows that number's card.
    /// EVALS_BENCH=<folder> picks the benchmark, EVALS_QUESTION=<id> the question, EVALS_JUDGE=<name> the judge.
    private func selfTest() {
        let env = ProcessInfo.processInfo.environment
        guard let v = env["ONEROOF_SELFTEST_EVALS_TAB"], let (tab, drill) = EvalsTabV2.selfTest(v) else { return }
        nav.tab = tab
        if let b = env["ONEROOF_SELFTEST_EVALS_BENCH"] { nav.benchmark = b }
        switch drill {
        case "questions": nav.route = .questions(benchmark: env["ONEROOF_SELFTEST_EVALS_BENCH"] ?? "gsm8k",
                                                 task: env["ONEROOF_SELFTEST_EVALS_TASK"] ?? env["ONEROOF_SELFTEST_EVALS_BENCH"] ?? "gsm8k")
        case "scores": nav.exploreTab = .scores
        case "runs": nav.exploreTab = .runs
        case "judge": nav.route = .judge(name: env["ONEROOF_SELFTEST_EVALS_JUDGE"] ?? board.judges.first?.name ?? "oneroof_triage", first: nil)
        case "sheet": nav.run(EvalRunPlan(tasks: ["gsm8k"], models: ["mockllm/model", "anthropic/claude-haiku-5-5"]))
        case "allbyall": nav.resultsMode = .allByAll
        case "xray": nav.resultsMode = .xray
        default: break
        }
        if let k = env["ONEROOF_SELFTEST_EVALS_KEY"] { nav.resultsKey = k }
        if let l = env["ONEROOF_SELFTEST_EVALS_LESSON"] { nav.lesson = l }   // learn: the lesson shown
        if let d = env["ONEROOF_SELFTEST_EVALS_DONE"] { lessonsDone = d }    // learn: lessons ticked done
        if v == "run-detail", let id = env["ONEROOF_SELFTEST_EVALS_RUN"] {
            nav.openRun(id, sample: env["ONEROOF_SELFTEST_EVALS_SAMPLE"])
        }
        if v == "run", let task = env["ONEROOF_SELFTEST_EVALS_TASK"] {   // Run pre-filled: a set (or task), agents and models
            nav.run(EvalRunPlan(tasks: [task], models: (env["ONEROOF_SELFTEST_EVALS_MODELS"] ?? "mockllm/model").split(separator: ",").map(String.init),
                                limit: Int(env["ONEROOF_SELFTEST_EVALS_LIMIT"] ?? "") ?? 20, epochs: Int(env["ONEROOF_SELFTEST_EVALS_EPOCHS"] ?? ""),
                                agents: (env["ONEROOF_SELFTEST_EVALS_AGENTS"] ?? "").split(separator: ",").map(String.init)))
        }
    }
}


private extension Int { var nonZeroText: String? { self > 0 ? String(self) : nil } }

// MARK: - Shared pieces (HP shared/COMPONENTS.md)

/// Uppercase section label (10 pt semibold, +0.06 em, text3).
struct EvalsLabel: View {
    @Environment(\.theme) private var t
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text.uppercased()).ui(10.5, .semibold).tracking(0.6).foregroundStyle(t.text3.color) }
}

/// A card split into equal cells with separators: label over value (HP FactsStrip).
struct EvalsFactsStrip: View {
    @Environment(\.theme) private var t
    let facts: [(label: String, value: String, tint: RGB?)]
    /// LAB-2070: a tile whose number has a lesson (Chance, Headroom, floor) explains itself on hover.
    var hover: (_ label: String, _ value: String) -> (EvalHover.Kind, String)? = { _, _ in nil }
    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(facts.enumerated()), id: \.offset) { i, f in
                VStack(alignment: .leading, spacing: 4) {
                    EvalsLabel(f.label)
                    Text(f.value).ui(TypeScale.body, .semibold).foregroundStyle((f.tint ?? t.text).color)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .evalHoverIf(hover(f.label, f.value))
                if i < facts.count - 1 { Rectangle().fill(t.separator.color).frame(width: 1) }
            }
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .accessibilityElement(children: .combine)
    }
}

/// Agent (accent 0.18 / accentText) · Model, On this Mac and Baseline (control / text2) (HP KindTag).
struct EvalsKindTag: View {
    @Environment(\.theme) private var t
    let kind: EvalContestant.Kind
    var body: some View {
        Text(EvalContestant.tag(kind)).ui(10.5, .semibold)
            .foregroundStyle(kind == .agent ? t.accentText.color : t.text2.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(kind == .agent ? t.accent.color.opacity(0.18) : t.control.color))
    }
}

/// A small capsule tag (★ Start here, run 2×, v1 · frozen …).
struct EvalsChip: View {
    @Environment(\.theme) private var t
    let text: String
    var accent = false
    var body: some View {
        Text(text).ui(10.5, .semibold)
            .foregroundStyle(accent ? t.accentText.color : t.text2.color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(accent ? t.accent.color.opacity(0.18) : t.control.color))
    }
}

/// The 95 % range on 0…100 % (range fill accent 0.35, a dot at the score) with the no-model floor as a dashed tick.
struct EvalsRangeBar: View {
    @Environment(\.theme) private var t
    let value: Double
    var lo: Double?
    var hi: Double?
    var floor: Double?
    /// Fewer than 30 answers: the track is dashed in the needs colour (HP: "dashed/needs styling when n < 30").
    var small = false
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, v = min(max(value, 0), 1)
            let l = min(max(lo ?? v, 0), 1), h = min(max(hi ?? v, 0), 1)
            ZStack(alignment: .leading) {
                Capsule().fill(t.control.color).frame(height: 4)
                if small {
                    Path { p in p.move(to: CGPoint(x: 0, y: g.size.height / 2)); p.addLine(to: CGPoint(x: w, y: g.size.height / 2)) }
                        .stroke(t.needsText.color.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                Capsule().fill(t.accent.color.opacity(0.35)).frame(width: max((h - l) * w, 2), height: 4).offset(x: l * w)
                if let f = floor {
                    Path { p in p.move(to: CGPoint(x: f * w, y: 0)); p.addLine(to: CGPoint(x: f * w, y: g.size.height)) }
                        .stroke(t.text2.color, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2]))
                }
                Circle().fill(t.accent.color).frame(width: 7, height: 7).offset(x: v * w - 3.5)
            }
            .frame(height: g.size.height)
        }
        .frame(height: 10)
        .accessibilityLabel("score \(Int((value * 100).rounded())) percent" + (lo != nil ? ", 95 percent range \(Int(((lo ?? 0) * 100).rounded())) to \(Int(((hi ?? 0) * 100).rounded()))" : "")
                            + (floor.map { ", no-model floor \(Int(($0 * 100).rounded())) percent" } ?? ""))
    }
}

/// A breadcrumb header for drill-downs: "‹ Back  Title  meta" and sub-tabs on the right.
struct EvalsDrillHeader<Tabs: View>: View {
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
    let crumb: String
    let back: String
    let title: String
    let meta: String
    var onBack: () -> Void
    @ViewBuilder var tabs: () -> Tabs
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(crumb).ui(TypeScale.caption).foregroundStyle(t.text3.color)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Button(action: onBack) { Text("‹ " + back).ui(13, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).accessibilityLabel("Back to " + back)
                Text(title).ui(18, .bold).foregroundStyle(t.text.color).lineLimit(1)
                Text(meta).ui(TypeScale.small).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer(minLength: 12)
                tabs()
            }
        }
        .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28).padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }
}

/// Plain text tabs (Anatomy · Questions · Scores · Your runs; Label · Rubric · Agreement · Versions): the selected one in
/// accentText, semibold.
struct EvalsTextTabs<T: Hashable>: View {
    @Environment(\.theme) private var t
    let options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 18) {
            ForEach(options, id: \.0) { v, label in
                Button { selection = v } label: {
                    VStack(spacing: 4) {
                        Text(label).ui(13, v == selection ? .semibold : .regular)
                            .foregroundStyle(v == selection ? t.accentText.color : t.text2.color)
                        Rectangle().fill(v == selection ? t.accent.color : .clear).frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(v == selection ? .isSelected : [])
            }
        }
    }
}

/// Percent with no decimals ("75 %"), the app's way of writing scores.
func evalsPct(_ x: Double?) -> String { x.map { "\(Int(($0 * 100).rounded())) %" } ?? "–" }

/// A wide layout puts the side column on the right; under `breakpoint` it folds under the main column (no clipping).
struct EvalsColumns<Main: View, Side: View>: View {
    var breakpoint: CGFloat = 1000
    var side: CGFloat = 300
    @ViewBuilder var main: () -> Main
    @ViewBuilder var aside: () -> Side
    @State private var width: CGFloat = 1200
    var body: some View {
        Group {
            if width >= breakpoint {
                HStack(alignment: .top, spacing: 16) {
                    main().frame(maxWidth: .infinity, alignment: .topLeading)
                    aside().frame(width: side, alignment: .topLeading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) { main(); aside() }
            }
        }
        .background(GeometryReader { g in Color.clear.onAppear { width = g.size.width }.onChange(of: g.size.width) { _, w in width = w } })
    }
}
