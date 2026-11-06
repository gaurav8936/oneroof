import AppKit
import SwiftUI
import OneRoofCore

// LAB-2242 · Evals v2 screen lane A: what Overview, Compare, One test, All results, Changes and Real history share — the
// engine answers they all read (kept once, off the main thread) and the small pieces they draw (squares, stamp, verdict
// block, bars). The words and counts come from OneRoofCore EvalsA_Models.swift (unit-tested).

// MARK: - The lane's engine answers, shared by its screens

/// Leaderboards per own task, changes, X-ray and run stamps: read once, refreshed when the run store changes. X-ray reads
/// git for up to a minute, so it is kept per repo list (Overview's third question and Real history share it).
final class EvalsAStore: ObservableObject {
    static let shared = EvalsAStore()

    @Published private(set) var boards: [String: Result<EvalSetupLeaderboard, EvalError>] = [:]
    @Published private(set) var changes: Result<[EvalChange], EvalError>?
    @Published private(set) var xray: [String: Result<EvalXRay, EvalError>] = [:]
    /// LAB-2254: the commits behind a Real history count, per repo list + days + kind + agent.
    @Published private(set) var commitLists: [String: Result<EvalCommitList, EvalError>] = [:]
    @Published private(set) var stamps: [String: EvalsARunStamp] = [:]
    /// nil while the stamps are being read (or never read), true once read, false when the read failed (re-review #6).
    @Published private(set) var stampsRead: Bool?
    private var boardsKey = ""
    private var loading = Set<String>()

    /// Our tasks (sets, not graders) in the board's order, fix locator first (the main signal: checked by code).
    static func ownSets(_ board: EvalsBoard) -> [EvalSetList.Entry] {
        board.sets.sorted { a, b in
            let ra = a.kind == "fix-locator" ? 0 : 1, rb = b.kind == "fix-locator" ? 0 : 1
            return ra != rb ? ra < rb : a.name < b.name
        }
    }

    /// The finished leaderboards, in our tasks' order.
    func loaded(_ board: EvalsBoard) -> [EvalSetupLeaderboard] {
        Self.ownSets(board).compactMap { s in if case .success(let lb)? = boards[s.name] { return lb }; return nil }
    }
    func error(_ board: EvalsBoard) -> String? {
        for s in Self.ownSets(board) { if case .failure(let e)? = boards[s.name] { return e.message } }
        return nil
    }

    /// `leaderboard <set> --by setup` for every own task; again only when the run store changed.
    func refreshBoards(_ board: EvalsBoard, force: Bool = false) {
        let names: String = Self.ownSets(board).map(\.name).joined(separator: ",")
        let res: String = board.results.map { (r: EvalResult) -> String in r.id + (r.status ?? "") }.joined()
        let live: String = board.runs.map { (r: EvalRunRow) -> String in r.id + (r.status ?? "") }.joined()
        let key = names + "|" + res + "|" + live
        guard !names.isEmpty, force || key != boardsKey else { return }
        boardsKey = key
        for s in Self.ownSets(board) where !loading.contains("lb:" + s.name) {
            loading.insert("lb:" + s.name)
            board.setupLeaderboard(task: s.name) { [weak self] r in
                guard let self else { return }
                self.loading.remove("lb:" + s.name)
                if self.boards[s.name].map({ Self.same($0, r) }) != true { self.boards[s.name] = r }
            }
        }
    }

    private static func same(_ a: Result<EvalSetupLeaderboard, EvalError>, _ b: Result<EvalSetupLeaderboard, EvalError>) -> Bool {
        switch (a, b) {
        case (.success(let x), .success(let y)): return x == y
        case (.failure(let x), .failure(let y)): return x.message == y.message
        default: return false
        }
    }

