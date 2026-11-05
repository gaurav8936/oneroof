import SwiftUI
import OneRoofCore

/// LAB-2242 · E7.1 Set up a test + Running and recent (screen lane B owns this file). A sheet over any tab: open with
/// `nav.test(plan)` (pre-filled; nothing starts until Start), Esc closes. Engine: `estimate` (CONTRACT §2, per setup),
/// `run … --agent --seat [--model] [--rules off|on] --background`, `power`, `status`, `cancel`, `resume`, `run-anyway`.
/// The queue's single home (the header's Running · N opens it). Placeholder: today's Run tab (what × who × how much,
/// cost panel, queue) until rebuilt.
struct EvalsSetupSheet: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Set up a test").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Spacer()
                RoofButton("Close") { nav.sheet = nil }.help("Close (Esc)")
            }
            EvalsRunTab(board: board, nav: nav)
        }
        .padding(20)
        .frame(minWidth: 980, idealWidth: 1240, minHeight: 620, idealHeight: 840, alignment: .topLeading)
    }
}
