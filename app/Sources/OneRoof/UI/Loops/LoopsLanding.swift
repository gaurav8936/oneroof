import AppKit
import SwiftUI
import OneRoofCore

// LAB-2286 · 7a Landing · kinds as lanes (handover 01-7a.png, pages/7a-landing): the state pills and This week line,
// one lane per kind (kind · on/all · bar · blurb | the loops that are on, their last runs, last · next · by | For you),
// and the footnote. Real data: LoopBoard.rows (the kit's on/off and mode, ledger runs, missed runs) and the Needs you
// items (LoopInboxState). Buttons do the real action or open where it is done; Set kind is not connected yet and says so.

struct LoopsLanding: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    @ObservedObject private var inbox = LoopInboxState.shared
    let actions: LoopsV7Actions
    /// A write the owner confirms first (Run now, Turn on): what it runs is said before it runs.
    @State private var confirm: LoopsV7.AskAction?

    var body: some View {
        let rows = board.rows
        let items = inbox.items
        let lanes = LoopsV7.lanes(rows: rows, items: items, pinned: Set(board.loops.filter(\.pinned).map(\.id)),
                                  setupMissing: Set(board.setup.compactMap { k, v in v == .ready ? nil : k }), kitKnown: board.kitKnown)
        VStack(alignment: .leading, spacing: 16) {
            pills(LoopsV7.statusCounts(rows: rows, items: items))
            LoopCard(padding: 0, shadow: false) {
                VStack(spacing: 0) {
                    headerRow
                    ForEach(Array(lanes.enumerated()), id: \.element.id) { i, lane in
                        if i > 0 { Rectangle().fill(t.separator.color).frame(height: 1) }
                        LoopLaneRow(lane: lane, kitKnown: board.kitKnown, nav: nav, actions: actions, ask: perform)
                    }
                }
            }
            Text("kit = the Agentic Engineering kit (ae, on launchd) · One Roof = roofd · shadow = trial runs that say what they would do, nothing acts")
                .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
        .alert(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }), presenting: confirm) { a in
            Button(confirmButton(a)) { run(a); confirm = nil }
            Button("Cancel", role: .cancel) { confirm = nil }
        } message: { a in
            Text(confirmMessage(a))
        }
    }

    // MARK: Pills and the week line

    private func pills(_ c: LoopsV7.StatusCounts) -> some View {
        HStack(spacing: 8) {
            if c.failing > 0 {
                pill("● \(c.failing) failing", .failing, help: "Open the first failing loop") { if let id = c.firstFailing { actions.openLoop(id) } }
            }
            let est = LoopsV7.estimateLabel(c.estimateSeconds)
            pill("\(c.needYou) need\(c.needYou == 1 ? "s" : "") you" + (est.isEmpty ? "" : " · " + est) + " ›", .needsYou,
                 help: "Every decision the loops wait for: one per PR, proposal, report, question, failure or loop with missed runs. The minutes are an estimate: 5 min per PR, 1 min per proposal, 30 s per report or other item.") {
                nav.open(.needsYou(loop: nil, item: nil))
            }
            if c.running > 0 {
                pill("● \(c.running) running", .running, help: "The runs and their rounds") { nav.open(.runs) }
            }
            pill("\(c.fine) fine", .fine, help: "Loops that are on and whose last run passed", action: nil)
            Button { nav.setRoot(.thisWeek) } label: {
                Text(LoopsV7.weekLine(runs: board.weekRuns) + " ›").ui(13).foregroundStyle(t.text.color).lineLimit(1)
            }
            .buttonStyle(.plain).padding(.leading, 6)
            .help("This week: every loop's runs, results and what they made")
            Spacer(minLength: 0)
        }
    }

    private func pill(_ text: String, _ tone: LoopLook.Tone, help: String, action: (() -> Void)?) -> some View {
        let p = LoopLook.tone(tone, theme: t.name)
        let label = Text(text).ui(12.5, .semibold).foregroundStyle(p.text.color).lineLimit(1).fixedSize()
            .padding(.vertical, 4).padding(.horizontal, 11)
            .background(Capsule().fill(p.fill.color))
        return Group {
            if let action {
                Button(action: action) { label }.buttonStyle(PressStyle(radius: 12)).accessibilityLabel(text.replacingOccurrences(of: "●", with: ""))
            } else {
                label.accessibilityLabel(text)
            }
        }
        .help(help)
    }

    private var headerRow: some View {
        HStack(spacing: 0) {
            MicroLabel("Kind · On / All").frame(width: LoopLaneRow.kindWidth, alignment: .leading)
            MicroLabel("On now · Last runs · Next").frame(maxWidth: .infinity, alignment: .leading)
            MicroLabel("For you").frame(width: LoopLaneRow.forYouWidth, alignment: .leading)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous).fill(t.surface2.color))
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }

    // MARK: Actions

    private func perform(_ a: LoopsV7.AskAction) {
        switch a {
        case .runNow, .turnOn: confirm = a
        case .setUp(let id), .open(let id): actions.openLoop(id)   // the pop-out has the setup box (Open config) and every control
        case .review(let loop, let item): nav.open(.needsYou(loop: loop, item: item))
        case .kind(let f): nav.open(.kind(f))
        case .setKind: break   // not connected yet (LP-2): the button says so
        }
    }

    private func name(_ id: String) -> String { board.row(id)?.name ?? id }
    private func isKit(_ id: String) -> Bool { board.row(id)?.engine == .kit }

    private var confirmTitle: String {
        switch confirm {
        case .runNow(let id)?: return "Run \(name(id)) now?"
        case .turnOn(let id)?: return "Turn on \(name(id))?"
        default: return ""
        }
    }

    private func confirmButton(_ a: LoopsV7.AskAction) -> String {
        if case .turnOn = a { return "Turn on, in trial" }
        return "Run now"
    }

    private func confirmMessage(_ a: LoopsV7.AskAction) -> String {
        switch a {
        case .runNow(let id):
            return isKit(id)
                ? "The kit runs it once now, as its schedule would (`\(KitLoops.command("run", id).dropFirst().joined(separator: " "))`). A loop in trial only writes what it would do. Nothing is pushed or merged."
                : "One Roof starts a run within 30 s: the check first, then rounds in the loop's own worktree. Nothing is pushed or merged."
        case .turnOn(let id):
            return isKit(id)
                ? "The kit turns it on (`\(KitLoops.command("on", id).dropFirst().joined(separator: " "))`): it adds the loop to its config and its launchd schedule, and starts with trial nights that only say what they would do. It asks before going live."
                : "One Roof resumes it; roofd runs it on its schedule."
        default: return ""
        }
    }

    private func run(_ a: LoopsV7.AskAction) {
        switch a {
        case .runNow(let id):
            board.runNowAny(id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() }
        case .turnOn(let id):
            if isKit(id) { board.turnOnKit(id) } else { board.resume(id) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() }
        default: break
        }
    }
}

