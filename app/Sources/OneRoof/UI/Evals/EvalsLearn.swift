import SwiftUI
import OneRoofCore

/// LAB-2070 · Learn (Claude Design 1A-8 = HP E5.1): 16 lessons in six groups with progress ticks, each with its body, a
/// Try it widget (local maths, no runs, no cost), In your runs (this Mac's real runs, each opens), Where this shows up
/// and Next; on the right, Your first eval, free, ticked from real state (today's walkthrough and its two buttons kept).
/// Lessons come from Resources/evals/lessons.json; bodies keep today's EvalGlossary text. App help, not AE content.
struct EvalsLearnV2: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @AppStorage(EvalsLearnStore.doneKey, store: Prefs.viewState) private var doneRaw = ""
    @AppStorage(EvalsLearnStore.currentKey, store: Prefs.viewState) private var current = ""
    @AppStorage(EvalsLearnStore.resultsKey, store: Prefs.viewState) private var openedResults = false
    @AppStorage(EvalsLearnStore.questionKey, store: Prefs.viewState) private var openedQuestion = false
    @AppStorage(EvalsLearnStore.compareKey, store: Prefs.viewState) private var compared = false
    private let book = EvalsLearnStore.book

    var body: some View {
        if let book {
            let id = selected(book)
            HStack(alignment: .top, spacing: 20) {
                list(book, selected: id).frame(width: 240)
                ScrollView {
                    EvalsColumns(breakpoint: 860, side: 280) {
                        if let l = book.lesson(id) { lesson(l, book).frame(maxWidth: 760, alignment: .leading) }
                    } aside: {
                        VStack(alignment: .leading, spacing: 14) {
                            firstEval
                            if let l = book.lesson(id) { whereCard(l, book) }
                        }
                    }
                    .padding(.bottom, 24)
                    Color.clear.frame(height: 1).onAppear { markDone(id) }   // HP: done when scrolled to the end
                }
                .id(id)
            }
            .onAppear { if nav.lesson == nil, !current.isEmpty { nav.lesson = current } }
            .onChange(of: nav.lesson) { _, l in if let l, book.lesson(l) != nil { current = l } }   // a hover's Lesson › too
        } else {
            // The lessons file is missing (a broken bundle): today's Learn, unchanged, so nothing is lost.
            EvalsLearnTab(board: board) { nav.run($0) }
        }
    }

    private func selected(_ b: EvalLessonBook) -> String {
        if let l = nav.lesson, b.lesson(l) != nil { return l }
        if b.lesson(current) != nil { return current }
        return b.lessons.first?.id ?? ""
    }

    private var done: Set<String> { Set(doneRaw.split(separator: ",").map(String.init)) }
    private func markDone(_ id: String) {
        guard !id.isEmpty, !done.contains(id) else { return }
        doneRaw = (Array(done) + [id]).sorted().joined(separator: ",")
    }
    private func open(_ id: String) { nav.lesson = id; current = id }

    // MARK: Left · the lessons, grouped, with ✓ done · ● current · ○ not yet

    private func list(_ b: EvalLessonBook, selected: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(b.sections, id: \.id) { s in
                    EvalsLabel(s.title).padding(.top, s.id == b.sections.first?.id ? 0 : 12).padding(.bottom, 4).padding(.leading, 8)
                    ForEach(b.lessons(in: s.id)) { l in
                        let on = l.id == selected, isDone = done.contains(l.id)
                        Button { open(l.id) } label: {
                            HStack(spacing: 9) {
                                EvalsLessonMark(state: on ? .current : isDone ? .done : .todo)
                                Text(l.title).ui(TypeScale.row, on ? .semibold : .regular).foregroundStyle(t.text.color).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(l.title + (isDone ? ", done" : ", not yet"))
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .accessibilityLabel("Lessons")
    }

    // MARK: Middle · the lesson

    @ViewBuilder private func lesson(_ l: EvalLesson, _ b: EvalLessonBook) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(b.position(l.id)).ui(TypeScale.small).foregroundStyle(t.text2.color)
                Text(l.title).ui(24, .bold).foregroundStyle(t.text.color)
                Text(l.body).ui(14.5).foregroundStyle(t.text.color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let m = l.more {
                    Text(m).ui(14.5).foregroundStyle(t.text.color).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                }
                if !l.example.isEmpty {
                    Text("Example: " + l.example).ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(l.glossary.dropFirst(), id: \.self) { g in
                if let e = EvalGlossary.entry(g) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(e.title).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                        Text(e.body).ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        Text("Example: " + e.example).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            EvalsTryIt(widget: l.widget, board: board, nav: nav, run: nav.run)
            inYourRuns(l)
        }
    }

    private func inYourRuns(_ l: EvalLesson) -> some View {
        let ex = EvalLessonExamples.pick(l.id, results: board.results)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                EvalsLabel("In your runs")
                if ex.rows.isEmpty {
                    HStack(spacing: 6) {
                        Text("No runs on this Mac show this yet.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                        if l.id != "first-eval" {
                            Button { open("first-eval") } label: { Text("Your first eval, free ›").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                                .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(ex.rows, id: \.run) { r in
                    HStack(spacing: 12) {
                        Text(r.title).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(evalsPct(r.score)).ui(TypeScale.small, .bold).foregroundStyle(t.text.color).frame(width: 52, alignment: .leading)
                        Text(r.rangeText).ui(TypeScale.small).foregroundStyle(r.small ? t.needsText.color : t.text.color)
                            .frame(width: 130, alignment: .leading)
                            .evalHover(.range, EvalHover.range(score: r.score, n: r.n, lo: r.lo, hi: r.hi))
                        Button { nav.openRun(r.run) } label: { Text("open ›").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                            .buttonStyle(.plain).accessibilityLabel("Open \(r.title)")
                    }
                }
                if let s = ex.sentence {
                    Text(s).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Right · your first eval, free · where this shows up · next

    private var firstEval: some View {
        let steps = EvalFirstEval.steps(results: board.results, openedResults: openedResults, openedQuestion: openedQuestion, compared: compared)
        let cur = EvalFirstEval.current(steps)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 9) {
                Text("Your first eval, free").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                    let isCur = cur == i + 1
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        EvalsLessonMark(state: s.done ? .done : isCur ? .next : .todo)
                        (Text(s.title).fontWeight(isCur ? .semibold : .regular) + Text(s.detail.isEmpty ? "" : " " + s.detail))
                            .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Step \(i + 1): \(s.title) \(s.detail), \(s.done ? "done" : "not yet")")
                }
                if let c = cur {
                    Button { cont(c) } label: {
                        Text("Continue: step \(c)").ui(TypeScale.small, .semibold).foregroundStyle(t.onAccent.color)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.accent.color))
                    }
                    .buttonStyle(.plain)
                    .help(c == 1 ? "Run pre-filled: GSM8K × 5 on the free stand-in, cap $0" : c == 4 ? "Run pre-filled: the same 5 on Claude Haiku, cap $0.05" : "")
                } else {
                    Text("All four steps done.").ui(TypeScale.small, .semibold).foregroundStyle(t.diffAddText.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// HP E5 interactions: step 1/4 → Run pre-filled (gsm8k, the stand-in or Haiku, 5, cap 0 / $0.05); step 2 → Results;
    /// step 3 → one run's first question.
    private func cont(_ step: Int) {
        let free = board.results.first { $0.status == "done" && $0.task == "gsm8k" && ($0.model ?? "").hasPrefix("mockllm/") }
        let paid = board.results.contains { $0.status == "done" && $0.task == "gsm8k" && !$0.isFree }
        switch step {
        case 1: nav.run(EvalFirstEval.freePlan)
        case 2: nav.showResults(key: "gsm8k")
        case 3: if let f = free { nav.openRun(f.id) } else { nav.showResults(key: "gsm8k") }
        default: if paid { nav.showResults(key: "gsm8k") } else { nav.run(EvalFirstEval.cheapPlan) }
        }
    }

    private func whereCard(_ l: EvalLesson, _ b: EvalLessonBook) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where this shows up").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                ForEach(l.links, id: \.route) { k in
                    Button { EvalsLearnStore.go(k.route, nav: nav, board: board) } label: {
                        Text(k.label + " ›").ui(TypeScale.small).foregroundStyle(t.accentText.color).multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .buttonStyle(.plain)
                }
                if let n = b.next(after: l.id) {
                    Button { open(n.id) } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Next: " + n.title).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                            Text(n.teaser).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// ✓ done (diffAddText) · ● current (accent) · ring = to do (accent ring for the next step, text3 otherwise). Drawn, so
/// no glyph outside the allowed set.
struct EvalsLessonMark: View {
    enum State { case done, current, next, todo }
    let state: State
    @Environment(\.theme) private var t
    var body: some View {
        Group {
            switch state {
            case .done: Text("✓").ui(12, .semibold).foregroundStyle(t.diffAddText.color)
            case .current: Circle().fill(t.accent.color).frame(width: 9, height: 9)
            case .next: Circle().strokeBorder(t.accent.color, lineWidth: 1.4).frame(width: 10, height: 10)
            case .todo: Circle().strokeBorder(t.text3.color, lineWidth: 1.2).frame(width: 10, height: 10)
            }
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

/// Where Learn keeps its state (`Prefs.viewState`: a self-test never touches the owner's settings) and the lessons.
enum EvalsLearnStore {
    static let doneKey = "evals.learn.done"
    static let currentKey = "evals.learn.current"
    static let resultsKey = "evals.first.openedResults"
    static let questionKey = "evals.first.openedQuestion"
    static let compareKey = "evals.first.compared"
    static let book: EvalLessonBook? = EvalLessonBook.bundled()
    static func note(_ key: String) { if !Prefs.viewState.bool(forKey: key) { Prefs.viewState.set(true, forKey: key) } }

    /// A lesson's "Where this shows up" link (EvalLessons.knownRoutes).
    static func go(_ route: String, nav: EvalsNav, board: EvalsBoard) {
        switch route {
        case "overview": nav.go(.overview)
        case "your-evals": nav.go(.yourEvals)
        case "your-evals/judge":
            if let j = board.judges.first?.name { nav.tab = .yourEvals; nav.route = .judge(name: j, first: nil) } else { nav.go(.yourEvals) }
        case "explore", "explore/anatomy": nav.exploreTab = .anatomy; nav.go(.explore)
        case "explore/questions": nav.exploreTab = .questions; nav.go(.explore)
        case "explore/scores": nav.exploreTab = .scores; nav.go(.explore)
        case "run": nav.go(.run)
        case "results/all-by-all": nav.resultsMode = .allByAll; nav.go(.results)
        case "results/run":
            if let r = board.results.first(where: { $0.status == "done" }) { nav.openRun(r.id) } else { nav.go(.results) }
        default: nav.resultsMode = .byEval; nav.go(.results)   // results, results/compare
        }
    }
}

// MARK: - Try it (one per lesson; all local maths, no runs, no cost)

struct EvalsTryIt: View {
    let widget: String
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    var run: (EvalRunPlan) -> Void
    @Environment(\.theme) private var t

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(widget == "harness" || widget == "golden" || widget == "frozen" ? "Picture it" : "Try it")
                        .ui(TypeScale.body, .bold).foregroundStyle(t.text.color)
                    Text(prompt).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var prompt: String {
        switch widget {
        case "firstEval": return "Today's four steps, and the two runs they use."
        case "chance": return "How many options does each question have?"
        case "range": return "A model gets 80 % right. How sure can you be?"
        case "stderr": return "A model scores 70 %. How much would that move on other questions?"
        case "compare": return "Two models, the same questions. Is A really better?"
        case "passk": return "How often does one attempt pass? Now allow more attempts."
        case "attempts": return "Questions × attempts: what a run can tell apart."
        case "exactMatch": return "The expected answer is 72. Type a reply and see what GSM8K's marking reads."
        case "judge": return "A judge with its own error rates grades the answers."
        case "labels": return "The judge agrees with 85 % of your labels. How many labels do you need?"
        case "harness": return "One model, one benchmark, two frameworks."
        case "cost": return "What each solved task costs."
        case "golden": return "How a fix in your history becomes a question."
        case "frozen": return "What happens when the set changes."
        case "saturation": return "How much room is left above the best score?"
        case "contamination": return "An old benchmark and a fresh one of the same kind."
        default: return ""
        }
    }

    @ViewBuilder private var content: some View {
        switch widget {
        case "firstEval":
            Text(EvalFirstEval.walkthrough).ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack {
                RoofButton("Step 1: run it free", .primary) { run(EvalFirstEval.freePlan) }
                RoofButton("Step 4: same questions on a cheap model") { run(EvalFirstEval.cheapPlan) }
            }
        case "chance": ChanceTry()
        case "range": RangeTry()
        case "stderr": StderrTry()
        case "compare": CompareTry()
        case "passk": PassKTry()
        case "attempts": AttemptsTry()
        case "exactMatch": ExactMatchTry()
        case "judge": JudgeTry()
        case "labels": LabelsTry()
        case "cost": CostTry()
        case "saturation": SaturationTry()
        case "contamination": ContaminationTry()
        case "harness": HarnessPicture()
        case "golden": StepsPicture(steps: [("Your repo's history", "A commit that fixes a bug and names its issue"),
                                            ("The question", "The bug report, and the source files just before the fix"),
                                            ("The answer", "Up to three files the agent or model would change"),
                                            ("The marking", "Right when one of them is a file the fix changed: checked by code")])
        case "frozen": StepsPicture(steps: [("v1 · frozen", "20 cases. Never edited; its runs keep their meaning"),
                                            ("Build v2", "v1's cases plus the fixes since, previewed first"),
                                            ("v2 · frozen", "A new version with its own results"),
                                            ("Compare", "Only runs on the same version, side by side")])
        default: EmptyView()
        }
    }
}

private func pct(_ x: Double) -> String { "\(Int((x * 100).rounded())) %" }
private func pts(_ x: Double) -> String { let v = Int((x * 100).rounded()); return (v > 0 ? "+" : "") + "\(v)" }

/// A labelled segmented row ("Questions  5 10 20 50 200 1000").
private struct TryRow<T: Hashable>: View {
    @Environment(\.theme) private var t
    let label: String
    let options: [(T, String)]
    @Binding var value: T
    var body: some View {
        HStack(spacing: 10) {
            Text(label).ui(TypeScale.small).foregroundStyle(t.text2.color).frame(width: 96, alignment: .leading)
            Segmented(options: options, selection: Binding(get: { value }, set: { v in   // HP: the range animates 0.3 s
                withAnimation(Motion.reduce ? nil : .easeInOut(duration: 0.3)) { value = v }
            }))
            .fixedSize()
            .accessibilityLabel(label)
        }
    }
}

/// 0 … 100 % with a range band, a dot (labelled) and an optional dashed tick (chance, floor).
private struct TryBar: View {
    @Environment(\.theme) private var t
    let value: Double
    var lo: Double?
    var hi: Double?
    var tick: Double?
    var tickLabel: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .topLeading) {
                    Capsule().fill(t.control.color).frame(height: 8).offset(y: 22)
                    if let lo, let hi {
                        Capsule().fill(t.accent.color.opacity(0.22))
                            .overlay(Capsule().strokeBorder(t.accent.color, lineWidth: 1.2))
                            .frame(width: max((hi - lo) * w, 4), height: 12).offset(x: lo * w, y: 20)
                    }
                    if let k = tick {
                        Path { p in p.move(to: .init(x: k * w, y: 14)); p.addLine(to: .init(x: k * w, y: 38)) }
                            .stroke(t.text2.color, style: StrokeStyle(lineWidth: 1.2, dash: [3, 2]))
                        if let l = tickLabel { Text(l).ui(10.5).foregroundStyle(t.text2.color).fixedSize().offset(x: max(k * w - 20, 0), y: 40) }
                    }
                    Rectangle().fill(t.accent.color).frame(width: 2.5, height: 20).offset(x: value * w - 1.25, y: 16)
                    Text(pct(value)).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).fixedSize()
                        .offset(x: min(max(value * w - 16, 0), w - 36), y: 0)
                }
            }
            .frame(height: tickLabel == nil ? 36 : 54)
            HStack { Text("0 %"); Spacer(); Text("100 %") }.ui(10.5).foregroundStyle(t.text3.color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(pct(value))" + (lo.map { ", range \(pct($0)) to \(pct(hi ?? $0))" } ?? ""))
    }
}

private struct Readout: View {
    @Environment(\.theme) private var t
    let big: String
    let note: String
    var warn = false
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(big).ui(24, .bold).foregroundStyle(warn ? t.needsText.color : t.text.color).fixedSize()
            Text(note).ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct RangeTry: View {
    @State private var n = 50
    var body: some View {
        let r = EvalLessonMath.range(n: n)
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Questions", options: EvalLessonMath.rangeNs.map { ($0, "\($0)") }, value: $n)
            TryBar(value: 0.8, lo: r.lo, hi: r.hi)
            Readout(big: EvalLessonMath.rangeText(r), note: EvalLessonMath.rangeNote(n: n), warn: EvalStats.isSmall(n))
        }
    }
}

private struct ChanceTry: View {
    @State private var options = 4
    @State private var score = 0.5
    var body: some View {
        let c = EvalLessonMath.chance(options: options), a = EvalLessonMath.aboveChance(score: score, options: options)
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Options", options: [(2, "2"), (4, "4"), (10, "10")], value: $options)
            TryRow(label: "Score", options: [(0.3, "30 %"), (0.5, "50 %"), (0.7, "70 %"), (0.9, "90 %")], value: $score)
            TryBar(value: score, tick: c, tickLabel: "chance \(pct(c))")
            Readout(big: "chance \(pct(c))",
                    note: a <= 0 ? "\(pct(score)) is no better than guessing among \(options) options."
                                 : "\(pct(score)) is \(pct(a)) of the way from guessing (\(pct(c))) to a perfect score.",
                    warn: a <= 0)
        }
    }
}

private struct StderrTry: View {
    @State private var n = 233
    var body: some View {
        let se = EvalLessonMath.stderr(p: 0.7, n: n), w = EvalStats.wilson(0.7, n: n)
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Questions", options: [(20, "20"), (50, "50"), (100, "100"), (233, "233"), (1000, "1000")], value: $n)
            TryBar(value: 0.7, lo: max(0, 0.7 - 2 * se), hi: min(1, 0.7 + 2 * se))
            Readout(big: String(format: "stderr %.3f", se),
                    note: "Score ± 2 standard errors: about \(pct(max(0, 0.7 - 2 * se)))–\(pct(min(1, 0.7 + 2 * se))). The Wilson range One Roof shows: \(EvalLessonMath.rangeText(w)).")
        }
    }
}

private struct CompareTry: View {
    @State private var a = 0.8
    @State private var b = 0.7
    @State private var n = 50
    @State private var paired = true
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "A scores", options: [(0.6, "60 %"), (0.7, "70 %"), (0.8, "80 %"), (0.9, "90 %")], value: $a)
            TryRow(label: "B scores", options: [(0.6, "60 %"), (0.7, "70 %"), (0.8, "80 %"), (0.9, "90 %")], value: $b)
            TryRow(label: "Questions", options: [(5, "5"), (20, "20"), (50, "50"), (200, "200")], value: $n)
            Toggle("Paired: both answered the same questions and mostly miss the same ones", isOn: $paired)
                .toggleStyle(.checkbox).ui(TypeScale.small)
            if let c = EvalLessonMath.compare(a: a, b: b, n: n, paired: paired) {
                EvalsDiffAxis(diff: c.diff, lo: c.lo, hi: c.hi).frame(height: 34)
                Readout(big: c.tooFew ? "too few" : c.verdict == .noise ? "not distinguishable" : c.verdict.rawValue,
                        note: "\(pts(c.diff)) points, 95 % range \(pts(c.lo)) to \(pts(c.hi))" + (c.tooFew ? ": under \(EvalStats.minVerdictN) shared questions no winner is called." : "."),
                        warn: c.verdict == .noise)
            }
            Text("Paired here means the best case: B is right only where A is. Real runs sit between paired and unpaired.")
                .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct PassKTry: View {
    @State private var p = 0.3
    @State private var k = 5
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "One attempt", options: [(0.1, "10 %"), (0.3, "30 %"), (0.5, "50 %"), (0.7, "70 %")], value: $p)
            TryRow(label: "Attempts k", options: [(1, "1"), (2, "2"), (5, "5"), (10, "10")], value: $k)
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(1...10, id: \.self) { i in
                    let v = EvalLessonMath.passAtK(p: p, k: i)
                    VStack(spacing: 3) {
                        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(i <= k ? t.accent.color : t.control.color)
                            .frame(width: 22, height: max(2, 70 * v))
                        Text("\(i)").ui(10.5).foregroundStyle(t.text3.color)
                    }
                }
            }
            .frame(height: 90, alignment: .bottom)
            .accessibilityElement(children: .ignore).accessibilityLabel("pass at k for k from 1 to 10")
            Readout(big: "pass@\(k) \(pct(EvalLessonMath.passAtK(p: p, k: k)))",
                    note: "pass@1 is \(pct(p)). With \(k) attempts, at least one passes \(pct(EvalLessonMath.passAtK(p: p, k: k))) of the time, if attempts are independent.")
        }
    }
}

private struct AttemptsTry: View {
    @State private var n = 20
    @State private var e = 3
    var body: some View {
        let pw = EvalPower.mirror(n: n, epochs: e)
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Questions", options: [(5, "5"), (10, "10"), (20, "20"), (50, "50"), (100, "100")], value: $n)
            TryRow(label: "Attempts", options: [(1, "1"), (3, "3"), (5, "5")], value: $e)
            Readout(big: "±\(Int(pw.plusMinusPoints.rounded())) points",
                    note: "\(n) × \(e) = \(n * e) calls. Same helper as Run's \"what this run can tell you\", which counts each attempt as a new question: the most repeats can narrow it.")
        }
    }
}

private struct ExactMatchTry: View {
    @State private var reply = "72 clips (48 + 24)"
    @Environment(\.theme) private var t
    private let presets = ["ANSWER: 72", "ANSWER: $72", "The answer is 72.", "72 clips (48 + 24)", "seventy-two", "ANSWER: 72%"]
    var body: some View {
        let m = EvalExactMatch.gsm8k(reply, target: "72")
        VStack(alignment: .leading, spacing: 10) {
            TextField("The model's reply", text: $reply).textFieldStyle(.roundedBorder).frame(maxWidth: 420)
                .accessibilityLabel("The model's reply")
            HStack(spacing: 6) {
                ForEach(presets, id: \.self) { p in
                    Button { reply = p } label: { EvalsChip(text: p, accent: p == reply) }.buttonStyle(.plain)
                }
            }
            Readout(big: m.right ? "✓ right" : "✕ wrong",
                    note: m.read.isEmpty ? "No number found at the end: nothing to compare with 72." : "Read \(m.read); expected 72.",
                    warn: !m.right)
        }
    }
}

private struct JudgeTry: View {
    @State private var p = 0.5
    @State private var tpr = 0.9
    @State private var tnr = 0.7
    var body: some View {
        let j = EvalLessonMath.judged(p: p, tpr: tpr, tnr: tnr)
        let rates: [(Double, String)] = [(0.6, "60 %"), (0.8, "80 %"), (0.9, "90 %"), (1.0, "100 %")]
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Truly right", options: [(0.3, "30 %"), (0.5, "50 %"), (0.7, "70 %")], value: $p)
            TryRow(label: "Passes good", options: rates, value: $tpr)
            TryRow(label: "Fails bad", options: rates, value: $tnr)
            TryBar(value: j, tick: p, tickLabel: "true \(pct(p))")
            Readout(big: "judged \(pct(j))",
                    note: abs(j - p) < 0.005 ? "The errors happen to cancel at this mix; change it and they do not."
                        : "\(Int((abs(j - p) * 100).rounded())) points too \(j > p ? "high" : "low"): it passes \(pct(1 - tnr)) of the bad answers and fails \(pct(1 - tpr)) of the good ones.",
                    warn: abs(j - p) >= 0.05)
        }
    }
}

private struct LabelsTry: View {
    @State private var n = 20
    var body: some View {
        let k = (0.85 * Double(n)).rounded(), r = EvalStats.wilson(k / Double(n), n: n)
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Your labels", options: [(5, "5"), (10, "10"), (20, "20"), (50, "50"), (100, "100")], value: $n)
            TryBar(value: k / Double(n), lo: r.lo, hi: r.hi)
            Readout(big: EvalLessonMath.rangeText(r),
                    note: "\(Int(k)) of \(n) agree." + (n < 10 ? " Under 10 held-back labels One Roof marks it too few." : " That is how far the agreement itself can be trusted."),
                    warn: n < 10)
        }
    }
}

private struct CostTry: View {
    @State private var cost = 0.01
    @State private var rate = 0.5
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Per attempt", options: [(0.001, "$0.001"), (0.01, "$0.01"), (0.1, "$0.10"), (1.0, "$1")], value: $cost)
            TryRow(label: "Solved", options: [(0.1, "10 %"), (0.3, "30 %"), (0.5, "50 %"), (0.8, "80 %")], value: $rate)
            Readout(big: EvalLessonMath.costPerSolved(costPerTry: cost, rate: rate).map { String(format: "$%.4f", $0) } ?? "–",
                    note: "per solved task: what 100 attempts cost (\(String(format: "$%.2f", cost * 100))) over the \(Int((rate * 100).rounded())) they solve.")
        }
    }
}

private struct SaturationTry: View {
    @State private var best = 0.92
    @State private var n = 500
    var body: some View {
        let r = EvalStats.wilson(best, n: n), half = (r.hi - r.lo) / 2
        let level = EvalLessonMath.headroomLevel(best: best)
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Best score", options: [(0.6, "60 %"), (0.75, "75 %"), (0.85, "85 %"), (0.92, "92 %"), (0.97, "97 %")], value: $best)
            TryRow(label: "Questions", options: [(100, "100"), (500, "500"), (1000, "1000")], value: $n)
            TryBar(value: best, lo: r.lo, hi: r.hi)
            Readout(big: level == "saturated" ? "Saturated" : level == "lots" ? "Lots of room" : "Some room",
                    note: "\(Int(((1 - best) * 100).rounded())) points above the best score; each score is about ±\(String(format: "%.1f", half * 100)) points. Explore calls 90 % or more saturated.",
                    warn: level == "saturated")
        }
    }
}

private struct ContaminationTry: View {
    @State private var old = 0.9
    @State private var fresh = 0.6
    var body: some View {
        let a = EvalStats.wilson(old, n: 200), b = EvalStats.wilson(fresh, n: 200)
        let apart = b.hi < a.lo
        VStack(alignment: .leading, spacing: 12) {
            TryRow(label: "Old benchmark", options: [(0.6, "60 %"), (0.75, "75 %"), (0.9, "90 %")], value: $old)
            TryRow(label: "Fresh one", options: [(0.4, "40 %"), (0.6, "60 %"), (0.75, "75 %")], value: $fresh)
            TryBar(value: old, lo: a.lo, hi: a.hi)
            TryBar(value: fresh, lo: b.lo, hi: b.hi)
            Readout(big: apart ? "a warning sign" : "no sign",
                    note: apart ? "200 questions each: the ranges do not overlap. Memory is one explanation; the fresh questions may also be harder."
                                : "200 questions each: the ranges overlap or the fresh score is higher, so nothing points to memory.",
                    warn: apart)
        }
    }
}

/// Static: the frameworks example from this Mac (EvalGlossary "frameworks", 2026-10-31).
private struct HarnessPicture: View {
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach([("Inspect", 0.72), ("lm-evaluation-harness", 0.64)], id: \.0) { name, v in
                let r = EvalStats.wilson(v, n: 100)
                HStack(spacing: 12) {
                    Text(name).ui(TypeScale.small).foregroundStyle(t.text.color).frame(width: 170, alignment: .leading)
                    Text(pct(v)).ui(TypeScale.small, .bold).foregroundStyle(t.text.color).frame(width: 44, alignment: .leading)
                    EvalsRangeBar(value: v, lo: r.lo, hi: r.hi).frame(maxWidth: 260)
                    Text(EvalLessonMath.rangeText(r)).ui(TypeScale.caption).foregroundStyle(t.text2.color)
                }
            }
            Text("ARC-Challenge, the same first 100 questions, Qwen3-1.7B on this Mac (2026-10-31). Same model, same questions: the wording and the way the answer is read differ.")
                .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct StepsPicture: View {
    @Environment(\.theme) private var t
    let steps: [(String, String)]
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(i + 1) · \(s.0)").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                    Text(s.1).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
            }
        }
    }
}

