import SwiftUI
import OneRoofCore

/// LAB-2260 · E2.1–E3.2 (+ E3.0 public agent benchmarks, D3): one page per bar segment. Tags (job kind + source in its
/// colour), the page's question and its one-sentence answer by rule, then the evidence — the 2.0.4 screen that held it,
/// kept whole so nothing is lost: Our tests = 2.0.4 Compare for that kind (rows, squares, paired verdict, Not tested yet,
/// the agent × model grid on agent jobs); Public tests = the 2.0.4 Public benchmarks landing (model or agent benchmarks);
/// Loop runs = the loops of that kind from the outcome ledger (good runs not recorded yet: never invented). Every way on
/// is a visible tile (LAB-2255).
struct EvalsSegmentPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let screen: EvalsV3Screen
    @ObservedObject private var store = EvalsAStore.shared
    @ObservedObject private var loops = EvalsLoopsStore.shared
    @Environment(\.theme) private var t

    private var kind: EvalJobKind { EvalsCrumbs.kind(of: screen) ?? .oneShot }
    private var source: EvalEvidenceSource { screen.segment?.1 ?? .publicTests }

    var body: some View {
        if screen == .oneShotOurs || screen == .agentOurs {
            // Compare scrolls on its own; the head sits above it.
            VStack(alignment: .leading, spacing: 14) {
                head
                EvalsCompareView(board: board, nav: nav, kind: kind)
            }
            .onAppear(perform: appear)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    head
                    evidence
                    foot
                }
                .frame(maxWidth: 1000, alignment: .leading)
                .padding(.bottom, 24)
            }
            .onAppear(perform: appear)
        }
    }

    private func appear() { loops.refresh(); store.refreshBoards(board) }

    // MARK: Head: tags, question, answer, and the ways on

    private var head: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                EvalsJobTag(kind: kind)
                EvalsSourceTag(source: source, title: screen == .agentPublic ? "Public · out of the box" : nil)
            }
            Text(EvalsV3Answers.question(screen)).ui(28, .bold).tracking(-0.4).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true)
            Text(answer).ui(15).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 900, alignment: .leading)
            if !ways.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(Array(ways.enumerated()), id: \.offset) { _, w in
                        EvalsGoTile(title: w.title, detail: w.detail, symbol: w.symbol, action: w.go)
                    }
                }
                .frame(maxWidth: 1000).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            }
        }
    }

    private var answer: String {
        switch screen {
        case .oneShotPublic: return EvalsV3Answers.publicOneShot
        case .agentPublic: return EvalsV3Answers.publicAgent
        case .oneShotOurs, .agentOurs: return EvalsV3Answers.ours(boards, kind: kind)
        case .oneShotLoops, .agentLoops:
            if !loops.loaded { return "Reading the loops and their runs…" }
            return EvalLoopRuns.answer(loops.rows.filter { $0.place.jobKind == kind }, kind: kind)
        default: return ""
        }
    }

    private var boards: [EvalSetupLeaderboard] {
        EvalsAStore.ownSets(board).compactMap { if case .success(let lb)? = store.boards[$0.name] { return lb }; return nil }
    }

    private struct Way { var title: String; var detail: String?; var symbol: String; var go: () -> Void }

    /// The pages one step on from here (v3 page footers + D9), as tiles.
    private var ways: [Way] {
        switch screen {
        case .oneShotOurs:
            return [Way(title: "All results", detail: "Every task × every setup, every test, export", symbol: "square.grid.3x3") { nav.open(.allResults) },
                    Way(title: "Our tasks", detail: "How each task is built, its versions and blind guess", symbol: "list.bullet.rectangle") { nav.open(.ourTasks) },
                    Way(title: "Check the grader", detail: "Label notes; how far to trust the grading model", symbol: "checkmark.seal") { nav.openGrader(nil) }]
        case .agentOurs:
            return [Way(title: "Did my last change help?", detail: "Rule and skill changes, before / after tests", symbol: "arrow.triangle.branch") { nav.open(.changes) },
                    Way(title: "What git shows", detail: "Real history: each agent's commits that needed a fix", symbol: "clock.arrow.circlepath") { nav.open(.realHistory) },
                    Way(title: "All results", detail: "Every task × every setup, export", symbol: "square.grid.3x3") { nav.open(.allResults) },
                    Way(title: "Our tasks", detail: "Tasks, versions, the next version", symbol: "list.bullet.rectangle") { nav.open(.ourTasks) }]
        case .oneShotPublic:
            return [Way(title: "All public benchmarks", detail: "The library: shelves, filters, how each one scores", symbol: "books.vertical") { nav.open(.benchmarks) }]
        case .agentPublic:
            return [Way(title: "All public benchmarks", detail: "The library, Agent tasks shelf included", symbol: "books.vertical") { nav.open(.benchmarks) }]
        case .agentLoops:
            return [Way(title: "What git shows", detail: "Real history: what happened to the agents' commits", symbol: "clock.arrow.circlepath") { nav.open(.realHistory) },
                    Way(title: "Open Loops", detail: "Every loop, its schedule, rounds and outcomes", symbol: "arrow.clockwise") { nav.openLoops() }]
        case .oneShotLoops:
            return [Way(title: "Open Loops", detail: "Every loop, its schedule, rounds and outcomes", symbol: "arrow.clockwise") { nav.openLoops() }]
        default: return []
        }
    }

    // MARK: The evidence

    @ViewBuilder private var evidence: some View {
        switch screen {
        case .oneShotPublic: EvalsBenchmarksView(board: board, nav: nav, layer: .model, embedded: true)
        case .agentPublic: EvalsBenchmarksView(board: board, nav: nav, layer: .agentModel, embedded: true)
        case .oneShotLoops, .agentLoops: EvalsLoopRunsList(nav: nav, kind: kind)
        default: EmptyView()
        }
    }

    @ViewBuilder private var foot: some View {
        let f = EvalsV3Answers.foot(screen)
        if !f.isEmpty { Text(f).ui(TypeScale.small).foregroundStyle(t.text2.color) }
    }
}

