import SwiftUI
import OneRoofCore

/// LAB-2242 · E2.1 Compare (screen lane A owns this file): one task, setups ranked, one square per bug.
/// Engine: `board.setupLeaderboard(task:version:)` (CONTRACT §3, `leaderboard <task> --by setup`); verdicts from
/// `EvalVerdicts.compare` / `.againstFloor`, ranges from `EvalVerdicts.expect`, stamps from `EvalStamp.parts`.
/// Placeholder: today's Results › By eval (leaderboard, compare with a plain verdict, over time) until rebuilt.
struct EvalsCompareView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                RoofButton("All results ›", .plain) { nav.route = .allResults }
                    .help("Every task × every setup, every test, export")
            }
            EvalsResultsV2(board: board, nav: nav)
        }
        .onAppear { if nav.resultsMode != .byEval { nav.resultsMode = .byEval } }
    }
}
