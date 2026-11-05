import SwiftUI
import OneRoofCore

/// LAB-2242 · E2.2 One test, bug by bug (screen lane A owns this file). Route `.oneTest(run:sample:only:other:)`; run nil =
/// the newest finished test. Engine: `board.caseResults(run:)` (CONTRACT §4: named / changed files per case),
/// `board.transcript`, the run's `EvalStamp`. Placeholder: today's run detail page until rebuilt.
struct EvalsOneTestView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let runID: String?
    var sample: String?
    var only: [String]?
    var other: String?
    @Environment(\.theme) private var t

    private var resolved: String? {
        if let r = runID, !r.isEmpty { return r }
        return board.results.first(where: { $0.status == "done" })?.id
    }

    var body: some View {
        if let id = resolved {
            EvalsRunDetailPage(board: board, nav: nav, runID: id, start: sample, only: only, other: other).id(id)
        } else {
            Text(board.results.isEmpty ? "Reading your tests…" : "No finished test yet.")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }
}
