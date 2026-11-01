import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2068 · Results (Claude Design 1A-6 = HP E4.1): By eval (leaderboard, compare with a plain verdict, over time) ·
/// All × all (1.9.37's matrix and every run) · X-ray (read-only table, EVO-2). Export CSV / JSON at the foot of the left
/// column. Replaces 1.9.37's Results tab and Compare card (kept behind the flag).
struct EvalsResultsV2: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        if board.results.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("No results yet.").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Button { nav.go(.run) } label: { Text("Run your first eval ›").ui(TypeScale.body).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain)
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                EvalsResultsSidebar(board: board, nav: nav).frame(width: 210)
                ScrollView {
                    Group {
                        switch nav.resultsMode {
                        case .byEval: EvalsByEval(board: board, nav: nav, key: selectedKey)
                        case .allByAll: EvalsAllByAll(board: board, nav: nav)
                        case .xray: EvalsXRayTable(board: board)
                        }
                    }
                    .frame(maxWidth: 1340, alignment: .topLeading)
                }
            }
        }
    }

    private var selectedKey: String? {
        let entries = EvalResultsEntry.from(board.results)
        if let k = nav.resultsKey, entries.contains(where: { $0.key == k }) { return k }
        return entries.first(where: { $0.runs > 0 })?.key ?? entries.first?.key
    }
}

/// The eval's name as the left column shows it: "fix locator v1", "oneroof triage judge v1", "gsm8k".
func evalsEntryTitle(_ e: EvalResultsEntry, sets: [EvalSetList.Entry]) -> String {
    if let s = e.set {
        let kind = sets.first { $0.name == s }?.kindTitle
        return "\(kind.map { sets.filter { $0.kindTitle == kind }.count > 1 ? "\(s) · \($0)" : $0 } ?? s) v\(e.version ?? 1)"
    }
    if e.task.hasPrefix("judge_") {
        let rest = e.task.dropFirst(6)
        if let r = rest.range(of: "_v", options: .backwards) {
            return rest[..<r.lowerBound].replacingOccurrences(of: "_", with: " ") + " judge v" + rest[r.upperBound...]
        }
    }
    return EvalBenchmark.taskLabel(e.task)
}

// MARK: - Left column (210 pt)

struct EvalsResultsSidebar: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        let entries = EvalResultsEntry.from(board.results)
        let selected = nav.resultsKey ?? entries.first(where: { $0.runs > 0 })?.key
        VStack(alignment: .leading, spacing: 4) {
            Segmented(options: EvalsNav.ResultsMode.allCases.map { ($0, $0.rawValue) }, selection: $nav.resultsMode)
                .padding(.bottom, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    let own = entries.filter(\.own), bench = entries.filter { !$0.own }
                    if !own.isEmpty { EvalsLabel("Your evals").padding(.bottom, 4) }
                    ForEach(own) { e in row(e, on: e.key == selected) }
                    if !bench.isEmpty { EvalsLabel("Benchmarks").padding(.top, 12).padding(.bottom, 4) }
                    ForEach(bench) { e in row(e, on: e.key == selected) }
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                RoofButton("Export CSV") { board.export(format: "csv") }
                RoofButton("JSON") { board.export(format: "json") }.help("Export every run with its metrics and 95 % ranges as JSON")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ e: EvalResultsEntry, on: Bool) -> some View {
        Button { nav.resultsMode = .byEval; nav.resultsKey = e.key } label: {
            HStack {
                Text(evalsEntryTitle(e, sets: board.sets)).ui(TypeScale.body, on ? .semibold : .regular).foregroundStyle(t.text.color)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if e.failed && e.runs == 0 { Text("failed").ui(TypeScale.small).foregroundStyle(t.needsText.color) }
                else { Text("\(e.runs)").ui(TypeScale.small, mono: true).foregroundStyle(e.failed ? t.needsText.color : t.text2.color) }
            }
            .padding(.vertical, 6).padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on && nav.resultsMode == .byEval ? t.selection.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(evalsEntryTitle(e, sets: board.sets)), \(e.runs) runs" + (e.failed ? ", latest failed" : ""))
    }
}

// MARK: - By eval: leaderboard · compare · over time

struct EvalsByEval: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let key: String?
    @Environment(\.theme) private var t
    @State private var board_: EvalLeaderboard?
    @State private var history: EvalHistory?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
            if let lb = board_ {
                if let vs = lb.versions, vs.count > 1, let set = lb.set {   // versions are never mixed: switch between them
                    HStack(spacing: 6) {
                        Text("Version").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        ForEach(vs, id: \.self) { v in
                            Button { nav.resultsKey = "\(set)@v\(v)" } label: {
                                EvalsChip(text: "v\(v)", accent: v == lb.version)
                            }.buttonStyle(.plain)
                        }
                    }
                }
                EvalsLeaderboardCard(lb: lb, board: board, nav: nav)
                EvalsColumns(breakpoint: 880, side: 440) {
                    EvalsCompareCard2(lb: lb, board: board, nav: nav)
                } aside: {
                    EvalsOverTimeCard(lb: lb, history: history, nav: nav)
                }
            } else if key != nil {
                Text("Reading…").ui(TypeScale.body).foregroundStyle(t.text2.color)
            }
        }
        .onAppear(perform: load)
        .onChange(of: key) { _, _ in board_ = nil; history = nil; load() }
        .onChange(of: board.results) { _, _ in load() }
    }

    private func load() {
        guard let k = key else { return }
        board.ask(["leaderboard", k], EvalLeaderboard.self, timeout: 300) { r in
            guard k == key else { return }
            switch r { case .success(let v): board_ = v; error = nil; case .failure(let e): error = e.message }
        }
        board.ask(["history", k], EvalHistory.self, timeout: 300) { r in
            guard k == key else { return }
            if case .success(let h) = r { history = h }
        }
    }
}

