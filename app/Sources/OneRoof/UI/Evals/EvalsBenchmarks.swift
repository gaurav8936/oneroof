import SwiftUI
import OneRoofCore

/// LAB-2242 · E6.1 Public benchmarks (screen lane B owns this file): summary, shelves, topics, graded by, filters,
/// search (⌘F), Rescan. Engine: `catalog` (board.catalog, board.refreshCatalog(force:)); open one with
/// `nav.openBenchmark(id, part:)`. Placeholder: today's Explore tab until rebuilt.
struct EvalsBenchmarksView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav

    var body: some View {
        EvalsExploreTab(board: board, nav: nav)
    }
}