// MARK: - Hover explanations (EV-9/EV-12): every number explains itself and links to its lesson

/// Shows one explanation card at a time, above everything in Evals (drawn in the page, so captures include it). Hover
/// for 400 ms; it stays while the pointer is on the number or the card.
final class EvalHoverCenter: ObservableObject {
    static let space = "evalsHoverSpace"
    struct Info: Equatable { var kind: EvalHover.Kind; var line: String; var frame: CGRect }
    @Published private(set) var shown: Info?
    var overCard = false { didSet { if !overCard { leave() } } }
    var openLesson: (String) -> Void = { _ in }
    private var pending: DispatchWorkItem?
    private var hiding: DispatchWorkItem?

    func enter(_ info: Info) {
        hiding?.cancel(); pending?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.shown = info }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
    }
    func leave() {
        pending?.cancel(); hiding?.cancel()
        let w = DispatchWorkItem { [weak self] in if self?.overCard == false { self?.shown = nil } }
        hiding = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: w)
    }
    func show(_ info: Info) { pending?.cancel(); hiding?.cancel(); shown = info }
    func hide() { pending?.cancel(); hiding?.cancel(); shown = nil }
}

private struct EvalHoverKey: EnvironmentKey { static let defaultValue: EvalHoverCenter? = nil }
extension EnvironmentValues {
    var evalHover: EvalHoverCenter? {
        get { self[EvalHoverKey.self] }
        set { self[EvalHoverKey.self] = newValue }
    }
}