/// Leaderboard card (HP Leaderboard): # · contestant · kind · score · 0…50…100 with the 95 % range and the floor · cost ·
/// $ / right · run. Baseline unranked and last. ↑/↓ move, ↩ opens the run.
struct EvalsLeaderboardCard: View {
    let lb: EvalLeaderboard
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @FocusState private var focused: Bool
    @State private var row = 0
    private let widths: [CGFloat?] = [22, 230, 84, 58, nil, 64, 70, 64]

    var body: some View {
        let ranked = lb.ranked
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(lb.title).ui(TypeScale.section, .bold).foregroundStyle(t.text.color)
                    Text(lb.subtitle).ui(TypeScale.small).foregroundStyle(t.text2.color).lineLimit(1)
                    Spacer()
                    if let j = lb.judge {
                        Button { nav.route = .judge(name: j.name, first: nil) } label: {
                            EvalsChip(text: j.badge, accent: (j.agreement ?? 0) >= 0.7)
                        }
                        .buttonStyle(.plain)
                        .evalHover(.agreement, "\(j.badge) with your held-back labels. Open the judge to see how far to trust the judged score.")
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                line(["#", "Contestant", "Kind", "Score", "axis", "Cost", "$ / right", "Run"].map { h in
                    h == "axis" ? AnyView(axis) : AnyView(EvalsLabel(h))
                })
                .padding(.horizontal, 14).padding(.vertical, 6)
                .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                ForEach(Array(ranked.enumerated()), id: \.element.row.id) { i, x in
                    let r = x.row
                    Button { nav.openRun(r.run) } label: {
                        line([
                            AnyView(Text(x.rank.map(String.init) ?? "–").ui(TypeScale.small).foregroundStyle(t.text2.color)),
                            AnyView(name(r)),
                            AnyView(EvalsKindTag(kind: r.kind)),
                            AnyView(Text(r.ciMethod == "wilson" || r.ciMethod == nil ? evalsPct(r.score) : String(format: "%.3f", r.score ?? 0))
                                .ui(TypeScale.body, .bold).foregroundStyle(t.text.color)
                                .evalHover(.score, EvalHover.score(score: r.score ?? 0, n: r.n))),
                            AnyView(EvalsRangeBar(value: r.score ?? 0, lo: r.ci95?.first, hi: r.ci95?.last, floor: lb.floor, small: EvalStats.isSmall(r.n))
                                .evalHover(.range, EvalsHoverText.range(r))),
                            AnyView(Text(r.costText).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                                .evalHover(.cost, EvalHover.cost(r.costText))),
                            AnyView(Text(r.usdPerRight.map { String(format: "$%.3f", $0) } ?? "–").ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                                .evalHoverIf(r.usdPerRight.map { (.costPerRight, EvalHover.costPerRight($0)) })),
                            AnyView(Text(EvalsDay.short(r.date) + " ›").ui(TypeScale.small).foregroundStyle(t.accentText.color)),
                        ])
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(focused && i == row ? t.selection.color : .clear)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(x.rank.map { "Rank \($0)" } ?? "Baseline"), \(r.contestant), \(EvalContestant.tag(r.kind)), \(evalsPct(r.score))")
                }
                if lb.rows.isEmpty {
                    Text("No finished run on this version yet.").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                }
                if let f = lb.latestFailed {
                    HStack(spacing: 8) {
                        Text("Latest run failed: " + (f.error ?? "see the run")).ui(TypeScale.small).foregroundStyle(t.needsText.color).lineLimit(2)
                            .help(f.hint ?? "")
                        RoofButton("Resume", .plain) { board.resume(f.run) }
                        RoofButton("Open", .plain) { nav.openRun(f.run) }
                    }
                    .padding(14)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                }
            }
        }
        .focusable().focused($focused).focusEffectDisabled()
        .onKeyPress(.upArrow) { row = max(row - 1, 0); return .handled }
        .onKeyPress(.downArrow) { row = min(row + 1, max(ranked.count - 1, 0)); return .handled }
        .onKeyPress(.return) { if ranked.indices.contains(row) { nav.openRun(ranked[row].row.run) }; return .handled }
    }

