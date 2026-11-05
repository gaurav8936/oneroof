import SwiftUI
import OneRoofCore

/// LAB-2242 · E2.3 All results (screen lane A owns this file): model × task grid (dashed under 30, own tasks marked),
/// every run, Export CSV · JSON. Engine: `board.results` (`results`), `board.export(format:)`.
/// Placeholder: today's All × all (matrix + every run) until rebuilt.
struct EvalsAllResultsView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    RoofButton("Export CSV") { board.export(format: "csv") }
                    RoofButton("Export JSON") { board.export(format: "json") }
                }
                EvalsAllByAll(board: board, nav: nav)
            }
            .frame(maxWidth: 1340, alignment: .topLeading)
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }
}
