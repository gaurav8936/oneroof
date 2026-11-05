import SwiftUI
import OneRoofCore

/// LAB-2242 · E6.2 A public benchmark (screen lane B): 2.0.3's Explore page, every feature kept — on the left the list
/// (search ⌘F, shelves, what it tests, more topics, graded by, No Docker needed, I've run it, Judges shelf, version +
/// Rescan), on the right the benchmark (source line, summary, Test a model on it…, Hugging Face lock) with How it works ·
/// Questions N · Published scores · Your runs N. Questions open full width (load prompt, gated sets, R for random 10).
/// Route `.oneBenchmark(id:task:part:)`. Engine: `catalog`, `anatomy`, `items`, `item`, `item-results`, `scores`.
struct EvalsBenchmarkDetailView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let id: String
    var task: String?
    var part: EvalsNav.ExploreTab
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2

    private var bench: EvalBenchmark? {
        board.catalog?.benchmarks.first { $0.id == id || $0.folder == id || $0.tasks.contains { $0.name == id } }
    }
    private var lead: CGFloat { v2 ? CGFloat(V2Layout.Bar.contentLead) : 28 }

    var body: some View {
        if part == .questions {
            EvalsQuestionsPage(board: board, nav: nav, benchmark: bench?.id ?? id, task: task ?? bench?.defaultTask ?? id)
                .padding(.horizontal, lead - 20)
        } else if board.catalog != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("One of \(board.catalog?.benchmarks.filter { !$0.isOwn }.count ?? 0) · the same page for every benchmark; your own tasks use Our tasks › One task instead")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                EvalsExploreTab(board: board, nav: nav)
            }
            .padding(.horizontal, lead).padding(.bottom, 20)
            .onAppear {
                if let b = bench, nav.benchmark != b.id { nav.benchmark = b.id }
                if nav.exploreTab != part { nav.exploreTab = part }
            }
        } else {
            Text("Reading the benchmarks…").ui(TypeScale.body).foregroundStyle(t.text2.color).padding(.horizontal, lead)
        }
    }
}