    private var axis: some View {
        HStack(spacing: 0) {
            Text("0").frame(maxWidth: .infinity, alignment: .leading)
            Text("50").frame(maxWidth: .infinity, alignment: .center)
            Text("100").frame(maxWidth: .infinity, alignment: .trailing)
        }
        .ui(10.5, .semibold).foregroundStyle(t.text3.color)
    }

    /// "Claude Code" bold + "C1" grey; a model in mono; the baseline "mockllm/model free stand-in".
    private func name(_ r: EvalOverview.Row) -> some View {
        let parts = r.contestant.components(separatedBy: " · ")
        let head = parts.first ?? r.contestant, rest = parts.dropFirst().joined(separator: " · ")
        let tail = r.kind == .baseline ? "free stand-in" : rest
        return (Text(head).bold().foregroundStyle(t.text.color) + Text(tail.isEmpty ? "" : " " + tail).foregroundStyle(t.text3.color))
            .ui(TypeScale.small, mono: r.kind != .agent).lineLimit(1).truncationMode(.middle)
    }

    private func line(_ cells: [AnyView]) -> some View {
        HStack(spacing: 12) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                if let w = widths[i] { c.frame(width: w, alignment: .leading) } else { c.frame(minWidth: 140, maxWidth: .infinity, alignment: .leading) }
            }
        }
    }
}

enum EvalsDay {
    /// "Oct 31".
    static func short(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) ?? ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z") else { return iso.map { String($0.prefix(10)) } ?? "–" }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        return f.string(from: d)
    }
    static func date(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return ISO8601DateFormatter().date(from: iso) ?? ISO8601DateFormatter().date(from: String(iso.prefix(19)) + "Z")
    }
}

/// Compare A vs B on the same cases (paired), with the verdict in words and the cases only one solved (HP CompareCard).
struct EvalsCompareCard2: View {
    let lb: EvalLeaderboard
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var a: String?
    @State private var b: String?
    @State private var result: EvalCompareResult?
    @State private var error: String?

