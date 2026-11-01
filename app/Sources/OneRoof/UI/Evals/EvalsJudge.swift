import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2066 · Your evals › <judge> (Claude Design 1A-4 = HP E2.2): label answers with the keyboard (P pass, F fail,
/// S skip, ↑/↓, Tab to Why, Return saves, ⌘Z takes the last label back), and see how far to trust the judge, measured
/// from its last run against your labels as they are now. Labels are yours (source "owner"); a model's labels are shown
/// as that model's and never count as you.
struct EvalsJudgePage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let name: String
    var first: String?
    @Environment(\.theme) private var t
    @State private var tab: Tab = .label
    @State private var items: [EvalJudgeItem] = []
    @State private var queue: EvalJudgeQueue?
    @State private var trust: EvalJudgeTrust?
    @State private var advice: [String] = []
    @State private var versions: EvalJudgeVersions?
    @State private var selected: String?
    @State private var why = ""
    @State private var error: String?
    @State private var saving = false
    @State private var rubricDraft = ""
    @State private var cell: [String]?
    @FocusState private var queueFocused: Bool
    @FocusState private var whyFocused: Bool

    enum Tab: String, CaseIterable { case label = "Label", rubric = "Rubric", agreement = "Agreement", versions = "Versions" }

    private var judge: EvalJudgeList.Judge? { board.judges.first { $0.name == name } }
    private var current: EvalJudgeItem? { items.first { $0.id == selected } }
    private var pairwise: Bool { judge?.mode == "pairwise" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EvalsDrillHeader(crumb: "Evals  Your evals › \(title)", back: "Your evals", title: title, meta: meta, onBack: { nav.back() }) {
                EvalsTextTabs(options: Tab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
            }
            if EvalsDraft.isDraft { EvalsDraftBanner().padding(.horizontal, 20).padding(.top, 10) }
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).padding(.horizontal, 20).padding(.top, 8) }
            switch tab {
            case .label: labelTab
            case .rubric: rubricTab
            case .agreement: agreementTab
            case .versions: versionsTab
            }
        }
        .onAppear { reload(); if let f = first { selected = f } }
    }

    private var title: String { name.replacingOccurrences(of: "_", with: " ") + " judge" }
    private var meta: String {
        var m: [String] = []
        if let j = judge { m.append(j.mode == "pairwise" ? "compares two runs' answers" : "grades \(j.items) prose answers") }
        if let jm = trust?.judgeModel { m.append("judge model " + EvalModels.short(jm)) }
        if let v = versions?.versions.last?.version ?? trust?.version { m.append("v\(v)") }
        return m.joined(separator: " · ")
    }

    // MARK: Engine

    private func reload() {
        board.ask(["judge", "items", name], [EvalJudgeItem].self, timeout: 300) { r in
            switch r { case .success(let x): items = x; case .failure(let e): error = e.message }
        }
        board.ask(["judge", "queue", name] + (first.map { ["--first", $0] } ?? []), EvalJudgeQueue.self, timeout: 300) { r in
            if case .success(let q) = r { queue = q; if selected == nil || !q.queue.contains(where: { $0.id == selected }) && current?.mine == nil { selected = q.queue.first?.id } }
        }
        refreshTrust()
        board.ask(["judge", "versions", name], EvalJudgeVersions.self) { r in
            if case .success(let v) = r { versions = v; if rubricDraft.isEmpty { rubricDraft = v.draft ?? judge?.rubric ?? "" } }
        }
    }

    private func refreshTrust() {
        board.ask(["judge", "trust", name], EvalJudgeTrust.self, timeout: 300) { if case .success(let tr) = $0 { trust = tr } }
        board.ask(["judge", "advise", name], EvalAdvice.self, timeout: 300) { if case .success(let a) = $0 { advice = a.advice } }
    }

    /// Writes through judge.py (source "owner"), moves to the next answer, re-measures without a new judge run.
    private func label(_ verdict: String) {
        guard let x = current, !saving else { return }
        saving = true
        let next = nextID(after: x.id)
        board.ask(["judge", "label", name, "--item", x.id, "--verdict", verdict, "--why", why], EvalLabelAck.self) { r in
            saving = false
            switch r {
            case .success: why = ""; selected = next; reload()
            case .failure(let e): error = e.message
            }
        }
    }

    private func undo() {
        board.ask(["judge", "label", name, "--undo"], EvalLabelAck.self) { r in
            if case .success(let a) = r { selected = a.item; reload() }
        }
    }

    private func nextID(after id: String) -> String? {
        let q = (queue?.queue ?? []).map(\.id).filter { $0 != id }
        return q.first
    }

    private func move(_ d: Int) {
        let order = (queue?.queue ?? []).map(\.id) + labelled.map(\.id)
        guard !order.isEmpty else { return }
        let i = order.firstIndex(of: selected ?? "") ?? 0
        selected = order[min(max(i + d, 0), order.count - 1)]
    }

    private var labelled: [EvalJudgeItem] { items.filter { $0.mine != nil } }

    // MARK: Label tab (three columns)

    private var labelTab: some View {
        HStack(alignment: .top, spacing: 0) {
            queueColumn.frame(width: 250).background(t.sidebar.color)
            Rectangle().fill(t.separator.color).frame(width: 1)
            ScrollView { middle.padding(20).frame(maxWidth: 760, alignment: .leading) }.frame(maxWidth: .infinity)
            Rectangle().fill(t.separator.color).frame(width: 1)
            trustColumn.frame(width: 300)
        }
    }

    private var queueColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("To label").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    Text("\(queue?.labelled ?? 0) of \(queue?.total ?? items.count) done").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                }
                ProgressView(value: Double(queue?.labelled ?? 0), total: Double(max(queue?.total ?? 1, 1))).tint(t.accent.color)
            }
            .padding(12)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(queue?.queue ?? []) { x in queueRow(x) }
                    if !labelled.isEmpty {
                        HStack {
                            EvalsLabel("Labelled · \(labelled.count)")
                            Spacer()
                            Button("Undo last ⌘Z") { undo() }.buttonStyle(.plain).font(.system(size: TypeScale.caption))
                                .foregroundStyle(t.accentText.color).accessibilityLabel("Take back your last label")
                        }
                        .padding(.top, 10).padding(.horizontal, 6)
                        ForEach(labelled) { x in labelledRow(x) }
                    }
                }
                .padding(.horizontal, 6)
            }
            .focusable().focused($queueFocused).focusEffectDisabled()
            .onKeyPress(characters: .letters) { k in key(k.characters, command: k.modifiers.contains(.command)) }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.tab) { whyFocused = true; return .handled }
            Rectangle().fill(t.separator.color).frame(height: 1)
            Text("Your first 10 labels become the judge's examples. The rest are held back to measure it.")
                .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).padding(12)
        }
        .onAppear { queueFocused = true }
    }

    private func key(_ chars: String, command: Bool) -> KeyPress.Result {
        guard let a = EvalLabelKey.action(chars, command: command, pairwise: pairwise, typing: whyFocused) else { return .ignored }
        switch a {
        case .undo: undo()
        case .skip: if let x = current { selected = nextID(after: x.id) }
        case .previous: move(-1)
        case .next: move(1)
        default: if let v = a.verdict { label(v) }
        }
        return .handled
    }

    private func queueRow(_ x: EvalJudgeItem) -> some View {
        let on = x.id == selected
        return Button { selected = x.id; queueFocused = true } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(x.issue.isEmpty ? x.id : x.issue).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                    Spacer()
                    Text(shortModel(x.model)).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
                Text(x.title).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1)
            }
            .padding(8).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.surface.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(x.issue) \(x.title), answered by \(shortModel(x.model))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func labelledRow(_ x: EvalJudgeItem) -> some View {
        let v = x.mine?.verdict ?? ""
        return Button { selected = x.id } label: {
            HStack(spacing: 6) {
                Text(v).ui(TypeScale.small, .semibold).foregroundStyle(v == "pass" ? t.diffAddText.color : t.needsText.color).frame(width: 32, alignment: .leading)
                Text(x.title).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1)
                Spacer()
                Text(x.split).ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
            .padding(.vertical, 5).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(x.id == selected ? t.surface.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(v), \(x.title), \(x.split)")
    }

    private func shortModel(_ m: String?) -> String {
        let s = EvalModels.short(m ?? "")
        return s.replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: "-5-5", with: "")
    }

    @ViewBuilder private var middle: some View {
        if let x = current {
            VStack(alignment: .leading, spacing: 12) {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        EvalsLabel("Bug report" + (x.issue.isEmpty ? "" : " · " + x.issue))
                        Text(x.report).ui(TypeScale.body).foregroundStyle(t.text.color).textSelection(.enabled).lineLimit(14)
                            .fixedSize(horizontal: false, vertical: true)
                        if !x.changed.isEmpty {
                            (Text("The fix changed ") + Text(x.changed.joined(separator: ", ")).font(.system(size: 11.5, design: .monospaced)))
                                .ui(TypeScale.caption).foregroundStyle(t.text2.color)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            EvalsLabel("Answer · " + EvalModels.short(x.model ?? "?"))
                            Spacer()
                            if let c = x.codeLine { Text(c).ui(TypeScale.caption).foregroundStyle(t.text2.color) }
                        }
                        Text(highlighted(x)).ui(TypeScale.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        if let m = x.labels["model"] {
                            Text("\(EvalModels.short(m.by ?? "a model"))'s label: \(m.verdict)" + ((m.why ?? "").isEmpty ? "" : " — \(m.why!)"))
                                .ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(2)
                        }
                        if let j = x.judge { Text("The judge said \(j) in its last run.").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        EvalsLabel("Rubric")
                        Text(judge?.rubric ?? "").ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let mine = x.mine {
                    Text("Your label: \(mine.verdict)" + ((mine.why ?? "").isEmpty ? "" : " — \(mine.why!)") + ". Label again to change it; ⌘Z takes back your last label.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
                actions
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text(items.isEmpty ? "Reading the answers…" : "Every answer is labelled.").ui(TypeScale.body).foregroundStyle(t.text2.color)
            }
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if pairwise {
                verdictButton("A better  A", "a", t.accent)
                verdictButton("B better  B", "b", t.accent)
                verdictButton("Tie  T", "tie", t.text2)
            } else {
                verdictButton("Pass  P", "pass", t.diffAddText)
                verdictButton("Fail  F", "fail", t.needsText)
            }
            TextField("Why? (one line, the judge learns from it)", text: $why).textFieldStyle(.roundedBorder).focused($whyFocused)
                .onSubmit { whyFocused = false; queueFocused = true }
            Button("Skip  S") { if let x = current { selected = nextID(after: x.id) } }.buttonStyle(.plain)
                .font(.system(size: TypeScale.small)).foregroundStyle(t.text2.color)
        }
    }

    private func verdictButton(_ title: String, _ v: String, _ fill: RGB) -> some View {
        Button { label(v) } label: {
            Text(title).ui(TypeScale.small, .semibold).foregroundStyle(t.onAccent.color)
                .padding(.vertical, 6).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(fill.color))
        }
        .buttonStyle(PressStyle()).disabled(saving)
        .accessibilityLabel(title)
    }

    /// The answer with the files it names highlighted (right ones in the selection colour).
    private func highlighted(_ x: EvalJudgeItem) -> AttributedString {
        var a = AttributedString(x.answer)
        a.foregroundColor = t.text.color
        for f in x.code?.named ?? [] {
            var from = a.startIndex
            while let r = a[from...].range(of: f) {
                a[r].font = .system(size: 12.5, design: .monospaced)
                if x.code?.hits.contains(f) == true { a[r].backgroundColor = t.selection.color }
                from = r.upperBound
            }
        }
        return a
    }

    // MARK: Trust column

    private var trustColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How far to trust it").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
            if let tr = trust {
                if tr.run == nil {
                    Text(tr.reading).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    RoofButton("Run the judge to measure it ›") { runJudge() }
                } else {
                    HStack(spacing: 8) {
                        tile("Agrees", EvalJudgeTrust.pct(tr.agreement), "n = \(tr.n)", EvalJudgeTrust.weak(tr.agreement))
                        tile("Passes good", EvalJudgeTrust.pct(tr.tpr), "of \(tr.labelPass ?? 0)", EvalJudgeTrust.weak(tr.tpr))
                        tile("Fails bad", EvalJudgeTrust.pct(tr.tnr), "of \(tr.labelFail ?? 0)", EvalJudgeTrust.weak(tr.tnr))
                    }
                    if tr.reference != "you" {
                        Text("Measured against the model's labels, not yours, until 10 of yours are held back.")
                            .ui(TypeScale.caption).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                    }
                    Text(tr.tooFew ? tr.reading.replacingOccurrences(of: " Too few of your labels to trust: label \(max(10 - (tr.heldBackYours ?? 0), 1)) more.", with: "") : tr.reading)
                        .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                }
                if tr.tooFew {
                    Text("Too few labels to trust: label \(max(10 - (tr.heldBackYours ?? 0), 1)) more.")
                        .ui(TypeScale.small, .semibold).foregroundStyle(t.statusColor(.needsYou).color)
                }
                Rectangle().fill(t.separator.color).frame(height: 1)
                Text("What would help").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                ForEach(advice, id: \.self) { Text($0).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                Rectangle().fill(t.separator.color).frame(height: 1)
                Text("Also checked").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                Text((tr.selfPreference.map { "Self-preference: " + $0 + "." } ?? "Self-preference: the judge didn't write any of these answers.")
                     + (pairwise ? "" : " Pairwise position bias: n/a, single grading."))
                    .ui(TypeScale.small).foregroundStyle(tr.selfPreference == nil ? t.text2.color : t.needsText.color).fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Reading…").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
            Spacer()
            RoofButton("Rebuild judge as v\((versions?.versions.last?.version ?? 1) + 1)") { rebuild() }
                .help("Your labels become its examples; a new version, the old one and its results stay as they are")
        }
        .padding(16)
    }

    private func tile(_ label: String, _ value: String, _ sub: String, _ weak: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).ui(9.5, .semibold).foregroundStyle(weak ? t.needsText.color : t.text3.color)
            Text(value).ui(20, .bold).foregroundStyle(weak ? t.needsText.color : t.text.color)
            Text(sub).ui(TypeScale.caption).foregroundStyle(t.text2.color)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(weak ? t.needsText.color : t.separator.color))
        .accessibilityElement(children: .combine)
    }

    private func rebuild() {
        board.ask(["judge", "build", name], EvalJudgeBuilt.self, timeout: 300) { r in
            switch r {
            case .success(let b): error = nil; reload(); if b.new { tab = .versions }
            case .failure(let e): error = e.message
            }
        }
    }

    private func runJudge() {
        guard let tf = judge?.taskFile else { rebuild(); return }
        nav.run(EvalRunPlan(tasks: [tf], models: [], limit: items.count))
    }

    // MARK: Rubric · Agreement · Versions

    private var rubricTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saving makes a draft for the next version; v\(versions?.versions.last?.version ?? 1) stays frozen. Rebuild to use it.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                TextEditor(text: $rubricDraft).font(.system(size: 13)).frame(height: 140)
                    .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(t.separator.color))
                HStack {
                    RoofButton("Save draft", .primary) {
                        board.ask(["judge", "rubric", name, "--set", rubricDraft], EvalRubric.self) { r in
                            if case .failure(let e) = r { error = e.message } else { reload() }
                        }
                    }
                    .disabled(rubricDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    if versions?.draft != nil { Text("Draft saved for v\((versions?.versions.last?.version ?? 1) + 1).").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                }
                if let cur = judge?.rubric, let d = versions?.draft, d != cur {
                    HStack(alignment: .top, spacing: 12) {
                        diffBox("Now (v\(versions?.versions.last?.version ?? 1))", cur)
                        diffBox("Draft", d)
                    }
                }
            }
            .padding(20).frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func diffBox(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            EvalsLabel(title)
            Text(text).ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.surface2.color))
    }

    private var agreementTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("On answers the judge never saw as examples, from its last run. Ranges are 95 % (Wilson).")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                ForEach([("owner", "You"), ("model", "A model's labels"), ("code", "Code (named a changed file)")], id: \.0) { src, label in
                    let c = EvalJudgeConfusion.from(items, source: src)
                    if c.n > 0 { agreementBlock(label, c) }
                }
                if let ids = cell {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            EvalsLabel("Those answers")
                            ForEach(items.filter { ids.contains($0.id) }) { x in
                                Button { selected = x.id; tab = .label } label: {
                                    Text("\(x.issue) · \(x.title)").ui(TypeScale.small).foregroundStyle(t.accentText.color).lineLimit(1)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(20).frame(maxWidth: 900, alignment: .leading)
        }
    }

    private func agreementBlock(_ label: String, _ c: EvalJudgeConfusion) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(label).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                HStack(spacing: 20) {
                    rate("Agrees", c.agreement, c.n)
                    rate("Passes good", c.tpr, c.judgePassLabelPass.count + c.judgeFailLabelPass.count)
                    rate("Fails bad", c.tnr, c.judgeFailLabelFail.count + c.judgePassLabelFail.count)
                }
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                    GridRow { Text(""); EvalsLabel("Label pass"); EvalsLabel("Label fail") }
                    GridRow { EvalsLabel("Judge pass"); cellButton(c.judgePassLabelPass, good: true); cellButton(c.judgePassLabelFail, good: false) }
                    GridRow { EvalsLabel("Judge fail"); cellButton(c.judgeFailLabelPass, good: false); cellButton(c.judgeFailLabelFail, good: true) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rate(_ label: String, _ v: Double?, _ n: Int) -> some View {
        let (lo, hi) = v.map { EvalStats.wilson($0, n: n) } ?? (0, 0)
        return VStack(alignment: .leading, spacing: 2) {
            EvalsLabel(label)
            Text(EvalJudgeTrust.pct(v)).ui(TypeScale.body, .semibold, mono: true).foregroundStyle(EvalJudgeTrust.weak(v) ? t.needsText.color : t.text.color)
            Text(v == nil ? "n = 0" : "n = \(n) · \(evalsPct(lo))–\(evalsPct(hi))").ui(TypeScale.caption).foregroundStyle(t.text2.color)
        }
    }

    private func cellButton(_ ids: [String], good: Bool) -> some View {
        Button { cell = ids } label: {
            Text("\(ids.count)").ui(TypeScale.body, .semibold, mono: true).foregroundStyle(good ? t.diffAddText.color : t.needsText.color)
                .frame(width: 70, alignment: .leading)
        }
        .buttonStyle(.plain).disabled(ids.isEmpty)
    }

    private var versionsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(versions?.versions ?? []) { v in
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("v\(v.version)").ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color)
                                Text("\(v.examples ?? 0) examples (\(v.examplesFrom == "owner" ? "yours" : "a model's")) · \(v.heldOut ?? 0) held back · used by \(v.runs) runs"
                                     + (v.agreement.map { " · agrees \(evalsPct($0))" } ?? ""))
                                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                                Spacer()
                                Text(EvalModels.when(v.built)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                            }
                            Text(v.rubric ?? "").ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let d = versions?.draft {
                    Text("Draft for v\((versions?.versions.last?.version ?? 0) + 1): \(d)").ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
            }
            .padding(20).frame(maxWidth: 900, alignment: .leading)
        }
    }
}

private struct EvalAdvice: Decodable { var advice: [String] }
private struct EvalLabelAck: Decodable { var item: String }
private struct EvalRubric: Decodable { var current: String; var draft: String? }
private struct EvalJudgeBuilt: Decodable { var version: Int; var new: Bool; var taskFile: String }
