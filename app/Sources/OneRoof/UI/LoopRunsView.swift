import SwiftUI
import OneRoofCore

/// LAB-1933 · loop rounds are not sessions: they never show in the session rail, Needs you or the counts. This is where
/// they are, on the Loops page: every round session (newest first), live ones on top, each opening its terminal.
/// Minimal entry point; the full loops dashboard (LAB-1918) builds on it.
struct LoopRunsView: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    /// How many ended rounds to show under the live ones.
    var recent = 5

    /// Round sessions with their loop's name, live first, then newest first.
    static func runs(_ items: [BoardItem], names: [String: String]) -> [(BoardItem, String)] {
        items.compactMap { i -> (BoardItem, String)? in
            guard let id = SessionScope.loopId(i.session.tags) else { return nil }
            return (i, names[id] ?? id)
        }
        .sorted { a, b in
            let la = a.0.liveAgent != nil, lb = b.0.liveAgent != nil
            if la != lb { return la }
            return a.0.session.createdAt > b.0.session.createdAt
        }
    }

    var body: some View {
        let names = Dictionary(board.loops.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let all = Self.runs(model.items, names: names)
        let live = all.filter { $0.0.liveAgent != nil }
        let shown = live + all.filter { $0.0.liveAgent == nil }.prefix(recent)
        if !shown.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    MicroLabel("Runs")
                    Spacer()
                    Text("\(live.count) running · \(all.count) rounds").ui(11.5, mono: true).foregroundStyle(t.text2.color)
                }
                ForEach(shown, id: \.0.id) { pair in row(pair.0, loop: pair.1) }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card.color))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Loop runs")
        }
    }

    private func row(_ i: BoardItem, loop: String) -> some View {
        HStack(spacing: 8) {
            AgentBadge(item: i, size: 18, status: true)
            VStack(alignment: .leading, spacing: 1) {
                Text(i.session.name).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(loop + " · " + i.status.rawValue).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
            }
            Spacer()
            RoofButton("Open ↗", .plain) { model.reveal(i) }
                .accessibilityLabel("Open the terminal of \(i.session.name)")
        }
        .padding(.vertical, 2)
    }
}
