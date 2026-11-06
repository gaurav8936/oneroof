import SwiftUI
import OneRoofCore

/// LAB-2242 · E2.3 All results: for when you want everything at once (Compare stays the simple view). The latest finished
/// result per (who answered, task) — our tasks first, in blue, then public benchmarks; a grader column is agreement with
/// your labels, not a score; dashed under 30 answers — then every test, newest first, and Export CSV · JSON (`export`).
/// LAB-2261 (v3 E4.2): every test and every grid row carry their kind — one-shot · agent · public model · public agent.
/// The export is built by the engine (`roof eval export`), so its `kind` field is the engine's to add.
struct EvalsAllResultsView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var showAll = false

    var body: some View {
        let g = EvalsAAllGrid.build(board.results, sets: board.sets)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Latest finished result per model and task. Dashed: fewer than 30 answers, so read with care. Click a cell for that test, bug by bug.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    RoofButton("Export CSV") { board.export(format: "csv") }.help("Every test with its metrics, 95 % ranges and stamp")
                    RoofButton("Export JSON") { board.export(format: "json") }
                }
                if g.rows.isEmpty {
                    EvalsAEmpty(title: "No finished test yet", detail: "Every finished test shows here, one cell per setup and task.",
                                action: ("Set up a test", { nav.test(nil) }))
                } else {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            // QA m6: the last column was cut off with no cue; the bar always shows, and it says so
                            ScrollView(.horizontal, showsIndicators: true) { grid(g).padding(.trailing, 12).padding(.bottom, 12) }
                                .scrollIndicators(.visible, axes: .horizontal)
                            if g.columns.count > 6 {
                                Text("\(g.columns.count) columns: scroll sideways for all of them.").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                            }
                            Text("Blue columns are our tasks; the rest are public. A grader column shows how often the grader agrees with your labels, not a score.")
                                .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                        }
                    }
                }
                everyRun(g)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)   // LAB-2273: flexes with the window
            .padding(.horizontal, 24).padding(.bottom, 24)
        }
    }

    private func grid(_ g: EvalsAAllGrid) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
            GridRow {
                Text("").frame(width: 250)
                Text("Kind").ui(TypeScale.caption, .semibold).foregroundStyle(t.text2.color).frame(width: 92, alignment: .leading)
                ForEach(g.columns) { c in
                    Text(c.title).ui(TypeScale.caption, .semibold).foregroundStyle(c.own ? t.accentText.color : t.text2.color)
                        .lineLimit(2).multilineTextAlignment(.center).frame(width: 118, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(c.own ? t.accent.color.opacity(0.12) : .clear))
                        .help(c.key)
                }
            }
            ForEach(g.rows, id: \.self) { row in
                GridRow {
                    Text(row).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).frame(width: 250, alignment: .leading).lineLimit(1).truncationMode(.middle)
                    kindMark(EvalResultKind.row(Array((g.cells[row] ?? [:]).values))).frame(width: 92, alignment: .leading)
                    ForEach(g.columns) { c in cell(g.cell(row, c.key), column: c) }
                }
            }
        }
    }

    @ViewBuilder private func cell(_ r: EvalResult?, column c: EvalsAAllGrid.Column) -> some View {
        let box = RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
        if let r, let p = r.primary, let v = p.value {
            let small = EvalStats.isSmall(p.n)
            let agree = c.grader ? r.judgeAgreement?.agreement : nil
            Button { nav.openRun(r.id) } label: {
                VStack(spacing: 2) {
                    Text(c.grader ? (agree.map { "\(evalsPct($0)) agree" } ?? "not measured") : evalFormat(v, p))
                        .ui(TypeScale.small, .bold, mono: true).foregroundStyle(t.text.color)
                    Text("n=\(c.grader ? (r.judgeAgreement?.n ?? p.n ?? 0) : (p.n ?? 0))").ui(TypeScale.micro, mono: true).foregroundStyle(t.text3.color)
                }
                .frame(width: 118, height: 40)
                .background(box.fill(c.own ? t.accent.color.opacity(0.06) : t.surface.color))
                .overlay(box.strokeBorder(small ? t.needsText.color.opacity(0.6) : t.separator.color,
                                          style: StrokeStyle(lineWidth: 1, dash: small ? [4, 3] : [])))
            }
            .buttonStyle(.plain)
            .evalHover(c.grader ? .agreement : (p.ciMethod == "wilson" ? .range : .score),
                       c.grader ? (r.judgeAgreement.map(EvalHover.agreement) ?? "Agreement with your labels: not measured yet.")
                       : (p.ciMethod == "wilson" ? EvalHover.range(score: v, n: p.n ?? 0, lo: p.ci95?.first ?? v, hi: p.ci95?.last ?? v)
                          : "\(p.label) · 95 % \(p.ci95.map { String(format: "%.3f to %.3f", $0[0], $0[1]) } ?? "n/a"). Open the test."))
        } else {
            Text("·").ui(TypeScale.small).foregroundStyle(t.text3.color).frame(width: 118, height: 40)
        }
    }

    private func everyRun(_ g: EvalsAAllGrid) -> some View {
        let runs = board.results
        let shown = showAll ? runs : Array(runs.prefix(40))
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Every test").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Text(EvalFinished.text(board.results) + " · newest first").ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
                HStack(spacing: 12) {
                    Text("When").frame(width: 96, alignment: .leading)
                    Text("Kind").frame(width: 92, alignment: .leading)
                    Text("Task · who answered").frame(maxWidth: .infinity, alignment: .leading)
                }
                .ui(TypeScale.micro, .semibold).foregroundStyle(t.text3.color)
                ForEach(shown) { r in runRow(r); Divider() }
                if runs.count > shown.count {
                    RoofButton("Show all \(runs.count)", .plain) { showAll = true }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func runRow(_ r: EvalResult) -> some View {
        HStack(spacing: 12) {
            Button { nav.openRun(r.id) } label: {
                HStack(spacing: 12) {
                    Text(EvalModels.when(r.started)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color).frame(width: 96, alignment: .leading)
                    kindMark(EvalResultKind.of(r)).frame(width: 92, alignment: .leading)
                    Text("\(title(r)) · \(EvalsAAllGrid.rowKey(r))").ui(TypeScale.small, .medium).foregroundStyle(t.text.color)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(1)
                    Text(r.status == "done" ? scoreText(r) : (r.status ?? "")).ui(TypeScale.small, mono: true)
                        .foregroundStyle(r.status == "done" ? t.text.color : t.needsText.color).frame(width: 110, alignment: .trailing)
                    if let j = r.judgeAgreement {
                        Text(j.short).ui(TypeScale.caption).foregroundStyle(j.trustworthy ? t.text2.color : t.needsText.color).lineLimit(1).frame(width: 150, alignment: .leading)
                            .evalHover(.agreement, EvalHover.agreement(j))
                    }
                    Text((r.model ?? "").hasPrefix("seat/") ? "seat" : EvalsAWords.dollars(r.cost)).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color).frame(width: 70, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            RoofButton("Open") { nav.openRun(r.id) }.help("Open this test, bug by bug")   // LAB-2255: a button, not a text link
        }
    }

    /// One-shot · agent · public model · public agent, in the job kind's tag colours (EvalsJobTag); public is outlined.
    @ViewBuilder private func kindMark(_ k: EvalResultKind?) -> some View {
        if let k {
            Text(k.title).ui(TypeScale.micro, .semibold).foregroundStyle(t.jobTag(k.jobKind).ink.color).lineLimit(1)
                .padding(.horizontal, 7).padding(.vertical, 2)
                .background(Capsule().fill(k.isPublic ? t.control.color : t.jobTag(k.jobKind).fill.color))
                .overlay(Capsule().strokeBorder(k.isPublic ? t.jobTag(k.jobKind).ink.color.opacity(0.5) : .clear))
                .help(k.isPublic ? "A public benchmark, \(k.jobKind == .agent ? "an agent using a model" : "the model answering once")"
                      : k.jobKind == .agent ? "Our task, an agent using a model" : "Our task, the model answering once")
                .accessibilityLabel("Kind: \(k.title)")
        } else {
            Text("·").ui(TypeScale.small).foregroundStyle(t.text3.color)
        }
    }

    private func title(_ r: EvalResult) -> String {
        if let s = r.setName { return (board.sets.first { $0.name == s }?.kindTitle ?? s) + " v\(r.setVersion ?? 1)" }
        return EvalBenchmark.taskLabel(r.task ?? "?")
    }

    /// "8 of 10" for a share of right answers, else the metric.
    private func scoreText(_ r: EvalResult) -> String {
        guard let p = r.primary, let v = p.value else { return "–" }
        if p.ciMethod == "wilson", let n = p.n { return "\(Int((v * Double(n)).rounded())) of \(n)" }
        return "\(p.metric) \(evalFormat(v, p))"
    }
}
