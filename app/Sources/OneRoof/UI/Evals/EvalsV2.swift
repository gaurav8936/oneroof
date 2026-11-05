import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · Evals v2 (One Roof 2.0.4, Claude Design "Evals v2.0" handover): six tabs — Overview · Compare · Changes ·
/// Real history · Our tasks · Public benchmarks — five drill-downs (one test, all results, one task, the grader, one
/// benchmark) and two sheets over any tab (Set up a test, Lessons). Names and self-test mapping: OneRoofCore
/// EvalsNavigation.swift. Each screen is its own file (EvalsCompare.swift …); until a screen is rebuilt it shows the 2.0.3
/// view that held the same job, so nothing is lost at any commit. Behind `Settings.evalsRedesign`; off shows 1.9.37's.
struct EvalsPlace: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var body: some View {
        if model.settings.evalsRedesign { EvalsViewV2(model: model, win: win) } else { EvalsView(model: model, win: win) }
    }
}

/// Drill-downs: the title becomes "‹ parent  title"; the tab bar stays; ⌘[ goes back.
enum EvalsRoute: Equatable {
    /// E2.2 one test, bug by bug. `run` nil = the newest finished run; `only`: the cases to list; `other`: B's run alongside.
    case oneTest(run: String?, sample: String?, only: [String]?, other: String?)
    /// E2.3 the all-results grid, every run, export.
    case allResults
    /// E5.2 one task (an eval set); nil = the first.
    case oneTask(name: String?, version: Int?)
    /// E5.3 check the grader; nil = the first grader.
    case grader(name: String?, first: String?)
    /// E6.2 a public benchmark: How it works · Questions · Published scores · Your runs.
    case oneBenchmark(id: String, task: String?, part: EvalsNav.ExploreTab)

    var screen: EvalsScreen {
        switch self {
        case .oneTest: return .oneTest; case .allResults: return .allResults; case .oneTask: return .oneTask
        case .grader: return .grader; case .oneBenchmark: return .oneBenchmark
        }
    }

    // 2.0.3 names, kept so the 2.0.3 views' links land on the new drill-downs.
    static func judge(name: String, first: String?) -> EvalsRoute { .grader(name: name, first: first) }
    static func questions(benchmark: String, task: String) -> EvalsRoute { .oneBenchmark(id: benchmark, task: task, part: .questions) }
    static func runDetail(run: String, sample: String?, only: [String]?, other: String?) -> EvalsRoute {
        .oneTest(run: run, sample: sample, only: only, other: other)
    }
}

/// The two sheets, openable from any tab.
enum EvalsSheet: String, Identifiable {
    case setup, lessons
    var id: String { rawValue }
}

final class EvalsNav: ObservableObject {
    @Published var tab: EvalsTabV2 = .overview
    /// A drill-down; setting one shows its parent tab and closes any sheet.
    @Published var route: EvalsRoute? {
        didSet { if route != nil, sheet != nil { sheet = nil } }   // v3: a drill-down sits on the current page; it never switches page
    }
    @Published var sheet: EvalsSheet?
    /// Set up a test, pre-filled by Test them / Run both agents / Test again / Test a model on it… (nothing starts until Start).
    @Published var draft: EvalRunPlan?
    /// What Set up a test shows, kept while the sheet is closed.
    var workPlan: EvalRunPlan?
    /// Compare: the task shown (set@vN or a task), and A for "Compare with…". `resultsMode` is 2.0.3's Results switch.
    @Published var resultsKey: String?
    @Published var resultsMode: ResultsMode = .byEval
    @Published var compareA: String?
    /// Public benchmarks: the benchmark shown and its part; Our tasks: the task (set) shown.
    @Published var benchmark: String?
    @Published var exploreTab: ExploreTab = .anatomy
    @Published var set: String?
    /// Our tasks › Next version opened from a suggestion.
    @Published var openBuild = false
    /// Lessons: the lesson shown; `lessonsPart` shows the lessons or the walkthrough (2.0.3 How to).
    @Published var lesson: String?
    @Published var lessonsPart: LessonsPart = .lessons
    /// "New test or task ▾" › New task from fixed bugs / New grader: Our tasks opens that sheet, then clears this.
    @Published var newRequest: NewRequest?

