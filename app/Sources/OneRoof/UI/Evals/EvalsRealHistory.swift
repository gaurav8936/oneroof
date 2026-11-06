import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E4.1 Real history: not a test — what git shows about agent commits. Engine: `xray --repo R [--repo …] --days N`
/// (CONTRACT §6). Per agent: commits, "followed by a fix" = fixup × commits (the count and the %, one decimal, never rounded
/// to "about 1 in 5"), rewritten, fixes its own work, reverted, model per commit (not recorded until LAB-2240). Commits
/// with no agent name are drawn hatched and never credited to an agent (LAB-2241 signs them from now on). Repos: the ones
/// our tasks were built from (as 2.0.3's X-ray), plus any you add; 60 days by default. Then the test-vs-history join.
/// LAB-2254 · E3.4: the "followed by a fix" count (its button and the bar's segment), rewritten and reverted open the commits
/// behind them inline (`xray … --commits KIND --agent NAME`), each with the later commit(s) that fixed, rewrote or reverted it.
struct EvalsRealHistoryView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    @AppStorage(Self.reposKey, store: Prefs.viewState) private var reposPref = ""
    @AppStorage(Self.daysKey, store: Prefs.viewState) private var days = 60
    /// LAB-2254: the commit list open under each agent's card (one at a time per card).
    @State private var openList: [String: EvalCommitList.Kind] = [:]

    static let reposKey = "evals.realHistory.repos"
    static let daysKey = "evals.realHistory.days"

    /// The saved repo list (newline-separated), else the default (our tasks' repos).
    static func repos(_ pref: String, board: EvalsBoard) -> [String] {
        let saved = pref.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return saved.isEmpty ? EvalsAStore.defaultRepos(board) : saved
    }
    private var repos: [String] { Self.repos(reposPref, board: board) }
    private var key: String { EvalsAStore.key(repos, days: days) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                switch store.xray[key] {
                case .success(let x)?: loaded(x)
                case .failure(let e)?:
                    EvalsAEmpty(title: "Git history could not be read", detail: "Real history reads `xray` over the repos above.", error: e.message,
                                action: ("Try again", { store.refreshXRay(board, repos: repos, days: days, force: true) }))
                case nil:
                    if repos.isEmpty {
                        EvalsAEmpty(title: "No repo chosen", detail: "Pick a repo to read what happened to its agents' commits.",
                                    action: ("Choose a repo…", { add() }))
                    } else {
                        Text("Reading \(repos.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")) over \(days) days (up to a minute)…")
                            .ui(TypeScale.small).foregroundStyle(t.text2.color)
                    }
                }
            }
            .frame(maxWidth: 1100, alignment: .leading)
            .padding(.bottom, 20)
        }
        .onAppear { store.refreshXRay(board, repos: repos, days: days); store.refreshBoards(board) }
        .onChange(of: key) { _, _ in store.refreshXRay(board, repos: repos, days: days) }
        .onChange(of: board.sets) { _, _ in store.refreshXRay(board, repos: repos, days: days); store.refreshBoards(board) }
    }

    // MARK: Controls: repos, days

    private var controls: some View {
        HStack(spacing: 10) {
            Text("Not a test: what actually happened to agent commits.").ui(TypeScale.small).foregroundStyle(t.text2.color)
            Spacer()
            FieldMenu(title: repos.isEmpty ? "Choose repos" : "Repos: " + repos.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "), expand: false) {
                ForEach(repos, id: \.self) { r in
                    Button("✓ " + (r as NSString).lastPathComponent) { setRepos(repos.filter { $0 != r }) }
                }
                Divider()
                ForEach(EvalsAStore.defaultRepos(board).filter { !repos.contains($0) }, id: \.self) { r in
                    Button((r as NSString).lastPathComponent) { setRepos(repos + [r]) }
                }
                Button("Add a repo…", action: add)
                Button("Back to our tasks' repos") { reposPref = "" }
            }
            Segmented(options: [(30, "30 days"), (60, "60 days"), (90, "90 days")], selection: $days).fixedSize()
            RoofButton("Read again") {   // LAB-2255: an action, a button you can see
                store.forgetCommitLists(repos: repos, days: days)
                store.refreshXRay(board, repos: repos, days: days, force: true)
            }
                .disabled(store.isReading(repos: repos, days: days))
        }
    }

    private func setRepos(_ xs: [String]) { reposPref = xs.joined(separator: "\n") }

    private func add() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; p.allowsMultipleSelection = true
        if p.runModal() == .OK { setRepos(Array(NSOrderedSet(array: repos + p.urls.map(\.path))) as? [String] ?? repos) }
    }

    // MARK: Loaded

    @ViewBuilder private func loaded(_ x: EvalXRay) -> some View {
        let rows = EvalHistoryRow.from(x)
        let names = repos.map { ($0 as NSString).lastPathComponent }.joined(separator: ", ")
        Text(EvalsAHistory.pageHeadline(rows)).ui(17, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        Text("\(names) · last \(x.windowDays) days · computed \(EvalModels.when(x.computed))").ui(TypeScale.caption).foregroundStyle(t.text3.color)
        ForEach(rows.filter { !$0.isUntagged }) { r in agentCard(r, horizon: x.horizonDays ?? 14) }
        if let u = rows.first(where: \.isUntagged) { untaggedCard(u, horizon: x.horizonDays ?? 14) }
        if rows.isEmpty {
            EvalsAEmpty(title: "No commits in this window", detail: "No commit in \(names) over the last \(x.windowDays) days.")
        }
        fitsCard(rows)
        Text("From git alone: a commit belongs to an agent when its Co-Authored-By or author names it; everything else has no agent name. Rewritten and fixes-own-work need commits at least \(x.horizonDays ?? 14) days old.")
            .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
    }

    private func agentCard(_ r: EvalHistoryRow, horizon: Int) -> some View {
        let s = EvalsAHistory.split(r)
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(r.agent).ui(TypeScale.section, .bold).foregroundStyle(t.text.color)
                    Text("\(r.commits) commits" + (r.lines.map { " · \($0.formatted()) lines" } ?? "") + " · signed Co-Authored-By or author: \(r.agent)")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color)
                        .evalsALesson(EvalXRay.definitions["Commits"] ?? "", lesson: "golden-sets", nav: nav)
                }
                bar(rest: s.rest, fix: s.fix, pct: EvalHistoryRow.pct(r.fixup), open: { toggle(r.agent, .fixup) })
                HStack(alignment: .top, spacing: 18) {
                    fact("Followed by a fix", "\(s.fix) · \(EvalHistoryRow.pct(r.fixup))", key: "Followed by a fix",
                         list: (.fixup, s.fix), agent: r.agent)
                    fact("Rewritten in \(horizon) days", EvalHistoryRow.pct(r.churn), key: "Churn",
                         list: r.rewrittenCommits.map { (.churn, $0) }, agent: r.agent)
                    fact("Fixes its own work", EvalHistoryRow.pct(r.selfShare), key: "Fixes own work")
                    fact("Reverted", "\(EvalHistoryRow.pct(r.revert))" + (r.reverted.map { " · \($0)" } ?? ""), key: "Reverted",
                         list: r.revertCount.map { (.revert, $0) }, agent: r.agent)
                    VStack(alignment: .leading, spacing: 2) {
                        EvalsLabel("Model per commit")
                        Text("not recorded · LAB-2240").ui(TypeScale.small, .semibold).foregroundStyle(t.needsText.color)
                    }
                    .help("Sessions do not record which model wrote a commit yet (LAB-2240), so history can't be split by model.")
                }
                if let k = openList[r.agent] {
                    EvalsCommitListCard(board: board, repos: repos, days: days, horizon: horizon, kind: k, agent: r.agent,
                                        expected: expected(r, k), close: { openList[r.agent] = nil })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The count a list must match: the one the card shows for that kind.
    private func expected(_ r: EvalHistoryRow, _ k: EvalCommitList.Kind) -> Int? {
        switch k {
        case .fixup: return EvalsAHistory.split(r).fix
        case .churn: return r.rewrittenCommits
        case .revert: return r.revertCount
        }
    }

    private func toggle(_ agent: String, _ k: EvalCommitList.Kind) {
        openList[agent] = openList[agent] == k ? nil : k
    }

    /// A fact; with `list` (a count above 0) a visible button under it opens the commits behind it (LAB-2254/LAB-2255).
    private func fact(_ label: String, _ value: String, key: String, list: (EvalCommitList.Kind, Int)? = nil, agent: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            VStack(alignment: .leading, spacing: 2) {
                EvalsLabel(label)
                Text(value).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color)
            }
            .evalsALesson(EvalXRay.definitions[key] ?? label, lesson: "golden-sets", nav: nav)
            if let l = list, l.1 > 0 {
                RoofButton(openList[agent] == l.0 ? EvalCommitList.hideTitle : EvalCommitList.seeTitle(l.1)) { toggle(agent, l.0) }
            }
        }
    }

    /// Commits not followed by a fix (green) | followed by a fix (peach), with the counts written in. The peach segment
    /// opens the commits behind it (as the button under "Followed by a fix" does).
    private func bar(rest: Int, fix: Int, pct: String, open: @escaping () -> Void) -> some View {
        let total = max(rest + fix, 1)
        let peach = t.evalsATone(.cantTell)
        return GeometryReader { g in
            let w = g.size.width, fw = max(CGFloat(fix) / CGFloat(total) * w, fix > 0 ? 70 : 0)
            HStack(spacing: 2) {
                Text("\(rest) not followed by a fix").ui(TypeScale.caption, .semibold).foregroundStyle(t.onAccent.color).lineLimit(1)
                    .padding(.horizontal, 8).frame(width: max(w - fw - 2, 0), height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.diffAddText.color))
                if fix > 0 {
                    Button(action: open) {
                        Text("\(fix) followed by a fix ›").ui(TypeScale.caption, .semibold).foregroundStyle(peach.ink.color).lineLimit(1).minimumScaleFactor(0.7)
                            .padding(.horizontal, 6).frame(width: fw, height: 24, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(peach.fill.color))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("See the \(fix) commits followed by a fix")
                }
            }
        }
        .frame(height: 24)
        .accessibilityLabel("\(rest) commits not followed by a fix, \(fix) followed by a fix, \(pct)")
    }

    private func untaggedCard(_ u: EvalHistoryRow, horizon: Int) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("No agent name").ui(TypeScale.section, .bold).foregroundStyle(t.text.color)
                    Text("\(u.commits) commits" + (u.lines.map { " · \($0.formatted()) lines" } ?? "")).ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
                Text(EvalsAHistory.untaggedLine).ui(TypeScale.caption, .semibold).foregroundStyle(t.text2.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
                    .background(EvalsAHatch())
                Text("No agent in Co-Authored-By or author, so these commits are never credited to an agent. For the record: \(EvalHistoryRow.pct(u.fixup)) followed by a fix, \(EvalHistoryRow.pct(u.churn)) rewritten in \(horizon) days, \(EvalHistoryRow.pct(u.revert)) reverted.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Text("To read them: have every agent sign its commits. LAB-2241: sessions One Roof starts set ONEROOF_AGENT, and the commit hook adds Co-Authored-By with the agent's name.")
                    .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                let lists: [(EvalCommitList.Kind, Int, String)] = [(.fixup, u.followedByFix ?? 0, "followed by a fix"),
                                                                    (.churn, u.rewrittenCommits ?? 0, "rewritten"),
                                                                    (.revert, u.revertCount ?? 0, "reverted")].filter { $0.1 > 0 }
                if !lists.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(lists, id: \.0) { e in
                            RoofButton(openList[u.agent] == e.0 ? EvalCommitList.hideTitle : "\(e.1) \(e.2) ›") { toggle(u.agent, e.0) }
                        }
                    }
                }
                if let k = openList[u.agent] {
                    EvalsCommitListCard(board: board, repos: repos, days: days, horizon: horizon, kind: k, agent: u.agent,
                                        expected: expected(u, k), close: { openList[u.agent] = nil })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: How this fits with the tests (+ v1 screen 6's join)

    private func fitsCard(_ rows: [EvalHistoryRow]) -> some View {
        let lb = store.loaded(board).first
        let join = EvalsAHistory.join(lb, history: rows)
        return VStack(alignment: .leading, spacing: 10) {
            Text("How this fits with the tests").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
            Text("Compare tests every setup on the same bugs: fair, but small. This page is the opposite: every real commit, but each agent got different work. Read them side by side; neither alone is the answer. If a setup tests well but needs many follow-up fixes, the tasks are missing something: turn those fixes into tasks for the next version.")
                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    EvalsLabel("Setup")
                    EvalsLabel("\(lb?.title ?? "Our task") (test)")
                    EvalsLabel("Followed by a fix (history)")
                    EvalsLabel("Reading")
                }
                ForEach(join) { j in
                    GridRow {
                        Text(j.setup).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                        Text(j.test).ui(TypeScale.small).foregroundStyle(t.text.color)
                        Text(j.history).ui(TypeScale.small).foregroundStyle(j.history == "unsigned commits" ? t.needsText.color : t.text.color)
                        Text(j.reading).ui(TypeScale.small).foregroundStyle(t.text2.color)
                    }
                }
            }
            RoofButton("Our tests ›", .secondary) { nav.open(.agentOurs) }   // QA #11: 2.0.5 name; LAB-2255: a visible button
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.selection.color.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
    }
}