    var body: some View {
        let rows = lb.rows
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Compare").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    if let c = result { Text(c.paired ? "same \(c.n) cases, paired" : "unpaired (no shared cases)").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                }
                if rows.count < 2 {
                    Text("Run a second contestant on the same cases to compare.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                } else {
                    HStack(spacing: 8) {
                        pick("A", $a, rows)
                        pick("B", $b, rows)
                    }
                    if let c = result {
                        let na = name(a), nb = name(b)
                        Text(c.headline(a: na, b: nb)).ui(20, .bold).foregroundStyle(t.text.color)
                            .evalHover(.compare, EvalHover.compare(diff: c.diff, lo: c.ci95.first ?? c.diff, hi: c.ci95.last ?? c.diff, paired: c.paired)
                                       + (c.tooFew == true ? " Too few shared questions to call a winner." : ""))
                        EvalsDiffAxis(diff: c.diff, lo: c.ci95.first ?? c.diff, hi: c.ci95.last ?? c.diff).frame(height: 34)
                        (Text(c.sentence(a: na, b: nb) + " ")
                         + (c.discordant.isEmpty || !c.paired ? Text("") : Text("See the \(c.discordant.count) cases ›").foregroundStyle(t.accentText.color)))
                            .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                            .onTapGesture { if let a, let b, !c.discordant.isEmpty { nav.openRun(a, only: c.discordant, other: b) } }
                            .accessibilityAddTraits(.isButton)
                        Text(EvalGlossary.entry("compare")?.body ?? "").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let e = error {
                        Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color)
                    } else {
                        Text("Comparing…").ui(TypeScale.small).foregroundStyle(t.text3.color)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        }
        .onAppear(perform: defaults)
        .onChange(of: lb) { _, _ in defaults() }
        .onChange(of: a) { _, _ in compare() }
        .onChange(of: b) { _, _ in compare() }
    }

    private func name(_ run: String?) -> String {
        let c = lb.rows.first { $0.run == run }?.contestant ?? "?"
        return c.components(separatedBy: " · ").first ?? c
    }

    /// The top two contestants by default; one run's "Compare with…" sets A.
    private func defaults() {
        let ranked = lb.rows.filter { $0.kind != .baseline }
        let pool = ranked.count >= 2 ? ranked : lb.rows
        if let want = nav.compareA, lb.rows.contains(where: { $0.run == want }) {
            a = want; nav.compareA = nil
            b = pool.first { $0.run != want }?.run
        } else if a == nil || !lb.rows.contains(where: { $0.run == a }) {
            a = pool.first?.run; b = pool.dropFirst().first?.run
        }
        compare()
    }

    private func compare() {
        guard let a, let b, a != b else { result = nil; return }
        board.ask(["compare", a, b], EvalCompareResult.self, timeout: 120) { r in
            guard a == self.a, b == self.b else { return }
            switch r {
            case .success(let c): result = c; error = nil; EvalsLearnStore.note(EvalsLearnStore.compareKey)   // first eval, step 4
            case .failure(let e): result = nil; error = e.message
            }
        }
    }

    private func pick(_ label: String, _ sel: Binding<String?>, _ rows: [EvalOverview.Row]) -> some View {
        let cur = rows.first { $0.run == sel.wrappedValue }
        return Menu {
            ForEach(rows) { r in Button("\(r.contestant) · \(EvalsDay.short(r.date))") { sel.wrappedValue = r.run } }
        } label: {
            Text("\(label): \((cur?.contestant.components(separatedBy: " · ").first) ?? "choose") ▾").ui(TypeScale.small, .medium)
                .foregroundStyle(t.text.color)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.selection.color))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

/// The difference with its 95 % range on an axis through 0 (−10 … +30 style), in points.
struct EvalsDiffAxis: View {
    let diff: Double
    let lo: Double
    let hi: Double
    @Environment(\.theme) private var t
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let lim = max(0.1, ([abs(lo), abs(hi), abs(diff)].max() ?? 0.1) * 1.25)
            let x: (Double) -> CGFloat = { CGFloat(($0 + lim) / (2 * lim)) * w }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(t.separatorStrong.color).frame(width: w, height: 1).offset(y: 11)
                RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.accent.color.opacity(0.18))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(t.accent.color.opacity(0.6)))
                    .frame(width: max(x(hi) - x(lo), 3), height: 14).offset(x: x(lo), y: 4)
                Rectangle().fill(t.text.color).frame(width: 1.5, height: 20).offset(x: x(0), y: 1)
                Rectangle().fill(t.accent.color).frame(width: 2, height: 14).offset(x: x(diff) - 1, y: 4)
                Text("0").ui(10.5).foregroundStyle(t.text2.color).offset(x: x(0) - 3, y: 22)
                if abs(x(lo) - x(0)) > 22 { Text(String(format: "%+.0f", lo * 100)).ui(10.5).foregroundStyle(t.text2.color).offset(x: x(lo) - 8, y: 22) }
                if abs(x(hi) - x(0)) > 22 { Text(String(format: "%+.0f", hi * 100)).ui(10.5).foregroundStyle(t.text2.color).offset(x: x(hi) - 10, y: 22) }
            }
        }
        .accessibilityLabel(String(format: "difference %+.0f points, 95 percent range %+.0f to %+.0f", diff * 100, lo * 100, hi * 100))
    }
}