private final class FrameBox { var rect: CGRect = .zero }

private struct EvalHoverModifier: ViewModifier {
    @Environment(\.evalHover) private var center
    let kind: EvalHover.Kind
    let line: String
    @State private var box = FrameBox()

    func body(content: Content) -> some View {
        if let center {
            content
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(EvalHoverCenter.space)) } action: { box.rect = $0 }
                .onHover { inside in
                    if inside { center.enter(.init(kind: kind, line: line, frame: box.rect)) } else { center.leave() }
                }
                .contextMenu {
                    Button("Explain this number") { center.show(.init(kind: kind, line: line, frame: box.rect)) }
                    Button("Open the lesson ›") { center.openLesson(EvalHover.lesson(kind)) }
                }
                .accessibilityHint(EvalHover.definition(kind) + " " + line)
                .accessibilityAction(named: "Open the lesson") { center.openLesson(EvalHover.lesson(kind)) }
                .onAppear {
                    // ONEROOF_SELFTEST_EVALS_HOVER=<kind>: the first number of that kind shows its card, for captures.
                    if ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_EVALS_HOVER"] == kind.rawValue {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            if center.shown == nil { center.show(.init(kind: kind, line: line, frame: box.rect)) }
                        }
                    }
                }
        } else {
            content.help(EvalHover.definition(kind) + "\n" + line)
        }
    }
}