    enum ExploreTab: String, CaseIterable { case anatomy = "How it works", questions = "Questions", scores = "Published scores", runs = "Your runs" }
    enum ResultsMode: String, CaseIterable { case byEval = "By eval", allByAll = "All × all", xray = "X-ray" }
    enum LessonsPart: String, CaseIterable { case lessons = "Lessons", howTo = "How to" }
    enum NewRequest: String { case task, grader }

    // MARK: v3 (2.0.5): no tabs. The launch view is the navigation; pages stack, drill-downs sit on top, ⌘[ goes back.

    /// The page shown under any drill-down (launch, a segment page, Changes, Real history, Our tasks, Public benchmarks).
    @Published var page: EvalsV3Screen = .launch
    /// The pages walked to get here (the breadcrumb), newest last; `page` is not in it.
    @Published var trail: [EvalsV3Screen] = []
    /// The kind of job last opened, so 2.0.4's "Compare" links land on that kind's Our tests.
    @Published var lastKind: EvalJobKind = .oneShot

    /// Open a page (never a sheet or a drill-down): closes any drill-down and sheet; re-opening a page on the trail goes back to it.
    func open(_ s: EvalsV3Screen) {
        switch s {
        case .setup: test(nil); return
        case .lessons: lessonsPart = .lessons; sheet = .lessons; return
        case .oneTest: route = .oneTest(run: nil, sample: nil, only: nil, other: nil); return
        case .allResults: route = .allResults; return
        case .oneTask: openTask(nil); return
        case .grader: openGrader(nil); return
        case .oneBenchmark: openBenchmark(benchmark ?? "gsm8k"); return
        default: break
        }
        route = nil; sheet = nil
        if let k = s.segment?.0 { lastKind = k } else if s == .agentPublic || s == .changes || s == .realHistory { lastKind = .agent }
        if s == page { return }
        if s == .launch { trail = []; page = .launch; tab = .overview; return }
        if let i = trail.firstIndex(of: s) { trail = Array(trail.prefix(i)); page = s; return }
        if page != .launch || !trail.isEmpty { trail.append(page) }
        page = s
        tab = Self.legacyTab(s)
    }
    func home() { open(.launch) }
    /// Opens One Roof › Loops (at that loop when given): a loop's own runs live there (v3 G10). Set by the shell.
    var loopsHandler: ((String?) -> Void)?
    func openLoops(_ id: String? = nil) { loopsHandler?(id) }
    /// The 2.0.4 tab a v3 page stands in for (2.0.4 code still reads `tab`).
    static func legacyTab(_ s: EvalsV3Screen) -> EvalsTabV2 {
        switch s {
        case .changes: return .changes; case .realHistory: return .realHistory; case .ourTasks: return .ourTasks
        case .benchmarks, .oneShotPublic, .agentPublic: return .benchmarks
        case .oneShotOurs, .agentOurs: return .compare
        default: return .overview
        }
    }
    /// The page a 2.0.4 tab opens now.
    func v3Page(_ t: EvalsTabV2) -> EvalsV3Screen {
        switch t {
        case .overview: return .launch
        case .compare: return lastKind == .agent ? .agentOurs : .oneShotOurs
        case .changes: return .changes; case .realHistory: return .realHistory; case .ourTasks: return .ourTasks
        case .benchmarks: return .benchmarks
        }
    }

