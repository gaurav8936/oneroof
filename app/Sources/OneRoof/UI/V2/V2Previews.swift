import SwiftUI
import OneRoofCore

#Preview("A1.1 Sessions + terminal") {
    @Previewable @State var step: FocusStep = .sessions
    @Previewable @State var place: Place = .sessions
    let k = V2Planes(look: .skyStudio)
    return V2Shell(step: $step, place: $place, tokens: k, rows: V2SessionRow.samples, selected: "1", dock: .sample,
                   window: .init(id: "w1", name: "Blogs & Public Presence", color: Color(.systemYellow), count: 16, state: "1 working"),
                   onSelect: { _ in }, onNewSession: {}, onSearch: {}, onLook: {}) {
        TerminalCard(summary: .init(asked: "Anchor in LAB-AGENTIC, then complete the repo with all the skills.", askedAt: "5:10 PM", rightNow: "Checking the bundled deck",
                                    steps: [.init(id: 1, title: "Start", done: true, calls: 2, age: "20h", summary: "Launched"), .init(id: 2, title: "Verify the deck", done: false, calls: 0, age: "", summary: "")], agent: "Claude1", ticket: "LAB-AGENTIC"),
                     tokens: k) { Color.black.opacity(0.0) }.padding(10)
    } inspector: { Text("Plan") }
    .frame(width: 1440, height: 900)
}

#Preview("A10.3 Looks") { @Previewable @State var look: Look = .skyStudio; return LooksPicker(look: $look, onCustomize: {}) }
