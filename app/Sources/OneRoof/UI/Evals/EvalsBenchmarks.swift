import SwiftUI
import OneRoofCore

/// LAB-2242 · E6.1 Public benchmarks (screen lane B): other people's tests, for context. The headline puts them in their
/// place (the model, sometimes the agent, never your full setup); a table of the benchmarks this Mac has run — what each
/// tests, its layer, your best run and the published best — with the small-sample warning; then three uses (check a new
/// model is wired up · check your numbers match the maker's · learn how evals work → browse all). Every benchmark opens
/// E6.2 (`nav.openBenchmark`). Engine: `catalog`, `results`, `scores show <task>` (published best, stored; no fetch).
struct EvalsBenchmarksView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    /// v3 (2.0.5): One-shot › Public tests shows the model benchmarks; Agent › Public agent benchmarks the agent ones
    /// (D3: outside the agent bar). nil = every benchmark (E6.1 on its own). `embedded`: the segment page draws the headline.
    var layer: EvalStamp.Layer? = nil
    var embedded = false
    @State private var published: [String: EvalPublishedScores] = [:]

    private var rows: [EvalBenchmarkSummaryRow] {
        EvalBenchmarkSummaryRow.rows(catalog: board.catalog?.benchmarks ?? [], results: board.results)
            .filter { r in layer.map { $0 == .model ? r.layer == .model : r.layer != .model } ?? true }
    }
    private var total: Int { board.catalog?.benchmarks.filter { !$0.isOwn }.count ?? 0 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if !embedded { headline }
                table
                uses
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.bottom, 20)
        }
        .onAppear(perform: loadPublished)
        .onChange(of: board.results) { _, _ in loadPublished() }
        .onChange(of: board.catalog) { _, _ in loadPublished() }
    }

    @ViewBuilder private var headline: some View {
                Text("Public benchmarks test the model, and sometimes the agent. They never test your full setup: only your own tasks can.")
                    .ui(TypeScale.section, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                Text("Use them to check a model is set up right, to compare with published scores, and to learn how evals work. They are context: never the answer on their own.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
    }

    private func loadPublished() {
        for r in rows where published[r.id] == nil {
            guard let b = board.catalog?.benchmarks.first(where: { $0.id == r.id }) else { continue }
            board.ask(["scores", "show", b.defaultTask], EvalPublishedScores.self, timeout: 60) { if case .success(let s) = $0 { published[r.id] = s } }
        }
    }

    // MARK: The table

    private var table: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if board.catalog == nil {
                    Text(board.busy ?? "Reading the benchmarks…").ui(TypeScale.small).foregroundStyle(t.text2.color).padding(14)
                } else if rows.isEmpty {
                    Text(layer != nil && layer != .model ? "No public agent benchmark has been run on this Mac yet."
                         : "No public benchmark has been run on this Mac yet. Smoke test below runs 5 free questions.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).padding(14)
                } else {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                        GridRow {
                            ForEach(["Benchmark", "What it tests", "Layer", "Your best run", "Published best"], id: \.self) { EvalsLabel($0) }
                        }
                        .padding(.vertical, 10)
                        ForEach(rows) { r in
                            GridRow {
                                Button { nav.openBenchmark(r.id) } label: {
                                    Text(r.name).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).help("Open \(r.name): how it works, its questions, published scores, your runs")
                                Text(r.tests).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                Text(r.layer == .model ? "The model" : "Agent, out of the box").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                                Text(r.bestRun).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                    .evalHoverIf(r.bestScore.flatMap { s in r.bestN.map { n in
                                        let w = EvalStats.wilson(s, n: n)
                                        return (.range, EvalHover.range(score: s, n: n, lo: w.lo, hi: w.hi))
                                    } })
                                Text(EvalBenchmarkSummaryRow.published(published[r.id])).ui(TypeScale.small).foregroundStyle(t.text2.color)
                                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                                    .help(published[r.id]?.source.map { "From \($0.name), checked \(published[r.id]?.checked?.prefix(10) ?? "")" } ?? "No published source for this benchmark")
                            }
                            .padding(.vertical, 9)
                            GridRow { Rectangle().fill(t.separator.color).frame(height: 1).gridCellColumns(5) }
                        }
                    }
                    .padding(.horizontal, 14)
                    if let note = EvalBenchmarkSummaryRow.smallNote(rows) {
                        Text(note).ui(TypeScale.caption).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                            .evalHover(.n, "Fewer than 30 questions: the 95 % range is wide, so the score says little on its own.")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Three uses

    @ViewBuilder private var uses: some View {
        if let l = layer, l != .model { agentUses } else { modelUses }
    }

    /// D3: the agent benchmarks' own uses (no smoke test: they need an agent, a sandbox and a key).
    private var agentUses: some View {
        let agents = board.catalog?.benchmarks.filter { !$0.isOwn && $0.isAgentTask } ?? []
        return HStack(alignment: .top, spacing: 12) {
            use("See how an agent does out of the box", "Other people's code and tests, none of our files. Useful to compare agents and models in general.",
                "Browse the \(agents.count) agent benchmarks ›") {
                nav.openBenchmark(agents.first { $0.isStarter }?.id ?? agents.first?.id ?? "swe_bench")
            }
            use("Test the agent as we use it", "Only our own tasks run the agent on our code with our setup.", "Agent jobs › Our tests ›") {
                nav.open(.agentOurs)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var modelUses: some View {
        HStack(alignment: .top, spacing: 12) {
            use("Check a new model is wired up", "5 GSM8K questions, free on the stand-in or a model on this Mac.", "Smoke test ›") {
                nav.test(EvalFirstEval.freePlan)
            }
            use("Check your numbers match the maker's", "If yours are far off, the setup is wrong, not the model.", "Compare with published ›") {
                nav.openBenchmark(rows.first { $0.layer == .model }?.id ?? "gsm8k", part: .scores)
            }
            use("Learn how evals work", "\(total) benchmarks to read and try, plus \(EvalsLearnStore.book?.lessons.count ?? 16) short lessons.", "Browse all \(total) ›") {
                nav.openBenchmark(board.catalog?.benchmarks.first { !$0.isOwn && $0.isStarter }?.id ?? board.catalog?.benchmarks.first?.id ?? "gsm8k")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func use(_ title: String, _ line: String, _ action: String, _ go: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
            Text(line).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 2)
            RoofButton(action, action: go).fixedSize()   // LAB-2255: a button you can see, not a text link
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
    }
}