/// E2.3 / E3.2: one row per loop of this kind. Bar = finished runs of all live runs (light blue, the loop-runs colour);
/// "good run: not recorded" until each run is judged (EV-12). A row opens One Roof › Loops at that loop.
struct EvalsLoopRunsList: View {
    @ObservedObject var nav: EvalsNav
    let kind: EvalJobKind
    @ObservedObject private var loops = EvalsLoopsStore.shared
    @Environment(\.theme) private var t

    var body: some View {
        let rows = loops.rows.filter { $0.place.jobKind == kind }.sorted { ($0.runs, $0.title) > ($1.runs, $1.title) }
        VStack(alignment: .leading, spacing: 8) {
            if let e = loops.error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if !loops.loaded {
                        Text("Reading the loops…").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                    } else if rows.isEmpty {
                        Text(kind == .oneShot ? "No loop that asks a model once was found." : "No loop that runs an agent on our code was found.")
                            .ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                    }
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        if i > 0 { Divider() }
                        row(r)
                    }
                }
            }
            .frame(maxWidth: 900)
        }
    }

    private func row(_ r: EvalLoopRuns) -> some View {
        Button { nav.openLoops(r.loop) } label: {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .bold))
                        Text(r.title).ui(TypeScale.body, .bold)
                    }
                    .foregroundStyle(t.text.color)
                    Text("Good run: \(r.goodRun)").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    Text("good run: not recorded yet").ui(TypeScale.caption, .semibold).foregroundStyle(t.needsText.color)
                        .help("Each run is not yet judged good or bad (EV-12), so only run counts are shown.")
                }
                Spacer(minLength: 12)
                bar(r).frame(width: 220, height: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(r.runs > 0 ? "\(r.finished) / \(r.runs) finished" : "no live runs").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                    Text(r.countLine).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
                .frame(width: 150, alignment: .trailing)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(t.accentText.color)
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
            .contentShape(Rectangle())
            .hoverHighlight(radius: 0)
        }
        .buttonStyle(.plain)
        .help("Open \(r.title) in Loops: its schedule, rounds and outcomes")
    }

    @ViewBuilder private func bar(_ r: EvalLoopRuns) -> some View {
        if r.runs == 0 {
            Capsule().strokeBorder(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .background(Capsule().fill(t.surface2.color))
        } else {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.surface2.color)
                    Capsule().fill(t.evidence(.loopRuns).fill.color).frame(width: g.size.width * CGFloat(r.finished) / CGFloat(max(r.runs, 1)))
                }
            }
        }
    }
}
