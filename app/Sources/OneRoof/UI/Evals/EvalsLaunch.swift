import SwiftUI
import OneRoofCore

/// LAB-2259 · E1.1 Launch (Evals v3, Claude Design 13A, adapted): "What can we trust to do our work?" Two kinds of job, the
/// agent sheet drawn on the one-shot sheet (agent jobs are built on a model), each with its tasks, its loops (placed by
/// definition, D1), what it is made of, and one evidence bar whose segments are buttons (width = share of the evidence).
/// Added so nothing is lost: public agent benchmarks as their own button under the agent bar (D3), the loops that use no
/// model (D2), and three answer buttons (D9: Changes, Real history, All results). No tab bar: this view is the navigation.
struct EvalsLaunchView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @ObservedObject private var loops = EvalsLoopsStore.shared
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    /// LAB-2273: the page's width. The sheets flex with the window; the bars, the layer stack and the agent sheet grow in
    /// proportion (each between its 2.0.5 size and a cap), so nothing is left empty at 1700 pt and wider.
    @State private var pageWidth: CGFloat = 1100

    private var benchmarks: [EvalBenchmark] { board.catalog?.benchmarks.filter { !$0.isOwn } ?? [] }
    private var barWidth: CGFloat { min(max(pageWidth * 0.40, 420), 760) }
    private var agentWidth: CGFloat { min(max(pageWidth * 0.52, 640), 1100) }
    private var stackWidth: CGFloat { min(max(pageWidth * 0.34, 380), 640) }
    /// QA #4: agent-harness benchmarks count on the agent side ("Public agent benchmarks"), never in the one-shot bar.
    private var agentBenchmarks: Set<String> { EvalEvidence.agentBenchmarks(board.catalog?.benchmarks ?? []) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What can we trust to do our work?").ui(30, .bold).tracking(-0.5).foregroundStyle(t.text.color)
                    Text("Two kinds of job. Each bar shows where its evidence comes from. Click a colour to see it.")
                        .ui(15).foregroundStyle(t.text2.color)
                }
                oneShotSheet
                legend
                noModelLine
                answers
                if let g = EvalsALayers.graderLine(EvalEvidence.graderRuns(board.results)) {
                    Text(g).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // LAB-2273: was capped at 1100 pt
            .padding(.bottom, 26)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
        .onAppear { loops.refresh(); store.refreshBoards(board) }
    }

    // MARK: The two sheets (the agent sheet sits on the one-shot sheet, lower right)

    private var oneShotSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            sheetHead(.oneShot)
            chips(.oneShot)
            EvalsLayerStack(kind: .oneShot).frame(maxWidth: stackWidth)
            EvalsEvidenceBar(kind: .oneShot, evidence: evidence(.oneShot), width: barWidth) { nav.open(.segment(.oneShot, $0)) }
            HStack {
                Spacer(minLength: 0)
                agentSheet.frame(maxWidth: agentWidth)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.evalsSheet(.oneShot).color))   // QA #1: a neutral, not `selection` blue
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.text2.color, lineWidth: 1.5))
    }

    private var agentSheet: some View {
        let pubAgent = EvalEvidence.publicAgentRuns(board.results, agentBenchmarks: agentBenchmarks)
        let agentBench = benchmarks.filter(\.isAgentTask).count
        return VStack(alignment: .leading, spacing: 12) {
            sheetHead(.agent)
            chips(.agent)
            EvalsLayerStack(kind: .agent)
            EvalsEvidenceBar(kind: .agent, evidence: evidence(.agent), width: min(barWidth, agentWidth - 44)) { nav.open(.segment(.agent, $0)) }
            Text("No public segment: nobody else has our code or setup.").ui(TypeScale.caption).foregroundStyle(t.text2.color)
            EvalsGoTile(title: "Public agent benchmarks · \(agentBench)",
                        detail: "Out of the box, never our setup. " + (pubAgent > 0 ? "\(EvalsAWords.count(pubAgent, "run")) here, for context." : "For context."),
                        symbol: "globe", tint: t.evidence(.publicTests).fill) { nav.open(.agentPublic) }
        }
        .padding(22)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(t.evalsSheet(.agent).color))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(t.text.color, lineWidth: 2))
        .shadow(color: t.text.color.opacity(0.12), radius: 14, y: 6)
    }

    private func sheetHead(_ k: EvalJobKind) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            EvalsJobTag(kind: k)
            Text(k.sheetTitle).ui(20, .bold).foregroundStyle(t.text.color)
        }
    }

    /// TASKS: our task sets this kind is tested on (one-shot: every task + the graders; agent: the tasks agents can run);
    /// LOOPS: the loops of this kind (D1). Loops with no live run in 30 days are drawn quieter.
    private func chips(_ k: EvalJobKind) -> some View {
        let sets = EvalsAStore.ownSets(board)
        let tasks = (k == .oneShot ? sets : sets.filter { $0.kind != "triage" }).map { EvalTaskWords.title(kind: $0.kind) }
        let graders = k == .oneShot ? board.judges.map { _ in "Grading our notes" } : []
        let ls = loops.rows.filter { $0.place.jobKind == k }.sorted { ($0.runs, $0.title) > ($1.runs, $1.title) }
        return VStack(alignment: .leading, spacing: 8) {
            chipRow("Tasks", k, Array(Set(tasks + graders)).sorted().map { ($0, false, true, nil as String?) })
            chipRow("Loops", k, ls.prefix(8).map { ($0.title, true, $0.runs > 0, "\($0.countLine) in 30 days · good run: \($0.goodRun)") },
                    more: ls.count > 8 ? ls.count - 8 : 0)
        }
    }

    private func chipRow(_ label: String, _ kind: EvalJobKind, _ items: [(String, Bool, Bool, String?)], more: Int = 0) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label.uppercased()).ui(10.5, .bold).tracking(0.6).foregroundStyle(t.text2.color).frame(width: 52, alignment: .leading)
            EvalsFlow(spacing: 6) { chipItems(label, kind, items, more: more) }
        }
    }

    @ViewBuilder private func chipItems(_ label: String, _ kind: EvalJobKind, _ items: [(String, Bool, Bool, String?)], more: Int) -> some View {
            if items.isEmpty {
                Text(label == "Loops" ? (loops.loaded ? "none of this kind" : "reading the loops…") : "none yet").ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
            ForEach(items, id: \.0) { name, loop, live, help in
                HStack(spacing: 4) {
                    if loop { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold)) }
                    Text(name).ui(12.5, .semibold).lineLimit(1).fixedSize()
                }
                .foregroundStyle(live ? t.text.color : t.text3.color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(t.surface.color))
                .overlay(Capsule().strokeBorder(t.separator.color))
                .help(help ?? name)
            }
            if more > 0 {
                // this sheet's loops (2.0.5 review P2); LAB-2255: a button you can see, not a text link
                RoofButton("+\(more) more") { nav.open(.segment(kind, .loopRuns)) }.fixedSize()
                    .help("See every loop of this kind and its runs")
            }
    }

    private func evidence(_ k: EvalJobKind) -> EvalEvidence {
        EvalEvidence.count(results: board.results, runs: board.runs, loops: loops.rows, kind: k, agentBenchmarks: agentBenchmarks)
    }

    // MARK: Under the sheets

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 14) {
                ForEach(EvalEvidenceSource.allCases) { s in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 3).fill(t.evidence(s).fill.color).frame(width: 14, height: 10)
                        Text(s.legend).ui(TypeScale.small).foregroundStyle(t.text2.color)
                    }
                }
                Text("· segment width = share of the evidence").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
            // QA #10 (OV-08): say what the bars are counted from.
            Text("Counted from this Mac's run store and the loops' ledger (30 days).").ui(TypeScale.caption).foregroundStyle(t.text3.color)
        }
    }

    /// D2: the loops that use no model are listed, not judged.
    @ViewBuilder private var noModelLine: some View {
        let none = loops.rows.filter { $0.place == .noModel }
        if !none.isEmpty {
            EvalsGoTile(title: "\(EvalsAWords.count(none.count, "loop")) use no model, so Evals doesn't judge them",
                        detail: none.sorted { $0.runs > $1.runs }.prefix(6).map(\.title).joined(separator: " · ") + (none.count > 6 ? " and \(none.count - 6) more" : "") + ". They are checks written in code; see them in Loops.",
                        symbol: "gearshape.2") { nav.openLoops() }
        }
    }

    /// D9: the 2.0.4 Overview's three questions (answer, what a test records today, "To answer it properly"), kept whole,
    /// and every result at once, one click from here.
    private var answers: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Three questions, answered from our own runs").ui(TypeScale.title, .bold).foregroundStyle(t.text.color).padding(.top, 8)
            EvalsOverviewTab(board: board, nav: nav, embedded: true)
            EvalsGoTile(title: "Every result, one grid", detail: "Every model and agent on every task, every test, export to CSV or JSON.",
                        symbol: "square.grid.3x3") { nav.open(.allResults) }
        }
    }
}