    /// `changes --repo <our tasks' repo> --days 60` (real rows only; an empty list is a valid answer).
    func refreshChanges(_ board: EvalsBoard, force: Bool = false) {
        guard force || changes == nil, !loading.contains("changes") else { return }
        loading.insert("changes")
        let repo = Self.ownSets(board).compactMap(\.repoPath).first
        board.changes(repo: repo, days: 60) { [weak self] r in self?.loading.remove("changes"); self?.changes = r }
    }

    static func key(_ repos: [String], days: Int) -> String { repos.joined(separator: "|") + "@\(days)" }

    /// `xray --repo R [--repo …] --days N`.
    func refreshXRay(_ board: EvalsBoard, repos: [String], days: Int, force: Bool = false) {
        let k = Self.key(repos, days: days)
        guard !repos.isEmpty, force || xray[k] == nil, !loading.contains("x:" + k) else { return }
        loading.insert("x:" + k)
        board.ask(["xray"] + repos.flatMap { ["--repo", $0] } + ["--days", String(days)], EvalXRay.self, timeout: 600) { [weak self] r in
            self?.loading.remove("x:" + k)
            self?.xray[k] = r
        }
    }
    func isReading(repos: [String], days: Int) -> Bool { loading.contains("x:" + Self.key(repos, days: days)) }

    static func listKey(_ repos: [String], days: Int, kind: EvalCommitList.Kind, agent: String) -> String {
        key(repos, days: days) + "#" + kind.rawValue + "#" + agent
    }
    /// LAB-2254 · `xray … --commits KIND --agent NAME`: the commits one count is made of (read once; again on Read again).
    func refreshCommitList(_ board: EvalsBoard, repos: [String], days: Int, kind: EvalCommitList.Kind, agent: String, force: Bool = false) {
        let k = Self.listKey(repos, days: days, kind: kind, agent: agent)
        guard !repos.isEmpty, force || commitLists[k] == nil, !loading.contains("cl:" + k) else { return }
        loading.insert("cl:" + k)
        board.ask(EvalCommitList.args(repos: repos, days: days, kind: kind, agent: agent), EvalCommitList.self, timeout: 600) { [weak self] r in
            self?.loading.remove("cl:" + k)
            self?.commitLists[k] = r
        }
    }
    /// Read again also drops the commit lists for that repo list and window, so an open list re-reads with the counts.
    func forgetCommitLists(repos: [String], days: Int) {
        let p = Self.key(repos, days: days) + "#"
        for k in commitLists.keys where k.hasPrefix(p) { commitLists[k] = nil }
    }