/// Over time (HP HistoryChart): every run on this version, a line per contestant (agents first in the legend), the floor
/// dashed, a drop circled with what to do.
struct EvalsOverTimeCard: View {
    let lb: EvalLeaderboard
    let history: EvalHistory?
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Over time").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Text(lb.version.map { "every run on v\($0)" } ?? "every run").ui(TypeScale.small).foregroundStyle(t.text2.color)
                    Spacer()
                    if let d = history?.dropsLine { Text(d).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
                }
                if let h = history, h.series.contains(where: { $0.points.count > 0 }) {
                    chart(h).frame(height: 150)
                    HStack(spacing: 12) {
                        ForEach(Array(h.series.prefix(5).enumerated()), id: \.offset) { i, s in
                            HStack(spacing: 4) {
                                Circle().fill(color(i)).frame(width: 7, height: 7)
                                Text(s.contestant.components(separatedBy: " · ").first ?? s.contestant).ui(TypeScale.caption).foregroundStyle(i == 0 ? t.accentText.color : t.text2.color).lineLimit(1)
                            }
                        }
                        Spacer()
                        Text("\(EvalsDay.short(h.first)) → \(EvalsDay.short(h.last))").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    }
                    ForEach(h.drops) { d in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(d.text).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                            if d.possible, let row = lb.rows.first(where: { $0.contestant == d.contestant }) {
                                RoofButton("Re-run ×3", .plain) { nav.run(rerun(row)) }.help("Run pre-filled with 3 attempts; the cost shows first")
                            }
                        }
                    }
                    if h.series.allSatisfy({ $0.points.count < 2 }) {
                        Text("One run per contestant so far: run again later to see a trend.").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    }
                } else {
                    Text(history == nil ? "Reading…" : "No finished run on this version yet.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
        }
    }

    private func color(_ i: Int) -> Color { [t.accent.color, t.text.color, t.text2.color, t.text3.color, t.accentText.color][i % 5] }

    private func rerun(_ r: EvalOverview.Row) -> EvalRunPlan {
        var p = EvalRunPlan(tasks: [lb.taskFile ?? lb.title], models: [], limit: lb.cases ?? 20, epochs: 3)
        if let a = r.agent, (r.model ?? "").hasPrefix("seat/") { p.agents = [a] }
        else if let a = r.agent, let m = r.model { p.apiAgents = [a + "@" + m] }
        else if let m = r.model { p.models = [m] }
        return p
    }

    private func chart(_ h: EvalHistory) -> some View {
        let all = h.series.flatMap(\.points).compactMap { EvalsDay.date($0.date) }
        let t0 = all.min() ?? Date(), t1 = max(all.max() ?? Date(), t0.addingTimeInterval(1))
        return GeometryReader { g in
            let w = g.size.width, ht = g.size.height - 6
            let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(t0) / t1.timeIntervalSince(t0)) * (w - 12) + 6 }
            let y: (Double) -> CGFloat = { ht - CGFloat($0) * (ht - 6) + 3 }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(t.separator.color).frame(width: w, height: 1).offset(y: ht + 3)
                if let f = h.floor ?? lb.floor {
                    Path { p in p.move(to: CGPoint(x: 0, y: y(f))); p.addLine(to: CGPoint(x: w, y: y(f))) }
                        .stroke(t.text3.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
                ForEach(Array(h.series.enumerated()), id: \.offset) { i, s in
                    let pts = s.points.compactMap { p -> CGPoint? in
                        guard let d = EvalsDay.date(p.date), let v = p.score else { return nil }
                        return CGPoint(x: x(d), y: y(v))
                    }
                    Path { p in
                        guard let f = pts.first else { return }
                        p.move(to: f); pts.dropFirst().forEach { p.addLine(to: $0) }
                    }
                    .stroke(color(i), style: StrokeStyle(lineWidth: i == 0 ? 2.2 : 1.6, lineCap: .round, lineJoin: .round))
                    ForEach(Array(pts.enumerated()), id: \.offset) { _, p in Circle().fill(color(i)).frame(width: 5, height: 5).position(p) }
                }
                ForEach(h.drops) { d in
                    if let s = h.series.first(where: { $0.contestant == d.contestant }), let p = s.points.first(where: { $0.run == d.run }),
                       let dt = EvalsDay.date(p.date), let v = p.score {
                        Circle().strokeBorder(t.needsText.color, lineWidth: 2).frame(width: 13, height: 13).position(x: x(dt), y: y(v))
                    }
                }
            }
        }
        .accessibilityLabel("Scores over time for \(h.series.count) contestants")
    }
}

