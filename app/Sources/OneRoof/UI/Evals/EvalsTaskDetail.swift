import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E5.2 One task (screen lane B): what it was built from, how many were picked, what a blind guess gets (and
/// its rule), the best so far with its verdict against the guess; every bug with the files its fix changed and who solved
/// it (each opens every setup's answer); the next version from a real dry run (every usable fix in the window, or this
/// version's bugs + the new ones), Preview · Freeze; the versions (results never mix them); the command line. Route
/// `.oneTask(name:version:)`. Engine: `evalset show|versions|build [--dry-run]`, `item-results`. Replaces 2.0.3's set page.
struct EvalsTaskDetailView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let name: String?
    var version: Int?
    @Environment(\.theme) private var t
    @Environment(\.v2Window) private var v2
    @State private var detail: EvalSetDetail?
    @State private var detailError: String?
    @State private var reportSource: String?
    @State private var versions: EvalSetVersions?
    /// The blind guess and its rule from `leaderboard <task> --by setup` (CONTRACT §3); `evalset show`'s floor until it answers.
    @State private var floor: EvalSetupLeaderboard.Floor?
    @State private var sort: EvalSetDetail.Sort = .hardest
    @State private var openCase: String?
    @State private var caseAnswers: [String: [EvalItemDetail.RunAnswer]] = [:]

    private var setName: String? { name ?? nav.set ?? board.sets.first?.name }
    private var key: String { "\(setName ?? "")|\(version.map(String.init) ?? "latest")" }

    var body: some View {
        Group {
            if let d = detail {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        titleRow(d)
                        facts(d)
                        EvalsColumns(breakpoint: 1040, side: 320) { bugs(d) } aside: {
                            VStack(alignment: .leading, spacing: 14) {
                                EvalsNextVersionCard(board: board, set: d, currentSource: reportSource, autoPreview: nav.openBuild) {
                                    nav.openBuild = false; reload()
                                }
                                .id(d.name + "\(d.version)")
                                versionsCard(d)
                                cliCard(d)
                            }
                        }
                    }
                    .frame(maxWidth: 1320, alignment: .leading)
                    .padding(.bottom, 24)
                }
            } else if let e = detailError {
                Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).textSelection(.enabled)
            } else if board.sets.isEmpty && setName == nil {
                Text("No task yet: make one from Our tasks › + New task.").ui(TypeScale.body).foregroundStyle(t.text2.color)
            } else {
                Text("Reading the task…").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
        }
        .padding(.horizontal, v2 ? CGFloat(V2Layout.Bar.contentLead) : 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { reload() }
        .onChange(of: key) { _, _ in detail = nil; reload() }
        .onChange(of: board.sets) { _, _ in if detail == nil { reload() } }
    }

    // MARK: Engine

    private struct ShowExtra: Decodable {
        struct Stats: Decodable { var linear: Int?; var subject: Int? }
        var stats: Stats?
    }

    private func reload() {
        guard let n = setName else { return }
        if nav.set != n { nav.set = n }
        let args = ["evalset", "show", n] + (version.map { ["--version", String($0)] } ?? [])
        board.ask(args, EvalSetDetail.self) { r in
            switch r { case .success(let d): detail = d; detailError = nil; case .failure(let e): detailError = e.message }
        }
        board.ask(args, ShowExtra.self) { r in
            if case .success(let x) = r { reportSource = EvalNextVersion.source(linear: x.stats?.linear, subject: x.stats?.subject) }
        }
        board.ask(["evalset", "versions", n], EvalSetVersions.self) { if case .success(let v) = $0 { versions = v } }
        board.setupLeaderboard(task: n, version: version) { if case .success(let lb) = $0 { floor = lb.floor } }
    }

    // MARK: Title and facts

    private func titleRow(_ d: EvalSetDetail) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(EvalTaskWords.title(kind: d.kind)).ui(22, .bold).foregroundStyle(t.text.color)
                Text("\(EvalTaskWords.engineName(kind: d.kind)) · v\(d.version)" + (EvalTaskWords.day(d.frozen ?? d.built).map { " · frozen \($0)" } ?? "")
                     + " · \(EvalTaskWords.checkedBy) · \(d.repo)")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
            }
            Spacer()
            RoofButton("Test setups on it…", .primary) { nav.test(EvalRunPlan(tasks: [d.taskFile], models: [], limit: d.count)) }
                .help("Opens Set up a test with this version; nothing starts until you press Start")
        }
    }

    private func facts(_ d: EvalSetDetail) -> some View {
        let guess = (right: self.floor?.right ?? d.floor.right, of: self.floor?.of ?? d.floor.of)
        let rule = self.floor?.rule?.replacingOccurrences(of: "a blind guess: ", with: "") ?? EvalTaskWords.guessRule
        let floor = guess.of > 0 ? Double(guess.right) / Double(guess.of) : nil
        let best = d.best
        let side = best.map { b -> EvalVerdicts.Side in
            let right = b.score * Double(b.n)   // the attempts policy: may be fractional
            let w = EvalStats.wilson(b.score, n: b.n)
            return EvalVerdicts.Side(label: EvalTaskWords.contestant(b.contestant), right: right, n: b.n, lo: w.lo, hi: w.hi)
        }
        let verdict = side.flatMap { EvalVerdicts.againstFloor($0, floor: floor) }
        return HStack(alignment: .top, spacing: 10) {
            fact("Built from", "\(d.repo) · last \(d.days ?? 120) days", sub: nil)
            fact("Picked", "\(d.count) of \(d.stats?.commitsConsidered.map(String.init) ?? "?") fixes", sub: "the rest were left out on purpose")
            fact("Blind guess gets", EvalTaskWords.guessText(right: guess.right, of: guess.of), sub: rule)
                .evalHover(.floor, EvalHover.floor(share: floor, right: guess.right, of: guess.of))
            if let b = best, let s = side {
                VStack(alignment: .leading, spacing: 6) {
                    fact("Best so far", "\(EvalScoreText.count(s.right ?? 0)) of \(b.n) · \(s.label)", sub: verdict?.text, subTint: verdict?.isCall == true ? t.diffAddText : t.needsText)
                        .evalHover(.range, EvalHover.range(score: b.score, n: b.n, lo: s.lo ?? 0, hi: s.hi ?? 1, unit: "bug"))
                    RoofButton("Open the best test ›") { nav.openRun(b.run) }.fixedSize()   // LAB-2255: a button, not a tappable fact
                }
            } else {
                fact("Best so far", "Not run yet", sub: "Test setups on it to see who finds these bugs", subTint: t.needsText)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func fact(_ label: String, _ value: String, sub: String?, subTint: RGB? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ui(TypeScale.caption).foregroundStyle(t.text2.color)
            Text(value).ui(TypeScale.section, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            if let sub { Text(sub).ui(TypeScale.caption).foregroundStyle((subTint ?? t.text3).color).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .accessibilityElement(children: .combine)
    }

    // MARK: The bugs

    private func bugs(_ d: EvalSetDetail) -> some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("The \(d.count) bugs").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Text("every setup gets these exact ones").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    Spacer()
                    FieldMenu(title: sort.rawValue, height: 24, expand: false) {
                        ForEach(EvalSetDetail.Sort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
                    }
                    .fixedSize()
                }
                .padding(12)
                Rectangle().fill(t.separator.color).frame(height: 1)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow { ForEach(["Bug", "Report", "Files the fix changed", "Solved by"], id: \.self) { EvalsLabel($0) } }.padding(.vertical, 8)
                    ForEach(d.sorted(sort)) { c in
                        GridRow {
                            Text(c.issue ?? "–").ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                            Button { toggle(d, c) } label: {
                                Text(c.report).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help("Open: the full report and every setup's answer")
                            Text(c.files.map { ($0 as NSString).lastPathComponent }.joined(separator: " · "))
                                .ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: 240, alignment: .leading).help(c.files.joined(separator: "\n"))
                            Text(EvalSetDetail.solvedText(c.solvedBy)).ui(TypeScale.small, .semibold)
                                .foregroundStyle(c.solvedBy.runs > 0 && c.solvedBy.right == 0 ? t.needsText.color
                                                 : c.solvedBy.runs > 0 && c.solvedBy.right == c.solvedBy.runs ? t.diffAddText.color : t.text.color)
                                .evalHoverIf(c.solvedBy.runs > 0 ? (.score, EvalHover.score(score: Double(c.solvedBy.right) / Double(c.solvedBy.runs), n: c.solvedBy.runs)) : nil)
                        }
                        .padding(.vertical, 7)
                        .accessibilityElement(children: .combine)
                        if openCase == c.id { GridRow { caseDetail(c).gridCellColumns(4) } }
                        GridRow { Rectangle().fill(t.separator.color).frame(height: 1).gridCellColumns(4) }
                    }
                }
                .padding(.horizontal, 12)
                Text(d.kind == "triage"
                     ? "The agent gets the bug report and the code as it was before the fix, and writes a short note. Right when the note names a file the fix changed (checked by code). A bug opens to every setup's answer."
                     : "The agent gets the bug report and the code as it was before the fix, and names up to 3 files. Right when one is a file the fix changed. A bug opens to every setup's answer.")
                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true).padding(12)
            }
        }
    }

    private func toggle(_ d: EvalSetDetail, _ c: EvalSetDetail.Case) {
        openCase = openCase == c.id ? nil : c.id
        guard openCase != nil, caseAnswers[c.id] == nil else { return }
        board.ask(["item-results", d.taskFile, c.id], [EvalItemDetail.RunAnswer].self, timeout: 120) { if case .success(let a) = $0 { caseAnswers[c.id] = a } }
    }

    private func caseDetail(_ c: EvalSetDetail.Case) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.report).ui(TypeScale.small).foregroundStyle(t.text.color).textSelection(.enabled)
            Text("The fix changed " + c.files.joined(separator: ", ")).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                .textSelection(.enabled)
            if let a = caseAnswers[c.id] {
                if a.isEmpty { Text("No test on this version has answered it yet.").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                ForEach(a) { r in
                    HStack(spacing: 8) {   // LAB-2255: the way into the test is a button, not a text link
                        Text(r.right ? "✓" : "✕").foregroundStyle(r.right ? t.diffAddText.color : t.needsText.color)
                        Text(EvalTaskWords.contestant(r.contestant ?? r.model ?? "?")).ui(TypeScale.caption).foregroundStyle(t.text.color)
                        Text(r.answer ?? r.answerTail).ui(TypeScale.caption).foregroundStyle(t.text2.color).lineLimit(1)
                        Spacer(minLength: 6)
                        RoofButton("Open the test ›") { nav.openRun(r.run) }.fixedSize()
                    }
                }
            } else { Text("Reading each test's answer…").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.surface2.color))
        .padding(.bottom, 6)
    }

    // MARK: Versions · command line

    private func versionsCard(_ d: EvalSetDetail) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Versions").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                ForEach(versions?.versions ?? []) { v in
                    HStack(alignment: .firstTextBaseline) {
                        Text("v\(v.version)").ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 26, alignment: .leading)
                        Text("\(v.count) bugs · \(EvalTaskWords.day(v.frozen ?? v.built) ?? "?") · \(v.runs) test\(v.runs == 1 ? "" : "s")")
                            .ui(TypeScale.small).foregroundStyle(t.text2.color)
                        Spacer()
                        if v.version == d.version {
                            Text("shown").ui(TypeScale.small).foregroundStyle(t.text3.color)
                        } else {
                            RoofButton("Open") { nav.openTask(d.name, version: v.version) }.fixedSize()   // LAB-2255
                        }
                    }
                }
                HStack {
                    Text("v\((versions?.versions.map(\.version).max() ?? d.version) + 1)").ui(TypeScale.small, mono: true).foregroundStyle(t.text3.color)
                        .frame(width: 26, alignment: .leading)
                    Text("not built").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
                Text("Results never mix versions: a version is frozen, and a new one gets a new number.")
                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func cliCard(_ d: EvalSetDetail) -> some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Also from the command line").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("roof eval evalset build --name \(d.name) --repo \(((d.repoPath ?? d.repo) as NSString).abbreviatingWithTildeInPath) --days \(d.days ?? 120) --dry-run")
                    .ui(TypeScale.caption, mono: true).foregroundStyle(t.text.color).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.surface2.color))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The next version (HP EV-6, owner decision 11-05): a dry run lists the usable fixes and what was left out; Freeze writes