extension View {
    /// The number explains itself on hover (definition + this value in words) and links to its lesson.
    func evalHover(_ kind: EvalHover.Kind, _ line: String) -> some View { modifier(EvalHoverModifier(kind: kind, line: line)) }
    @ViewBuilder func evalHoverIf(_ h: (EvalHover.Kind, String)?) -> some View {
        if let h { evalHover(h.0, h.1) } else { self }
    }
}

/// The range line for a scorecard or leaderboard row.
enum EvalsHoverText {
    static func range(_ r: EvalOverview.Row) -> String {
        guard let c = r.ci95, c.count == 2, let n = r.n else { return "No range for this score: it is not a share of right answers." }
        return EvalHover.range(score: r.score ?? 0, n: n, lo: c[0], hi: c[1], unit: "answer")
    }
}

/// The card, drawn over the page under (or above) the number.
struct EvalHoverLayer: View {
    @ObservedObject var center: EvalHoverCenter
    @Environment(\.theme) private var t
    var body: some View {
        GeometryReader { g in
            if let s = center.shown {
                let w: CGFloat = 330
                let x = min(max(s.frame.minX, 8), max(g.size.width - w - 8, 8))
                let above = s.frame.maxY + 130 > g.size.height
                card(s)
                    .frame(width: w, alignment: .leading)
                    .alignmentGuide(.leading) { _ in -x }
                    .alignmentGuide(.top) { d in above ? d.height - (s.frame.minY - 6) : -(s.frame.maxY + 6) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(.opacity)
            }
        }
        .allowsHitTesting(center.shown != nil)
    }

    private func card(_ s: EvalHoverCenter.Info) -> some View {
        let lesson = EvalHover.lesson(s.kind)
        return VStack(alignment: .leading, spacing: 6) {
            Text(EvalHover.definition(s.kind)).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            Text(s.line).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            Button { center.hide(); center.openLesson(lesson) } label: {
                Text("Lesson: \(EvalsLearnStore.book?.lesson(lesson)?.title ?? "Learn") ›").ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color)
            .shadow(color: t.text.color.opacity(0.16), radius: 10, y: 4))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separatorStrong.color))
        .onHover { center.overCard = $0 }
        .accessibilityElement(children: .contain)
    }
}
