import SwiftUI
import OneRoofCore

/// LAB-2062 · Overview, the tab Evals opens on: "how are my agents doing on my work?" without a click. One scorecard per
/// eval of yours (then benchmarks run twice or more), what changed since the last run, what is running, and one suggested
/// next eval. Everything from `roof eval overview --json`; nothing is computed here.
struct EvalsOverviewTab: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("How your agents are doing on your work").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    HStack(spacing: 6) {
                        Path { p in p.move(to: .init(x: 0, y: 0)); p.addLine(to: .init(x: 0, y: 10)) }
                            .stroke(t.text2.color, style: StrokeStyle(lineWidth: 1.2, dash: [2, 2])).frame(width: 2, height: 10)
                        Text("dashed line = no-model floor").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    }
                }
                if let o = board.overview {
                    if o.evals.isEmpty { firstEval } else {
                        ForEach(o.evals) { c in EvalsScorecard(card: c, nav: nav) }
                    }
                    EvalsColumns(breakpoint: 900, side: 360) {
                        changes(o)
                    } aside: {
                        VStack(alignment: .leading, spacing: 16) { running(o); suggestion(o) }
                    }
                } else if let e = board.overviewError {
                    Card(padding: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("The overview could not be read").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                            Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled)
                            RoofButton("Try again") { board.refreshOverview() }
                        }
                    }
                } else {
                    skeleton
                }
            }
            .frame(maxWidth: 1240, alignment: .leading)
            .padding(.bottom, 20)
        }
    }

    private var skeleton: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Reading…").ui(TypeScale.small).foregroundStyle(t.text3.color)
            ForEach(0..<4, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.control.color).frame(height: 22)
            }
        }
        .accessibilityLabel("Reading the overview")
    }

    /// An empty profile: the free invitation, no numbers.
    private var firstEval: some View {
        Card(padding: 16) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No results yet.").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text("Your first eval is free: 5 GSM8K questions on the stand-in model, which costs nothing.")
                        .ui(TypeScale.body).foregroundStyle(t.text2.color)
                }
                Spacer()
                RoofButton("Your first eval, free ›", .primary) {
                    nav.run(EvalRunPlan(tasks: ["gsm8k"], models: ["mockllm/model"], limit: 5, cap: 0))
                }
            }
        }
    }

    private func changes(_ o: EvalOverview) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                EvalsLabel("What changed since last time")
                if o.changes.isEmpty {
                    Text("Nothing to compare yet: a contestant needs two runs on the same eval.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
                ForEach(o.changes) { c in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(c.isNoise || c.delta >= 0 ? "●" : "▾").ui(TypeScale.caption)
                            .foregroundStyle(c.isNoise ? t.text3.color : (c.delta < 0 ? t.needsText.color : t.diffAddText.color))
                        Button { nav.openRun(c.runs[0]) } label: {
                            Text(c.text).ui(TypeScale.body).foregroundStyle(c.isNoise ? t.text2.color : t.text.color)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .help(String(format: "Paired difference %+.0f points, 95 %% range %+.0f to %+.0f · open the newer run",
                                     c.delta * 100, c.ci95[0] * 100, c.ci95[1] * 100))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func running(_ o: EvalOverview) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                EvalsLabel("Running now")
                if o.running.isEmpty {
                    Text("Nothing running.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
                ForEach(o.running) { r in
                    HStack(spacing: 8) {
                        Text("\(r.task ?? "?") × \(r.contestant ?? r.model ?? "?")").ui(TypeScale.small, .medium).foregroundStyle(t.text.color).lineLimit(1)
                        Spacer()
                        Text(r.progress).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                        Button("Cancel") { board.cancel(r.id) }.buttonStyle(.plain).foregroundStyle(t.accentText.color)
                            .font(.system(size: TypeScale.caption))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func suggestion(_ o: EvalOverview) -> some View {
        if let s = o.suggestion {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    EvalsLabel("Suggested next")
                    Button { follow(s) } label: {
                        Text(s.text + " ›").ui(TypeScale.body, .semibold).foregroundStyle(t.accentText.color)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func follow(_ s: EvalOverview.Suggestion) {
        let tg = s.target
        switch tg.tab {
        case "your-evals":
            if let j = tg.judge { nav.tab = .yourEvals; nav.route = .judge(name: j, first: nil) }
            else { nav.set = tg.set; nav.openBuild = tg.set != nil; nav.go(.yourEvals) }
        case "run": nav.run(EvalRunPlan(tasks: [tg.task ?? "gsm8k"], models: [], limit: tg.limit ?? 20, epochs: tg.epochs))
        case "learn": nav.go(.learn)
        default: break
        }
    }
}

/// One eval's scorecard: contestants (agents first), score, the 95 % range with the floor, cost, $ per right, run date.
struct EvalsScorecard: View {
    let card: EvalOverview.Card
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @FocusState private var focused: Bool
    @State private var row = 0

    var body: some View {
        let rows = Array(card.rows.prefix(6))
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Button { nav.go(.results) } label: {
                        Text(card.header).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    }
                    .buttonStyle(.plain).help("All results for this eval")
                    if let f = card.floor, let r = f.right, let of = f.of {
                        Text("floor \(r) of \(of)").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                            .evalHover(.floor, EvalHover.floor(share: nil, right: r, of: of))
                    }
                    Spacer()
                    Button { nav.go(.results) } label: { Text("All results ›").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain)
                }
                VStack(alignment: .leading, spacing: 6) {
                    row(cells: ["Contestant", "Kind", "Score", "95 % range", "Cost", "$ / right", "Run"].map { AnyView(EvalsLabel($0)) })
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        row(cells: [
                            AnyView(Text(r.contestant).ui(TypeScale.small, mono: r.kind != .agent).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)),
                            AnyView(EvalsKindTag(kind: r.kind)),
                            AnyView(Text(r.ciMethod == "wilson" || r.ciMethod == nil ? evalsPct(r.score) : String(format: "%.3f", r.score ?? 0))
                                .ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color)
                                .evalHover(.score, EvalHover.score(score: r.score ?? 0, n: r.n))),
                            AnyView(EvalsRangeBar(value: r.score ?? 0, lo: r.ci95?.first, hi: r.ci95?.last, floor: card.floorShare)
                                .evalHover(.range, EvalsHoverText.range(r))),
                            AnyView(Text(r.costText).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                                .evalHover(.cost, EvalHover.cost(r.costText))),
                            AnyView(Text(r.usdPerRight.map { String(format: "$%.4f", $0) } ?? "–").ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                                .evalHoverIf(r.usdPerRight.map { (.costPerRight, EvalHover.costPerRight($0)) })),
                            AnyView(Button { nav.openRun(r.run) } label: {
                                Text(EvalModels.when(r.date)).ui(TypeScale.caption, mono: true).foregroundStyle(t.accentText.color)
                            }.buttonStyle(.plain).help("Open this run"))])
                        .padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(focused && i == row ? t.selection.color : .clear).padding(.horizontal, -4))
                        .accessibilityElement(children: .combine)
                    }
                }
                if card.rows.count > 6 {
                    Text("\(card.rows.count - 6) more in Results").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
                if rows.isEmpty {
                    Text("Not run yet. Run… it from Your evals; the cost shows first.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
            }
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { row = max(row - 1, 0); return .handled }
        .onKeyPress(.downArrow) { row = min(row + 1, max(rows.count - 1, 0)); return .handled }
        .onKeyPress(.return) { if rows.indices.contains(row) { nav.openRun(rows[row].run) }; return .handled }
        .accessibilityLabel("Scorecard: " + card.header)
    }

    /// Fixed columns, the same in every card (contestant · kind · score · range · cost · $ / right · run).
    private func row(cells: [AnyView]) -> some View {
        let widths: [CGFloat?] = [230, 96, 64, nil, 70, 80, 96]
        return HStack(spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                if let w = widths[i] { c.frame(width: w, alignment: .leading) } else { c.frame(minWidth: 120, maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
}
