import SwiftUI
import OneRoofCore

/// LAB-2242 · E3.1 Changes: did my last change help? The same setup on the same frozen bugs, before and after a change.
/// Engine: `changes --repo <our tasks' repo> --days 60` (CONTRACT §5: yours from git, the vendor's from recorded stamps);
/// `samples` + `compare` for a change tested on both sides. Real data only: the list is what git and the stamps say, an empty
/// list is an answer, and no sample entries ever ship. Until a stamped agent test exists the page says "We can't tell yet"
/// (LAB-2240). Also here: 2.0.3's "what changed since last time" (the same setup tested twice, paired) with Re-run ×3.
struct EvalsChangesView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    @State private var pair: Pair?

    /// A change tested on both sides: its squares (set order, flips ringed) and the verdict by rule.
    struct Pair: Equatable {
        var change: EvalChange
        var before: [EvalsASquare]
        var after: [EvalsASquare]
        var toRight: [String]
        var toWrong: [String]
        var compare: EvalCompareResult?
        var error: String?
        /// The blind-guess floor of the pair's own task version, read by task + version (re-review #5).
        var floor: EvalsAChanges.Floor = .reading
    }

    var body: some View {
        let boards = store.loaded(board)
        let canTell = EvalsAChanges.canTell(boards)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Every time you change how an agent works, test it on the same bugs before and after.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                if !canTell { banner }
                changesCard(boards)
                answerCard(boards)
                sameSetupCard
                loopCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)   // LAB-2273: flexes with the window
            .padding(.bottom, 20)
        }
        .onAppear { store.refreshChanges(board); store.refreshBoards(board); loadPair() }
        .onChange(of: store.changes.map { if case .success(let c) = $0 { return c.count }; return -1 }) { _, _ in loadPair() }
    }

    // MARK: Banner (until LAB-2240's stamps exist)

    private var banner: some View {
        let c = t.evalsATone(.gap)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("We can't tell yet.").ui(TypeScale.section, .bold).foregroundStyle(c.ink.color)
                Text("No agent test has recorded which version of your rules (CLAUDE.md, skills, permissions) it used, so there is no “before” to compare with. LAB-2240 adds that stamp to every test from 2.0.4: test a setup now, make your change, test it again.")
                    .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            RoofButton("Test the baseline now") { testBeforeAfter(nil) }
                .help("Set up a test pre-filled with an agent on our main task; nothing starts until Start")
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(c.fill.color))
    }

    // MARK: Your recent changes

    @ViewBuilder private func changesCard(_ boards: [EvalSetupLeaderboard]) -> some View {
        let repo = EvalsAStore.ownSets(board).compactMap(\.repoPath).first.map { ($0 as NSString).lastPathComponent }
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Your recent changes").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text("read from git" + (repo.map { " (\($0))" } ?? "") + " and from agent updates · last 60 days").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    Spacer()
                    RoofButton("Read again") { store.refreshChanges(board, force: true) }   // LAB-2255: an action, a button you can see
                }
                .padding(14)
                Divider()
                switch store.changes {
                case .success(let cs)?:
                    if cs.isEmpty {
                        Text("No change to your rules, skills or agents in the last 60 days.").ui(TypeScale.small).foregroundStyle(t.text2.color).padding(14)
                    }
                    ForEach(Array(cs.enumerated()), id: \.element.id) { i, c in
                        if i > 0 { Divider() }
                        changeRow(c)
                    }
                case .failure(let e)?:
                    Text("The changes could not be read: " + e.message).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled).padding(14)
                case nil:
                    Text("Reading git and agent updates…").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                }
            }
        }
    }

    private func changeRow(_ c: EvalChange) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(EvalsAWords.day(c.at)).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color).frame(width: 56, alignment: .leading)
            whoPill(c)
            VStack(alignment: .leading, spacing: 1) {
                Text(c.what).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(2)
                if let cm = c.commit {
                    Text("commit \(cm)" + (c.path.map { " · \($0)" } ?? "")).ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color).textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(EvalsAChanges.status(c)).ui(TypeScale.caption).foregroundStyle(c.testedAlone ? t.diffAddText.color : t.text2.color).frame(width: 150, alignment: .leading)
            RoofButton("Test before & after") { testBeforeAfter(c) }.fixedSize()   // LAB-2255
                .help("Set up a test pre-filled with the same setup and task; nothing starts until Start")
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
    }

    private func whoPill(_ c: EvalChange) -> some View {
        let you = c.who == .you
        let tone = you ? (fill: t.diffAddFill, ink: t.diffAddText) : t.evalsATone(.cantTell)
        return Text(EvalsAChanges.who(c)).ui(10.5, .semibold).foregroundStyle(tone.ink.color)
            .padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(tone.fill.color))
            .frame(width: 60, alignment: .leading)
            .help(you ? "You changed it (git log on CLAUDE.md, AGENTS.md, skills, settings)" : "The vendor changed it (agent CLI version or its default model, from recorded stamps)")
    }

    /// Set up a test pre-filled: the same agent setup on our main task (the "before"; the "after" is the same plan later).
    private func testBeforeAfter(_ c: EvalChange?) {
        let boards = store.loaded(board)
        guard let lb = boards.first, let file = EvalsCompareView.taskFile(lb, board: board) else { nav.test(nil); return }
        let agent = lb.rows.first { $0.layer != .model }.flatMap { $0.stamp?.agent ?? String($0.setupId.split(separator: ":").first ?? "") } ?? "claude_code"
        nav.test(EvalsACompare.plan([EvalsAUntested(label: agent, agent: agent, model: nil)], taskFile: file, cases: lb.n ?? lb.cases.count))
    }

    // MARK: Before / after

    @ViewBuilder private func answerCard(_ boards: [EvalSetupLeaderboard]) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Text(pair == nil ? "What an answer will look like" : "Before and after").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                if let p = pair {
                    Text("“\(p.change.what)” · the same \(p.after.count) bugs, before and after").ui(TypeScale.small).foregroundStyle(t.text2.color)
                    squaresRow("Before", p.before)
                    squaresRow("After", p.after)
                    EvalsASquaresLegend(ring: true)
                    verdictLine(p, floor: p.floor)
                } else {
                    Text("When a change has a stamped test on each side, it shows here: the same frozen bugs before and after, every bug that flipped outlined, and a verdict chosen by rule from the paired range (“probably helped, not proven” while the range still includes no change). Nothing is drawn until real tests exist.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func squaresRow(_ label: String, _ xs: [EvalsASquare]) -> some View {
        HStack(spacing: 14) {
            Text(label).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).frame(width: 52, alignment: .leading)
            Text("\(EvalsAOneTest.score(xs).map { EvalScoreText.count($0.right) } ?? "0") of \(xs.filter { $0.score != nil }.count)").ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 60, alignment: .leading)
            EvalsABugSquares(squares: xs)
        }
    }

    private func verdictLine(_ p: Pair, floor: EvalsAChanges.Floor) -> some View {
        // review P2 #5: the floor of the pair's task version and each side's own Wilson bounds go into the rule
        let v = EvalsAChanges.verdict(before: p.before, after: p.after, compare: p.compare, floor: floor)
        let lead = EvalsAChanges.lead(diff: p.compare?.diff ?? 0, verdict: v)
        return VStack(alignment: .leading, spacing: 4) {
            (Text("Verdict: \(lead). ").bold() + Text(EvalsAChanges.flipLine(toRight: p.toRight.count, toWrong: p.toWrong.count) + " " + v.text + "."))
                .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                .evalHoverIf(p.compare.map { c in (.compare, EvalHover.compare(diff: c.diff, lo: c.ci95.first ?? c.diff, hi: c.ci95.last ?? c.diff, paired: c.paired)) })
            if let e = p.error { Text(e).ui(TypeScale.caption).foregroundStyle(t.needsText.color) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
    }

    /// The newest change with a test on both sides: its two runs' cases and the paired compare.
    private func loadPair() {
        // a pair that covers several changes together is never drawn as one change's before/after (re-review #3)
        guard case .success(let cs)? = store.changes, let c = cs.first(where: \.testedAlone),
              let before = c.tested?.before, let after = c.tested?.after else { pair = nil; return }
        board.caseResults(run: before) { b in
            board.caseResults(run: after) { a in
                var order: [String] = []
                for x in a where !order.contains(x.id) { order.append(x.id) }
                func sq(_ xs: [EvalCaseResult]) -> [EvalsASquare] { EvalsASquares.fromCaseResults(xs, order: order) }
                let f = EvalsASquares.flips(before: sq(b), after: sq(a))
                pair = Pair(change: c, before: f.before, after: f.after, toRight: f.toRight, toWrong: f.toWrong)
                if let q = EvalsAChanges.floorQuery(c) {   // the floor of the pair's task version, never the latest board's
                    board.ask(q, EvalSetupLeaderboard.self, timeout: 120) { r in
                        guard pair?.change == c else { return }
                        if case .success(let lb) = r { pair?.floor = EvalsAChanges.floor(of: c, board: lb) } else { pair?.floor = .unknown }
                    }
                } else {
                    pair?.floor = .unknown
                }
                board.ask(["compare", after, before], EvalCompareResult.self, timeout: 120) { r in
                    switch r {
                    case .success(let x): pair?.compare = x
                    case .failure(let e): pair?.error = e.message
                    }
                }
            }
        }
    }

    // MARK: The same setup, tested twice (2.0.3's "what changed since last time" + Over time's Re-run ×3)

    @ViewBuilder private var sameSetupCard: some View {
        if let o = board.overview, !o.changes.isEmpty {
            Card(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("The same setup, tested again").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text("Two tests of one setup on one task, paired. Without a stamp these can't be tied to a change; they show drift and noise.")
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    ForEach(o.changes) { c in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(c.isNoise || c.delta >= 0 ? "●" : "▾").ui(TypeScale.caption)
                                .foregroundStyle(c.isNoise ? t.text3.color : (c.delta < 0 ? t.needsText.color : t.diffAddText.color))
                            Button { nav.openRun(c.runs[0]) } label: {   // LAB-2255: a row that looks clickable (chevron + hover)
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text(c.text).ui(TypeScale.small).foregroundStyle(c.isNoise ? t.text2.color : t.text.color)
                                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(t.accentText.color)
                                }
                                .padding(.horizontal, 6).padding(.vertical, 2).hoverHighlight()
                            }
                            .buttonStyle(.plain)
                            .evalHover(.compare, EvalHover.compare(diff: c.delta, lo: c.ci95.first ?? c.delta, hi: c.ci95.last ?? c.delta, paired: true))
                            Spacer()
                            if c.delta < 0, let r = board.results.first(where: { $0.id == c.runs[0] }) {
                                RoofButton("Re-run ×3") {
                                    var p = EvalRunPlan.again(r, stamp: store.stamps[r.id]?.stamp); p.epochs = 3; nav.test(p)
                                }
                                .help("Set up a test pre-filled with 3 attempts each; a drop only counts when it is bigger than the noise")
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: Re-test after every change (needs LAB-2240)

    private var loopCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Re-test automatically after every change").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                Text("A Loop runs the same bugs whenever CLAUDE.md, a skill, a rule or the model changes. Seat time only.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: .constant(false)).toggleStyle(.switch).labelsHidden().disabled(true)
                .help("Needs LAB-2240: every test stamped with its rules version first")
            Text("needs LAB-2240").ui(TypeScale.caption).foregroundStyle(t.text3.color)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.selection.color.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
    }
}
