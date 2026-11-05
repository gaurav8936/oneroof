import SwiftUI
import OneRoofCore

/// LAB-2242 · E5.3 Check the grader (screen lane B owns this file): trust tiles, label queue (P/F/S, Why, ⌘Z), rubric,
/// agreement, versions. Route `.grader(name:first:)`; name nil = the first grader. Engine: `judge show|queue|label|
/// agreement|trust|rubric|versions|build`. Placeholder: today's judge page until rebuilt.
struct EvalsGraderView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let name: String?
    var first: String?
    @Environment(\.theme) private var t

    var body: some View {
        if let n = name ?? board.judges.first?.name {
            EvalsJudgePage(board: board, nav: nav, name: n, first: first)
        } else {
            Text(board.judges.isEmpty ? "No grader yet: make one from Our tasks › + New grader." : "Reading your graders…")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }
}
