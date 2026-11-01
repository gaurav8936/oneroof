import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2064 · Explore › <benchmark> › Questions (Claude Design 1A-2 = HP E1.2): the benchmark's real questions on this
/// Mac, one dot per run that saw each, and one question up close: reference, what the model sees, how it's marked and how
/// each run answered. The dataset downloads only after a one-line confirm with its size; gated sets show the terms step.
struct EvalsQuestionsPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let benchmark: String
    let task: String
    @Environment(\.theme) private var t
    @State private var page: EvalsItemsState = .loading
    @State private var items: [EvalItemsPage.Item] = []
    @State private var info: EvalItemsPage?
    @State private var filter = "all"
    @State private var seed = 17
    @State private var selected: String?
    @State private var detail: EvalItemDetail?
    @State private var detailError: String?
    @State private var adding = false
    @FocusState private var listFocused: Bool

    enum EvalsItemsState: Equatable { case loading, confirm, gated, downloading, failed(String), ready }

    private var bench: EvalBenchmark? { board.catalog?.benchmarks.first { $0.id == benchmark } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EvalsDrillHeader(crumb: "Evals  Explore › \(bench?.name ?? benchmark) › Questions", back: "Catalog", title: bench?.name ?? benchmark,
                             meta: meta, onBack: { nav.back() }) {
                EvalsTextTabs(options: tabs, selection: Binding(get: { EvalsNav.ExploreTab.questions }, set: { tab in
                    nav.exploreTab = tab; nav.benchmark = benchmark; nav.back()
                }))
            }
            if EvalsDraft.isDraft { EvalsDraftBanner().padding(.horizontal, 20).padding(.top, 10) }
            switch page {
            case .ready: split
            case .loading: note("Reading the questions…")
            case .downloading: VStack(alignment: .leading, spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading \(bench?.name ?? task) questions (first time: downloading the dataset)…").ui(TypeScale.body).foregroundStyle(t.text2.color)
            }.padding(24)
            case .confirm: confirmCard
            case .gated: gatedCard
            case .failed(let m): VStack(alignment: .leading, spacing: 8) {
                Text("The questions could not be loaded: \(m)").ui(TypeScale.body).foregroundStyle(t.needsText.color).textSelection(.enabled)
                RoofButton("Try again") { load(download: true) }
            }.padding(24)
            }
        }
        .onAppear { load(download: false) }
    }

    private var meta: String {
        [bench?.category, bench?.questionCount.map { "\($0.formatted()) questions" }, bench?.gradedBy.map { $0 == "code" ? "exact match" : $0 == "judge" ? "judged" : "runs tests" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private var tabs: [(EvalsNav.ExploreTab, String)] {
        var o: [(EvalsNav.ExploreTab, String)] = [(.anatomy, "Anatomy"), (.questions, "Questions")]
        if bench?.isOwn != true { o.append((.scores, "Scores")) }
        o.append((.runs, "Your runs \(info?.runs?.count ?? 0)"))
        return o
    }

    private func note(_ s: String) -> some View {
        Text(s).ui(TypeScale.body).foregroundStyle(t.text2.color).padding(24)
    }

    // MARK: First open: confirm, gated

    private var confirmCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(info?.confirmLine ?? "Download the questions to this Mac?").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                Text("Question text is loaded from the dataset onto this Mac only; nothing is sent anywhere.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                HStack {
                    RoofButton(info?.alreadyOnMac == true ? "Load" : "Download", .primary) { load(download: true) }
                    RoofButton("Not now") { nav.back() }
                }
            }
        }
        .frame(maxWidth: 620, alignment: .leading).padding(24)
    }

    private var gatedCard: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(bench?.name ?? task) is gated on Hugging Face").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("Sign in to Hugging Face and accept the dataset's terms to see questions. Then add a Hugging Face token: roof eval providers set hf --key-file PATH. The questions stay on this Mac.")
                    .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if let u = info?.termsUrl.flatMap(URL.init(string:)) { Link("Open terms ↗", destination: u).font(.system(size: TypeScale.small, weight: .semibold)) }
                    RoofButton("Check again") { load(download: true) }
                }
            }
        }
        .frame(maxWidth: 640, alignment: .leading).padding(24)
    }

    // MARK: Ready: list and detail

    private var split: some View {
        HStack(alignment: .top, spacing: 0) {
            list.frame(width: 360).background(t.sidebar.color)
            Rectangle().fill(t.separator.color).frame(width: 1)
            ScrollView {
                Group {
                    if let d = detail { EvalsQuestionDetail(detail: d, nav: nav, adding: $adding, board: board) { runOne(d) } }
                    else if let e = detailError { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
                    else { Text("Reading the question…").ui(TypeScale.small).foregroundStyle(t.text3.color) }
                }
                .padding(20).frame(maxWidth: 980, alignment: .leading)
            }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            FlowChips(chips: chips, selected: filter) { f in
                if f == "random" { seed = filter == "random" ? seed + 1 : seed }
                filter = f; load(download: false)
            }
            .padding(10)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(items) { x in
                            questionRow(x).id(x.id).onAppear { if x.id == items.last?.id { more() } }
                        }
                        if items.isEmpty { Text("No questions match.").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(10) }
                    }
                    .padding(.horizontal, 8)
                }
                .focusable().focused($listFocused).focusEffectDisabled()
                .onKeyPress(.downArrow) { step(1, proxy); return .handled }
                .onKeyPress(.upArrow) { step(-1, proxy); return .handled }
                .onKeyPress(.return) { if let s = selected { open(s) }; return .handled }
                .onKeyPress("r") { seed += filter == "random" ? 1 : 0; filter = "random"; load(download: false); return .handled }
            }
            Rectangle().fill(t.separator.color).frame(height: 1)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text("Dots: one per run that saw this question.").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    Text("●").foregroundStyle(t.diffAddText.color).ui(TypeScale.caption); Text("right").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    Text("●").foregroundStyle(t.needsText.color).ui(TypeScale.caption); Text("wrong").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                }
                Text("Question text is loaded from the dataset onto this Mac only." + (filter == "random" ? "  Random 10 · seed \(seed)" : ""))
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
            .padding(10)
        }
    }

    private var chips: [(String, String)] {
        let c = info?.counts
        return [("all", "All \(c.map { $0.all.formatted() } ?? "")"), ("seen", "Seen in your runs \(c?.seen ?? 0)"),
                ("wrong", "Any run got wrong \(c?.wrong ?? 0)"), ("random", "Random 10")]
    }

    private func questionRow(_ x: EvalItemsPage.Item) -> some View {
        let on = x.id == selected
        return Button { open(x.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(x.index)").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                    Spacer()
                    if x.dots.isEmpty { Text("not run yet").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                    else {
                        HStack(spacing: 3) {
                            ForEach(Array(x.dots.enumerated()), id: \.offset) { _, d in
                                Circle().fill(d.score == nil ? Color.clear : ((d.score ?? 0) >= 1 ? t.diffAddText.color : t.needsText.color))
                                    .overlay(Circle().strokeBorder(d.score == nil ? t.text3.color : .clear))
                                    .frame(width: 8, height: 8)
                            }
                        }
                        .accessibilityLabel("\(x.dots.filter { ($0.score ?? 0) >= 1 }.count) runs right, \(x.dots.filter { ($0.score ?? 1) < 1 }.count) wrong")
                    }
                }
                Text(x.input).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(2).multilineTextAlignment(.leading)
            }
            .padding(9).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.surface.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Question \(x.index): \(x.input.prefix(80))")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func step(_ d: Int, _ proxy: ScrollViewProxy) {
        guard !items.isEmpty else { return }
        let i = items.firstIndex { $0.id == selected } ?? 0
        let j = min(max(i + d, 0), items.count - 1)
        open(items[j].id); proxy.scrollTo(items[j].id)
    }

    // MARK: Engine

    private func load(download: Bool) {
        if download { page = .downloading } else if items.isEmpty { page = .loading }
        var a = ["items", task, "--limit", "50", "--filter", filter, "--seed", String(seed)]
        if download { a.append("--download") }
        board.ask(a, EvalItemsPage.self, timeout: 1800) { r in
            switch r {
            case .failure(let e): page = .failed(e.message)
            case .success(let p):
                info = p
                if p.isPage {
                    items = p.items ?? []; page = .ready
                    if selected == nil || !items.contains(where: { $0.id == selected }) {
                        if let first = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_EVALS_QUESTION"],
                           let x = items.first(where: { $0.id == first || String($0.index) == first }) { open(x.id) }
                        else if let x = items.first { open(x.id) }
                    }
                } else if p.gated == true { page = .gated }   // known gated: the terms step first, then Check again loads
                else { page = .confirm }
            }
        }
    }

    private func more() {
        guard let p = info, let total = p.shown, items.count < total, filter != "random" else { return }
        board.ask(["items", task, "--limit", "50", "--offset", String(items.count), "--filter", filter], EvalItemsPage.self) { r in
            if case .success(let p) = r, let more = p.items { items += more.filter { m in !items.contains { $0.id == m.id } } }
        }
    }

    private func open(_ id: String) {
        selected = id; detail = nil; detailError = nil
        board.ask(["item", task, id], EvalItemDetail.self, timeout: 300) { r in
            guard selected == id else { return }
            switch r { case .success(let d): detail = d; case .failure(let e): detailError = e.message }
        }
    }

    /// Run just this one: the run sheet with this task, one question, the last run's contestants; cost before Start.
    private func runOne(_ d: EvalItemDetail) {
        let models = Array(Set(d.runs.compactMap(\.model))).sorted()
        nav.run(EvalRunPlan(benchmark: bench, tasks: [task], models: models.isEmpty ? ["mockllm/model"] : models, limit: 1, sampleID: d.id))
    }
}

