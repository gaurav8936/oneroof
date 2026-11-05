import SwiftUI
import OneRoofCore

/// LAB-2242 · E5.1 Our tasks (screen lane B owns this file): task cards (plain name, engine name + version, bug count,
/// layer coverage), graders, + New task. Engine: `evalset list` (board.sets), `judge list` (board.judges); open one with
/// `nav.openTask(name)` / `nav.openGrader(name)`; "+ New ▾" arrives as `nav.newRequest`.
/// Placeholder: today's Your evals tab (sets, set page, build next version, versions, judges) until rebuilt.
struct EvalsTasksView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav

    var body: some View {
        EvalsYourEvalsTab(board: board, nav: nav)
    }
}