    /// Every way into Set up a test goes through here (the only prefill).
    func test(_ plan: EvalRunPlan?) { draft = plan; sheet = .setup }
    /// 2.0.3's name for `test`.
    func run(_ plan: EvalRunPlan) { test(plan) }
    /// ⌘[ and "‹": a drill-down first, then the trail, then the launch view.
    func back() {
        if route != nil { route = nil; return }
        guard page != .launch else { return }
        let prev = trail.popLast() ?? .launch
        page = prev; tab = Self.legacyTab(prev)
        if let k = prev.segment?.0 { lastKind = k }
    }
    func go(_ t: EvalsTabV2) { open(v3Page(t)) }
    /// A 2.0.3 tab, to its new home (How to / Learn → Lessons, Run → Set up a test, Results › All × all → All results …).
    func go(_ old: EvalsLegacyTab) {
        switch old {
        case .howTo: lessonsPart = .howTo; route = nil; sheet = .lessons
        case .learn: lessonsPart = .lessons; route = nil; sheet = .lessons
        case .run: test(nil)
        case .results:
            switch resultsMode {
            case .allByAll: resultsMode = .byEval; route = .allResults
            case .xray: resultsMode = .byEval; go(.realHistory)
            case .byEval: go(.compare)
            }
        case .overview, .yourEvals, .explore: if let tb = old.home.tab { go(tb) }
        }
    }
    /// Any score or run date opens that test, bug by bug (E2.2); Back lands on Compare.
    func openRun(_ id: String, sample: String? = nil, only: [String]? = nil, other: String? = nil) {
        route = .oneTest(run: id, sample: sample, only: only, other: other)
    }
    /// `kind`: the run's kind of job, so Compare with… opens that kind's Our tests (2.0.5 review P1), not the last one seen.
    func showResults(key: String, compareA: String? = nil, kind: EvalJobKind? = nil) {
        if let kind { lastKind = kind }
        resultsMode = .byEval; resultsKey = key; self.compareA = compareA; go(.compare)
    }
    func openLesson(_ id: String) { lesson = id; lessonsPart = .lessons; sheet = .lessons }
    func openTask(_ name: String?, version: Int? = nil) { set = name; route = .oneTask(name: name, version: version) }
    func openGrader(_ name: String?, first: String? = nil) { route = .grader(name: name, first: first) }
    func openBenchmark(_ id: String, task: String? = nil, part: ExploreTab = .anatomy) {
        benchmark = id; exploreTab = part; route = .oneBenchmark(id: id, task: task, part: part)
    }
    /// "New test or task ▾".
    func new(_ r: NewRequest) { newRequest = r; go(.ourTasks) }
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

    // 2.0.4 calls (CONTRACT.md). Each answers on the main queue; the screens keep the result in their own state.
    /// §3 · Compare: `leaderboard <task> [--version N] --by setup`.
    func setupLeaderboard(task: String, version: Int? = nil, done: @escaping (Result<EvalSetupLeaderboard, EvalError>) -> Void) {
        ask(["leaderboard", task] + (version.map { ["--version", String($0)] } ?? []) + ["--by", "setup"], EvalSetupLeaderboard.self, done: done)
    }
    /// §4 · one test's cases with named / changed files (`samples <run>`).
    func caseResults(run: String, done: @escaping ([EvalCaseResult]) -> Void) {
        samples(run) { done($0.map(EvalCaseResult.init)) }
    }
    /// §5 · Changes: `changes [--repo PATH] [--days 60]`.
    func changes(repo: String? = nil, days: Int = 60, done: @escaping (Result<[EvalChange], EvalError>) -> Void) {
        ask(["changes"] + (repo.map { ["--repo", $0] } ?? []) + ["--days", String(days)], [EvalChange].self, done: done)
    }
}