/// Filter chips in rows that wrap (All · Seen in your runs · Any run got wrong · Random 10).
struct FlowChips: View {
    @Environment(\.theme) private var t
    let chips: [(String, String)]
    let selected: String
    var pick: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) { ForEach(chips.prefix(2), id: \.0) { chip($0) } }
            HStack(spacing: 6) { ForEach(chips.dropFirst(2), id: \.0) { chip($0) } }
        }
    }
    private func chip(_ c: (String, String)) -> some View {
        let on = c.0 == selected
        return Button { pick(c.0) } label: {
            Text(c.1).ui(11.5, .medium).foregroundStyle(on ? t.window.color : t.text.color).lineLimit(1).fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 3)
                .background(Capsule().fill(on ? t.text.color : t.control.color))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// One question up close.
struct EvalsQuestionDetail: View {
    let detail: EvalItemDetail
    @ObservedObject var nav: EvalsNav
    @Binding var adding: Bool
    @ObservedObject var board: EvalsBoard
    var runOne: () -> Void
    @State private var toast: String?
    @Environment(\.theme) private var t

    var body: some View {
        let d = detail
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(d.locator).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color)
                Spacer()
                RoofButton("Add to an eval set") { adding = true }
                RoofButton("Run just this one", action: runOne).help("Opens the run sheet with this one question; the cost shows first")
            }
            Card(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    EvalsLabel("The question")
                    Text(d.input).ui(15).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if d.image == true { Text("This question has an image (not shown here).").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    HStack(alignment: .top, spacing: 28) {
                        VStack(alignment: .leading, spacing: 4) {
                            EvalsLabel("Reference answer")
                            if d.noReference == true {
                                Text("No single reference answer: a model judge grades this one.").ui(TypeScale.small).foregroundStyle(t.text2.color)
                            } else {
                                Text(d.target).ui(20, .bold).foregroundStyle(t.text.color).textSelection(.enabled).lineLimit(6)
                            }
                        }
                        if let s = d.solution, !s.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                EvalsLabel("Worked solution in the dataset")
                                Text(s).ui(11.5, mono: true).foregroundStyle(t.text2.color).textSelection(.enabled).lineLimit(8)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: 12) {
                Card(padding: 14) { sees(d).frame(maxWidth: .infinity, alignment: .leading) }
                Card(padding: 14) { marked(d).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Card(padding: 14) { answered(d).frame(maxWidth: .infinity, alignment: .leading) }
        }
        .overlay(alignment: .top) {
            if let m = toast {
                Text(m).ui(TypeScale.small, .semibold).foregroundStyle(t.onAccent.color)
                    .padding(.horizontal, 12).padding(.vertical, 6).background(Capsule().fill(t.accent.color))
            }
        }
        .sheet(isPresented: $adding) {
            // LAB-2069 (HP EV-11) connects stage 1's "Add to an eval set": a new version of a set, never a frozen one.
            EvalsAddToSetSheet(board: board, title: "Add to an eval set", source: ["--from-task", detail.task, "--sample", detail.id],
                               codeKind: detail.task.hasSuffix(".py"), suggested: EvalBenchmark.taskLabel(detail.task) + "_questions") { msg in
                adding = false
                if let msg {
                    toast = msg
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) { if toast == msg { toast = nil } }
                }
            }
            .themed(t.name)
        }
    }

    @ViewBuilder private func sees(_ d: EvalItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EvalsLabel("What the model sees")
            if let p = d.prompt {
                let user = p.messages?.last(where: { $0.role == "user" })?.text ?? p.template ?? ""
                Text(user).ui(11.5, mono: true).foregroundStyle(t.text.color).textSelection(.enabled).lineLimit(18)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.surface2.color))
                if let n = p.fewShot, n > 0 { Text("+ \(n) worked examples (few-shot)").ui(11.5, mono: true).foregroundStyle(t.text2.color) }
                Text(p.source.prefix(1).uppercased() + p.source.dropFirst()).ui(TypeScale.caption).foregroundStyle(t.text3.color)
            } else {
                Text("No run has seen this question yet, and the benchmark's template could not be read.").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
        }
    }

    @ViewBuilder private func marked(_ d: EvalItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            EvalsLabel("How it's marked")
            if d.marking.isEmpty { Text("Graded by the benchmark's own scorer.").ui(TypeScale.body).foregroundStyle(t.text.color) }
            ForEach(Array(d.marking.enumerated()), id: \.offset) { _, m in
                Text(m.text).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            }
            if let l = d.lesson {
                Button { nav.openLesson(EvalLessons.forMarking(l)) } label: {
                    Text("Lesson: " + l).ui(TypeScale.body).foregroundStyle(t.accentText.color).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.accent.color.opacity(0.18)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder private func answered(_ d: EvalItemDetail) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            EvalsLabel("How your runs answered")
            if d.runs.isEmpty { Text("No run has seen this question yet. Run just this one shows the cost first.").ui(TypeScale.small).foregroundStyle(t.text3.color) }
            ForEach(d.runs) { r in
                HStack(spacing: 10) {
                    Text(r.right ? "✓" : "✕").ui(TypeScale.body, .semibold).foregroundStyle(r.right ? t.diffAddText.color : t.needsText.color).frame(width: 16)
                    Text(r.contestant ?? r.model ?? "?").ui(TypeScale.small, mono: true).foregroundStyle(t.text.color).lineLimit(1).frame(width: 200, alignment: .leading)
                    Text("…" + r.answerTail + ((r.model ?? "").hasPrefix("mockllm/") ? " · the free stand-in, always this" : ""))
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).lineLimit(1)
                    Spacer()
                    Button { nav.openRun(r.run, sample: detail.id) } label: { Text("transcript ›").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

}
