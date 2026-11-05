import SwiftUI
import OneRoofCore

/// LAB-2242 · E4.1 Real history (git) (screen lane A owns this file): per agent, stood / needed a fix / reverted, across
/// repos, 60 days. Engine: `xray --repo R [--repo …] --days 60` (CONTRACT §6) → `EvalHistoryRow.from(EvalXRay)` (or
/// decode [EvalHistoryRow]); "followed by a fix" = `followedByFix` with `EvalHistoryRow.pct(fixup)`.
/// Placeholder: today's X-ray table until rebuilt.
struct EvalsRealHistoryView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav

    var body: some View {
        ScrollView {
            EvalsXRayTable(board: board).frame(maxWidth: 1200, alignment: .topLeading)
        }
    }
}