struct EvalsViewV2: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @StateObject private var board = EvalsBoard()
    @StateObject private var nav = EvalsNav()
    @StateObject private var hover = EvalHoverCenter()
    @StateObject private var sheetHover = EvalHoverCenter()
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
    @AppStorage(EvalsLearnStore.doneKey, store: Prefs.viewState) private var lessonsDone = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            lines
            main(nav.route)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(v2 ? AnyShapeStyle(t.window.color) : AnyShapeStyle(LinearGradient(colors: [t.desk.top.color, t.desk.bottom.color], startPoint: .top, endPoint: .bottom)))
        .environment(\.evalHover, hover)
        .coordinateSpace(name: EvalHoverCenter.space)
        .overlay { EvalHoverLayer(center: hover) }
        .background(shortcuts)
        .sheet(item: $nav.sheet) { s in sheet(s) }
        .onAppear {
            hover.openLesson = { [weak nav] in nav?.openLesson($0) }
            nav.loopsHandler = { [weak model, weak win] id in
                guard let model, let win else { return }
                LoopInboxState.shared.focus = id; model.show(.loops, in: win)
            }
            sheetHover.openLesson = { [weak nav] in nav?.openLesson($0) }
            board.start()
            board.refreshOwn()
            board.refreshOverview()
            selfTest()
        }
        .onDisappear { board.stop() }
        .onChange(of: nav.page) { _, page in
            if page == .launch { board.refreshOverview() }
            if page == .oneShotOurs || page == .agentOurs { EvalsLearnStore.note(EvalsLearnStore.resultsKey) }   // first test, step 2
            hover.hide()
        }
        .onChange(of: nav.sheet) { _, s in
            board.tab = s == .setup ? .runs : .catalog   // 3 s polling while the queue shows
            hover.hide(); sheetHover.hide()
        }
        .onChange(of: nav.route) { _, r in
            hover.hide()
            if case .oneTest = r { EvalsLearnStore.note(EvalsLearnStore.questionKey) }   // first test, step 3
        }
        .onChange(of: board.started) { _, _ in if nav.sheet != .setup { nav.sheet = .setup } }   // a started test shows in the queue
        .onChange(of: board.results) { _, _ in board.refreshOverview(); board.refreshOwn() }
    }

    // MARK: Header (v3): the breadcrumb ("‹ Evals › job › source › item") + the page title + one Draft tag, the subtitle,
    // Running · N, New test or task ▾, Lessons. No tab bar: the launch view is the navigation.

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            if nav.page != .launch || nav.route != nil { breadcrumb }
            HStack(alignment: .bottom, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        // A segment page's title is its question (v3): the header shows only the breadcrumb above.
                        if !isSegmentPage {
                            Text(pageTitle).ui(TypeScale.display, .semibold).tracking(-0.5).foregroundStyle(t.text.color).lineLimit(1)
                        }
                        if EvalsDraft.isDraft { EvalsDraftTag() }   // LAB-2220: one tag by the title, no second banner
                    }
                    if !isSegmentPage { Text(subtitle).ui(14).foregroundStyle(t.text2.color).lineLimit(1) }
                }
                Spacer()
                if board.doctor?.engine.ready == true {
                    EvalsRunningPill(count: board.runs.filter(\.isActive).count) { nav.sheet = .setup }
                    newMenu
                    RoofButton("Lessons") { nav.lessonsPart = .lessons; nav.sheet = .lessons }.fixedSize()
                        .help("What the numbers mean, one lesson at a time")
                }
            }
        }
        .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28).padding(.top, 22).padding(.bottom, 12)
    }

    private var isSegmentPage: Bool { nav.route == nil && (nav.page.segment != nil || nav.page == .agentPublic) }

    /// The page (or drill-down) title.
    private var pageTitle: String {
        if let r = nav.route { return r.screen.title }
        switch nav.page {
        case .launch: return "Evals"
        default: return nav.page.title
        }
    }

    /// Each step is a button with a visible hover (LAB-2255); the kind of job is a step too (it opens that kind's Our tests).
    private var breadcrumb: some View {
        let steps = EvalsCrumbs.steps(page: nav.page, trail: nav.trail, drill: nav.route?.screen.title)
        return HStack(spacing: 4) {
            Button { nav.back() } label: {
                HStack(spacing: 3) { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)); Text("Back") }
                    .ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color)
                    .padding(.horizontal, 7).padding(.vertical, 3).hoverHighlight(radius: Radius.button)
            }
            .buttonStyle(.plain).help("Back (⌘[)").accessibilityLabel("Back")
            Text("·").ui(TypeScale.small).foregroundStyle(t.text3.color)
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                if i > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(t.text3.color) }
                if let target = s.target {
                    Button { nav.open(target) } label: {
                        Text(s.title).ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color)
                            .padding(.horizontal, 6).padding(.vertical, 3).hoverHighlight(radius: Radius.button)
                    }
                    .buttonStyle(.plain).accessibilityLabel("Go to " + s.title)
                } else {
                    Text(s.title).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).padding(.horizontal, 6)
                }
            }
        }
    }

    private var newMenu: some View {
        Menu {   // QA m2: one "+ New" (the window toolbar's); this one is named for what it makes
            Button(EvalsNewMenu.items[0]) { nav.test(nil) }
            Button(EvalsNewMenu.items[1]) { nav.new(.task) }
            Button(EvalsNewMenu.items[2]) { nav.new(.grader) }
        } label: { Text(EvalsNewMenu.title) }
        .menuStyle(.button).fixedSize()
        .accessibilityLabel("New: a test, a task from fixed bugs, or a grader")
    }

    /// The busy and error lines under the header (as 1.9.37).
    @ViewBuilder private var lines: some View {
        if board.busy != nil || board.error != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let b = board.busy { Text(b).ui(TypeScale.small).foregroundStyle(t.text2.color) }
                if let e = board.error {
                    Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled).lineLimit(4)
                }
            }
            .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28).padding(.bottom, 8)
        }
    }

    @ViewBuilder private func main(_ route: EvalsRoute?) -> some View {
        if let d = board.doctor, !d.engine.ready {
            EvalsSetupCard(doctor: d, board: board).padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28)
            Spacer(minLength: 0)
        } else if board.doctor == nil {
            Text("Checking the eval engine…").ui(TypeScale.body).foregroundStyle(t.text2.color)
                .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28)
            Spacer(minLength: 0)
        } else if let r = route {
            drill(r).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            tab.padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28).padding(.bottom, 26)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    /// The page under any drill-down (v3 SCREEN_MAP): the launch view, the six segment pages, and the 2.0.4 screens that
    /// keep their own page (Changes, Real history, Our tasks, Public benchmarks).
    @ViewBuilder private var tab: some View {
        switch nav.page {
        case .launch: EvalsLaunchView(board: board, nav: nav)                                  // E1.1 · EvalsLaunch.swift
        case .oneShotPublic, .oneShotOurs, .oneShotLoops, .agentOurs, .agentLoops, .agentPublic:
            EvalsSegmentPage(board: board, nav: nav, screen: nav.page).id(nav.page.rawValue)   // E2.x · E3.x · EvalsSegmentPage.swift
        case .changes: EvalsChangesView(board: board, nav: nav)                                // E3.3
        case .realHistory: EvalsRealHistoryView(board: board, nav: nav)                        // E3.4
        case .ourTasks: EvalsTasksView(board: board, nav: nav)                                 // E5.1
        case .benchmarks: EvalsBenchmarksView(board: board, nav: nav)                          // E6.1
        case .oneTest, .allResults, .oneTask, .grader, .oneBenchmark, .setup, .lessons:        // never a page (nav.open routes them)
            EvalsLaunchView(board: board, nav: nav)
        }
    }

    @ViewBuilder private func drill(_ r: EvalsRoute) -> some View {
        switch r {
        case .oneTest(let run, let sample, let only, let other):          // lane A · EvalsOneTest.swift
            EvalsOneTestView(board: board, nav: nav, runID: run, sample: sample, only: only, other: other)
                .id((run ?? "latest") + (only?.joined() ?? ""))
        case .allResults: EvalsAllResultsView(board: board, nav: nav)      // lane A · EvalsAllResults.swift
        case .oneTask(let name, let version):                              // lane B · EvalsTaskDetail.swift
            EvalsTaskDetailView(board: board, nav: nav, name: name, version: version)
        case .grader(let name, let first):                                 // lane B · EvalsGrader.swift
            EvalsGraderView(board: board, nav: nav, name: name, first: first).id(name ?? "first")
        case .oneBenchmark(let id, let task, let part):                    // lane B · EvalsBenchmarkDetail.swift
            EvalsBenchmarkDetailView(board: board, nav: nav, id: id, task: task, part: part).id(id + part.rawValue)
        }
    }

    @ViewBuilder private func sheet(_ s: EvalsSheet) -> some View {
        Group {
            switch s {
            case .setup: EvalsSetupSheet(board: board, nav: nav)           // lane B · EvalsSetupSheet.swift
            case .lessons: EvalsLessonsSheet(board: board, nav: nav, model: model)   // lane B · EvalsLessons.swift
            }
        }
        .background(Button("") { nav.sheet = nil }.keyboardShortcut(.cancelAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true))
        .environment(\.evalHover, sheetHover)
        .coordinateSpace(name: EvalHoverCenter.space)
        .overlay { EvalHoverLayer(center: sheetHover) }
        .background(t.surface.color)
        .themed(t.name)
    }

    private var subtitle: String {
        guard let d = board.doctor else { return "Measure your agents and models on your own work, and learn what the numbers mean" }
        guard d.engine.ready else { return "The eval engine is not installed yet" }
        if (nav.page == .oneShotOurs || nav.page == .agentOurs) && nav.route == nil {
            return EvalFinished.text(board.results)   // one count everywhere (QA)
        }
        return EvalsSubtitle.text(benchmarks: board.catalog.map(\.benchmarkCount), ownEvals: board.sets.count,
                                  judges: board.judges.count, finished: EvalFinished.count(board.results).tests,
                                  running: board.runs.filter(\.isActive).count)
    }

    /// v3 (D8): ⌃⌥0 the launch view, ⌃⌥1–5 the five segment pages, ⌃⌥6 public agent benchmarks, ⌃⌥7 Changes, ⌃⌥8 Real
    /// history (scoped to Evals: the buttons exist only while it shows); ⌘[ goes back one step.
    private var shortcuts: some View {
        ZStack {
            ForEach(EvalsV3Screen.allCases.filter { $0.keyDigit != nil }, id: \.self) { s in
                Button("") { nav.open(s) }.keyboardShortcut(KeyEquivalent(s.keyDigit!), modifiers: [.control, .option])
            }
            if nav.route != nil || nav.page != .launch { Button("") { nav.back() }.keyboardShortcut("[", modifiers: .command) }
        }
        .opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
    }

    /// ONEROOF_SELFTEST_EVALS_TAB=<launch|oneshot-public|oneshot-ours|oneshot-loops|agent-ours|agent-loops|agent-public|changes|
    /// real-history|one-test|all-results|our-tasks|one-task|grader|benchmarks|one-benchmark|setup|lessons>, and every 2.0.4 /
    /// 2.0.3 name (EvalsV3Screen.selfTest maps it to its v3 home).
    /// EVALS_RUN=<run id> (one test), EVALS_SAMPLE, EVALS_SET=<set> (one task), EVALS_JUDGE=<grader>, EVALS_BENCH=<folder>
    /// (+ EVALS_TASK), EVALS_LESSON=<lesson id>, EVALS_DONE=<id,id>, EVALS_KEY=<compare key>; setup pre-fill: EVALS_TASK,
    /// EVALS_MODELS, EVALS_AGENTS, EVALS_LIMIT, EVALS_EPOCHS.
    private func selfTest() {
        let env = ProcessInfo.processInfo.environment
        guard let v = env["ONEROOF_SELFTEST_EVALS_TAB"], let st = EvalsV3Screen.selfTest(v) else { return }
        if v.lowercased() == "compare-grid" || env["ONEROOF_SELFTEST_EVALS_COMPARE_VIEW"] == "grid" { nav.lastKind = .agent }
        if let b = env["ONEROOF_SELFTEST_EVALS_BENCH"] { nav.benchmark = b }
        if let k = env["ONEROOF_SELFTEST_EVALS_KEY"] { nav.resultsKey = k }
        if let l = env["ONEROOF_SELFTEST_EVALS_LESSON"] { nav.lesson = l }   // lessons: the lesson shown
        if let d = env["ONEROOF_SELFTEST_EVALS_DONE"] { lessonsDone = d }    // lessons: ticked done
        switch st.screen {
        case .launch, .oneShotPublic, .oneShotOurs, .oneShotLoops, .agentOurs, .agentLoops, .agentPublic, .changes, .realHistory, .ourTasks, .benchmarks:
            // COMPARE_VIEW=grid: the agent × model grid lives on Agent jobs › Our tests.
            nav.open(st.screen == .oneShotOurs && nav.lastKind == .agent ? .agentOurs : st.screen)
        case .oneTest: nav.route = .oneTest(run: env["ONEROOF_SELFTEST_EVALS_RUN"], sample: env["ONEROOF_SELFTEST_EVALS_SAMPLE"], only: nil, other: nil)
        case .allResults: nav.route = .allResults
        case .oneTask: nav.openTask(env["ONEROOF_SELFTEST_EVALS_SET"])
        case .grader: nav.openGrader(env["ONEROOF_SELFTEST_EVALS_JUDGE"])
        case .oneBenchmark:
            let part: EvalsNav.ExploreTab = st.part == "questions" ? .questions : st.part == "scores" ? .scores : st.part == "runs" ? .runs : .anatomy
            let b = env["ONEROOF_SELFTEST_EVALS_BENCH"] ?? "gsm8k"
            nav.openBenchmark(b, task: env["ONEROOF_SELFTEST_EVALS_TASK"] ?? b, part: part)
        case .setup:
            if st.part == "sheet" {
                nav.test(EvalRunPlan(tasks: ["gsm8k"], models: ["mockllm/model", "anthropic/claude-haiku-5-5"]))
            } else if let task = env["ONEROOF_SELFTEST_EVALS_TASK"] {   // pre-filled: a set (or task), agents and models
                nav.test(EvalRunPlan(tasks: [task], models: (env["ONEROOF_SELFTEST_EVALS_MODELS"] ?? "mockllm/model").split(separator: ",").map(String.init),
                                     limit: Int(env["ONEROOF_SELFTEST_EVALS_LIMIT"] ?? "") ?? 20, epochs: Int(env["ONEROOF_SELFTEST_EVALS_EPOCHS"] ?? ""),
                                     agents: (env["ONEROOF_SELFTEST_EVALS_AGENTS"] ?? "").split(separator: ",").map(String.init)))
            } else { nav.test(nil) }
        case .lessons:
            nav.lessonsPart = st.part == "how-to" ? .howTo : .lessons
            nav.sheet = .lessons
        }
    }
}

/// LAB-2220: the one Draft tag next to the title (replaces the banner on every tab and drill-down); its detail on hover.
struct EvalsDraftTag: View {
    @Environment(\.theme) private var t
    var body: some View {
        Text(EvalsDraft.tag.uppercased()).ui(10, .bold).foregroundStyle(t.onAccent.color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Capsule().fill(t.accent.color))   // LAB-2170: a draft is news, not something that needs you
            .help(EvalsDraft.detail)
            .accessibilityLabel(EvalsDraft.banner + ". " + EvalsDraft.detail)
    }
}

/// "Running · N": the queue's single home in the header; opens Set up a test › Running and recent. Hidden at 0.
struct EvalsRunningPill: View {
    @Environment(\.theme) private var t
    let count: Int
    var open: () -> Void
    var body: some View {
        if count > 0 {
            Button(action: open) {
                HStack(spacing: 6) {
                    Circle().fill(t.accent.color).frame(width: 7, height: 7)
                    Text("Running · \(count)").ui(12.5, .semibold).foregroundStyle(t.text.color)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(t.control.color))
                .overlay(Capsule().strokeBorder(t.separator.color))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Open the queue: what is running and what finished lately")
            .accessibilityLabel("\(count) running; open the queue")
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
