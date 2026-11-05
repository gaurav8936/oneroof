import SwiftUI
import OneRoofCore

/// LAB-2242 · E5.2 One task: bugs, solved by, next version, versions (screen lane B owns this file). Route
/// `.oneTask(name:version:)`; name nil = the first set. Engine: `evalset show <name> [--version N]` (EvalSetDetail, with
/// the floor, EV-5), `evalset versions`, `evalset build --dry-run` / `build`.
/// Placeholder: today's Your evals page on that set until rebuilt.
struct EvalsTaskDetailView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let name: String?
    var version: Int?

    var body: some View {
        EvalsYourEvalsTab(board: board, nav: nav)
            .padding(.horizontal, 24).padding(.bottom, 24)
            .onAppear { if let name, nav.set != name { nav.set = name } }
    }
}