// MARK: - A lane

struct LoopLaneRow: View {
    @Environment(\.theme) private var t
    static let kindWidth: CGFloat = 190, forYouWidth: CGFloat = 300
    let lane: LoopsV7.Lane
    let kitKnown: Bool
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    var ask: (LoopsV7.AskAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            kindCell.frame(width: Self.kindWidth, alignment: .topLeading).padding(.trailing, 14)
            onNow.frame(maxWidth: .infinity, alignment: .topLeading)
            forYou.frame(width: Self.forYouWidth, alignment: .topLeading).padding(.leading, 14)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(lane.family.title), \(lane.on) of \(lane.all) on")
    }

    private var kindCell: some View {
        let k = LoopLook.kind(lane.family.id, theme: t.name)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { nav.open(.kind(lane.family.id)) } label: {
                    Text(lane.family.title + " ›").ui(17, .semibold).foregroundStyle(k.text.color)
                }
                .buttonStyle(.plain)
                .help("Every \(lane.family.title) loop, on and off")
                .accessibilityLabel("Open \(lane.family.title)")
                Text("\(lane.on) / \(lane.all)").ui(16, .semibold).foregroundStyle(t.text.color)
                    .accessibilityLabel("\(lane.on) of \(lane.all) on")
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(t.surface2.color)
                    Capsule().fill(k.text.color).frame(width: lane.all == 0 ? 0 : g.size.width * CGFloat(lane.on) / CGFloat(lane.all))
                }
            }
            .frame(height: 6).frame(maxWidth: 190)
            .accessibilityHidden(true)
            Text(lane.blurb).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var onNow: some View {
        if lane.rows.isEmpty {
            Text(lane.all == 0 ? "No loops of this kind yet." : kitKnown || lane.family.id == "other" ? "None on." : "None on that One Roof knows of (kit state unknown).")
                .ui(12.5).foregroundStyle(t.text2.color).padding(.top, 3)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lane.rows) { r in LoopLine(row: r, kitKnown: kitKnown, open: { actions.openLoop(r.id) }) }
            }
        }
    }

    private var forYou: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(lane.asks) { a in askLine(a, muted: false) }
            ForEach(lane.gaps) { a in askLine(a, muted: true) }
            if lane.asks.isEmpty && lane.gaps.isEmpty {
                Text("Nothing for you.").ui(12.5).foregroundStyle(t.text3.color)
            }
        }
    }

    @ViewBuilder private func askLine(_ a: LoopsV7.Ask, muted: Bool) -> some View {
        if case .kind = a.action {
            // The rest of the kind's off loops: a link to its page.
            Button { ask(a.action) } label: { Text(a.button).ui(12, .medium).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain).help("Every \(lane.family.title) loop, on and off")
        } else {
            askRow(a, muted: muted)
        }
    }

    private func askRow(_ a: LoopsV7.Ask, muted: Bool) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(a.text).ui(12.5).foregroundStyle((muted ? t.text2 : t.text).color)
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .help(a.detail.isEmpty ? a.text : a.text + ". Its goal: " + a.detail)
            if case .setKind = a.action {
                LoopButton(a.button, reason: "Not connected yet: Set kind will write `kind:` to each loop's file (LP-2, with the Library)") {}
            } else {
                LoopButton(a.button, a.primary ? .primary : .secondary) { ask(a.action) }
            }
        }
    }
}

