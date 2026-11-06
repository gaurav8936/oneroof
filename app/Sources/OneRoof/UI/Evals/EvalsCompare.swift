import SwiftUI
import OneRoofCore

/// LAB-2242 · E2.1 Compare: one task at a time, who gets it right. Engine: `leaderboard <set> --by setup` (CONTRACT §3) per
/// own task, `compare <A> <B>` for the paired verdict. Story in order: the headline sentence (answer) → one row of squares
/// per setup, the blind-guess tick (picture) → "On new bugs, expect L to H", $ per right, the paired verdict (numbers) →
/// a square or a row opens the test bug by bug (evidence). A second view is the agent × model grid (v1 screen 2) for the
/// same task. Waiting and expired setups keep their row with the reason; "Not tested on this task yet" opens Set up a test
/// pre-filled. Never mixes versions (the engine answers one version); never a winner under 10 shared bugs.
struct EvalsCompareView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    /// v3 (2.0.5): the segment page's kind of job: only that kind's setups; the agent × model grid only on agent jobs.
    var kind: EvalJobKind? = nil
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    @State private var view: Mode = .setups
    @State private var picked: [String] = []          // up to two run ids for the paired verdict
    @State private var compared: EvalCompareResult?
    @State private var compareError: String?
    @State private var focusRow = 0
    /// The grid's rules mode (review P2 #8): one mode per grid, never both in a row. QA #5 (D4): with our rules by default.
    @State private var gridRules = true
    @FocusState private var listFocused: Bool

    enum Mode: String, CaseIterable { case setups = "By setup", grid = "Agent × model" }

    private var sets: [EvalSetList.Entry] { EvalsAStore.ownSets(board) }

    /// The task shown: nav.resultsKey (a set name, or 2.0.3's "set@vN"), else the first of our tasks.
    private var selected: EvalSetList.Entry? {
        let k = nav.resultsKey.map { $0.components(separatedBy: "@").first ?? $0 }
        return sets.first { $0.name == k || "own_" + $0.name == k } ?? sets.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(sets) { s in taskCard(s) }
                    Spacer(minLength: 8)
                    if kind == nil {   // v3: on a segment page the tile above does this
                        RoofButton("All results ›") { nav.route = .allResults }.help("Every task × every setup, every test, export")
                    }
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // LAB-2273: flexes with the window
            .padding(.bottom, 20)
        }
        .onAppear {
            store.refreshBoards(board)
            if nav.resultsMode != .byEval { nav.resultsMode = .byEval }
            // Self-test: ONEROOF_SELFTEST_EVALS_COMPARE_VIEW=grid shows the agent × model grid.
            if ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_EVALS_COMPARE_VIEW"] == "grid" { view = .grid }
        }
        .onChange(of: board.results) { _, _ in store.refreshBoards(board) }
        .onChange(of: board.sets) { _, _ in store.refreshBoards(board, force: true) }
        .onChange(of: selected?.name) { _, _ in picked = []; compared = nil; focusRow = 0 }
        .onChange(of: picked) { _, p in compare(p) }
    }

    // MARK: Task picker

    private func taskCard(_ s: EvalSetList.Entry) -> some View {
        let on = s.name == selected?.name
        let lb = board(s)
        return Button { nav.resultsKey = s.name } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text("TASK").ui(10, .semibold).tracking(0.5).foregroundStyle(t.text3.color)
                Text(lb?.title ?? s.title).ui(TypeScale.body, .bold).foregroundStyle(t.text.color).lineLimit(1)
                Text(Self.source(s, lb)).ui(TypeScale.caption).foregroundStyle(t.text2.color).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 9).frame(minWidth: 280, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(on ? t.accent.color : t.separator.color, lineWidth: on ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
        .help("\(s.name) v\(lb?.version ?? s.version) (engine name)")
    }

    /// "10 real bugs from oneroof · checked automatically" (who checks it, in words).
    static func source(_ s: EvalSetList.Entry, _ lb: EvalSetupLeaderboard?) -> String {
        let n = lb?.n ?? s.count
        let how: String
        switch lb?.checkedBy ?? (s.kind == "triage" ? "code" : "code") {
        case "judge": how = "a grading model reads each answer"
        case "tests": how = "checked by its tests"
        default: how = s.kind == "triage" ? "checked by code: does the note name a file the fix changed?" : "the answer is checked automatically"
        }
        return "\(n) real bugs from \(s.repo) · \(how)"
    }

    private func board(_ s: EvalSetList.Entry) -> EvalSetupLeaderboard? {
        if case .success(let lb)? = store.boards[s.name] { return lb }
        return nil
    }

    /// The set's task file (what Set up a test runs), matched by the leaderboard's task.
    static func taskFile(_ lb: EvalSetupLeaderboard, board: EvalsBoard) -> String? {
        let s = board.sets.first { "own_" + $0.name == lb.task || $0.name == lb.task || (($0.taskFile as NSString).lastPathComponent).hasPrefix(lb.task) }
        return s?.taskFile
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if sets.isEmpty {
            EvalsAEmpty(title: "No task of our own yet",
                        detail: "Compare tests setups on tasks built from your repo's fixed bugs. Build one in Our tasks; then every setup faces the same frozen bugs.",
                        action: ("Our tasks", { nav.go(.ourTasks) }))
        } else if let s = selected {
            switch store.boards[s.name] {
            case .success(let lb)?: loaded(lb)
            case .failure(let e)?:
                EvalsAEmpty(title: "The setups on this task could not be read",
                            detail: "Compare reads `leaderboard \(s.name) --by setup` from the eval engine (2.0.4). Nothing is shown in its place.",
                            error: e.message, action: ("Try again", { store.refreshBoards(board, force: true) }))
            case nil:
                Text("Reading every setup's latest test on this task…").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
        }
    }

    @ViewBuilder private func loaded(_ lb: EvalSetupLeaderboard) -> some View {
        if kind == nil { Text(EvalsACompare.headline(lb)).ui(17, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true) }
        HStack {
            if kind != .oneShot { Segmented(options: Mode.allCases.map { ($0, $0.rawValue) }, selection: $view).fixedSize() }
            Spacer()
            if let v = lb.version { Text("v\(v) · frozen bugs, the same for every setup").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
        }
        switch kind == .oneShot ? .setups : view {
        case .setups: setups(lb)
        case .grid: grid(lb)
        }
        untested(lb)
    }

    // MARK: By setup

    private func setups(_ lb: EvalSetupLeaderboard) -> some View {
        let rows = lb.ranked.filter { kind == nil || EvalJobKind.of($0) == kind }
        return VStack(alignment: .leading, spacing: 12) {
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if rows.isEmpty {
                        Text("No setup has a test on this task yet.").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider() }
                        setupRow(r, lb: lb, focused: listFocused && i == focusRow)
                    }
                    Divider()
                    HStack {
                        EvalsASquaresLegend(floorText: lb.floor.map { "\($0.text)" + ($0.rule.flatMap { r in r.split(separator: ":", maxSplits: 1).dropFirst().first.map { " (\($0.trimmingCharacters(in: .whitespaces)))" } } ?? "") })
                        Spacer()
                        if let s = lb.standIn { Text("stand-in model: \(EvalScoreText.count(s.right)) of \(s.n)").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                }
            }
            .focusable().focused($listFocused).focusEffectDisabled()
            .onKeyPress(.upArrow) { focusRow = max(focusRow - 1, 0); return .handled }
            .onKeyPress(.downArrow) { focusRow = min(focusRow + 1, max(rows.count - 1, 0)); return .handled }
            .onKeyPress(.return) { if rows.indices.contains(focusRow), let run = rows[focusRow].run, rows[focusRow].isDone { nav.openRun(run) }; return .handled }
            pairedCard(lb)
        }
    }

    private func setupRow(_ r: EvalSetupRow, lb: EvalSetupLeaderboard, focused: Bool) -> some View {
        let isPicked = r.run.map(picked.contains) ?? false
        let floor = lb.floor?.share
        let verdict = EvalVerdicts.againstFloor(EvalVerdicts.Side(r), floor: floor)
        return HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if r.isDone, let run = r.run {
                        Button { toggle(run) } label: {
                            Image(systemName: isPicked ? "checkmark.square.fill" : "square").foregroundStyle(isPicked ? t.accent.color : t.text3.color)
                        }
                        .buttonStyle(.plain).help(isPicked ? "Picked for the paired verdict" : "Pick two setups for the paired verdict")
                        .accessibilityLabel(isPicked ? "Unpick \(r.label)" : "Pick \(r.label) to compare")
                    }
                    Text(r.label).ui(TypeScale.body, .bold).foregroundStyle(t.text.color).lineLimit(2)
                }
                Text(how(r)).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                EvalsAStampLine(stamp: r.stamp)
            }
            .frame(width: 250, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                if r.isDone, let right = r.right, let n = r.n {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(EvalScoreText.count(right)).ui(24, .bold).foregroundStyle(t.text.color)
                            .evalHover(.score, EvalHover.score(score: r.share ?? 0, n: n))
                        Text("of \(n)").ui(TypeScale.small).foregroundStyle(t.text2.color)
                    }
                    if let v = verdict {
                        Text(v.text).ui(TypeScale.caption, .semibold).foregroundStyle(v.isCall ? t.diffAddText.color : t.evalsATone(.cantTell).ink.color)
                            .fixedSize(horizontal: false, vertical: true)
                            .evalHover(.floor, EvalHover.floor(share: floor, right: lb.floor?.right, of: lb.floor?.of))
                    }
                } else {
                    Text(EvalsACompare.statusText(r)).ui(TypeScale.small, .semibold)
                        .foregroundStyle(r.isActive ? t.evalsATone(.cantTell).ink.color : t.needsText.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: 150, alignment: .leading)
            VStack(alignment: .leading, spacing: 5) {
                EvalsABugSquares(squares: EvalsASquares.ordered(cases: lb.cases, perCase: r.perCase),
                                 guess: EvalsASquares.guessIndex(floor: lb.floor, n: r.n ?? lb.n ?? lb.cases.count),
                                 open: r.isDone ? { s in if let run = r.run { nav.openRun(run, sample: s.id) } } : nil)
                if r.isDone {
                    let note = [EvalsACompare.missedText(r, in: lb), r.expectText.map { $0 + "." }].compactMap { $0 }.joined(separator: " ")
                    Text(note).ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        .evalHoverIf(r.lo.map { lo in (.range, EvalHover.range(score: r.share ?? 0, n: r.n ?? 0, lo: lo, hi: r.hi ?? lo, unit: "bug")) })
                    HStack(spacing: 12) {
                        Text(costText(r)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                            .evalHover(.cost, EvalHover.cost(costText(r)))
                        if let c = r.costPerRight {
                            Text("\(EvalsAWords.dollars(c)) per right answer").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                                .evalHover(.costPerRight, EvalHover.costPerRight(c))
                        }
                        if let run = r.run {
                            HStack(spacing: 8) {   // LAB-2255: the way into One test is a button, not a text link
                                RoofButton("See each bug ›") { nav.openRun(run) }.fixedSize()
                                Text(EvalsAWords.day(r.started)).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                            }
                        }
                    }
                } else if r.isActive {
                    HStack(spacing: 10) {
                        Text("No squares until it finishes.").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                        RoofButton("Open the queue ›") { nav.sheet = .setup }.fixedSize()   // LAB-2255
                            .help("Run anyway, cancel or resume it in Set up a test › Running and recent")
                    }
                } else {
                    RoofButton("Resume or start again in the queue ›") { nav.sheet = .setup }.fixedSize()   // LAB-2255
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(focused || isPicked ? t.selection.color.opacity(isPicked ? 0.6 : 0.4) : .clear)
        .accessibilityElement(children: .contain)
    }

    private func how(_ r: EvalSetupRow) -> String {
        switch r.layer {
        case .model: return "answering on its own, no tools" + (r.stamp?.runsOn.map { " · \(Self.runsOn($0))" } ?? "")
        case .agentModel: return "using its tools" + (r.stamp?.runsOn.map { " · \(Self.runsOn($0))" } ?? "")
        case .full: return "using its tools, with your rules" + (r.stamp?.runsOn.map { " · \(Self.runsOn($0))" } ?? "")
        }
    }

    static func runsOn(_ s: String) -> String {
        if s.hasPrefix("seat:") { return "on your \(s.dropFirst(5)) seat" }
        if s.hasPrefix("api:") { return "API key · \(s.dropFirst(4))" }
        return s == "local" ? "on this Mac" : s
    }

    private func costText(_ r: EvalSetupRow) -> String {
        if (r.stamp?.runsOn ?? "").hasPrefix("seat:") { return "seat" }
        guard let c = r.cost else { return "cost unknown" }
        return c == 0 ? "free" : EvalsAWords.dollars(c) + " in all"
    }

    // MARK: Paired verdict

    private func toggle(_ run: String) {
        if let i = picked.firstIndex(of: run) { picked.remove(at: i) } else { picked = Array((picked + [run]).suffix(2)) }
    }

    private func compare(_ p: [String]) {
        compared = nil; compareError = nil
        guard p.count == 2 else { return }
        board.ask(["compare", p[0], p[1]], EvalCompareResult.self, timeout: 120) { r in
            guard self.picked == p else { return }
            switch r {
            case .success(let c): compared = c; EvalsLearnStore.note(EvalsLearnStore.compareKey)
            case .failure(let e): compareError = e.message
            }
        }
    }

    @ViewBuilder private func pairedCard(_ lb: EvalSetupLeaderboard) -> some View {
        let done = lb.rows.filter { $0.isDone && (kind == nil || EvalJobKind.of($0) == kind) }   // the same rows the page shows
        if done.count >= 2 || !picked.isEmpty {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    EvalsLabel("Two setups, the same bugs")
                    let a = lb.rows.first { $0.run == picked.first }, b = lb.rows.first { $0.run == picked.dropFirst().first }
                    if let a, let b {
                        let paired = compared.map(EvalsACompare.paired)
                        let v = EvalVerdicts.compare(EvalVerdicts.Side(a), EvalVerdicts.Side(b), paired: paired, floor: lb.floor?.share)
                        Text(compared == nil && compareError == nil ? "Comparing \(a.label) with \(b.label)…" : v.text)
                            .ui(TypeScale.section, .bold).foregroundStyle(v.isCall ? t.diffAddText.color : t.text.color)
                            .evalHoverIf(compared.map { c in (.compare, EvalHover.compare(diff: c.diff, lo: c.ci95.first ?? c.diff, hi: c.ci95.last ?? c.diff, paired: c.paired)) })
                        if let c = compared {
                            EvalsDiffAxis(diff: c.diff, lo: c.ci95.first ?? c.diff, hi: c.ci95.last ?? c.diff).frame(height: 34).frame(maxWidth: 420)
                            Text("\(a.label) minus \(b.label) over \(c.paired ? "\(c.n) shared bugs" : "no shared bugs (unpaired)")").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                            Text(EvalsACompare.onlyLine(c, a: a.label, b: b.label))
                                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                            if !c.discordant.isEmpty, let ra = a.run, let rb = b.run {   // LAB-2255: a button, not tappable text
                                RoofButton("See the \(c.discordant.count) bugs ›") { nav.openRun(ra, only: c.discordant, other: rb) }.fixedSize()
                            }
                        }
                        if let e = compareError { Text(e).ui(TypeScale.caption).foregroundStyle(t.needsText.color) }
                    } else {
                        Text(done.count < 2 ? "Only one setup has finished this task: a second one makes a comparison." : "Tick two setups above for the paired verdict.")
                            .ui(TypeScale.small).foregroundStyle(t.text2.color)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear {
                if picked.isEmpty, let want = nav.compareA, done.contains(where: { $0.run == want }) {
                    picked = [want]; nav.compareA = nil
                }
            }
        }
    }

    // MARK: Agent × model grid (v1 screen 2)

    private func grid(_ lb: EvalSetupLeaderboard) -> some View {
        let g = EvalsAGrid.build(lb, rules: gridRules)
        let cols = g.columns.isEmpty ? [EvalsAGrid.cliDefault] : g.columns
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(gridRules
                         ? "Rows are who does the work, columns are the model. Agent rows here ran with our rules on: the gap to the model on its own is the agent plus our rules."
                         : "Rows are who does the work, columns are the model. The gap between a model on its own and the agent below it is what the agent adds: reading the repo, tools, retries.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Picker("Our rules", selection: $gridRules) {
                        Text("With our rules").tag(true)
                        Text("Clean (no rules)").tag(false)
                    }
                    .pickerStyle(.segmented).frame(width: 240)
                    .help("Agent rows show only tests with our rules, or only clean ones (no rules); never both in one row")
                }
                ScrollView(.horizontal) {
                    Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
                        GridRow {
                            Text("").frame(width: 190)
                            ForEach(cols, id: \.self) { c in
                                Text(c).ui(TypeScale.caption, .semibold, mono: true).foregroundStyle(t.text2.color).frame(width: 150, alignment: .leading).lineLimit(1)
                            }
                        }
                        ForEach(g.rows) { row in
                            GridRow {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(row.title).ui(TypeScale.small, .bold).foregroundStyle(t.text.color)
                                    Text(row.sub).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                                }
                                .frame(width: 190, alignment: .leading)
                                ForEach(cols, id: \.self) { c in gridCell(row.cells[c], agent: row.agent, model: c, lb: lb) }
                            }
                        }
                        if let f = lb.floor {
                            GridRow {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text("No model").ui(TypeScale.small, .bold).foregroundStyle(t.text.color)
                                    Text("a simple rule: the floor").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                                }
                                .frame(width: 190, alignment: .leading)
                                Text("\(f.right) of \(f.of) on every column (\(f.text)). A setup has to clear this to be worth paying for.")
                                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).gridCellColumns(max(cols.count, 1))
                                    .evalHover(.floor, EvalHover.floor(share: f.share, right: f.right, of: f.of))
                            }
                        }
                    }
                }
                Text("Agents on your seats pass no model today unless you choose one (LAB-2240): their column is the CLI default until the stamp records the model that answered.")
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func gridCell(_ r: EvalSetupRow?, agent: String?, model: String, lb: EvalSetupLeaderboard) -> some View {
        let box = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        if let r, r.isDone, let share = r.share {
            Button { if let run = r.run { nav.openRun(run) } } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(evalsPct(share)).ui(TypeScale.body, .bold, mono: true).foregroundStyle(t.text.color)
                    if let lo = r.lo, let hi = r.hi { Text("\(Int((lo * 100).rounded()))–\(Int((hi * 100).rounded())) %").ui(TypeScale.micro, mono: true).foregroundStyle(t.text3.color) }
                    if let c = r.costPerRight { Text("\(EvalsAWords.dollars(c)) / right").ui(TypeScale.micro, mono: true).foregroundStyle(t.text3.color) }
                }
                .padding(8).frame(width: 150, alignment: .leading)
                .background(box.fill(t.surface2.color)).overlay(box.strokeBorder(t.separator.color))
            }
            .buttonStyle(.plain)
            .evalHoverIf(r.lo.map { lo in (.range, EvalHover.range(score: share, n: r.n ?? 0, lo: lo, hi: r.hi ?? lo, unit: "bug")) })
        } else if let r {
            Text(EvalsACompare.statusText(r)).ui(TypeScale.caption).foregroundStyle(t.evalsATone(.cantTell).ink.color)
                .padding(8).frame(width: 150, alignment: .leading).fixedSize(horizontal: false, vertical: true)
                .background(box.strokeBorder(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        } else if let choice = EvalsAGrid.choice(agent: agent, column: model, rules: gridRules, lb: lb) {
            EvalsGridTestCell { testCell(choice, lb: lb) }   // LAB-2255: a button you can see, with a hover
                .help("Set up a test, pre-filled with \(choice.label) on this task")
        } else {
            Text("not available").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                .padding(8).frame(width: 150, alignment: .leading)
                .background(box.strokeBorder(t.separator.color, style: StrokeStyle(lineWidth: 1, dash: [2, 3])))
                .help(agent.map { "\(EvalAgents.name($0))'s CLI can't be asked for \(model)" } ?? "Pick a model to test on its own")
        }
    }

    /// Set up a test pre-filled with exactly this cell's setup: the agent with the column's model and the grid's rules
    /// (review P2 #7), or the model on its own.
    private func testCell(_ choice: EvalSetupChoice, lb: EvalSetupLeaderboard) {
        guard let file = Self.taskFile(lb, board: board) else { return }
        let u = EvalsAUntested(label: choice.label, agent: choice.agent, model: choice.model, rules: choice.rules)
        nav.test(EvalsACompare.plan([u], taskFile: file, cases: lb.n ?? lb.cases.count))
    }

    // MARK: Not tested yet

    @ViewBuilder private func untested(_ lb: EvalSetupLeaderboard) -> some View {
        let others = sets.compactMap(board)
        let xs = EvalsACompare.untested(lb, others: others).filter { kind == nil || EvalJobKind.of($0) == kind }
        if !xs.isEmpty {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Not tested on this task yet (\(xs.count))").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text(xs.map(\.label).joined(separator: " · ")).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                if let file = Self.taskFile(lb, board: board) {
                    RoofButton("Test them", .primary) { nav.test(EvalsACompare.plan(xs, taskFile: file, cases: lb.n ?? lb.cases.count)) }
                        .help("Set up a test, with these setups ticked; nothing starts until Start")
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
        }
    }
}


/// LAB-2255: an empty grid cell you can test from: a framed button with a hover, not dashed text.
struct EvalsGridTestCell: View {
    @Environment(\.theme) private var t
    var action: () -> Void
    @State private var hover = false
    var body: some View {
        let box = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        Button(action: action) {
            HStack(spacing: 4) {
                Text("not run").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                Spacer(minLength: 4)
                Text("Test ›").ui(TypeScale.caption, .semibold).foregroundStyle(t.text.color)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.surface.color))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color, lineWidth: 1))
            }
            .padding(8).frame(width: 150, alignment: .leading)
            .background(box.fill(hover ? t.control.color : t.surface2.color))
            .overlay(box.strokeBorder(hover ? t.text2.color : t.separatorStrong.color, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel("Not run. Test this setup.")
    }
}