// MARK: - Pieces

/// "ONE-SHOT JOBS" (slate) / "AGENT JOBS" (ink).
struct EvalsJobTag: View {
    @Environment(\.theme) private var t
    let kind: EvalJobKind
    var body: some View {
        Text(kind.tag.uppercased()).ui(10.5, .bold).tracking(0.8).foregroundStyle(t.jobTag(kind).ink.color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.jobTag(kind).fill.color))
    }
}

/// A source tag in the source's colour ("PUBLIC", "OURS", "LOOP RUNS").
struct EvalsSourceTag: View {
    @Environment(\.theme) private var t
    let source: EvalEvidenceSource
    var title: String? = nil
    var body: some View {
        HStack(spacing: 4) {
            if source == .loopRuns { Image(systemName: "arrow.clockwise").font(.system(size: 9, weight: .bold)) }
            Text((title ?? source.tag).uppercased()).ui(10.5, .bold).tracking(0.8)
        }
        .foregroundStyle(t.evidence(source).ink.color)
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.evidence(source).fill.color))
    }
}

/// What a sheet is made of: one band per part, light to ink; the loop band dashed.
struct EvalsLayerStack: View {
    @Environment(\.theme) private var t
    let kind: EvalJobKind
    var body: some View {
        let parts = kind.stack
        VStack(spacing: 4) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, p in
                let isLoop = i == parts.count - 1
                let (fill, ink) = band(i, of: parts.count, loop: isLoop)
                HStack {
                    Text(p.name).ui(13, .bold)
                    Spacer(minLength: 8)
                    Text(p.detail).ui(12).lineLimit(1)
                }
                .foregroundStyle(ink.color)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(fill.color))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isLoop ? t.text.color : t.separator.color, style: StrokeStyle(lineWidth: isLoop ? 1.5 : 1, dash: isLoop ? [5, 4] : [])))
            }
        }
    }
    /// The model is plain surface; each added part steps toward ink in neutrals (QA #1: colour = source only); the loop is plain again.
    private func band(_ i: Int, of n: Int, loop: Bool) -> (RGB, RGB) { t.layerBand(i, of: n, loop: loop) }
}