// MARK: - A loop's line (7a, 7b, filtered lists)

/// dot · name · short line · last-runs strip · "last · next · by".
struct LoopLine: View {
    @Environment(\.theme) private var t
    let row: LoopRow
    let kitKnown: Bool
    var showKind = false
    var open: () -> Void

    var body: some View {
        let lnb = LoopsV7.lastNextBy(row, kitKnown: kitKnown)
        let sub = LoopsV7.subLine(row)
        Button(action: open) {
            HStack(spacing: 10) {
                Circle().fill(dotColour.color).frame(width: 8, height: 8).accessibilityHidden(true)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1).layoutPriority(1)
                    if !sub.isEmpty { Text(sub).ui(12).foregroundStyle(t.text2.color).lineLimit(1) }
                    if showKind {
                        let k = LoopLook.kind(row.family, theme: t.name)
                        Text(LoopKinds.family(row.family)?.title ?? row.family).ui(10.5, .semibold).foregroundStyle(k.text.color)
                            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(k.fill.color))
                        LoopStateWords(row: row, kitKnown: kitKnown)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                LoopRunStrip(results: row.strip).frame(width: 100, alignment: .leading)
                Text(lnb.text).ui(12).foregroundStyle(toneColour(lnb.tone).color).lineLimit(1)
                    .frame(width: 190, alignment: .leading)
            }
            .padding(.vertical, 1.5).padding(.horizontal, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .hoverHighlight(radius: Radius.row)
        .help(row.goal.isEmpty ? row.name : row.goal)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.name), \(LoopLook.onLabel(row, kitKnown: kitKnown) ?? row.state.rawValue), \(sub), \(lnb.text)")
        .accessibilityHint("Opens the loop")
    }

    private var dotColour: RGB {
        if row.engine == .kit && !kitKnown { return t.text3 }
        return LoopLook.dot(row.state, theme: t.name)
    }

    private func toneColour(_ tone: LoopsV7.Tone) -> RGB {
        switch tone {
        case .failed: return t.needsText
        case .missed: return LoopLook.tone(.needsYou, theme: t.name).text
        case .normal: return t.text2
        }
    }
}

/// "On · live" / "On · trial" / "Off" / "kit state unknown" as a small chip.
struct LoopStateWords: View {
    @Environment(\.theme) private var t
    let row: LoopRow
    let kitKnown: Bool
    var body: some View {
        let words = LoopLook.onLabel(row, kitKnown: kitKnown) ?? "On · live"
        let p = LoopLook.tone(LoopLook.onTone(row, kitKnown: kitKnown), theme: t.name)
        Text(words).ui(10.5, .semibold).foregroundStyle(p.text.color)
            .padding(.horizontal, 6).padding(.vertical, 1).background(Capsule().fill(p.fill.color)).fixedSize()
    }
}

/// The last runs, newest right (up to 14): passed green, failed red, trial grey (lower), missed dashed amber, not run
/// dashed grey, to come outlined.
struct LoopRunStrip: View {
    @Environment(\.theme) private var t
    let results: [LoopRun7.Result]
    static let height: CGFloat = 15

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(results.suffix(14).enumerated()), id: \.offset) { _, r in
                let m = LoopLook.strip(r, theme: t.name)
                let shape = RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                ZStack {
                    if let f = m.fill { shape.fill(f.color) }
                    switch m.edge {
                    case .dashed(let c): shape.strokeBorder(c.color, style: StrokeStyle(lineWidth: 1, dash: [2, 1.5]))
                    case .solid(let c): shape.strokeBorder(c.color, lineWidth: 1)
                    default: EmptyView()
                    }
                }
                .frame(width: 5, height: Self.height * m.height)
            }
        }
        .frame(height: Self.height, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.words(results))
    }

    static func words(_ rs: [LoopRun7.Result]) -> String {
        guard !rs.isEmpty else { return "No runs yet" }
        let c = Dictionary(grouping: rs.suffix(14), by: { $0 }).mapValues(\.count)
        let parts: [(LoopRun7.Result, String)] = [(.passed, "passed"), (.failed, "failed"), (.trial, "trial"), (.missed, "missed"), (.notRun, "not run")]
        return "Last runs: " + parts.compactMap { k, w in c[k].map { "\($0) \(w)" } }.joined(separator: ", ")
    }
}