// MARK: - All × all (1.9.37's matrix + every run, in v2 tokens)

struct EvalsAllByAll: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t

    var body: some View {
        let m = EvalStats.matrix(board.results)
        let models = m.keys.sorted()
        let tasks = Array(Set(m.values.flatMap(\.keys))).sorted()
        VStack(alignment: .leading, spacing: 16) {
            Text("Latest finished run per model and task. The number is the main score; the bar shows its 95 % range. Dashed: fewer than 30 questions.")
                .ui(TypeScale.small).foregroundStyle(t.text2.color)
            ScrollView(.horizontal) {
                Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 6) {
                    GridRow {
                        Text("").frame(width: 220)
                        ForEach(tasks, id: \.self) { Text(EvalBenchmark.taskLabel($0)).ui(TypeScale.caption, .semibold, mono: true).foregroundStyle(t.text2.color).frame(width: 130).lineLimit(1) }
                    }
                    ForEach(models, id: \.self) { model in
                        GridRow {
                            Text(EvalModels.short(model)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).frame(width: 220, alignment: .leading).lineLimit(1)
                            ForEach(tasks, id: \.self) { task in cell(m[model]?[task]) }
                        }
                    }
                }
            }
            Text("Every run").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
            LazyVStack(alignment: .leading, spacing: 4) { ForEach(board.results) { r in runRow(r) } }
        }
    }

    @ViewBuilder private func cell(_ r: EvalResult?) -> some View {
        if let r, let p = r.primary, let v = p.value {
            Button { nav.openRun(r.id) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(evalFormat(v, p)).ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color)
                    EvalIntervalBar(metric: p).frame(height: 6)
                    Text("n=\(p.n ?? 0)" + ((r.cost ?? 0) > 0 ? String(format: " · $%.3f", r.cost!) : (r.isFree ? " · free" : "")))
                        .ui(TypeScale.micro, mono: true).foregroundStyle(t.text3.color)
                    if let j = r.judgeAgreement {
                        Text(j.short).ui(TypeScale.micro).foregroundStyle(j.trustworthy ? t.text2.color : t.needsText.color)
                            .evalHover(.agreement, EvalHover.agreement(j))
                            .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(8).frame(width: 130, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous)
                    .strokeBorder(EvalStats.isSmall(p.n) ? t.needsText.color.opacity(0.6) : t.separator.color,
                                  style: StrokeStyle(lineWidth: 1, dash: EvalStats.isSmall(p.n) ? [4, 3] : [])))
            }
            .buttonStyle(.plain)
            .evalHover(p.label.contains("pass") ? .passK : .range,
                       p.ciMethod == "wilson" ? EvalHover.range(score: v, n: p.n ?? 0, lo: p.ci95?.first ?? v, hi: p.ci95?.last ?? v)
                       : "\(p.label) · 95 % \(p.ci95.map { String(format: "%.3f to %.3f", $0[0], $0[1]) } ?? "n/a"). Open the run.")
        } else {
            Text("–").ui(TypeScale.small).foregroundStyle(t.text3.color).frame(width: 130)
        }
    }

    private func runRow(_ r: EvalResult) -> some View {
        Button { nav.openRun(r.id) } label: {
            HStack(spacing: 10) {
                Text("\(EvalBenchmark.taskLabel(r.task ?? "?")) × \(r.contestant?.name ?? EvalModels.short(r.model ?? "?"))").ui(TypeScale.small, .medium)
                    .foregroundStyle(t.text.color).frame(width: 330, alignment: .leading).lineLimit(1)
                Text(r.status ?? "").ui(TypeScale.small).foregroundStyle(r.status == "done" ? t.text2.color : t.needsText.color).frame(width: 70, alignment: .leading)
                if let p = r.primary, let v = p.value { Text("\(p.metric) \(evalFormat(v, p))").ui(TypeScale.small, mono: true).foregroundStyle(t.text.color) }
                if let j = r.judgeAgreement {
                    Text(j.short).ui(TypeScale.caption).foregroundStyle(j.trustworthy ? t.text2.color : t.needsText.color).lineLimit(1)
                        .evalHover(.agreement, EvalHover.agreement(j))
                }
                Spacer()
                Text(EvalModels.when(r.started)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - X-ray (EVO-2: read-only table)

struct EvalsXRayTable: View {
    @ObservedObject var board: EvalsBoard
    @Environment(\.theme) private var t
    @State private var repo = ""
    @State private var x: EvalXRay?
    @State private var error: String?
    @State private var reading = false
    private let cols = ["Agent", "Commits", "Lines added", "Churn", "Fixes own work", "Reverted", "Followed by a fix"]

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("X-ray").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Text("how much of each agent's work survives in git · last 30 days").ui(TypeScale.small).foregroundStyle(t.text2.color)
                    Spacer()
                    FieldMenu(title: repo.isEmpty ? "Choose a repo" : (repo as NSString).lastPathComponent, expand: false) {
                        ForEach(repos, id: \.self) { r in Button((r as NSString).lastPathComponent) { repo = r } }
                        Divider()
                        Button("Choose a repo…", action: choose)
                    }
                }
                if reading { Text("Reading \((repo as NSString).lastPathComponent)'s history (about half a minute)…").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
                if let x {
                    Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 8) {
                        GridRow { ForEach(cols, id: \.self) { c in EvalsLabel(c).help(EvalXRay.definitions[c] ?? "") } }
                        ForEach(x.rows, id: \.name) { r in
                            GridRow {
                                Text(r.name).ui(TypeScale.small, .semibold).foregroundStyle(r.name == "unattributed" ? t.text2.color : t.text.color)
                                Text("\(r.agent.commits)").ui(TypeScale.small, mono: true)
                                Text(r.agent.linesAdded.formatted()).ui(TypeScale.small, mono: true)
                                Text(evalsPct(r.agent.churn)).ui(TypeScale.small, mono: true).help(r.agent.churn == nil ? "No commit old enough yet (needs \(x.horizonDays ?? 14) days)" : "")
                                Text(evalsPct(r.agent.selfChurnShare)).ui(TypeScale.small, mono: true)
                                Text(evalsPct(r.agent.revertRate)).ui(TypeScale.small, mono: true)
                                Text(evalsPct(r.agent.fixupRate)).ui(TypeScale.small, mono: true)
                            }
                            .foregroundStyle(t.text.color)
                        }
                    }
                    Text("From git alone: a commit belongs to an agent when its Co-Authored-By or author names it; everything else is unattributed. Churn needs commits at least \(x.horizonDays ?? 14) days old. Computed \(EvalModels.when(x.computed)).")
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear(perform: load)
        .onChange(of: repo) { _, _ in load() }
    }

    /// The repos your sets were built from (the ones whose agents you measure), then any you choose.
    private var repos: [String] {
        Array(Set(board.sets.compactMap(\.repoPath))).sorted().filter { FileManager.default.fileExists(atPath: $0 + "/.git") }
    }

    private func choose() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if p.runModal() == .OK, let u = p.url { repo = u.path }
    }

    private func load() {
        if repo.isEmpty, let first = repos.first { repo = first; return }
        guard !repo.isEmpty else { x = nil; error = "Choose a repo to read its agents' history."; return }
        x = nil; error = nil; reading = true
        let r0 = repo
        board.ask(["xray", "--repo", r0, "--days", "30"], EvalXRay.self, timeout: 600) { r in
            guard r0 == repo else { return }
            reading = false
            switch r { case .success(let v): x = v; case .failure(let e): error = e.message }
        }
    }
}