/// One bar per kind of job: each segment is a button in its source's colour, width = its share of the evidence.
struct EvalsEvidenceBar: View {
    @Environment(\.theme) private var t
    let kind: EvalJobKind
    let evidence: EvalEvidence
    var width: CGFloat = 420
    var open: (EvalEvidenceSource) -> Void
    @State private var hovered: EvalEvidenceSource?

    var body: some View {
        let srcs = EvalEvidenceSource.sources(kind)
        let shares = evidence.shares(kind)
        let widths = EvalEvidence.widths(shares: srcs.map { shares[$0] ?? 0 }, total: Double(width), gap: 4, minimum: 92)
        HStack(spacing: 4) {
            ForEach(Array(srcs.enumerated()), id: \.element) { i, s in
                let w = CGFloat(widths[i])
                let e = t.evidence(s)
                Button { open(s) } label: {
                    HStack(spacing: 4) {
                        if s == .loopRuns { Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .bold)) }
                        Text(s.label(kind, narrow: w < 120)).ui(12.5, .bold).lineLimit(1)
                        Spacer(minLength: 2)
                        Text("›").ui(13, .bold)
                    }
                    .foregroundStyle(e.ink.color)
                    .padding(.horizontal, 10)
                    .frame(width: w, height: 34)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(e.fill.color).brightness(hovered == s ? 0.05 : 0))
                    .shadow(color: t.text.color.opacity(0.18), radius: 0, y: 2)
                    .offset(y: hovered == s ? -1 : 0)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? s : (hovered == s ? nil : hovered) }
                .help(help(s))
                .accessibilityLabel("\(kind.title): \(s.title), \(evidence.count(s)). Opens its page.")
            }
        }
        .animation(.easeOut(duration: 0.12), value: hovered)
    }

    private func help(_ s: EvalEvidenceSource) -> String {
        switch s {
        case .publicTests: return "\(EvalsAWords.count(evidence.publicTests, "finished public test")) on this Mac. Open: which models are worth trying."
        case .ours:
            var x = "\(EvalsAWords.count(evidence.ours, "finished test")) on our own tasks"
            if evidence.waiting > 0 { x += ", \(evidence.waiting) waiting" }
            if evidence.standIn > 0 { x += ", \(evidence.standIn) on the stand-in (not counted)" }
            return x + ". Open it."
        case .loopRuns: return "\(EvalsAWords.count(evidence.loopRuns, "live loop run")) in the last 30 days. Open it."
        }
    }
}

