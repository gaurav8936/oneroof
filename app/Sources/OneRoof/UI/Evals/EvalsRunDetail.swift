import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2069 · one run, question by question (Claude Design 1A-7 = HP E4.2): header with the facts, Compare with… and Run
/// again; the strip (score + range, the code-checked score, how far to trust the judge); answers with All · Wrong ·
/// Judge ≠ you; the transcript; Code check · Judge · You side by side; Label for the judge; Add to a regression set.
/// Replaces 1.9.37's EvalRunDetail (kept behind the flag): its facts, every metric with its range, the error, only-wrong,
/// the transcript with tool calls, the expected answer and every scorer's reasoning stay.
struct EvalsRunDetailPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
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
    @State private var transcript: EvalTranscript?
    @State private var adding = false
    @State private var toast: String?
    @State private var labelling = false
    @FocusState private var listFocused: Bool
    private let poll = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    private var result: EvalResult? { board.results.first { $0.id == runID } }
    private var row: EvalRunRow? { board.runs.first { $0.id == runID } }
    private var active: Bool { row?.isActive ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let r = result { strip(r) }
            if let r = result, r.status == "failed" || r.error != nil { failure(r) }
            if let msg = toast {
                Text(msg).ui(TypeScale.small, .semibold).foregroundStyle(t.onAccent.color)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(t.accent.color))
                    .padding(.horizontal, 24).padding(.top, 8)
                    .transition(.opacity)
            }
            HStack(alignment: .top, spacing: 0) {
                list.frame(width: 400)
                Rectangle().fill(t.separator.color).frame(width: 1)
                detail.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(shortcuts)
        .onAppear { load(); if result == nil { board.refreshResults() } }
        .onReceive(poll) { _ in if active { load() } }
        .sheet(isPresented: $adding) {
            EvalsAddToSetSheet(board: board, title: "Add to a regression set",
                               source: ["--from-run", runID, "--sample", selected ?? "", "--epoch", String(epoch)],
                               codeKind: result?.setName != nil || (result?.task ?? "").hasPrefix("judge_"),
                               suggested: (result?.setName ?? EvalBenchmark.taskLabel(result?.task ?? "my")) + "_regressions") { msg in
                adding = false
                if let msg { say(msg) }
            }
            .themed(t.name)
        }
    }

    // MARK: Header (breadcrumb row)

    /// Breadcrumb, then "‹ Results  task × model" with Compare with… and Run again, then the facts line (HP E4.2).
    private var header: some View {
        let r = result
        let who = r?.contestant?.name ?? r?.model ?? "?"
        return VStack(alignment: .leading, spacing: 6) {
            Text("Evals  Results › \(evalTitle) › \(who)").ui(TypeScale.caption).foregroundStyle(t.text3.color)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Button { nav.back() } label: { Text("‹ Results").ui(13, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).accessibilityLabel("Back to Results")
                Text("\(EvalBenchmark.taskLabel(r?.task ?? row?.task ?? runID)) × \(r?.agent != nil ? who : (r?.model ?? who))")
                    .ui(18, .bold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 12)
                RoofButton("Compare with…") { compareWith() }.disabled(r?.status != "done")
                    .help("Results › Compare, with this run as A")
                RoofButton("Run again") { if let r { nav.run(EvalRunPlan.again(r)) } }.disabled(r == nil)
                    .help("Run pre-filled with the same settings; the cost shows first")
            }
            Text(facts).ui(TypeScale.small).foregroundStyle(t.text2.color).lineLimit(2).padding(.leading, 82)
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }

    private var evalTitle: String {
        guard let r = result else { return "" }
        let key = r.setName.map { "\($0)@v\(r.setVersion ?? 1)" } ?? (r.task ?? "")
        let e = EvalResultsEntry.from(board.results).first { $0.key == key }
        return e.map { evalsEntryTitle($0, sets: board.sets) } ?? EvalBenchmark.taskLabel(r.task ?? "")
    }

    /// "done · 40 answers · 61,204 in / 9,870 out tokens · $0.095 · $0.004 per right answer · 3 m 12 s · seed 42 · Oct 31 20:38".
    private var facts: String {
        guard let r = result else { return row.map { "\($0.status ?? "") · \($0.progress)" } ?? "Reading…" }
        var f = [r.status ?? "?"]
        if active, let p = row?.progress { f.append("\(p) answered") } else { f.append("\(r.samplesDone ?? samples.count) answers") }
        if let i = r.inputTokens, let o = r.outputTokens, i + o > 0 { f.append("\(i.formatted()) in / \(o.formatted()) out tokens") }
        if (r.model ?? "").hasPrefix("seat/") { f.append("on your seat, no API credit") }
        else if let c = r.cost, c > 0 { f.append(String(format: "$%.3f", c)) } else if r.isFree { f.append("free") } else { f.append("cost unknown") }
        if let c = r.costPerCorrect { f.append(String(format: "$%.3f per right answer", c)) }
        if let d = r.duration { f.append(d >= 60 ? "\(Int(d) / 60) m \(Int(d) % 60) s" : String(format: "%.0f s", d)) }
        if let s = r.seed { f.append("seed \(s)") }
        if let v = r.inspectEvals { f.append("inspect-evals \(v)") }
        f.append(EvalModels.when(r.started))
        return f.joined(separator: " · ")
    }

    // MARK: Strip (HP FactsStrip)

    private var judged: Bool { result?.judgeAgreement != nil || samples.contains { $0.judge != nil } }

    private func strip(_ r: EvalResult) -> some View {
        HStack(alignment: .top, spacing: 0) {
            cell { mainScore(r) }
            secondCell(r)
            trustCell(r)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24).padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }

    @ViewBuilder private func secondCell(_ r: EvalResult) -> some View {
        if judged, let code = codeScore {
            divider
            cell {
                EvalsLabel("Files named · checked by code")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(evalsPct(Double(code.right) / Double(max(code.of, 1)))).ui(26, .bold).foregroundStyle(t.text.color)
                    Text("\(code.right) of \(code.of)").ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
            }
        } else if r.metrics.filter({ $0.value != nil }).count > 1 {
            divider
            cell {
                EvalsLabel("Every metric")
                ForEach(Array(r.metrics.dropFirst().prefix(4).enumerated()), id: \.offset) { _, m in
                    Text(metricLine(m)).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color).lineLimit(1)
                }
            }
        }
    }

    private func metricLine(_ m: EvalMetric) -> String {
        let v = m.value.map { evalFormat($0, m) } ?? "n/a"
        let r = rangeText(m)
        return "\(m.label) \(v)" + (r.isEmpty ? "" : " · 95 % " + r)
    }

    @ViewBuilder private func trustCell(_ r: EvalResult) -> some View {
        if let a = r.judgeAgreement {
            let line = EvalTrustLine.text(a)
            divider
            cell {
                Text(line.heading.uppercased()).ui(10.5, .semibold).tracking(0.6).foregroundStyle(line.trusted ? t.text3.color : t.needsText.color)
                (Text(line.body + " ") + Text("Judge ›").foregroundStyle(t.accentText.color))
                    .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    .onTapGesture { openJudge() }
                    .evalHover(.agreement, EvalHover.agreement(a))
            }
        } else if judged {
            divider
            cell {
                EvalsLabel("How far to trust the judge")
                Text("This judge has not been measured against your labels yet. Label answers to find out.").ui(TypeScale.small).foregroundStyle(t.needsText.color)
            }
        }
    }

    private func openJudge() {
        if let j = samples.first(where: { $0.judgeItem != nil })?.judgeItem?.judge { nav.route = .judge(name: j, first: nil) }
    }

    @ViewBuilder private func mainScore(_ r: EvalResult) -> some View {
        EvalsLabel(judged ? "Judged score" : (r.primary?.label ?? "Score"))
        if let p = r.primary, let v = p.value {
            HStack(alignment: .center, spacing: 14) {
                Text(evalFormat(v, p)).ui(26, .bold).foregroundStyle(t.text.color).fixedSize()
                    .evalHover(p.label.contains("pass") ? .passK : .score,
                               p.label.contains("pass") ? "\(evalsPct(v)) of the questions passed with at least one of the attempts." : EvalHover.score(score: v, n: p.n))
                if p.ciMethod == "wilson" {
                    EvalsRangeBar(value: v, lo: p.ci95?.first, hi: p.ci95?.last, small: EvalStats.isSmall(p.n)).frame(maxWidth: 160)
                        .evalHover(.range, EvalHover.range(score: v, n: p.n ?? 0, lo: p.ci95?.first ?? v, hi: p.ci95?.last ?? v))
                }
                Text(rangeText(p)).ui(TypeScale.small).foregroundStyle(t.text2.color)
                    .evalHoverIf(p.ciMethod == "wilson" ? nil : (.stderr, "The range comes from the standard error: score ± about 2 standard errors."))
            }
            Text("n = \(p.n ?? 0)" + (EvalStats.isSmall(p.n) ? " · fewer than 30: a wide range" : ""))
                .ui(TypeScale.caption).foregroundStyle(EvalStats.isSmall(p.n) ? t.needsText.color : t.text3.color)
                .evalHover(.n, "\(p.n ?? 0) answers." + (EvalStats.isSmall(p.n) ? " Under 30, One Roof marks the range as wide." : " Enough for a range you can read."))
        } else {
            Text(active ? "running" : "–").ui(26, .bold).foregroundStyle(t.text2.color)
        }
    }

    private func rangeText(_ p: EvalMetric) -> String {
        guard let c = p.ci95, c.count == 2, c[0] != c[1] else { return "" }   // no range computed: none shown
        return p.ciMethod == "wilson" ? String(format: "%.0f–%.0f %%", c[0] * 100, c[1] * 100) : String(format: "%.3f–%.3f", c[0], c[1])
    }

    private var divider: some View { Rectangle().fill(t.separator.color).frame(width: 1).padding(.vertical, -10) }
    private func cell<C: View>(@ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { c() }.padding(.horizontal, 16).frame(maxWidth: .infinity, alignment: .leading)
    }
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
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }

    // MARK: List (left, 400 pt)

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
                if judged { chip(.disagree, "Judge ≠ you \(c.disagree)") }
                Spacer()
                Menu {
                    ForEach(EvalSample.Sort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
                } label: { Text("Sort ▾").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            }
            if let o = only { Text("\(o.count) cases where the two runs disagree" + (other != nil ? "; B's answer is shown beside A's" : "")).ui(TypeScale.caption).foregroundStyle(t.text3.color) }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { s in answerRow(s).id(s.id) }
                        if shown.isEmpty {
                            Text(loadError ?? (loaded ? "Nothing here." : "Reading…")).ui(TypeScale.small)
                                .foregroundStyle(loadError == nil ? t.text3.color : t.needsText.color).padding(8)
                        }
                    }
                }
                .onChange(of: selected) { _, id in if let s = samples.first(where: { $0.sampleID == id }) { proxy.scrollTo(s.id) } }
            }
        }
        .padding(14)
        .focusable().focused($listFocused).focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1); return .handled }
        .onKeyPress(.downArrow) { step(1); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "wW")) { _ in filter = filter == .wrong ? .all : .wrong; return .handled }
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
            HStack(alignment: .top, spacing: 8) {
                Text(s.isRight ? "✓" : "✕").ui(TypeScale.body, .semibold).foregroundStyle(s.isRight ? t.diffAddText.color : t.needsText.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.title ?? s.input ?? s.sampleID).ui(TypeScale.body).foregroundStyle(t.text.color).lineLimit(2)
                    Text(s.summary).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).lineLimit(2)
                }
                Spacer(minLength: 4)
                if s.disagree == true { Text("judge ≠ you").ui(TypeScale.caption).foregroundStyle(t.needsText.color) }
                else if s.judgeItem != nil && s.labelled != true { Text("unlabelled").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.surface.color : .clear)
                .shadow(color: on ? .black.opacity(0.08) : .clear, radius: 3, y: 1))
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
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text([s.issue, s.title].compactMap { $0 }.joined(separator: " · ").isEmpty ? s.sampleID : [s.issue, s.title].compactMap { $0 }.joined(separator: " · "))
                            .ui(TypeScale.section, .semibold).foregroundStyle(t.text.color).lineLimit(2)
                        Spacer()
                        if let ji = s.judgeItem {
                            RoofButton("Label for the judge") { nav.route = .judge(name: ji.judge, first: ji.item) }
                                .help("The judge screen, with this answer first in the queue")
                        }
                        RoofButton("Add to a regression set") { adding = true }.disabled(result == nil)
                    }
                    let attempts = samples.filter { $0.sampleID == id }.map(\.epoch).sorted()
                    if attempts.count > 1 {
                        Segmented(options: attempts.map { ($0, "attempt \($0)") }, selection: Binding(get: { epoch }, set: { epoch = $0; fetchTranscript() }))
                    }
                    transcriptView(s)
                    verdicts(s)
                    if let tk = s.takeaway { Text(tk).ui(TypeScale.small).foregroundStyle(t.text2.color) }
                    if let b = otherSamples[id] {
                        Text("B's answer: \(b.answer ?? "–") " + (b.isRight ? "✓" : "✕")).ui(TypeScale.small, mono: true)
                            .foregroundStyle(b.isRight ? t.diffAddText.color : t.needsText.color)
                    }
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
                }
                .padding(24)
            }
        } else {
            Text(samples.isEmpty ? (loadError ?? (loaded ? "This run has no answers yet." : "Reading…")) : "Pick an answer on the left.")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }

    @State private var epoch = 1
    private func attempt(_ id: String) -> EvalSample? {
        samples.first { $0.sampleID == id && $0.epoch == epoch } ?? samples.first { $0.sampleID == id }
    }

    /// system, user (long inputs folded), assistant in a card with the files it names highlighted, tool calls folded.
    @ViewBuilder private func transcriptView(_ s: EvalSample) -> some View {
        if let ji = s.judgeItem, judgeName != nil, let item = judgeItems[ji.item] {
            // A judge run: what was judged (the report and the answer), then the judge's own reply, folded.
            EvalsFoldedMessage(role: "user", text: item.report, calls: [])
            VStack(alignment: .leading, spacing: 5) {
                Text("assistant · \(EvalModels.short(item.model ?? "the answering model"))").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                highlighted(item.answer, files: (s.code?.named ?? []) + (s.code?.changed ?? []))
                    .ui(TypeScale.body).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface.color))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.separator.color))
            if let tr = transcript, tr.id == s.sampleID {
                DisclosureGroup {
                    ForEach(Array(tr.messages.enumerated()), id: \.offset) { _, m in EvalsFoldedMessage(role: m.role, text: m.text, calls: m.toolCalls) }
                } label: { Text("The judge's prompt and reply (\(EvalModels.short(result?.model ?? "")))").ui(TypeScale.small).foregroundStyle(t.text2.color) }
            }
        } else if let tr = transcript, tr.id == s.sampleID {
            ForEach(Array(tr.messages.enumerated()), id: \.offset) { _, m in
                if m.role == "assistant" {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("assistant · \(EvalModels.short(result?.model ?? ""))").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                        highlighted(m.text, files: (s.code?.named ?? []) + (s.code?.changed ?? []))
                            .ui(TypeScale.body).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if !m.toolCalls.isEmpty {
                            DisclosureGroup {
                                ForEach(Array(m.toolCalls.enumerated()), id: \.offset) { _, c in
                                    Text("→ \(c.function)(\(c.arguments))").ui(TypeScale.caption, mono: true).foregroundStyle(t.accentText.color).textSelection(.enabled)
                                }
                            } label: { Text("\(m.toolCalls.count) tool call\(m.toolCalls.count == 1 ? "" : "s")").ui(TypeScale.caption).foregroundStyle(t.text2.color) }
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface.color))
                    .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.separator.color))
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

    /// File paths the answer names, in the needs tint (HP: "file named highlighted").
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

    /// CODE CHECK (or SCORER) · JUDGE · YOU (HP VerdictTriple).
    private func verdicts(_ s: EvalSample) -> some View {
        HStack(alignment: .top, spacing: 10) {
            box(s.code?.changed != nil || judged ? "Code check" : "Scorer") {
                if let c = s.code, c.verdict != "none" {
                    mark(c.isPass, c.isPass ? (c.changed != nil ? "right file" : "right") : (c.changed != nil ? "wrong file" : "wrong"))
                    if let w = c.why, !w.isEmpty { Text(w).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(4) }
                } else {
                    mark(s.isRight, s.isRight ? "right" : "wrong")
                    if let e = s.explanation { Text(e).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(4) }
                }
            }
            if let j = s.judge {
                box("Judge") {
                    mark(j.isPass, j.verdict)
                    Text(j.why.map { "\"\($0)\"" } ?? "No reason given: the judge answered with its verdict only.").ui(TypeScale.small)
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
                        RoofButton("P", .plain) { label(ji, "pass") }.help("Pass: writes your label for the judge")
                        RoofButton("F", .plain) { label(ji, "fail") }.help("Fail: writes your label for the judge")
                    }
                    .disabled(labelling)
                } else {
                    Text("No judge reads this run, so there is nothing to label here. Judges are made in Your evals.")
                        .ui(TypeScale.small).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func box<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) { EvalsLabel(title); c() }
            .padding(10).frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
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

    @State private var transcriptError: String?
    @State private var judgeItems: [String: EvalJudgeItem] = [:]

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
        // The task, or the run id before the results arrive ("20261031-203836-judge_oneroof_triage_v1-oepe").
        let t = result?.task ?? runID.range(of: #"judge_.+_v\d+(?=-[a-z0-9]{4}$)"#, options: .regularExpression).map { String(runID[$0]) } ?? ""
        guard t.hasPrefix("judge_"), let r = t.range(of: "_v", options: .backwards) else { return nil }
        return String(t[t.index(t.startIndex, offsetBy: 6)..<r.lowerBound])
    }

    private func compareWith() {
        guard let r = result else { return }
        nav.showResults(key: r.setName.map { "\($0)@v\(r.setVersion ?? 1)" } ?? (r.task ?? ""), compareA: r.id)
    }

    /// ⌘[ back is the shell's; W and ↑/↓ act on the list when it has focus.
    private var shortcuts: some View { EmptyView() }
}

/// A system or user message: the source-file list a set's question carries is folded ("+ 214 source paths").
struct EvalsFoldedMessage: View {
    let role: String
    let text: String
    let calls: [EvalTranscript.Message.Call]
    @Environment(\.theme) private var t
    @State private var open = false
    var body: some View {
        let parts = text.components(separatedBy: "\n\nSource files:\n")
        let paths = parts.count > 1 ? parts[1].split(separator: "\n").count : 0
        let long = parts[0].count > 700
        VStack(alignment: .leading, spacing: 3) {
            Text(role).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
            Text(open || !long ? parts[0] : String(parts[0].prefix(700)) + " …").ui(TypeScale.body).foregroundStyle(t.text.color)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if paths > 0 || long {
                Button { open.toggle() } label: {
                    Text(open ? "fold" : (paths > 0 ? "+ \(paths) source paths" : "show all")).ui(TypeScale.small).foregroundStyle(t.text3.color)
                }.buttonStyle(.plain)
            }
            if open && paths > 0 {
                Text(parts[1]).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).textSelection(.enabled).lineLimit(400)
            }
            ForEach(Array(calls.enumerated()), id: \.offset) { _, c in
                Text("→ \(c.function)(\(c.arguments))").ui(TypeScale.caption, mono: true).foregroundStyle(t.accentText.color)
            }
        }
    }
}

