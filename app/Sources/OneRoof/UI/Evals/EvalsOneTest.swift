import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E2.2 One test, bug by bug. Route `.oneTest(run:sample:only:other:)`; run nil = the newest finished test.
/// The strip: N of M with the verdict against the blind guess, one square per bug (right first, the tick at the guess),
/// "On new bugs, expect L to H", total cost, $ per right, date, seed, and the stamp. Left: every bug, wrong first (All ·
/// Wrong · Grader ≠ you, sort). Right: the bug, "What it named" vs "What the fix changed" (CONTRACT §4 named / changed,
/// real only), why it was marked so, its reasoning and full answer folded, "Add to next version of this task".
/// Kept from 2.0.3's run detail: facts, every metric, the failure + Resume, Code check · Grader · You, Label for the grader,
/// attempts, the transcript with tool calls, expected answer and every scorer, B's answer beside A's, Compare with…, Test again.
struct EvalsOneTestView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let runID: String?
    var sample: String?
    var only: [String]?
    var other: String?
    @Environment(\.theme) private var t

    private var resolved: String? {
        if let r = runID, !r.isEmpty { return r }
        return board.results.first(where: { $0.status == "done" })?.id
    }

    var body: some View {
        if let id = resolved {
            EvalsOneTestPage(board: board, nav: nav, runID: id, start: sample, only: only, other: other).id(id)
        } else {
            Text(board.results.isEmpty ? "Reading your tests…" : "No finished test yet.")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }
}

