import SwiftUI
import OneRoofCore

/// LAB-2242 · E6.2 A public benchmark: How it works · Questions · Published scores · Your runs (screen lane B owns this
/// file). Route `.oneBenchmark(id:task:part:)`. Engine: `anatomy`, `items`, `item`, `item-results`, `scores`.
/// Placeholder: today's benchmark page (and its Questions page) until rebuilt.
struct EvalsBenchmarkDetailView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let id: String
    var task: String?
    var part: EvalsNav.ExploreTab
    @Environment(\.theme) private var t

    private var bench: EvalBenchmark? {
        board.catalog?.benchmarks.first { $0.id == id || $0.folder == id || $0.tasks.contains { $0.name == id } }
    }

    var body: some View {
        if part == .questions {
            EvalsQuestionsPage(board: board, nav: nav, benchmark: bench?.id ?? id, task: task ?? bench?.defaultTask ?? id)
        } else if let b = bench {
            EvalsBenchmarkPage(board: board, nav: nav, benchmark: b)
                .padding(.horizontal, 24).padding(.bottom, 24)
                .onAppear { if nav.exploreTab != part { nav.exploreTab = part } }
        } else {
            Text(board.catalog == nil ? "Reading the benchmarks…" : "No benchmark named \(id).")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }
}