    /// Run stamps from `results` (2.0.4 rows carry `stamp` and `setup_id`).
    func refreshStamps(_ board: EvalsBoard) {
        guard !loading.contains("stamps") else { return }
        loading.insert("stamps")
        stampsRead = nil
        board.ask(["results"], [EvalsARunStamp].self, timeout: 300) { [weak self] r in
            self?.loading.remove("stamps")
            switch r {
            case .success(let xs):
                self?.stamps = Dictionary(xs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
                self?.stampsRead = true
            case .failure:
                self?.stampsRead = false
            }
        }
    }

    /// The repos Real history reads by default: the ones our tasks were built from (as 2.0.3's X-ray), existing on disk.
    static func defaultRepos(_ board: EvalsBoard) -> [String] {
        Array(Set(board.sets.compactMap(\.repoPath))).sorted().filter { FileManager.default.fileExists(atPath: $0 + "/.git") }
    }
}

// MARK: - Colours by verdict tone (tokens only)

extension ThemeTokens {
    /// Fill and ink of a verdict block: a finding (green family), a gap (needs), can't tell (peach sticker), reading.
    func evalsATone(_ tone: EvalsAAnswer.Tone) -> (fill: RGB, ink: RGB) {
        switch tone {
        case .call: return (diffAddFill, diffAddText)
        case .gap: return (needsText.opacity(0.12).over(surface), needsText)
        case .cantTell: return sticker(Pastel.named("peach") ?? Pastel.all[1], on: surface)
        case .reading: return (control, text2)
        }
    }
}

// MARK: - Pieces

/// One square per bug (right = diffAddText, wrong = surface2, not answered = dashed), the blind-guess tick after the floor's
/// count, a ring on flipped bugs. Hover names the bug; a click opens it in the test (when a run is given).
struct EvalsABugSquares: View {
    @Environment(\.theme) private var t
    let squares: [EvalsASquare]
    var guess: Int?
    var size: CGFloat = 18
    var open: ((EvalsASquare) -> Void)?

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(squares.enumerated()), id: \.element.id) { i, s in
                if let g = guess, g == i, g > 0 { tick }
                square(s)
            }
            if let g = guess, g >= squares.count, g > 0 { tick }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(EvalScoreText.count(squares.reduce(0) { $0 + ($1.score ?? 0) })) of \(squares.count) right" + (guess.map { ", a blind guess gets \($0)" } ?? ""))
    }

    private var tick: some View {
        Rectangle().fill(t.text.color).frame(width: 2, height: size + 8).padding(.horizontal, 1)
            .help("A blind guess gets \(guess ?? 0): squares left of this line are what guessing scores")
    }

    @ViewBuilder private func square(_ s: EvalsASquare) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        let base = Group {
            if s.score == nil {
                shape.strokeBorder(t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
            } else if s.isPartial, let sc = s.score {
                // right on some attempts: filled from the bottom by that share (the attempts policy)
                shape.fill(t.surface2.color)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(t.diffAddText.color).frame(height: size * CGFloat(sc))
                    }
                    .clipShape(shape)
                    .overlay(shape.strokeBorder(t.separatorStrong.color, lineWidth: 1))
            } else {
                shape.fill(s.right == true ? t.diffAddText.color : t.surface2.color)
                    .overlay(shape.strokeBorder(s.right == true ? .clear : t.separatorStrong.color, lineWidth: 1))
            }
        }
        .frame(width: size * 1.25, height: size)
        .overlay(s.flipped ? shape.inset(by: -2).stroke(t.accent.color, lineWidth: 2) : nil)
        .help("\(s.issue)\(s.title.map { " · " + $0 } ?? ""): \(s.isPartial ? "right on \(Int(((s.score ?? 0) * 100).rounded())) % of its attempts" : s.right == true ? "right" : s.score == nil ? "not answered" : "wrong")" + (s.flipped ? " · changed" : ""))
        if let open {
            Button { open(s) } label: { base.contentShape(Rectangle()) }.buttonStyle(.plain)
        } else {
            base
        }
    }
}

/// The legend under squares: right · wrong · the tick (· ring).
struct EvalsASquaresLegend: View {
    @Environment(\.theme) private var t
    var floorText: String?
    var ring = false
    var body: some View {
        HStack(spacing: 14) {
            item(AnyView(RoundedRectangle(cornerRadius: 2).fill(t.diffAddText.color)), "got it right")
            item(AnyView(RoundedRectangle(cornerRadius: 2).fill(t.surface2.color).overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(t.separatorStrong.color))), "got it wrong")
            if ring { item(AnyView(RoundedRectangle(cornerRadius: 2).stroke(t.accent.color, lineWidth: 2)), "changed between the two") }
            if let f = floorText { item(AnyView(Rectangle().fill(t.text.color).frame(width: 2)), f) }
        }
    }
    private func item(_ v: AnyView, _ s: String) -> some View {
        HStack(spacing: 5) { v.frame(width: 10, height: 10); Text(s).ui(TypeScale.caption).foregroundStyle(t.text2.color) }
    }
}

