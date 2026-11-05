import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E5.3 Check the grader (screen lane B): can we trust the model that marks the notes? Three trust tiles
/// (agrees · passes good · fails bad, measured on held-back labels) and the verdict ("Not trusted yet" until both rates
/// reach 70 % and 10 of your own labels are held back; a model's labels never count as yours); then 2.0.3's judge page,
/// every feature kept: Label (P good · F bad · S skip, ↑/↓, Tab to Why, Return saves, ⌘Z undo), the rule it grades by
/// (Rule: draft for the next version, diff), Agreement (judge × each label source, click a cell for its answers),
/// Versions, Rebuild grader as vN, what would help, also checked. Route `.grader(name:first:)`; nil = the first grader.
/// Engine: `judge items|queue|label|trust|advise|rubric|versions|build`.
struct EvalsGraderView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let name: String?
    var first: String?
    @Environment(\.theme) private var t

    var body: some View {
        if let n = name ?? board.judges.first?.name {
            EvalsGraderPage(board: board, nav: nav, name: n, first: first)
        } else {
            Text(board.judges.isEmpty ? "No grader yet: make one from " + EvalsNewMenu.path("New grader") + "." : "Reading your graders…")
                .ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
        }
    }
}

struct EvalsGraderPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let name: String
    var first: String?
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
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

    enum Tab: String, CaseIterable { case label = "Label", rubric = "Rule", agreement = "Agreement", versions = "Versions" }

    private var judge: EvalJudgeList.Judge? { board.judges.first { $0.name == name } }
    private var current: EvalJudgeItem? { items.first { $0.id == selected } }
    private var pairwise: Bool { judge?.mode == "pairwise" }
    private var lead: CGFloat { v2 ? CGFloat(V2Layout.Bar.contentLead) : 28 }
    private var latest: Int { versions?.versions.last?.version ?? trust?.version ?? 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            titleRow.padding(.horizontal, lead)
            tiles.padding(.horizontal, lead)
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).padding(.horizontal, lead) }
            Group {
                switch tab {
                case .label: labelTab
                case .rubric: rubricTab
                case .agreement: agreementTab
                case .versions: versionsTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { reload(); if let f = first { selected = f } }
    }

    /// The task the grader studies, in plain words ("Write a useful note"), else its name.
    private var title: String {
        if let task = judge?.task, let s = board.sets.first(where: { task.hasPrefix("own_\($0.name)_v") }) {
            let full = EvalTaskWords.title(kind: s.kind)
            return s.kind == "triage" ? "Write a useful note" : full
        }
        return name.replacingOccurrences(of: "_", with: " ")
    }

    private var titleRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text("The grader for \"\(title)\"").ui(20, .bold).foregroundStyle(t.text.color).lineLimit(1)
                Text(EvalGraderWords.subtitle(items: judge?.items ?? items.count, model: trust?.judgeModel, version: latest, n: trust?.n ?? 0)
                     + (pairwise ? " · compares two answers" : ""))
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).lineLimit(1)
            }
            Spacer(minLength: 12)
            EvalsTextTabs(options: Tab.allCases.map { ($0, $0.rawValue) }, selection: $tab)
        }
    }

    // MARK: Trust tiles + verdict

    private var tiles: some View {
        HStack(alignment: .top, spacing: 10) {
            let tr = trust
            tile("Agrees with the labels", tr?.run == nil ? "–" : EvalJudgeTrust.pct(tr?.agreement), EvalGraderWords.ofText(tr?.agreement, tr?.n ?? 0),
                 weak: tr?.run != nil && EvalJudgeTrust.weak(tr?.agreement), good: false)
                .evalHover(.agreement, "Agrees: how often the grader marks a held-back note the way the label does (\(EvalGraderWords.ofText(tr?.agreement, tr?.n ?? 0))). Labels from: \(tr?.reference == "you" ? "you" : "another model").")
            tile("Passes good notes", tr?.run == nil ? "–" : EvalJudgeTrust.pct(tr?.tpr), EvalGraderWords.ofText(tr?.tpr, tr?.labelPass ?? 0),
                 weak: tr?.run != nil && EvalJudgeTrust.weak(tr?.tpr), good: tr?.run != nil && !EvalJudgeTrust.weak(tr?.tpr))
                .evalHover(.agreement, "Passes good: of the notes labelled good, the share the grader also passed (true positive rate).")
            tile("Fails bad notes", tr?.run == nil ? "–" : EvalJudgeTrust.pct(tr?.tnr), EvalGraderWords.ofText(tr?.tnr, tr?.labelFail ?? 0),
                 weak: tr?.run != nil && EvalJudgeTrust.weak(tr?.tnr), good: tr?.run != nil && !EvalJudgeTrust.weak(tr?.tnr))
                .evalHover(.agreement, "Fails bad: of the notes labelled bad, the share the grader also failed (true negative rate). Under 70 % it's lenient.")
            verdictTile
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func tile(_ label: String, _ value: String, _ sub: String, weak: Bool, good: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ui(TypeScale.caption).foregroundStyle(t.text2.color)
            Text(value).ui(24, .bold).foregroundStyle(weak ? t.needsText.color : good ? t.diffAddText.color : t.text.color)
            Text(sub).ui(TypeScale.caption).foregroundStyle(t.text2.color)
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .accessibilityElement(children: .combine)
    }

    private var verdictTile: some View {
        let ready = trust?.ready ?? false
        return VStack(alignment: .leading, spacing: 5) {
            Text(trust.map(EvalGraderWords.verdictTitle) ?? "Reading…").ui(TypeScale.section, .semibold)
                .foregroundStyle(ready ? t.diffAddText.color : t.needsText.color)
            if let tr = trust {
                Text(EvalGraderWords.verdictBody(tr)).ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                if tr.run == nil { RoofButton("Run the grader to measure it ›") { runJudge() } }
            }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill((ready ? t.diffAddText : t.needsText).color.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder((ready ? t.diffAddText : t.needsText).color.opacity(0.35)))
        .accessibilityElement(children: .combine)
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

    /// Writes through judge.py (source "owner"), moves to the next note, re-measures without a new grader run.
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

    private func nextID(after id: String) -> String? { (queue?.queue ?? []).map(\.id).filter { $0 != id }.first }

    private func move(_ d: Int) {
        let order = (queue?.queue ?? []).map(\.id) + labelled.map(\.id)
        guard !order.isEmpty else { return }
        let i = order.firstIndex(of: selected ?? "") ?? 0
        selected = order[min(max(i + d, 0), order.count - 1)]
    }

    private var labelled: [EvalJudgeItem] { items.filter { $0.mine != nil } }

    // MARK: Label tab (queue · the note · the rule and versions)

    private var labelTab: some View {
        HStack(alignment: .top, spacing: 14) {
            queueColumn.frame(width: 250)
            ScrollView { middle.frame(maxWidth: 760, alignment: .leading) }.frame(maxWidth: .infinity)
            ScrollView { sideColumn }.frame(width: 300)
        }
        .padding(.horizontal, lead).padding(.bottom, 16)
    }

    private var queueColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("To label").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    Text("\(queue?.labelled ?? 0) of \(queue?.total ?? items.count)").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                }
                ProgressView(value: Double(queue?.labelled ?? 0), total: Double(max(queue?.total ?? 1, 1))).tint(t.accent.color)
            }
            .padding(12)
            Rectangle().fill(t.separator.color).frame(height: 1)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(queue?.queue ?? []) { x in queueRow(x) }
                    if !labelled.isEmpty {
                        HStack {
                            EvalsLabel("Labelled by you · \(labelled.count)")
                            Spacer()
                            Button("Undo last ⌘Z") { undo() }.buttonStyle(.plain).font(.system(size: TypeScale.caption))
                                .foregroundStyle(t.accentText.color).accessibilityLabel("Take back your last label")
                        }
                        .padding(.top, 10).padding(.horizontal, 10)
                        ForEach(labelled) { x in labelledRow(x) }
                    }
                }
            }
            .focusable().focused($queueFocused).focusEffectDisabled()
            .onKeyPress(characters: .letters) { k in key(k.characters, command: k.modifiers.contains(.command)) }
            .onKeyPress(.upArrow) { move(-1); return .handled }
            .onKeyPress(.downArrow) { move(1); return .handled }
            .onKeyPress(.tab) { whyFocused = true; return .handled }
            Rectangle().fill(t.separator.color).frame(height: 1)
            Text("Likely fails first. Your first 10 labels teach the grader; the rest check it.")
                .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).padding(12)
        }
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
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
            .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(on ? t.selection.color : .clear))
            .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
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
                Text(v == "pass" ? "good" : v == "fail" ? "bad" : v).ui(TypeScale.small, .semibold)
                    .foregroundStyle(v == "pass" ? t.diffAddText.color : t.needsText.color).frame(width: 34, alignment: .leading)
                Text(x.title).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1)
                Spacer()
                Text(x.split == "example" ? "teaches" : "checks").ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
            .padding(.vertical, 5).padding(.horizontal, 10)
            .background(Rectangle().fill(x.id == selected ? t.selection.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(v), \(x.title), \(x.split)")
    }

    private func shortModel(_ m: String?) -> String {
        EvalModels.short(m ?? "").replacingOccurrences(of: "claude-", with: "").replacingOccurrences(of: "-5-5", with: "")
            .replacingOccurrences(of: "gpt-5-", with: "")
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
                            (Text("The fix changed ") + Text(x.changed.map { ($0 as NSString).lastPathComponent }.joined(separator: " and ")).font(.system(size: 11.5, design: .monospaced)))
                                .ui(TypeScale.caption).foregroundStyle(t.text2.color).help(x.changed.joined(separator: "\n"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        EvalsLabel((pairwise ? "The answers · " : "The note · ") + shortModel(x.model ?? "?"))
                        Text(highlighted(x)).ui(TypeScale.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            if let c = x.code {
                                (Text("Files named: ") + Text("\(c.right) of \(c.of) right").fontWeight(.semibold)
                                    .foregroundColor(c.right > 0 ? t.diffAddText.color : t.needsText.color))
                                    .ui(TypeScale.caption).foregroundStyle(t.text2.color)
                                    .help("Checked by code: does the note name a file the fix changed?")
                            }
                            if let j = x.judge {
                                (Text("Grader said: ") + Text(j).fontWeight(.semibold).foregroundColor(j == "pass" ? t.diffAddText.color : t.needsText.color))
                                    .ui(TypeScale.caption).foregroundStyle(t.text2.color)
                            }
                            if let m = x.labels["model"] {
                                (Text("Other model said: ") + Text(m.verdict).fontWeight(.semibold).foregroundColor(m.verdict == "pass" ? t.diffAddText.color : t.needsText.color))
                                    .ui(TypeScale.caption).foregroundStyle(t.text2.color)
                                    .help("\(EvalModels.short(m.by ?? "a model"))'s label" + ((m.why ?? "").isEmpty ? "" : ": \(m.why!)") + ". A model's labels never count as yours.")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let mine = x.mine {
                    Text("Your label: \(mine.verdict == "pass" ? "good" : mine.verdict == "fail" ? "bad" : mine.verdict)" + ((mine.why ?? "").isEmpty ? "" : " — \(mine.why!)") + ". Label again to change it; ⌘Z takes back your last label.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
                actions
            }
        } else {
            Text(items.isEmpty ? "Reading the notes…" : "Every note is labelled.").ui(TypeScale.body).foregroundStyle(t.text2.color)
        }
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if pairwise {
                verdictButton("A better · A", "a", t.accent)
                verdictButton("B better · B", "b", t.accent)
                verdictButton("Tie · T", "tie", t.text2)
            } else {
                verdictButton("Good note · P", "pass", t.diffAddText)
                verdictButton("Bad note · F", "fail", t.needsText)
            }
            TextField("Why? One line, the grader learns from it", text: $why).textFieldStyle(.roundedBorder).focused($whyFocused)
                .onSubmit { whyFocused = false; queueFocused = true }
            Button("Skip · S") { if let x = current { selected = nextID(after: x.id) } }.buttonStyle(.plain)
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

    /// The note with the files it names highlighted (right ones in the selection colour).
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

    // MARK: Right column: the rule · versions · rebuild · what would help · also checked

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    EvalsLabel("The rule it grades by")
                    Text(judge?.rubric ?? "").ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Button { tab = .rubric } label: { Text("Edit the rule ›").ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    EvalsLabel("Versions")
                    ForEach(versions?.versions ?? []) { v in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("v\(v.version)").ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 24, alignment: .leading)
                            Text("\(v.examples ?? 0) examples (\(v.examplesFrom == "owner" ? "yours" : "a model's")) · \(v.heldOut ?? 0) held back · \(v.runs) test\(v.runs == 1 ? "" : "s") · \(EvalTaskWords.day(v.built) ?? "")")
                                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("v\(latest + 1)").ui(TypeScale.small, mono: true).foregroundStyle(t.text3.color).frame(width: 24, alignment: .leading)
                        Text("after you label 10: your labels become its examples").ui(TypeScale.small).foregroundStyle(t.text3.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    RoofButton("Rebuild grader as v\(latest + 1)") { rebuild() }
                        .help("Your labels become its examples; a new version, the old one and its results stay as they are")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let tr = trust {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        EvalsLabel("What would help")
                        if advice.isEmpty { Text(tr.reading).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                        ForEach(advice, id: \.self) { Text($0).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                        EvalsLabel("Also checked").padding(.top, 6)
                        Text((tr.selfPreference.map { "Self-preference: " + $0 + "." } ?? "Self-preference: the grader didn't write any of these notes.")
                             + (pairwise ? "" : " Pairwise position bias: n/a, single grading."))
                            .ui(TypeScale.small).foregroundStyle(tr.selfPreference == nil ? t.text2.color : t.needsText.color).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
        nav.test(EvalRunPlan(tasks: [tf], models: [], limit: items.count))
    }

    // MARK: Rule · Agreement · Versions

    private var rubricTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Saving makes a draft for the next version; v\(latest) stays frozen. Rebuild to use it.")
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
                    if versions?.draft != nil { Text("Draft saved for v\(latest + 1).").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                }
                if let cur = judge?.rubric, let d = versions?.draft, d != cur {
                    HStack(alignment: .top, spacing: 12) {
                        diffBox("Now (v\(latest))", cur)
                        diffBox("Draft", d)
                    }
                }
            }
            .padding(.horizontal, lead).padding(.bottom, 20).frame(maxWidth: 900 + lead, alignment: .leading)
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
                Text("On notes the grader never saw as examples, from its last run. Ranges are 95 % (Wilson).")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                ForEach([("owner", "You"), ("model", "A model's labels"), ("code", "Code (named a changed file)")], id: \.0) { src, label in
                    let c = EvalJudgeConfusion.from(items, source: src)
                    if c.n > 0 { agreementBlock(label, c) }
                }
                if let ids = cell {
                    Card(padding: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            EvalsLabel("Those notes")
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
            .padding(.horizontal, lead).padding(.bottom, 20).frame(maxWidth: 900 + lead, alignment: .leading)
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
                    GridRow { Text(""); EvalsLabel("Label good"); EvalsLabel("Label bad") }
                    GridRow { EvalsLabel("Grader pass"); cellButton(c.judgePassLabelPass, good: true); cellButton(c.judgePassLabelFail, good: false) }
                    GridRow { EvalsLabel("Grader fail"); cellButton(c.judgeFailLabelPass, good: false); cellButton(c.judgeFailLabelFail, good: true) }
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
        .evalHoverIf(v.map { (.range, EvalHover.range(score: $0, n: n, lo: lo, hi: hi, unit: "note")) })
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
                                Text("\(v.examples ?? 0) examples (\(v.examplesFrom == "owner" ? "yours" : "a model's")) · \(v.heldOut ?? 0) held back · used by \(v.runs) tests"
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
                    Text("Draft for v\(latest + 1): \(d)").ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
                RoofButton("Rebuild grader as v\(latest + 1)") { rebuild() }
            }
            .padding(.horizontal, lead).padding(.bottom, 20).frame(maxWidth: 900 + lead, alignment: .leading)
        }
    }
}

private struct EvalAdvice: Decodable { var advice: [String] }
private struct EvalLabelAck: Decodable { var item: String }
private struct EvalRubric: Decodable { var current: String; var draft: String? }
private struct EvalJudgeBuilt: Decodable { var version: Int; var new: Bool; var taskFile: String }