/// v<N+1> as a new version of the same task (the old one and its results never change). Two ways to build it: every
/// usable fix in the window (default: the real count, today ~52 from commit subjects) or this version's bugs + the new ones.
struct EvalsNextVersionCard: View {
    @ObservedObject var board: EvalsBoard
    let set: EvalSetDetail
    let currentSource: String?
    var autoPreview = false
    var built: () -> Void
    @Environment(\.theme) private var t
    @State private var preview: EvalBuildPreview?
    @State private var error: String?
    @State private var reading = false
    @State private var showBugs = false
    @State private var confirm = false
    @State private var days = 120
    @State private var extend = false
    @State private var repo = ""
    @State private var keyFile: String = Prefs.defaults.string(forKey: "evals.linearKeyFile") ?? ""

    var body: some View {
        let next = preview?.nextVersion ?? set.version + 1
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Next version (v\(next))").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Segmented(options: [(false, "Every fix in the window"), (true, "v\(set.version) + new fixes")], selection: $extend)
                    .onChange(of: extend) { _, _ in dry() }
                if reading { Text("Reading \(days) days of git history…").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                else if let p = preview {
                    Text(EvalNextVersion.headline(p, extend: extend) + " v\(set.version) stays frozen, so old results still compare.")
                        .ui(TypeScale.small, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                    Text(EvalNextVersion.sourceNote(p, current: set.version, currentSource: currentSource))
                        .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    if p.total > set.count {
                        Text(EvalNextVersion.powerNote(current: set.version, currentN: set.count, next: p.nextVersion, nextN: p.total))
                            .ui(TypeScale.caption).foregroundStyle(t.accentText.color).fixedSize(horizontal: false, vertical: true)
                            .evalHover(.canTell, EvalHover.canTell(points: EvalPower.mirror(n: p.total, epochs: 1).plusMinusPoints))
                    }
                } else if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true) }
                Rectangle().fill(t.separator.color).frame(height: 1)
                row("Repo") {
                    Button { pickRepo() } label: { Text(repo.isEmpty ? "choose…" : (repo as NSString).abbreviatingWithTildeInPath).ui(TypeScale.small, mono: true).lineLimit(1).truncationMode(.head) }
                        .buttonStyle(.plain).foregroundStyle(t.text.color)
                }
                row("Look back") { Stepper("\(days) days", value: $days, in: 7...720, step: 30).ui(TypeScale.small).onChange(of: days) { _, _ in dry() } }
                row("Bug reports from") {
                    Button { pickKey() } label: {
                        Text(preview?.reportSource ?? (keyFile.isEmpty ? "commit subjects (no Linear key)" : "Linear · key file set")).ui(TypeScale.small).lineLimit(1)
                    }
                    .buttonStyle(.plain).foregroundStyle(t.text.color).help("Choose a Linear key file (its path only; the key is never shown or stored by One Roof)")
                }
                row("Checked by") { Text("code: names a changed file").ui(TypeScale.small) }
                row("Bugs") {
                    Text(preview.map { extend ? "\($0.total) (\($0.kept) + \($0.new.count) new)" : "\($0.total)" } ?? "\(set.count)").ui(TypeScale.small, .semibold)
                }
                Text(preview?.leftOutText ?? "Left out on purpose: reports that already name the file (too easy), issues still open, fixes touching more than 3 source files, commits that are not a fix.")
                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if let p = preview, !p.new.isEmpty {
                    if showBugs {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(p.new) { c in
                                    HStack(spacing: 6) {
                                        Text(c.issue ?? "").ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                                        Text(c.report).ui(TypeScale.caption).foregroundStyle(t.text.color).lineLimit(1)
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                    HStack(spacing: 8) {
                        RoofButton(showBugs ? "Hide the \(p.new.count)" : "Preview \(p.new.count) new bug\(p.new.count == 1 ? "" : "s")", .primary) { showBugs.toggle() }
                        RoofButton("Freeze as v\(next)") { confirm = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            repo = set.repoPath ?? ""
            days = set.days ?? 120
            dry()
            if autoPreview { showBugs = true }
        }
        .alert("v\(next) will be frozen", isPresented: $confirm) {
            Button("Freeze as v\(next)") { freeze() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("A new version of the same task. It can't be edited; a later build makes v\(next + 1). v\(set.version) and its results stay as they are.") }
    }

    private func row<V: View>(_ label: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack(alignment: .firstTextBaseline) { Text(label).ui(TypeScale.small).foregroundStyle(t.text2.color).frame(width: 112, alignment: .leading); v(); Spacer(minLength: 0) }
    }

    private func args(dryRun: Bool) -> [String] {
        EvalNextVersion.buildArguments(name: set.name, repo: repo, kind: set.kind, days: days, extend: extend,
                                       count: preview?.total, keyFile: keyFile, dryRun: dryRun)
    }

    private func dry() {
        guard !repo.isEmpty else { error = "Choose the repo this task was built from."; return }
        reading = true; error = nil
        board.ask(EvalNextVersion.buildArguments(name: set.name, repo: repo, kind: set.kind, days: days, extend: extend, count: 200,
                                                 keyFile: keyFile, dryRun: true), EvalBuildPreview.self, timeout: 600) { r in
            reading = false
            switch r { case .success(let p): preview = p; case .failure(let e): error = e.message }
        }
    }

    private func freeze() {
        reading = true
        board.ask(args(dryRun: false), EvalBuildPreview.self, timeout: 900) { r in
            reading = false
            switch r { case .success: preview = nil; built(); case .failure(let e): error = e.message }
        }
    }

    private func pickRepo() {
        let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
        if !repo.isEmpty { p.directoryURL = URL(fileURLWithPath: repo) }
        if p.runModal() == .OK, let u = p.url { repo = u.path; dry() }
    }

    private func pickKey() {
        let p = NSOpenPanel(); p.canChooseFiles = true; p.canChooseDirectories = false; p.showsHiddenFiles = true
        p.message = "Choose the file that holds only your Linear API key (One Roof reads the path, never shows the key)"
        if p.runModal() == .OK, let u = p.url { keyFile = u.path; Prefs.defaults.set(u.path, forKey: "evals.linearKeyFile"); dry() }
    }
}
