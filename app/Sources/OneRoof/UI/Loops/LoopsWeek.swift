import AppKit
import SwiftUI
import OneRoofCore

// LAB-2291 · 7e This week (by day) (handover 06-7e.png, pages/7e-this-week): the filter bar and ‹ › week paging, IS IT
// WORTH IT? (one sentence from the real numbers, following the filter) beside RUNS · FAILED · MISSED · SPEND, and the
// grid: each loop that is on × the seven real days (passed with a count, failed ✕, trial grey, missed dashed amber,
// still to come outlined) with row totals. A day opens Today for that day; a loop's name opens the loop. 2.0.5's
// Activity › Outcomes table (result, runs, cost, produced, staged) stays here, under the grid (NO_REGRESSION.md).

struct LoopsWeek: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    /// 0 = the seven days ending today; −1 the week before …
    @State private var offset = 0
    /// Runs of an earlier week, read from the ledger off the main thread (nil while loading).
    @State private var older: [String: [LoopRun7]]?
    @State private var showOutcomes = false

    var body: some View {
        let f = nav.filter("7e")
        let range = LoopsV7.weekRange(offset: offset)
        let runsBy = offset == 0 ? Dictionary(grouping: board.weekRuns, by: \.loop) : (older ?? [:])
        let shown = LoopsV7.filter(board.rows, f.wrappedValue)
        let grid = LoopsV7.weekRows(shown)
        let cells = Dictionary(grid.map { r in
            (r.id, LoopsV7.weekCells(row: r, runs: runsBy[r.id] ?? [], cron: board.crons[r.id], start: range.start))
        }, uniquingKeysWith: { a, _ in a })
        let weekRuns = shown.flatMap { r in (runsBy[r.id] ?? []).filter { $0.started >= range.start && $0.started < range.end } }
        let ids = Set(shown.map(\.id))
        let staged = board.outcomesByLoop.filter { ids.contains($0.key) }.values.joined().filter { $0.status == "staged" }.count
        let sum = LoopsV7.weekSummary(rows: shown, runs: weekRuns, cells: cells, staged: staged)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    LoopFilterBar(filter: f)
                    Spacer(minLength: 8)
                    weekPager(range)
                }
                tiles(sum)
                LoopCard(padding: 0, shadow: false) {
                    VStack(spacing: 0) {
                        if grid.isEmpty {
                            HStack(spacing: 10) {
                                Text(f.wrappedValue.isEmpty ? "No loop is on." : LoopsV7.emptyLine(f.wrappedValue)).ui(13).foregroundStyle(t.text2.color)
                                if !f.wrappedValue.isEmpty { RoofButton("Clear", .plain) { f.wrappedValue = LoopFilter() } }
                                Spacer()
                            }
                            .padding(16)
                        } else {
                            gridHead(range.start, count: grid.count)
                            ForEach(grid) { r in gridRow(r, cells[r.id] ?? []) }
                        }
                        legend
                    }
                }
                outcomes
            }
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.top)
        .onChange(of: offset) { _, o in load(o) }
        .accessibilityLabel("Loops this week")
    }

    // MARK: Pager

    private func weekPager(_ r: (start: Date, end: Date)) -> some View {
        HStack(spacing: 4) {
            Text(LoopsV7.weekLabel(start: r.start, end: r.end)).ui(13).foregroundStyle(t.text2.color)
                .accessibilityLabel("Week " + LoopsV7.weekLabel(start: r.start, end: r.end))
            Button { offset -= 1 } label: { Text("‹").ui(16, .semibold).foregroundStyle(t.text.color).frame(width: 22, height: 22) }
                .buttonStyle(PressStyle(radius: 6)).help("The week before").accessibilityLabel("Previous week")
            Button { offset = min(0, offset + 1) } label: {
                Text("›").ui(16, .semibold).foregroundStyle((offset < 0 ? t.text : t.text3).color).frame(width: 22, height: 22)
            }
            .buttonStyle(PressStyle(radius: 6)).disabled(offset >= 0).help("The week after").accessibilityLabel("Next week")
        }
        .fixedSize()
    }

    private func load(_ o: Int) {
        guard o < 0 else { older = nil; return }
        older = nil
        let r = LoopsV7.weekRange(offset: o)
        let path = LoopLedger.defaultPath(loopsRoot: board.store.root)
        DispatchQueue.global(qos: .userInitiated).async {
            let led = try? LoopLedger(readingOnly: path)
            let runs = LoopsV7.runsByLoop(led, from: r.start.addingTimeInterval(-8 * 86400), to: r.end)
            DispatchQueue.main.async { if offset == o { older = runs } }
        }
    }

    // MARK: Tiles

    private func tiles(_ s: LoopsV7.WeekSummary) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                LoopLabel("Is it worth it?")
                Text(s.answer).ui(15, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                Text("Time saved: not recorded").ui(11.5).foregroundStyle(t.text2.color)
                    .help("The ledger records runs, results and cost, not the minutes a loop saves you, so no figure is shown.")
            }
            .padding(14).frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
            .overlay(alignment: .top) {
                UnevenRoundedRectangle(topLeadingRadius: Radius.card, topTrailingRadius: Radius.card, style: .continuous)
                    .fill((s.failed > 0 ? LoopLook.tone(.needsYou, theme: t.name).text : t.statusDone).color).frame(height: 4)
            }
            .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            tile("Runs", "\(s.runs)", s.trialRuns > 0 ? "incl. \(s.trialRuns) trial run\(s.trialRuns == 1 ? "" : "s")" + (s.offTrialRuns > 0 ? " (\(s.offTrialRuns) of off loops)" : "") : "runs", t.text)
            tile("Failed", "\(s.failed)", s.failed == 0 ? "runs" : "runs · \(s.failedLoops) loop\(s.failedLoops == 1 ? "" : "s")", s.failed > 0 ? t.needsText : t.text)
            tile("Missed", "\(s.missed)", s.missed == 0 ? "scheduled runs" : "scheduled runs · \(s.missedLoops) loop\(s.missedLoops == 1 ? "" : "s")",
                 s.missed > 0 ? LoopLook.tone(.needsYou, theme: t.name).text : t.text)
            tile("Spend", s.costRecorded ? String(format: "$%.2f", s.cost) : "—", s.costRecorded ? "API, as the ledger records it" : "not recorded", t.text)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ label: String, _ value: String, _ sub: String, _ tone: RGB) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LoopLabel(label)
            Text(value).ui(24, .bold).foregroundStyle(tone.color)
            Text(sub).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14).frame(width: 190, alignment: .topLeading).frame(maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value), \(sub)")
    }

    // MARK: Grid

    static let nameWidth: CGFloat = 230, totalWidth: CGFloat = 56

    private func gridHead(_ start: Date, count: Int) -> some View {
        HStack(spacing: 4) {
            LoopLabel("Loop · \(count) on").frame(width: Self.nameWidth, alignment: .leading)
            ForEach(0..<7, id: \.self) { i in
                let d = Calendar.current.date(byAdding: .day, value: i, to: start)!
                LoopLabel(LoopsV7.dayHead(d)).frame(maxWidth: .infinity)
            }
            LoopLabel("Runs").frame(width: Self.totalWidth, alignment: .trailing)
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 6)
    }

    private func gridRow(_ r: LoopRow, _ cells: [LoopsV7.DayCell]) -> some View {
        let total = cells.reduce(0) { $0 + LoopsV7.ran($1) }
        return VStack(spacing: 0) {
            Rectangle().fill(t.separator.color).frame(height: 1)
            HStack(spacing: 4) {
                Button { actions.openLoop(r.id) } label: {
                    HStack(spacing: 7) {
                        LoopKindTag(family: r.family)
                        Text(r.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        if r.mode == .shadow { Text("trial").ui(10.5).foregroundStyle(t.text2.color) }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).frame(width: Self.nameWidth, alignment: .leading)
                .help((r.engine == .kit ? "Run by the kit" : "Run by One Roof") + " · " + r.schedule + ". Opens the loop.")
                .accessibilityLabel("\(r.name), \(r.engine == .kit ? "run by the kit" : "run by One Roof"). Opens the loop")
                ForEach(Array(cells.enumerated()), id: \.offset) { _, c in
                    LoopWeekCell(cell: c) { nav.open(.day(c.day, loop: r.id)) }
                }
                Text("\(total)").ui(13, .semibold).foregroundStyle(t.text.color).frame(width: Self.totalWidth, alignment: .trailing)
                    .accessibilityLabel("\(total) runs this week")
            }
            .padding(.horizontal, 16).padding(.vertical, 4)
        }
    }

    private var legend: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.separator.color).frame(height: 1)
            HStack(spacing: 16) {
                legendItem(.passed, "passed (count)")
                legendItem(.failed, "failed")
                legendItem(.trial, "trial")
                legendItem(.missed, "missed")
                legendItem(.toCome, "still to come")
                Spacer()
                Text("Click a day to open Today for that day").ui(12).foregroundStyle(t.text2.color)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    private func legendItem(_ r: LoopRun7.Result, _ s: String) -> some View {
        HStack(spacing: 6) {
            LoopWeekSwatch(result: r).frame(width: 16, height: 10)
            Text(s).ui(12).foregroundStyle(t.text2.color)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Outcomes (2.0.5's table, kept)

    @ViewBuilder private var outcomes: some View {
        if !board.outcomes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Button { showOutcomes.toggle() } label: {
                    Text((showOutcomes ? "▾ " : "▸ ") + "Outcomes per loop: result, runs, cost, what each produced and what is staged")
                        .ui(12.5, .semibold).foregroundStyle(t.accentText.color)
                }
                .buttonStyle(.plain)
                .help("2.0.5's Outcomes table, from the outcome ledger (all time). Staged items wait in Needs you.")
                if showOutcomes {
                    LoopOutcomesCard(rows: board.outcomes, setup: board.setup) { actions.openLoop($0) }
                }
            }
        }
    }
}

/// One day of one loop: passed green with a count, failed red ✕, trial grey, missed dashed amber, to come outlined.
struct LoopWeekCell: View {
    @Environment(\.theme) private var t
    let cell: LoopsV7.DayCell
    var open: () -> Void

    var main: LoopRun7.Result? {
        if cell.failed > 0 { return .failed }
        if cell.passed > 0 { return .passed }
        if cell.trial > 0 { return .trial }
        if cell.missed > 0 { return .missed }
        if cell.toCome > 0 { return .toCome }
        return nil
    }

    var body: some View {
        Button(action: open) {
            ZStack {
                if let m = main {
                    LoopWeekSwatch(result: m)
                    label(m)
                }
            }
            .frame(maxWidth: .infinity).frame(height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: 5))
        .help(words)
        .accessibilityLabel(LoopsV7.dayTitle(cell.day) + ": " + words)
        .accessibilityHint("Opens Today for that day")
    }

    @ViewBuilder private func label(_ m: LoopRun7.Result) -> some View {
        switch m {
        case .failed:
            Text(cell.failed > 1 ? "✕ \(cell.failed)" : "✕").ui(11.5, .semibold).foregroundStyle(LoopLook.tone(.failing, theme: t.name).text.color)
        case .passed where cell.passed > 1:
            Text("\(cell.passed)").ui(11.5, .semibold).foregroundStyle(LoopLook.tone(.fine, theme: t.name).text.color)
        default: EmptyView()
        }
    }

    private var words: String {
        var p: [String] = []
        if cell.passed > 0 { p.append("\(cell.passed) passed") }
        if cell.failed > 0 { p.append("\(cell.failed) failed") }
        if cell.trial > 0 { p.append("\(cell.trial) trial") }
        if cell.missed > 0 { p.append("\(cell.missed) missed") }
        if cell.toCome > 0 { p.append("\(cell.toCome) still to come") }
        return p.isEmpty ? "no run" : p.joined(separator: ", ")
    }
}

/// The fill and edge of a This week cell (and its legend).
struct LoopWeekSwatch: View {
    @Environment(\.theme) private var t
    let result: LoopRun7.Result
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 5, style: .continuous)
        switch result {
        case .passed: shape.fill(LoopLook.tone(.fine, theme: t.name).fill.color)
            .overlay(shape.strokeBorder(LoopLook.tone(.fine, theme: t.name).text.color.opacity(0.35), lineWidth: 1))
        case .failed: shape.fill(LoopLook.tone(.failing, theme: t.name).fill.color)
            .overlay(shape.strokeBorder(LoopLook.tone(.failing, theme: t.name).text.color.opacity(0.35), lineWidth: 1))
        case .trial: shape.fill(LoopLook.tone(.off, theme: t.name).fill.color)
        case .missed: shape.strokeBorder(LoopLook.tone(.needsYou, theme: t.name).text.color, style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
        case .toCome, .notRun: shape.strokeBorder(t.separatorStrong.color, lineWidth: 1)
        }
    }
}

/// A loop's kind as a small coloured tag (Watch, Check, Improve, Report, Other).
struct LoopKindTag: View {
    @Environment(\.theme) private var t
    let family: String
    var body: some View {
        let k = LoopLook.kind(family, theme: t.name)
        Text(LoopKinds.family(family)?.title ?? family).ui(10.5, .semibold).foregroundStyle(k.text.color)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(k.fill.color))
            .fixedSize()
    }
}