/// LAB-2255: every way to another screen is a tile you can see (title, one line, a chevron, a hover), never a bare link.
struct EvalsGoTile: View {
    @Environment(\.theme) private var t
    let title: String
    var detail: String? = nil
    var symbol: String? = nil
    var tint: RGB? = nil
    var action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                        .foregroundStyle((tint.map { RGB.contrast($0, t.surface) > 1.6 ? $0 : t.text2 } ?? t.accentText).color)
                        .frame(width: 18)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    if let detail { Text(detail).ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .bold)).foregroundStyle(t.accentText.color)
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(hover ? t.selection.opacity(0.5).over(t.surface).color : t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(hover ? t.accent.color : t.separatorStrong.color.opacity(0.6), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .accessibilityLabel(title + (detail.map { ". " + $0 } ?? ""))
    }
}

// MARK: - Loops and their runs (read off the main thread; refreshed at most once a minute)

final class EvalsLoopsStore: ObservableObject {
    static let shared = EvalsLoopsStore()
    @Published private(set) var rows: [EvalLoopRuns] = []
    @Published private(set) var loaded = false
    @Published private(set) var error: String?
    private var last: Date?
    private let q = DispatchQueue(label: "evals.v3.loops", qos: .userInitiated)

    func refresh(force: Bool = false) {
        if !force, let l = last, Date().timeIntervalSince(l) < 60 { return }
        last = Date()
        q.async {
            let all = LoopStore().all()
            var counts: [LoopLedger.WindowCount] = []
            var err: String?
            do { counts = try LoopLedger(readingOnly: LoopLedger.defaultPath()).counts(since: Date().addingTimeInterval(-30 * 86_400)) }   // counted in SQLite: the whole window
            catch { err = "The loops' outcome ledger could not be read: \(error)" }
            let rows = EvalLoopRuns.summarize(loops: all, counts: counts)
            DispatchQueue.main.async { self.rows = rows; self.error = err; self.loaded = true }
        }
    }
}

/// Lays chips out left to right and wraps to the next line (no squashed or two-line chips).
struct EvalsFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > w { y += line + spacing; x = 0; line = 0 }
            x += s.width + spacing; line = max(line, s.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, line: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { y += line + spacing; x = b.minX; line = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; line = max(line, s.height)
        }
    }
}
