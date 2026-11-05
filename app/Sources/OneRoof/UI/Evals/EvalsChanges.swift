import SwiftUI
import OneRoofCore

/// LAB-2242 · E3.1 Changes: did my last change help? (screen lane A owns this file). Engine: `board.changes(repo:days:)`
/// (CONTRACT §5 → [EvalChange]); before/after via `compare`; re-test via `nav.test(plan)`. Real data only: an empty
/// list is a valid answer (no sample rows ship). Placeholder: the raw list + 2.0.3's "what changed since last time".
struct EvalsChangesView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var changes: [EvalChange]?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Did my last change help?").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                if let e = error {
                    Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled)
                } else if let c = changes {
                    if c.isEmpty {
                        Text("No changes to your rules, skills or agents in the last 60 days.").ui(TypeScale.body).foregroundStyle(t.text2.color)
                    }
                    ForEach(c) { ch in
                        HStack(spacing: 10) {
                            Text(String(ch.at.prefix(10))).ui(TypeScale.small, mono: true).foregroundStyle(t.text3.color)
                            Text(ch.who == .you ? "You" : "Vendor").ui(TypeScale.caption, .semibold).foregroundStyle(t.text2.color)
                            Text(ch.what).ui(TypeScale.body).foregroundStyle(t.text.color)
                            Spacer()
                            Text(ch.testedBoth ? "tested before and after" : "not tested yet").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        }
                    }
                } else {
                    Text("Reading changes…").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
                if let o = board.overview, !o.changes.isEmpty {
                    Text("Since your last tests").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color).padding(.top, 8)
                    ForEach(o.changes) { c in
                        Button { nav.openRun(c.runs[0]) } label: {
                            Text(c.text).ui(TypeScale.body).foregroundStyle(c.isNoise ? t.text2.color : t.text.color)
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
        }
        .onAppear {
            board.changes { r in
                switch r { case .success(let c): changes = c; error = nil; case .failure(let e): error = e.message }
            }
        }
    }
}