/// The stamp under every score: layer · model · agent (+CLI version) · rules @ hash · task version; missing parts say
/// "not recorded" in the verdict colour.
struct EvalsAStampLine: View {
    @Environment(\.theme) private var t
    let stamp: EvalStamp?
    var body: some View {
        if let s = stamp {
            let parts = s.parts
            parts.enumerated().reduce(Text("")) { acc, e in
                let p = e.element
                let piece = Text(p.value ?? "\(p.label) not recorded").foregroundColor(p.value == nil ? t.needsText.color : t.text3.color)
                return e.offset == 0 ? piece : acc + Text(" · ").foregroundColor(t.text3.color) + piece
            }
            .ui(TypeScale.micro, mono: true).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            .help(s.recorded ? "Recorded with this test" : "Derived for a test made before 2.0.4: the parts it could not know say \"not recorded\"")
        } else {
            Text("stamp not recorded").ui(TypeScale.micro, mono: true).foregroundStyle(t.needsText.color)
                .help("This test carries no stamp (layer, model, agent, rules, task version)")
        }
    }
}

/// "TODAY'S ANSWER" block filled by its tone.
struct EvalsAAnswerBlock: View {
    @Environment(\.theme) private var t
    let answer: EvalsAAnswer
    var kicker = "Today's answer"
    var body: some View {
        let c = t.evalsATone(answer.tone)
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker.uppercased()).ui(10.5, .semibold).tracking(0.6).foregroundStyle(c.ink.color.opacity(0.85))
            Text(answer.headline).ui(TypeScale.section, .bold).foregroundStyle(c.ink.color).fixedSize(horizontal: false, vertical: true)
            Text(answer.body).ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(c.fill.color))
        .accessibilityElement(children: .combine)
    }
}

/// One bar of a mini-chart: label and value text on top, the bar (floor tick dashed), a note under it.
struct EvalsABarRow: View {
    @Environment(\.theme) private var t
    let bar: EvalsABar
    var hover: (EvalHover.Kind, String)?
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(bar.label).ui(TypeScale.small, .semibold).foregroundStyle(bar.muted ? t.text2.color : t.text.color).lineLimit(1)
                Spacer(minLength: 6)
                Text(bar.text).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(bar.muted ? t.text2.color : t.accentText.color)
                    .evalHoverIf(hover)
            }
            GeometryReader { g in
                let w = g.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(t.control.color).frame(height: 6)
                    if let v = bar.value {
                        Capsule().fill(bar.muted ? t.text3.color : t.accent.color).frame(width: max(CGFloat(min(max(v, 0), 1)) * w, 3), height: 6)
                    }
                    if let f = bar.floor {
                        Rectangle().fill(t.text.color).frame(width: 2, height: 12).offset(x: CGFloat(f) * w - 1)
                    }
                }
                .frame(height: 12)
            }
            .frame(height: 12)
            if let n = bar.note { Text(n).ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(2).fixedSize(horizontal: false, vertical: true) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// An honest empty or error state: what is missing, why, and (optionally) the engine's own words.
struct EvalsAEmpty: View {
    @Environment(\.theme) private var t
    let title: String
    let detail: String
    var error: String?
    var action: (String, () -> Void)?
    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                Text(detail).ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if let e = error { Text(e).ui(TypeScale.caption, mono: true).foregroundStyle(t.needsText.color).textSelection(.enabled).lineLimit(4) }
                if let a = action { RoofButton(a.0, action: a.1).padding(.top, 4) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// A numbers line whose words come with a lesson: the system tooltip has the definition, right-click opens the lesson.
/// (Git history numbers have no hover kind of their own in EvalHover; they use this.)
struct EvalsALessonHint: ViewModifier {
    let definition: String
    let lesson: String
    let nav: EvalsNav
    func body(content: Content) -> some View {
        content.help(definition + "\nRight-click: open the lesson")
            .contextMenu { Button("Open the lesson ›") { nav.openLesson(lesson) } }
            .accessibilityHint(definition)
    }
}

extension View {
    func evalsALesson(_ definition: String, lesson: String, nav: EvalsNav) -> some View {
        modifier(EvalsALessonHint(definition: definition, lesson: lesson, nav: nav))
    }
}