/// Add one answered question to a set (HP EV-11): into the next version of a set of the same kind, never a frozen one,
/// or a new set. Used by one run (Add to a regression set) and Explore › Questions (Add to an eval set).
struct EvalsAddToSetSheet: View {
    @ObservedObject var board: EvalsBoard
    let title: String
    /// ["--from-run", RUN, "--sample", ID] or ["--from-task", TASK, "--sample", ID].
    let source: [String]
    /// A fix-locator or triage case (goes with those sets); otherwise a plain question (goes into a set of questions).
    let codeKind: Bool
    let suggested: String
    var done: (String?) -> Void
    @Environment(\.theme) private var t
    @State private var name = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        let fits = board.sets.filter { ($0.kind == "fix-locator" || $0.kind == "triage") == codeKind }
        VStack(alignment: .leading, spacing: 12) {
            Text(title).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            Text("It goes into the next version of a set, never into a frozen one, so old scores stay comparable.")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            ForEach(fits) { s in
                HStack {
                    Text("\(s.title) · \(s.name)").ui(TypeScale.body).foregroundStyle(t.text.color)
                    Spacer()
                    Text("into v\(s.version + 1)").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                    RoofButton("Add") { add([s.name]) }.disabled(working)
                }
            }
            if fits.isEmpty {
                Text(codeKind ? "No set of this kind yet: make a new one." : "No set of questions yet: make a new one.")
                    .ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
            HStack {
                TextField("new set name", text: $name).textFieldStyle(.roundedBorder).frame(width: 260)
                RoofButton("New set", .primary) { add(["--new", name]) }
                    .disabled(working || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true) }
            HStack { Spacer(); RoofButton("Close") { done(nil) }.keyboardShortcut(.cancelAction) }
        }
        .padding(22).frame(width: 520).background(t.surface.color)
        .onAppear { name = suggested; error = nil }
    }

    private func add(_ target: [String]) {
        working = true
        board.ask(["evalset", "add"] + target + source, EvalSetAddResult.self, timeout: 300) { r in
            working = false
            switch r {
            case .success(let a): board.refreshOwn(); done(a.message)
            case .failure(let e): error = e.message
            }
        }
    }
}
