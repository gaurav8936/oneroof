import AppKit
import SwiftUI
import OneRoofCore

// LAB-2293 · 7j Runs and their rounds (handover 11-7j.png, pages/7j-runs): one feed for kit and roofd runs (the
// ledger's runs, roofd's rounds.jsonl, the run going now, missed slots), filtered by the bar (search, kind) and a result
// chip (Any · Running · Failed or stopped · Missed · Trial). The selected run: id and start, title, one line, Report ›
// and The loop ›, then its steps: started (by whom), roofd's check and each round (agent, time, check result, Open
// session ↗) or a kit run's report steps, and how it ended; HOW A RUN WORKS. 2.0.5's runs card (round sessions with
// their agent mark and Open ↗, "N running · N rounds") stays under it.

struct LoopRunsPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    @State var selected: String?
    @State private var result: LoopsV7.FeedFilter = .any
    /// Kit runs' journal reports, parsed off the main thread (key = run id; path nil = no report file).
    @State private var reports: [String: LoopRunReport.Loaded] = [:]
    static let limit = 300
    /// 24-hour clock with seconds ("10:40:02"), as the kit's journal writes it.
    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f }()

    private var feed: [LoopsV7.FeedRun] {
        var current: [String: (id: String, started: Date)] = [:]
        for l in board.loops { if let r = l.run { current[l.id] = (r.id, r.started) } }
        return LoopsV7.runsFeed(runs: board.weekRuns, rounds: board.rounds, rows: board.rows, crons: board.crons, current: current,
                                from: Date().addingTimeInterval(-7 * 86400))
    }

    var body: some View {
        let f = nav.filter("7j")
        let all = feed
        let shown = LoopsV7.filterFeed(all, rows: board.rows, filter: f.wrappedValue, result: result)
        let sel = shown.first { $0.id == selected } ?? all.first { $0.id == selected } ?? shown.first
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(LoopsV7.feedCounts(all, rounds: board.rounds)).ui(13).foregroundStyle(t.text2.color)
                    .accessibilityLabel("Runs: " + LoopsV7.feedCounts(all, rounds: board.rounds))
                Spacer()
            }
            HStack(spacing: 8) {
                LoopFilterBar(filter: f)
                Rectangle().fill(t.separator.color).frame(width: 1, height: 20)
                ForEach(LoopsV7.FeedFilter.allCases, id: \.self) { c in resultChip(c) }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 16) {
                list(shown, total: all.count, selected: sel?.id, filter: f)
                    .frame(width: 420)
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if let r = sel { detail(r) } else {
                            Text("No run selected.").ui(13).foregroundStyle(t.text2.color)
                        }
                        LoopRunsView(model: model, board: board)   // 2.0.5: round sessions, Open ↗ (LAB-1933)
                    }
                    .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
                .frame(maxWidth: .infinity)
            }
        }
        .onChange(of: sel?.id) { _, _ in loadReport(sel) }
        .onAppear { loadReport(sel) }
        .accessibilityLabel("Runs and their rounds")
    }

    private func resultChip(_ c: LoopsV7.FeedFilter) -> some View {
        let on = result == c
        return Button { result = c } label: {
            Text(c.label).ui(12, .semibold).foregroundStyle((on ? t.surface : t.text2).color)
                .padding(.vertical, 4).padding(.horizontal, 10)
                .background(Capsule().fill(on ? t.text.color : .clear))
                .overlay(Capsule().strokeBorder((on ? t.text : t.separatorStrong).color, lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(PressStyle(radius: 12))
        .accessibilityLabel("Result " + c.label + (on ? ", selected" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: List

    private func list(_ runs: [LoopsV7.FeedRun], total: Int, selected: String?, filter: Binding<LoopFilter>) -> some View {
        LoopCard(padding: 0, shadow: false) {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(runs.prefix(Self.limit)) { r in
                            Button { self.selected = r.id } label: { runRow(r, on: r.id == selected) }
                                .buttonStyle(.plain)
                            Rectangle().fill(t.separator.color).frame(height: 1)
                        }
                        if runs.isEmpty {
                            HStack(spacing: 10) {
                                Text(filter.wrappedValue.isEmpty && result == .any ? "No runs this week." : "No run matches.").ui(13).foregroundStyle(t.text2.color)
                                if !filter.wrappedValue.isEmpty || result != .any {
                                    RoofButton("Clear", .plain) { filter.wrappedValue = LoopFilter(); result = .any }
                                }
                                Spacer()
                            }
                            .padding(14)
                        }
                    }
                }
                .defaultScrollAnchor(.top)
                Text("Showing \(min(runs.count, Self.limit)) of \(total) this week (runs and missed slots) · newest first").ui(12).foregroundStyle(t.text2.color)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 14).padding(.vertical, 10)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
            }
        }
    }

    private func runRow(_ r: LoopsV7.FeedRun, on: Bool) -> some View {
        HStack(spacing: 10) {
            Circle().fill(Self.tone(r.result, t.name).text.color).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(r.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(LoopsV7.feedLine(r)).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
            }
            Spacer(minLength: 6)
            LoopResultChip(result: r.result)
        }
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(on ? t.selection.color : .clear)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(r.name), \(Self.word(r.result)), \(LoopsV7.feedLine(r))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    static func tone(_ r: LoopsV7.FeedRun.Result, _ name: ThemeName) -> LoopLook.Pair {
        switch r {
        case .running: return LoopLook.tone(.running, theme: name)
        case .passed, .done: return LoopLook.tone(.fine, theme: name)
        case .failed, .stopped: return LoopLook.tone(.failing, theme: name)
        case .missed: return LoopLook.tone(.needsYou, theme: name)
        case .trial: return LoopLook.tone(.trial, theme: name)
        }
    }

    static func word(_ r: LoopsV7.FeedRun.Result) -> String { r == .trial ? "shadow" : r.rawValue }

    // MARK: The selected run

    private func detail(_ r: LoopsV7.FeedRun) -> some View {
        let row = board.row(r.loop)
        let loop = board.loops.first { $0.id == r.loop }
        let rep = reports[r.id]?.parsed
        let steps = LoopsV7.runSteps(r, rounds: board.rounds[r.loop] ?? [], report: rep, schedule: row?.schedule ?? "manual", check: loop?.check ?? "")
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        LoopLabel("Run")
                        Text(r.roofdRunId ?? r.id).ui(TypeScale.micro, .semibold, mono: true).foregroundStyle(t.text2.color).textSelection(.enabled)
                        LoopLabel("· " + (r.result == .missed ? "expected " : "started ") + Self.clock.string(from: r.started))
                    }
                    Text(r.name + " · " + title(r)).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Text(LoopsV7.runSentence(r, family: r.family)).ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 10)
                if r.result != .missed {
                    RoofButton("Report ›") { nav.open(.report(LoopsRunRef(r))) }
                        .help(r.engine == .kit ? "The run's journal report" : "roofd keeps rounds.jsonl, not a report file: the page says so")
                }
                RoofButton("The loop ›") { actions.openLoop(r.loop) }
            }
            VStack(spacing: 0) {
                ForEach(steps) { s in
                    if s.id > 0 { Rectangle().fill(t.separator.color).frame(height: 1).padding(.leading, 112) }
                    stepRow(s)
                }
            }
            if r.engine == .kit, let l = reports[r.id], l.path == nil, r.result != .running {
                Text("No report written for this run.").ui(12).foregroundStyle(t.text2.color)
            }
            (Text("How a run works. ").bold() + Text("One Roof runs the check first. If it already passes, no round is needed. Otherwise a round starts: an agent session in the loop's own worktree. After each round the check runs again, until it passes or a limit stops it. Kit loops run their own steps (inputs, findings, check, notify) and write a report to the journal."))
                .ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.text.color.opacity(0.8), lineWidth: 1.5))
        .accessibilityElement(children: .contain)
    }

    private func title(_ r: LoopsV7.FeedRun) -> String {
        switch r.result {
        case .running: return "running now"
        case .missed: return "missed"
        case .trial: return "trial run"
        default: return Self.word(r.result) + (r.seconds.map { " in " + LoopsV7.duration($0) } ?? "")
        }
    }

    private func stepRow(_ s: LoopsV7.RunStep) -> some View {
        return HStack(alignment: .top, spacing: 12) {
            Text(s.at.map { Self.clock.string(from: $0) } ?? "").ui(12, mono: true).foregroundStyle(t.text2.color).frame(width: 68, alignment: .leading)
            ZStack {
                Circle().fill(stepFill(s.tone).color)
                Text(stepGlyph(s.tone)).ui(10, .bold).foregroundStyle(stepInk(s.tone).color)
            }
            .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(s.title).ui(13.5, .semibold).foregroundStyle(t.text.color)
                Text(s.line).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                if let c = s.code {
                    Text(c).ui(11.5, mono: true).foregroundStyle(t.text.color).lineLimit(2).textSelection(.enabled)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.surface2.color))
                }
            }
            Spacer(minLength: 6)
            if let sid = s.sessionId {
                if let it = model.item(sid) {
                    HStack(spacing: 6) {
                        AgentBadge(item: it, size: 18, status: true)
                        RoofButton("Open session ↗", .plain) { model.reveal(it) }
                    }
                    .accessibilityLabel("Open the round's session")
                } else {
                    Text("session ended").ui(11.5).foregroundStyle(t.text3.color).help("The round's session is no longer in One Roof")
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func stepFill(_ tone: LoopsV7.RunStep.Tone) -> RGB {
        switch tone {
        case .pass: return LoopLook.tone(.fine, theme: t.name).fill
        case .fail: return LoopLook.tone(.failing, theme: t.name).fill
        case .running: return LoopLook.tone(.running, theme: t.name).fill
        case .trial: return LoopLook.tone(.trial, theme: t.name).fill
        case .normal: return t.surface2
        }
    }
    private func stepInk(_ tone: LoopsV7.RunStep.Tone) -> RGB {
        switch tone {
        case .pass: return LoopLook.tone(.fine, theme: t.name).text
        case .fail: return LoopLook.tone(.failing, theme: t.name).text
        case .running: return LoopLook.tone(.running, theme: t.name).text
        case .trial: return LoopLook.tone(.trial, theme: t.name).text
        case .normal: return t.text2
        }
    }
    private func stepGlyph(_ tone: LoopsV7.RunStep.Tone) -> String {
        switch tone { case .pass: return "✓"; case .fail: return "✕"; case .running: return "…"; case .trial: return "●"; case .normal: return "▸" }
    }

    // MARK: Report (kit runs)

    private func loadReport(_ r: LoopsV7.FeedRun?) {
        guard let r, r.engine == .kit, r.result != .missed, reports[r.id] == nil else { return }
        let ref = r.journalRef, id = r.id
        DispatchQueue.global(qos: .userInitiated).async {
            let l = LoopRunReport.read(ref)
            DispatchQueue.main.async { reports[id] = l }
        }
    }
}

/// A run's result as a small chip: running, passed, done, failed, stopped, missed, shadow.
struct LoopResultChip: View {
    @Environment(\.theme) private var t
    let result: LoopsV7.FeedRun.Result
    var body: some View {
        let p = LoopRunsPage.tone(result, t.name)
        Text(LoopRunsPage.word(result)).ui(11, .semibold).foregroundStyle(p.text.color)
            .padding(.horizontal, 8).padding(.vertical, 1).background(Capsule().fill(p.fill.color)).fixedSize()
    }
}