struct EvalsOneTestPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @ObservedObject private var store = EvalsAStore.shared
    let runID: String
    var start: String?
    var only: [String]?
    var other: String?
    @Environment(\.theme) private var t
    @State private var samples: [EvalSample] = []
    @State private var otherSamples: [String: EvalSample] = [:]
    @State private var loadError: String?
    @State private var loaded = false
    @State private var filter: EvalSample.Filter = .all
    @State private var sort: EvalSample.Sort = .wrongFirst
    @State private var selected: String?
    @State private var epoch = 1
    @State private var transcript: EvalTranscript?
    @State private var transcriptError: String?
    @State private var judgeItems: [String: EvalJudgeItem] = [:]
    @State private var adding = false
    @State private var toast: String?
    @State private var labelling = false
    @State private var reasoningOpen = false
    @FocusState private var listFocused: Bool
    private let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var result: EvalResult? { board.results.first { $0.id == runID } }
    private var row: EvalRunRow? { board.runs.first { $0.id == runID } }
    private var active: Bool { row?.isActive ?? false }
    /// Our task's setup leaderboard (floor, plain title, who solved what), when this test is on one of our tasks.
    private var lb: EvalSetupLeaderboard? {
        guard let s = result?.setName else { return nil }
        if case .success(let l)? = store.boards[s], l.version == nil || l.version == result?.setVersion { return l }
        return nil
    }
    private var setupRow: EvalSetupRow? { lb?.rows.first { $0.run == runID } }
    private var stamp: EvalStamp? { setupRow?.stamp ?? store.stamps[runID]?.stamp }
    private var againState: EvalRunPlan.AgainState {
        EvalRunPlan.againState(hasResult: result != nil, stamp: stamp, stampsRead: setupRow?.stamp != nil ? true : store.stampsRead)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            titleLine
            strip
            if let r = result, r.status == "failed" || r.error != nil { failure(r) }
            if let msg = toast {
                Text(msg).ui(TypeScale.small, .semibold).foregroundStyle(t.onAccent.color)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(t.accent.color))
                    .padding(.horizontal, 24).padding(.top, 8)
            }
            HStack(alignment: .top, spacing: 14) {
                list.frame(width: 380)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 24).padding(.top, 12)
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            load()
            if result == nil { board.refreshResults() }
            store.refreshBoards(board)
            if setupRow?.stamp == nil { store.refreshStamps(board) }
        }
        .onReceive(poll) { _ in if active { load() } }
        .onChange(of: board.sets) { _, _ in store.refreshBoards(board) }
        .sheet(isPresented: $adding) {
            EvalsAddToSetSheet(board: board, title: "Add to next version of this task",
                               source: ["--from-run", runID, "--sample", selected ?? "", "--epoch", String(epoch)],
                               codeKind: result?.setName != nil || (result?.task ?? "").hasPrefix("judge_"),
                               suggested: (result?.setName ?? EvalBenchmark.taskLabel(result?.task ?? "my")) + "_regressions") { msg in
                adding = false
                if let msg { say(msg) }
            }
            .themed(t.name)
        }
    }

    // MARK: Title + strip

    private var who: String {
        setupRow?.label ?? result?.contestant?.name ?? EvalModels.short(result?.model ?? row?.model ?? "?")
    }
    private var taskTitle: String { lb?.title ?? EvalBenchmark.taskLabel(result?.task ?? row?.task ?? runID) }

    private var titleLine: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(who) · \(taskTitle)").ui(TypeScale.title, .bold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
            Text("Every answer, wrong ones first. Opened from a score or a square.").ui(TypeScale.small).foregroundStyle(t.text2.color)
        }
        .padding(.horizontal, 24).padding(.bottom, 10)
    }

    private var squares: [EvalsASquare] {
        if let r = setupRow, let lb { return EvalsASquares.ordered(cases: lb.cases, perCase: r.perCase) }
        return EvalsASquares.fromSamples(samples)
    }

    private var strip: some View {
        let sq = squares
        let sc = EvalsAOneTest.score(sq)
        let floor = lb?.floor
        let verdict = sc.flatMap { s in EvalVerdicts.againstFloor(EvalVerdicts.Side(label: who, right: s.right, n: s.n, lo: s.lo, hi: s.hi), floor: floor?.share) }
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let s = sc {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(EvalScoreText.count(s.right)).ui(26, .bold).foregroundStyle(t.text.color)
                                    .evalHover(.score, EvalHover.score(score: s.right / Double(max(s.n, 1)), n: s.n))
                                Text("of \(s.n)").ui(TypeScale.small).foregroundStyle(t.text2.color)
                            }
                            if let v = verdict {
                                Text(v.text).ui(TypeScale.caption, .semibold).foregroundStyle(v.isCall ? t.diffAddText.color : t.evalsATone(.cantTell).ink.color)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .evalHover(.floor, EvalHover.floor(share: floor?.share, right: floor?.right, of: floor?.of))
                            }
                        } else {
                            Text(active ? "running" : "–").ui(26, .bold).foregroundStyle(t.text2.color)
                        }
                    }
                    .frame(width: 170, alignment: .leading)
                    if !sq.isEmpty {
                        EvalsABugSquares(squares: sq, guess: EvalsASquares.guessIndex(floor: floor, n: sq.count), size: 16) { s in open(s.id) }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(numbersLine(sc)).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                            .evalHoverIf(sc.map { s in (.range, EvalHover.range(score: s.right / Double(max(s.n, 1)), n: s.n, lo: s.lo, hi: s.hi, unit: "bug")) })
                        EvalsAStampLine(stamp: stamp)
                    }
                    Spacer(minLength: 8)
                    RoofButton("Compare with…") { compareWith() }.disabled(result?.status != "done")
                        .help("Compare, with this test picked; pick a second for the paired verdict")
                    VStack(alignment: .trailing, spacing: 2) {
                        RoofButton("Test again") { if let r = result, let p = EvalRunPlan.again(r, stamp: stamp, state: againState) { nav.test(p) } }
                            .disabled(againState == .reading)
                            .help(againState == .reading ? "Reading this test's setup (model, rules) first"
                                  : "Set up a test, pre-filled with the same settings; nothing starts until Start")
                        // re-review #6: never a silent CLI-default / rules-off repeat
                        if againState == .reading {
                            Text(EvalRunPlan.againReading).ui(TypeScale.micro).foregroundStyle(t.text3.color)
                        } else if againState == .unreadable {
                            Text(EvalRunPlan.againUnreadable).ui(TypeScale.micro).foregroundStyle(t.needsText.color)
                                .frame(maxWidth: 220, alignment: .trailing).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                extras
            }
        }
        .padding(.horizontal, 24)
    }

    /// "On new bugs, expect 5 to 9 · $0.256 in all · $0.032 per right answer · Nov 1 08:31 · seed 42".
    private func numbersLine(_ sc: (right: Double, n: Int, lo: Double, hi: Double)?) -> String {
        var f: [String] = []
        if let s = sc { f.append(EvalVerdicts.expect(lo: s.lo, hi: s.hi, n: s.n)) }
        if let r = result {
            if (r.model ?? "").hasPrefix("seat/") || (stamp?.runsOn ?? "").hasPrefix("seat:") { f.append("on your seat, no API cost") }
            else if let c = r.cost, c > 0 { f.append(EvalsAWords.dollars(c) + " in all") } else if r.isFree { f.append("free") } else { f.append("cost unknown") }
            if let c = setupRow?.costPerRight ?? r.costPerCorrect { f.append(EvalsAWords.dollars(c) + " per right answer") }
            f.append(EvalModels.when(r.started))
            if let s = r.seed ?? stamp?.seed { f.append("seed \(s)") }
        } else if let rw = row {
            f.append("\(rw.status ?? "") · \(rw.progress)")
        }
        return f.joined(separator: " · ")
    }

    /// The facts 2.0.3 showed (answers, tokens, time, engine), every other metric, the code score and grader trust.
    @ViewBuilder private var extras: some View {
        if let r = result {
            let judged = isJudged
            HStack(alignment: .top, spacing: 16) {
                Text(facts(r)).ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if judged, let code = codeScore {
                    Text("Files named · checked by code: \(code.right) of \(code.of)").ui(TypeScale.caption, .semibold).foregroundStyle(t.text2.color)
                }
                if let a = r.judgeAgreement {
                    let line = EvalTrustLine.text(a)
                    Button { openGrader() } label: {
                        Text("\(line.heading): \(line.body) Grader ›").ui(TypeScale.caption).foregroundStyle(line.trusted ? t.text2.color : t.needsText.color)
                            .multilineTextAlignment(.leading).frame(maxWidth: 360, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .evalHover(.agreement, EvalHover.agreement(a))
                } else if judged {
                    Text("This grader has not been measured against your labels yet.").ui(TypeScale.caption).foregroundStyle(t.needsText.color)
                }
            }
            let more = r.metrics.filter { $0.value != nil }.dropFirst().prefix(4)
            if !more.isEmpty {
                Text(more.map { m in "\(m.label) \(m.value.map { evalFormat($0, m) } ?? "n/a")" }.joined(separator: " · "))
                    .ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
            }
        }
    }

    private func facts(_ r: EvalResult) -> String {
        var f = [r.status ?? "?"]
        if active, let p = row?.progress { f.append("\(p) answered") } else { f.append("\(r.samplesDone ?? samples.count) answers") }
        if let i = r.inputTokens, let o = r.outputTokens, i + o > 0 { f.append("\(i.formatted()) in / \(o.formatted()) out tokens") }
        if let d = r.duration { f.append(d >= 60 ? "\(Int(d) / 60) m \(Int(d) % 60) s" : String(format: "%.0f s", d)) }
        if let v = r.inspectEvals { f.append("inspect-evals \(v)") }
        f.append(r.id)
        return f.joined(separator: " · ")
    }

    private var isJudged: Bool { result?.judgeAgreement != nil || samples.contains { $0.judge != nil } }
    private var codeScore: (right: Int, of: Int)? {
        let c = samples.compactMap(\.code).filter { $0.verdict != "none" }
        return c.isEmpty ? nil : (c.filter(\.isPass).count, c.count)
    }

    private func failure(_ r: EvalResult) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(r.error.map { "failed: " + ($0.split(separator: "\n").last.map(String.init) ?? $0) } ?? "failed")
                .ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled).lineLimit(3)
            if let h = row?.hint { Text("What to do: " + h).ui(TypeScale.small).foregroundStyle(t.text2.color).lineLimit(3) }
            Spacer()
            if row?.canResume ?? (r.status == "failed") { RoofButton("Resume") { board.resume(r.id) } }
        }
        .padding(.horizontal, 24).padding(.vertical, 8)
    }

    // MARK: List (left)

    private var shown: [EvalSample] {
        let base = only.map { Set($0) }
        var low: [String: Int] = [:]
        for x in samples { low[x.sampleID] = min(low[x.sampleID] ?? x.epoch, x.epoch) }
        let firstAttempt = samples.filter { $0.epoch == low[$0.sampleID] }
        return EvalSample.sorted(EvalSample.filtered(firstAttempt, filter, only: base), sort)
    }

    private var list: some View {
        let c = EvalSample.counts(only.map { ids in samples.filter { ids.contains($0.sampleID) } } ?? samples)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                chip(.all, "All \(c.all)")
                chip(.wrong, "Wrong \(c.wrong)")
                if isJudged { chip(.disagree, "Grader ≠ you \(c.disagree)") }
                Spacer()
                Menu {
                    ForEach(EvalSample.Sort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
                } label: { Text(sort.rawValue + " ▾").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if let o = only { Text("\(o.count) bugs where the two tests differ" + (other != nil ? "; B's answer is shown beside A's" : "")).ui(TypeScale.caption).foregroundStyle(t.text3.color) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(shown) { s in answerRow(s).id(s.id); Divider() }
                        if shown.isEmpty {
                            Text(loadError ?? (loaded ? "Nothing here." : "Reading…")).ui(TypeScale.small)
                                .foregroundStyle(loadError == nil ? t.text3.color : t.needsText.color).padding(8)
                        }
                    }
                }
                .onChange(of: selected) { _, id in if let s = samples.first(where: { $0.sampleID == id }) { proxy.scrollTo(s.id) } }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .focusable().focused($listFocused).focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "wW")) { _ in filter = filter == .wrong ? .all : .wrong; return .handled }
        .padding(.bottom, 12)
    }

    private func chip(_ f: EvalSample.Filter, _ title: String) -> some View {
        let on = filter == f
        return Button { filter = f } label: {
            Text(title).ui(11.5, .medium).foregroundStyle(on ? t.window.color : t.text.color).lineLimit(1).fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(on ? t.text.color : t.control.color))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func answerRow(_ s: EvalSample) -> some View {
        let on = selected == s.sampleID
        return Button { open(s.sampleID); listFocused = true } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(s.isRight ? "✓" : "✕").ui(TypeScale.body, .semibold).foregroundStyle(s.isRight ? t.diffAddText.color : t.needsText.color)
                Text(s.issue ?? EvalsASquares.issue(s.sampleID)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).frame(width: 74, alignment: .leading)
                Text(s.title ?? s.input ?? s.sampleID).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1)
                Spacer(minLength: 4)
                if s.disagree == true { Text("grader ≠ you").ui(TypeScale.caption).foregroundStyle(t.needsText.color) }
                else if s.judgeItem != nil && s.labelled != true { Text("unlabelled").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
            }
            .padding(.horizontal, 8).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel((s.isRight ? "right: " : "wrong: ") + (s.title ?? s.sampleID))
    }

    private func step(_ d: Int) {
        let xs = shown
        guard !xs.isEmpty else { return }
        let i = xs.firstIndex { $0.sampleID == selected } ?? -1
        open(xs[min(max(i + d, 0), xs.count - 1)].sampleID)
    }

    // MARK: Detail (right)

    @ViewBuilder private var detail: some View {
        if let id = selected, let s = attempt(id) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    bugHeader(s)
                    let attempts = samples.filter { $0.sampleID == id }.map(\.epoch).sorted()
                    if attempts.count > 1 {
                        Segmented(options: attempts.map { ($0, "attempt \($0)") }, selection: Binding(get: { epoch }, set: { epoch = $0; fetchTranscript() }))
                    }
                    evidence(s)
                    verdicts(s)
                    if let tk = s.takeaway { Text(tk).ui(TypeScale.small).foregroundStyle(t.text2.color) }
                    if let b = otherSamples[id] {
                        Text("B's answer: \(b.answer ?? "–") " + (b.isRight ? "✓" : "✕")).ui(TypeScale.small, mono: true)
                            .foregroundStyle(b.isRight ? t.diffAddText.color : t.needsText.color)
                    }
                    reasoning(s)
                }
                .padding(.bottom, 20)
            }
        } else {
            Text(samples.isEmpty ? (loadError ?? (loaded ? "This test has no answers yet." : "Reading…")) : "Pick a bug on the left.")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }

    private func bugHeader(_ s: EvalSample) -> some View {
        let nobody = lb.map { l in !l.rows.filter(\.isDone).contains { r in r.perCase.contains { $0.id == s.sampleID && $0.right == true } } } ?? false
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(s.issue ?? EvalsASquares.issue(s.sampleID)).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                    Text(s.title ?? s.sampleID).ui(TypeScale.section, .semibold).foregroundStyle(t.text.color).lineLimit(2)
                    Spacer()
                    if let ji = s.judgeItem {
                        RoofButton("Label for the grader") { nav.openGrader(ji.judge, first: ji.item) }
                            .help("Check the grader, with this answer first in the queue")
                    }
                    RoofButton("Add to next version of this task") { adding = true }.disabled(result == nil)
                        .help("Into the next version of a task, never a frozen one, so old scores stay comparable")
                }
                Text(result?.setName != nil ? "The bug report and the code as it was the day before the fix." + (nobody ? " Nobody has solved this one yet." : "") : (s.input.map { String($0.prefix(240)) } ?? ""))
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// What it named vs what the fix changed (only when the engine returns the files; never sample text).
    @ViewBuilder private func evidence(_ s: EvalSample) -> some View {
        let e = EvalsAOneTest.evidence(s)
        if !e.named.isEmpty || !e.changed.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                box("What it named") {
                    if e.named.isEmpty { Text("It named no file.").ui(TypeScale.small).foregroundStyle(t.text3.color) }
                    ForEach(e.named, id: \.self) { f in
                        let hit = e.changed.contains { $0 == f || $0.hasSuffix("/" + f) || f.hasSuffix("/" + $0) }
                        file(f, fill: hit ? t.diffAddFill : t.needsText.opacity(0.12).over(t.surface), ink: hit ? t.diffAddText : t.text)
                    }
                }
                box("What the fix changed") {
                    ForEach(e.changed, id: \.self) { f in file(f, fill: t.diffAddFill, ink: t.diffAddText) }
                    Text(EvalsAOneTest.markLine(named: e.named, changed: e.changed, right: s.isRight))
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func file(_ path: String, fill: RGB, ink: RGB) -> some View {
        Text((path as NSString).lastPathComponent).ui(TypeScale.small, mono: true).foregroundStyle(ink.color).lineLimit(1)
            .padding(.horizontal, 8).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(fill.color))
            .help(path)
    }

    /// Its reasoning and the full answer, folded (token counts on the fold), then the expected answer and every scorer.
    private func reasoning(_ s: EvalSample) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Button { reasoningOpen.toggle() } label: {
                    HStack(spacing: 8) {
                        Text("Its reasoning").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                        Text(tokenLine(s)).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                        Spacer()
                        Text(reasoningOpen ? "Fold ▴" : "Show the full answer ›").ui(TypeScale.caption, .semibold).foregroundStyle(t.accentText.color)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if reasoningOpen {
                    transcriptView(s)
                    if let tr = transcript {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Expected: \(tr.target ?? "–")").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).textSelection(.enabled)
                            ForEach(tr.scores.keys.sorted(), id: \.self) { k in
                                let sc = tr.scores[k]!
                                Text("Scorer \(k): \(sc.value)" + (sc.explanation.map { $0.isEmpty ? "" : " — \($0)" } ?? ""))
                                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).textSelection(.enabled)
                            }
                        }
                    }
                } else if let a = s.answer, !a.isEmpty {
                    Text(a).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tokenLine(_ s: EvalSample) -> String {
        var f: [String] = []
        if let tr = transcript, tr.id == s.sampleID {
            let calls = tr.messages.reduce(0) { $0 + $1.toolCalls.count }
            if calls > 0 { f.append("\(calls) tool call\(calls == 1 ? "" : "s") folded") }
        }
        if let tok = EvalSampleTokens.text(input: s.inputTokens, output: s.outputTokens) { f.append(tok) }   // QA m11
        if let tm = s.time { f.append(String(format: "%.1f s", tm)) }
        return f.joined(separator: " · ")
    }

    private func attempt(_ id: String) -> EvalSample? {
        samples.first { $0.sampleID == id && $0.epoch == epoch } ?? samples.first { $0.sampleID == id }
    }

    /// system, user (long inputs folded), assistant in a card with the files it names highlighted, tool calls folded.
    @ViewBuilder private func transcriptView(_ s: EvalSample) -> some View {
        let files = EvalsAOneTest.evidence(s).named + EvalsAOneTest.evidence(s).changed
        if let ji = s.judgeItem, judgeName != nil, let item = judgeItems[ji.item] {
            EvalsFoldedMessage(role: "user", text: item.report, calls: [])
            assistant(item.answer, model: item.model ?? "the answering model", files: files, calls: [])
            if let tr = transcript, tr.id == s.sampleID {
                DisclosureGroup {
                    ForEach(Array(tr.messages.enumerated()), id: \.offset) { _, m in EvalsFoldedMessage(role: m.role, text: m.text, calls: m.toolCalls) }
                } label: { Text("The grader's prompt and reply (\(EvalModels.short(result?.model ?? "")))").ui(TypeScale.small).foregroundStyle(t.text2.color) }
            }
        } else if let tr = transcript, tr.id == s.sampleID {
            ForEach(Array(tr.messages.enumerated()), id: \.offset) { _, m in
                if m.role == "assistant" {
                    assistant(m.text, model: result?.model ?? "", files: files, calls: m.toolCalls)
                } else {
                    EvalsFoldedMessage(role: m.role, text: m.text, calls: m.toolCalls)
                }
            }
        } else if let e = transcriptError {
            Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color)
        } else {
            Text("Reading the transcript…").ui(TypeScale.small).foregroundStyle(t.text3.color)
        }
    }

    private func assistant(_ text: String, model: String, files: [String], calls: [EvalTranscript.Message.Call]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("assistant · \(EvalModels.short(model))").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
            highlighted(text, files: files)
                .ui(TypeScale.body).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if !calls.isEmpty {
                DisclosureGroup {
                    ForEach(Array(calls.enumerated()), id: \.offset) { _, c in
                        Text("→ \(c.function)(\(c.arguments))").ui(TypeScale.caption, mono: true).foregroundStyle(t.accentText.color).textSelection(.enabled)
                    }
                } label: { Text("\(calls.count) tool call\(calls.count == 1 ? "" : "s")").ui(TypeScale.caption).foregroundStyle(t.text2.color) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
    }

    /// File paths the answer names, in the needs tint.
    private func highlighted(_ text: String, files: [String]) -> Text {
        let names = Set(files.flatMap { [$0, ($0 as NSString).lastPathComponent] }).filter { $0.count > 3 }
        guard !names.isEmpty, let re = try? NSRegularExpression(pattern: "[\\w./+-]+\\.\\w+") else { return Text(text) }
        var out = Text(""), last = text.startIndex
        for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let r = Range(m.range, in: text) else { continue }
            let w = String(text[r])
            guard names.contains(where: { w.hasSuffix($0) || $0.hasSuffix(w) }) else { continue }
            out = out + Text(text[last..<r.lowerBound]) + Text(w).font(.system(size: TypeScale.small, design: .monospaced)).foregroundColor(t.needsText.color)
            last = r.upperBound
        }
        return out + Text(text[last...])
    }

    /// CODE CHECK (or SCORER) · GRADER · YOU.
    private func verdicts(_ s: EvalSample) -> some View {
        HStack(alignment: .top, spacing: 10) {
            box(s.code?.changed != nil || isJudged ? "Code check" : "Scorer") {
                if let c = s.code, c.verdict != "none" {
                    mark(c.isPass, c.isPass ? (c.changed != nil ? "right file" : "right") : (c.changed != nil ? "wrong file" : "wrong"))
                    if let w = c.why, !w.isEmpty { Text(w).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(4) }
                } else {
                    mark(s.isRight, s.isRight ? "right" : "wrong")
                    if let e = s.explanation { Text(e).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(4) }
                }
            }
            if let j = s.judge {
                box("Grader") {
                    mark(j.isPass, j.verdict)
                    Text(j.why.map { "\"\($0)\"" } ?? "No reason given: the grader answered with its verdict only.").ui(TypeScale.small)
                        .foregroundStyle(j.why == nil ? t.text3.color : t.text.color).lineLimit(4)
                }
            }
            box("You") {
                if let y = s.you {
                    mark(y.isPass, y.verdict)
                    if let w = y.why { Text("\"\(w)\"").ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(4) }
                } else if let ji = s.judgeItem {
                    HStack(spacing: 6) {
                        Text("Not labelled ·").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        RoofButton("P", .plain) { label(ji, "pass") }.help("Pass: writes your label for the grader")
                        RoofButton("F", .plain) { label(ji, "fail") }.help("Fail: writes your label for the grader")
                    }
                    .disabled(labelling)
                } else {
                    Text("No grader reads this test, so there is nothing to label here. Graders are made in Our tasks.")
                        .ui(TypeScale.small).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func box<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) { EvalsLabel(title); c() }
            .padding(10).frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.separator.color))
            .accessibilityElement(children: .combine)
    }
    private func mark(_ ok: Bool, _ word: String) -> some View {
        Text((ok ? "✓ " : "✕ ") + word).ui(TypeScale.body, .semibold).foregroundStyle(ok ? t.diffAddText.color : t.needsText.color)
    }

    private func label(_ ji: EvalJudgeItemRef, _ verdict: String) {
        labelling = true
        board.io.async {
            let o = EvalEngine.run(["judge", "label", ji.judge, "--item", ji.item, "--verdict", verdict, "--why", "", "--json"], timeout: 60)
            DispatchQueue.main.async {
                labelling = false
                if o.code == 0 { say("Labelled \(verdict) for \(ji.judge)"); load() } else { say("Could not label: " + o.stderr.suffix(200)) }
            }
        }
    }

    private func say(_ m: String) {
        withAnimation { toast = m }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { withAnimation { if toast == m { toast = nil } } }
    }

    // MARK: Loading

    private func load() {
        board.io.async {
            let r = EvalEngine.decode([EvalSample].self, EvalEngine.run(["samples", runID, "--json"], timeout: 300))
            DispatchQueue.main.async {
                loaded = true
                switch r {
                case .success(let xs):
                    if xs != samples { samples = xs }
                    loadError = nil
                    if selected == nil {
                        let first = start.flatMap { id in xs.first { $0.sampleID == id } } ?? EvalSample.sorted(xs, .wrongFirst).first { only?.contains($0.sampleID) ?? true }
                        if let f = first { open(f.sampleID) }
                    }
                case .failure(let e): loadError = e.message
                }
            }
        }
        if judgeItems.isEmpty, let name = judgeName {
            board.ask(["judge", "items", name], [EvalJudgeItem].self, timeout: 300) { r in
                if case .success(let xs) = r { judgeItems = Dictionary(xs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
            }
        }
        if let o = other, otherSamples.isEmpty {
            board.io.async {
                let r = EvalEngine.decode([EvalSample].self, EvalEngine.run(["samples", o, "--json"], timeout: 300))
                DispatchQueue.main.async { if case .success(let xs) = r { otherSamples = Dictionary(xs.map { ($0.sampleID, $0) }, uniquingKeysWith: { a, _ in a }) } }
            }
        }
    }

    private func open(_ id: String) {
        guard selected != id || transcript == nil else { return }
        selected = id
        epoch = samples.filter { $0.sampleID == id }.map(\.epoch).min() ?? 1
        fetchTranscript()
    }

    private func fetchTranscript() {
        guard let id = selected else { return }
        transcript = nil; transcriptError = nil
        let ep = epoch
        board.io.async {
            let r = EvalEngine.decode(EvalTranscript.self, EvalEngine.run(["sample", runID, id, "--epoch", String(ep), "--json"], timeout: 120))
            DispatchQueue.main.async {
                guard selected == id, epoch == ep else { return }
                switch r { case .success(let tr): transcript = tr; case .failure(let e): transcriptError = e.message }
            }
        }
    }

    /// judge_<name>_v<N> → <name>.
    private var judgeName: String? {
        let tk = result?.task ?? runID.range(of: #"judge_.+_v\d+(?=-[a-z0-9]{4}$)"#, options: .regularExpression).map { String(runID[$0]) } ?? ""
        guard tk.hasPrefix("judge_"), let r = tk.range(of: "_v", options: .backwards) else { return nil }
        return String(tk[tk.index(tk.startIndex, offsetBy: 6)..<r.lowerBound])
    }

    private func openGrader() {
        if let j = samples.first(where: { $0.judgeItem != nil })?.judgeItem?.judge ?? judgeName { nav.openGrader(j) }
    }

    private func compareWith() {
        guard let r = result else { return }
        nav.showResults(key: r.setName ?? (r.task ?? ""), compareA: r.id, kind: EvalJobKind.of(r))
    }
}