/// Diagonal hatching (separatorStrong on surface2): "can't be read" without a number.
struct EvalsAHatch: View {
    @Environment(\.theme) private var t
    var body: some View {
        Canvas { ctx, size in
            ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5), with: .color(t.surface2.color))
            var p = Path()
            var x: CGFloat = -size.height
            while x < size.width { p.move(to: CGPoint(x: x, y: size.height)); p.addLine(to: CGPoint(x: x + size.height, y: 0)); x += 8 }
            ctx.clip(to: Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 5))
            ctx.stroke(p, with: .color(t.separatorStrong.color), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

/// LAB-2254 · the commits behind one Real history count, inline under the agent's card: subject, date, repo, short SHA and
/// agent, and beside each the later commit(s) that fixed, rewrote or reverted it. Read from `xray … --commits KIND --agent`,
/// which builds the count and the list in one pass; if the list and the card's count still differ (read at different
/// times), it says so instead of hiding it.
struct EvalsCommitListCard: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    let repos: [String]
    let days: Int
    let horizon: Int
    let kind: EvalCommitList.Kind
    let agent: String
    let expected: Int?
    let close: () -> Void

    private var key: String { EvalsAStore.listKey(repos, days: days, kind: kind, agent: agent) }
    private var missing: Bool { store.commitLists[key] == nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch store.commitLists[key] {
            case .success(let l)?: loaded(l)
            case .failure(let e)?:
                Text("The commits could not be read").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                Text(e.message).ui(TypeScale.caption, mono: true).foregroundStyle(t.needsText.color).textSelection(.enabled).lineLimit(4)
                HStack(spacing: 8) {
                    RoofButton("Try again") { refresh(force: true) }
                    RoofButton(EvalCommitList.hideTitle, .plain, action: close)
                }
            case nil:
                Text("Reading the commits \(kind.what(horizon: horizon)) (up to a minute)…").ui(TypeScale.small).foregroundStyle(t.text2.color)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface2.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .onAppear { refresh() }
        .onChange(of: missing) { _, m in if m { refresh() } }
        .onChange(of: kind) { _, _ in refresh() }
    }

    private func refresh(force: Bool = false) {
        store.refreshCommitList(board, repos: repos, days: days, kind: kind, agent: agent, force: force)
    }

    @ViewBuilder private func loaded(_ l: EvalCommitList) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(l.title(horizon: horizon)).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
            Spacer()
            RoofButton(EvalCommitList.hideTitle, .plain, action: close)
        }
        if let n = expected, n != l.count {
            Text("This list has \(l.count) and the count above says \(n): they were read at different times. Read again to read both together.")
                .ui(TypeScale.caption, .semibold).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
        }
        if kind == .fixup {
            Text("A later commit within 3 days that touches a same file and says fix, bug, regress, broke or revert. A proxy: it does not prove the fix was for this commit.")
                .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
        }
        if l.commits.isEmpty {
            Text("No commit in this window.").ui(TypeScale.small).foregroundStyle(t.text2.color)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(l.commits) { c in row(c) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)
        }
    }

    private func row(_ c: EvalCommitList.Commit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(c.short).ui(TypeScale.caption, .semibold, mono: true).foregroundStyle(t.text2.color).help(c.sha).textSelection(.enabled)
                Text(c.subject).ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).lineLimit(2)
                Spacer(minLength: 8)
                Text(meta(c.agent, c.date, repo: c.repo) + (c.linesRewritten.map { " · \($0) lines rewritten" } ?? ""))
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
            }
            ForEach(Array(c.by.enumerated()), id: \.element.id) { i, b in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(i == 0 ? kind.byLabel : "and").ui(TypeScale.caption).foregroundStyle(t.text3.color).frame(width: 84, alignment: .trailing)
                    Text(b.short).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).help(b.sha).textSelection(.enabled)
                    Text(b.subject).ui(TypeScale.caption).foregroundStyle(t.text.color).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(meta(b.agent, b.date, repo: nil)).ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func meta(_ agent: String, _ date: String, repo: String?) -> String {
        let who = agent == "unattributed" ? "no agent name" : agent
        return ([who, EvalCommitList.day(date)] + (repo.map { [$0] } ?? [])).joined(separator: " · ")
    }
}
