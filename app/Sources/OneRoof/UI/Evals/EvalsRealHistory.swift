import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E4.1 Real history: not a test — what git shows about agent commits. Engine: `xray --repo R [--repo …] --days N`
/// (CONTRACT §6). Per agent: commits, "followed by a fix" = fixup × commits (the count and the %, one decimal, never rounded
/// to "about 1 in 5"), rewritten, fixes its own work, reverted, model per commit (not recorded until LAB-2240). Commits
/// with no agent name are drawn hatched and never credited to an agent (LAB-2241 signs them from now on). Repos: the ones
/// our tasks were built from (as 2.0.3's X-ray), plus any you add; 60 days by default. Then the test-vs-history join.
struct EvalsRealHistoryView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @ObservedObject private var store = EvalsAStore.shared
    @Environment(\.theme) private var t
    @AppStorage(Self.reposKey, store: Prefs.viewState) private var reposPref = ""
    @AppStorage(Self.daysKey, store: Prefs.viewState) private var days = 60

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
            RoofButton("Read again", .plain) { store.refreshXRay(board, repos: repos, days: days, force: true) }
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
                bar(rest: s.rest, fix: s.fix, pct: EvalHistoryRow.pct(r.fixup))
                HStack(spacing: 18) {
                    fact("Followed by a fix", "\(s.fix) · \(EvalHistoryRow.pct(r.fixup))", key: "Followed by a fix")
                    fact("Rewritten in \(horizon) days", EvalHistoryRow.pct(r.churn), key: "Churn")
                    fact("Fixes its own work", EvalHistoryRow.pct(r.selfShare), key: "Fixes own work")
                    fact("Reverted", "\(EvalHistoryRow.pct(r.revert))" + (r.reverted.map { " · \($0)" } ?? ""), key: "Reverted")
                    VStack(alignment: .leading, spacing: 2) {
                        EvalsLabel("Model per commit")
                        Text("not recorded · LAB-2240").ui(TypeScale.small, .semibold).foregroundStyle(t.needsText.color)
                    }
                    .help("Sessions do not record which model wrote a commit yet (LAB-2240), so history can't be split by model.")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func fact(_ label: String, _ value: String, key: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            EvalsLabel(label)
            Text(value).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color)
        }
        .evalsALesson(EvalXRay.definitions[key] ?? label, lesson: "golden-sets", nav: nav)
    }

    /// Commits not followed by a fix (green) | followed by a fix (peach), with the counts written in.
    private func bar(rest: Int, fix: Int, pct: String) -> some View {
        let total = max(rest + fix, 1)
        let peach = t.evalsATone(.cantTell)
        return GeometryReader { g in
            let w = g.size.width, fw = max(CGFloat(fix) / CGFloat(total) * w, fix > 0 ? 70 : 0)
            HStack(spacing: 2) {
                Text("\(rest) not followed by a fix").ui(TypeScale.caption, .semibold).foregroundStyle(t.onAccent.color).lineLimit(1)
                    .padding(.horizontal, 8).frame(width: max(w - fw - 2, 0), height: 24, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(t.diffAddText.color))
                if fix > 0 {
                    Text("\(fix) followed by a fix").ui(TypeScale.caption, .semibold).foregroundStyle(peach.ink.color).lineLimit(1).minimumScaleFactor(0.7)
                        .padding(.horizontal, 6).frame(width: fw, height: 24, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(peach.fill.color))
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
                ZStack(alignment: .leading) {
                    EvalsAHatch().frame(height: 24)
                    Text("Probably Codex, Kimi and hand edits: can't be split by agent").ui(TypeScale.caption, .semibold).foregroundStyle(t.text2.color)
                        .padding(.horizontal, 8)
                }
                Text("No agent in Co-Authored-By or author, so these commits are never credited to an agent. For the record: \(EvalHistoryRow.pct(u.fixup)) followed by a fix, \(EvalHistoryRow.pct(u.churn)) rewritten in \(horizon) days, \(EvalHistoryRow.pct(u.revert)) reverted.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Text("To read them: have every agent sign its commits. LAB-2241: sessions One Roof starts set ONEROOF_AGENT, and the commit hook adds Co-Authored-By with the agent's name.")
                    .ui(TypeScale.small).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
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
            Button { nav.go(.compare) } label: { Text("Open Compare ›").ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain)
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
