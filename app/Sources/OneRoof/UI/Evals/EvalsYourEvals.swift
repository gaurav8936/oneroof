import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2065 · Your evals (Claude Design 1A-3 = HP E2.1, HP's "Build"): your eval sets, built from a repo's fixed bugs,
/// versioned and frozen; every case with who solved it; the floor and the best so far; Build v2 previewed before it is
/// written (v1 never changes). Judges sit here too (LAB-2066).
struct EvalsYourEvalsTab: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var detail: EvalSetDetail?
    @State private var detailError: String?
    @State private var trust: [String: EvalJudgeTrust] = [:]
    @State private var sheet: Sheet?
    @State private var version: Int?

    enum Sheet: String, Identifiable { case fromRepo, fromSessions, fromFile, judge; var id: String { rawValue } }

    private var current: EvalSetList.Entry? { board.sets.first { $0.name == nav.set } ?? board.sets.first }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            sidebar.frame(width: 230)
            Rectangle().fill(t.separator.color).frame(width: 1).padding(.horizontal, 12)
            Group {
                if board.sets.isEmpty { hero } else if let d = detail { EvalsSetPage(board: board, nav: nav, set: d, changed: { version = nil; reload() }, openVersion: { version = $0; reload() }).id("\(d.name)v\(d.version)") }
                else if let e = detailError { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
                else { Text("Reading your set…").ui(TypeScale.small).foregroundStyle(t.text3.color) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .onAppear { reload(); loadTrust() }
        .onChange(of: nav.set) { _, _ in version = nil; reload() }
        .onChange(of: board.sets) { _, _ in if detail == nil { reload() } }
        .onChange(of: board.judges) { _, _ in loadTrust() }
        .sheet(item: $sheet) { s in sheetView(s).themed(t.name) }
    }

    private func reload() {
        guard let s = current else { detail = nil; return }
        board.ask(["evalset", "show", s.name] + (version.map { ["--version", String($0)] } ?? []), EvalSetDetail.self) { r in
            switch r { case .success(let d): detail = d; detailError = nil; case .failure(let e): detailError = e.message }
        }
    }

    private func loadTrust() {
        for j in board.judges {
            board.ask(["judge", "trust", j.name], EvalJudgeTrust.self, timeout: 120) { if case .success(let tr) = $0 { trust[j.name] = tr } }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                EvalsLabel("Eval sets").padding(.bottom, 4)
                if board.sets.isEmpty { Text("None yet.").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(.horizontal, 8) }
                ForEach(board.sets) { s in
                    sideRow(s.title, "v\(s.version) · \(s.count) cases · \(s.checkedBy)", warn: false, on: s.name == current?.name) { nav.set = s.name }
                }
                EvalsLabel("Judges").padding(.top, 12).padding(.bottom, 4)
                if board.judges.isEmpty { Text("None yet.").ui(TypeScale.small).foregroundStyle(t.text3.color).padding(.horizontal, 8) }
                ForEach(board.judges) { j in
                    let tr = trust[j.name]
                    let toLabel = tr.map { max(0, 30 - ($0.heldBackYours ?? 0)) }
                    sideRow(j.name.replacingOccurrences(of: "_", with: " ") + " judge",
                            (tr.map { "\(EvalJudgeTrust.pct($0.agreement)) agree" } ?? "not measured")
                            + (toLabel.map { $0 > 0 ? " · \($0) to label" : "" } ?? ""),
                            warn: tr.map { ($0.heldBackYours ?? 0) < 30 } ?? false, on: false) {
                        nav.route = .judge(name: j.name, first: nil)
                    }
                }
                EvalsLabel("Start a new one").padding(.top, 12).padding(.bottom, 4)
                startRow("arrow.triangle.branch", "From a repo's fixed bugs") { sheet = .fromRepo }
                startRow("square.stack.3d.up", "From past sessions") { sheet = .fromSessions }
                startRow("doc.text", "From a file of questions") { sheet = .fromFile }
                startRow("scalemass", "A judge for prose answers") { sheet = .judge }
            }
        }
    }

    private func sideRow(_ title: String, _ sub: String, warn: Bool, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).ui(TypeScale.small, on ? .semibold : .medium).foregroundStyle(t.text.color).lineLimit(1)
                Text(sub).ui(11.5).foregroundStyle(warn ? t.needsText.color : t.text2.color).lineLimit(1)
            }
            .padding(.vertical, 6).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverHighlight(radius: Radius.row, selected: on)
        .accessibilityLabel("\(title), \(sub)")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func startRow(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16).foregroundStyle(t.text2.color)
                Text(title).ui(TypeScale.small).foregroundStyle(t.text.color)
            }
            .padding(.vertical, 5).padding(.horizontal, 10).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
        }
        .buttonStyle(.plain).hoverHighlight()
    }

    private var hero: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Build your first eval from a repo's fixed bugs").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("One Roof reads a repo's history for fixes that name an issue, and turns each into a question: the bug report and the code as it was before the fix. An agent passes when it names a file the fix changed. Versions are frozen, so scores stay comparable.")
                    .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                RoofButton("From a repo's fixed bugs…", .primary) { sheet = .fromRepo }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    @ViewBuilder private func sheetView(_ s: Sheet) -> some View {
        switch s {
        case .fromRepo: EvalsNewSetSheet(board: board) { name in sheet = nil; if let name { board.refreshOwn(); nav.set = name } }
        case .fromSessions: EvalsComingSheet(title: "From past sessions",
                                             line: "turn real asks from your agents' past sessions into cases, keep or drop each, then freeze them as a set.",
                                             issue: "LAB-2079") { sheet = nil }
        case .fromFile: EvalsComingSheet(title: "From a file of questions",
                                         line: "pick a CSV or JSONL file of questions and answers, preview it, choose how it's graded, and freeze it as a set.",
                                         issue: "LAB-2078") { sheet = nil }
        case .judge: EvalsNewJudgeSheet(board: board) { name in
            sheet = nil
            if let name { board.refreshOwn(); nav.route = .judge(name: name, first: nil) }
        }
        }
    }
}

/// One set: version badge, Build v2 · Run…, what the agent gets, the facts strip, every case, and on the right the Build
/// v2 card and the versions.
struct EvalsSetPage: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    let set: EvalSetDetail
    var changed: () -> Void
    var openVersion: (Int) -> Void = { _ in }
    @Environment(\.theme) private var t
    @State private var sort: EvalSetDetail.Sort = .hardest
    @State private var openCase: String?
    @State private var caseAnswers: [String: [EvalItemDetail.RunAnswer]] = [:]
    @State private var versions: EvalSetVersions?

    var body: some View {
        ScrollView {
            EvalsColumns(breakpoint: 1000, side: 300) { main } aside: {   // folds under the cases at 1280 (HP widths)
                VStack(alignment: .leading, spacing: 14) {
                    EvalsBuildNextCard(board: board, set: set, autoOpen: nav.openBuild) { nav.openBuild = false; changed(); loadVersions() }
                    versionsCard
                }
            }
            .frame(maxWidth: 1300, alignment: .leading)
            .padding(.bottom, 20)
        }
        .onAppear(perform: loadVersions)
    }

    private func loadVersions() {
        board.ask(["evalset", "versions", set.name], EvalSetVersions.self) { if case .success(let v) = $0 { versions = v } }
    }

    private var main: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Text("\(set.repo) · \(set.kindTitle)").ui(22, .bold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                EvalsChip(text: "v\(set.version) · frozen \(set.frozen ?? String(set.built.prefix(10)))").padding(.top, 6)
                Spacer()
                RoofButton("Run…", .primary) { nav.run(EvalRunPlan(tasks: [set.taskFile], models: [], limit: set.count)) }
                    .help("Opens the run sheet with this version; the cost shows before anything starts")
            }
            Text(set.description ?? "").ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            EvalsFactsStrip(facts: [
                ("Source", "\(set.repo) · \(set.days ?? 120) days", nil),
                ("Picked", "\(set.count) of \(set.stats?.commitsConsidered.map(String.init) ?? "?") fixes", nil),
                ("No-model floor", "\(set.floor.right) of \(set.floor.of) · \(evalsPct(Double(set.floor.right) / Double(max(set.floor.of, 1))))", nil),
                ("Best so far", set.best.map { "\(evalsPct($0.score)) · \($0.contestant)" } ?? "not run yet", nil)],
                hover: { label, _ in label == "No-model floor" ? (.floor, EvalHover.floor(share: nil, right: set.floor.right, of: set.floor.of)) : nil })
            cases
        }
    }

    private var cases: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Cases").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                    Text("\(set.count) · each run sees these exact cases").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    Spacer()
                    FieldMenu(title: "Sort: " + sort.rawValue, height: 24, expand: false) {
                        ForEach(EvalSetDetail.Sort.allCases, id: \.self) { s in Button(s.rawValue) { sort = s } }
                    }
                }
                .padding(12)
                Rectangle().fill(t.separator.color).frame(height: 1)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 0) {
                    GridRow { ForEach(["Issue", "Report", "Fix touched", "Solved by"], id: \.self) { EvalsLabel($0) } }.padding(.vertical, 8)
                    ForEach(set.sorted(sort)) { c in
                        GridRow {
                            Text(c.issue ?? "–").ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                            Button { toggle(c) } label: {
                                Text(c.report).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            Text(c.files.map { ($0 as NSString).lastPathComponent }.joined(separator: " · "))
                                .ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color).lineLimit(1).truncationMode(.tail)
                                .frame(maxWidth: 220, alignment: .leading).help(c.files.joined(separator: "\n"))
                            Text(EvalSetDetail.solvedText(c.solvedBy)).ui(TypeScale.small, .semibold)
                                .foregroundStyle(c.solvedBy.runs > 0 && c.solvedBy.right == 0 ? t.needsText.color
                                                 : c.solvedBy.runs > 0 && c.solvedBy.right == c.solvedBy.runs ? t.diffAddText.color : t.text.color)
                        }
                        .padding(.vertical, 6)
                        .accessibilityElement(children: .combine)
                        if openCase == c.id {
                            GridRow { caseDetail(c).gridCellColumns(4) }
                        }
                        GridRow { Rectangle().fill(t.separator.color).frame(height: 1).gridCellColumns(4) }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private func toggle(_ c: EvalSetDetail.Case) {
        openCase = openCase == c.id ? nil : c.id
        guard openCase != nil, caseAnswers[c.id] == nil else { return }
        board.ask(["item-results", set.taskFile, c.id], [EvalItemDetail.RunAnswer].self, timeout: 120) { if case .success(let a) = $0 { caseAnswers[c.id] = a } }
    }

    private func caseDetail(_ c: EvalSetDetail.Case) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.report).ui(TypeScale.small).foregroundStyle(t.text.color).textSelection(.enabled)
            Text("The fix changed " + c.files.joined(separator: ", ")).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
            if let a = caseAnswers[c.id] {
                if a.isEmpty { Text("No run on this version has answered it yet.").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                ForEach(a) { r in
                    Button { nav.openRun(r.run) } label: {
                        HStack(spacing: 8) {
                            Text(r.right ? "✓" : "✕").foregroundStyle(r.right ? t.diffAddText.color : t.needsText.color)
                            Text(r.contestant ?? r.model ?? "?").ui(TypeScale.caption, mono: true).foregroundStyle(t.text.color)
                            Text(r.answer ?? r.answerTail).ui(TypeScale.caption).foregroundStyle(t.text2.color).lineLimit(1)
                            Text("open run ›").ui(TypeScale.caption).foregroundStyle(t.accentText.color)
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else { Text("Reading each run's answer…").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.surface2.color))
        .padding(.bottom, 6)
    }

    private var versionsCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Versions").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                ForEach(versions?.versions ?? []) { v in
                    HStack {
                        Text("v\(v.version)").ui(TypeScale.small, .semibold, mono: true).foregroundStyle(t.text.color)
                        Text("\(v.count) cases · \(EvalModels.when(v.built).split(separator: " ").prefix(2).joined(separator: " ")) · \(v.runs) runs")
                            .ui(TypeScale.small).foregroundStyle(t.text2.color)
                        Spacer()
                        Button(v.version == set.version ? "shown" : "open") { openVersion(v.version) }
                        .buttonStyle(.plain).disabled(v.version == set.version).font(.system(size: TypeScale.small))
                        .foregroundStyle(v.version == set.version ? t.text3.color : t.accentText.color)
                    }
                }
                HStack {
                    Text("v\((versions?.versions.last?.version ?? set.version) + 1)").ui(TypeScale.small, mono: true).foregroundStyle(t.text3.color)
                    Text("not built").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Build the next version (HP EV-6): a dry run lists the fixes since this version and what was left out; Freeze writes
/// v<N+1> with this version's cases unchanged plus the new ones. Nothing is written before Freeze.
struct EvalsBuildNextCard: View {
    @ObservedObject var board: EvalsBoard
    let set: EvalSetDetail
    var autoOpen = false
    var built: () -> Void
    @Environment(\.theme) private var t
    @State private var preview: EvalBuildPreview?
    @State private var error: String?
    @State private var reading = false
    @State private var showCases = false
    @State private var confirm = false
    @State private var days = 120
    @State private var repo: String = ""
    @State private var keyFile: String = Prefs.defaults.string(forKey: "evals.linearKeyFile") ?? ""

    var body: some View {
        let next = set.version + 1
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Build v\(next)").ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
                if reading { Text("Reading \(days) days of git history…").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                else if let p = preview {
                    Text(p.new.isEmpty ? "No new fixes since v\(set.version): nothing to build."
                         : "\(p.new.count) bugs fixed since v\(set.version). v\(set.version) stays frozen, so old scores stay comparable.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                } else if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true) }
                settingRow("Repo") {
                    Button { pickRepo() } label: { Text(repo.isEmpty ? "choose…" : (repo as NSString).abbreviatingWithTildeInPath).ui(TypeScale.small, mono: true).lineLimit(1).truncationMode(.head) }
                        .buttonStyle(.plain).foregroundStyle(t.text.color)
                }
                settingRow("Look back") {
                    Stepper("\(days) days", value: $days, in: 7...720, step: 30).ui(TypeScale.small).onChange(of: days) { _, _ in dry() }
                }
                settingRow("Bug reports from") {
                    Button { pickKey() } label: {
                        Text(keyFile.isEmpty ? "commit subjects (no Linear key file set)" : "Linear · key file set").ui(TypeScale.small).lineLimit(1)
                    }
                    .buttonStyle(.plain).foregroundStyle(t.text.color).help("A key file path only; the key is never shown or stored by One Roof")
                }
                settingRow("Kind") { Text(set.kindTitle.capitalized + (set.kind == "triage" ? " · judged" : " · checked by code")).ui(TypeScale.small) }
                settingRow("Cases") { Text(preview.map { "\($0.total) (\($0.kept) + \($0.new.count) new)" } ?? "\(set.count)").ui(TypeScale.small, .semibold) }
                Rectangle().fill(t.separator.color).frame(height: 1)
                Text(preview?.leftOutText ?? "Left out on purpose: reports that already name the file (too easy), issues still open, fixes touching more than 3 source files.")
                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if let p = preview, !p.new.isEmpty {
                    if showCases {
                        ForEach(p.new) { c in
                            HStack(spacing: 6) {
                                Text(c.issue ?? "").ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color)
                                Text(c.report).ui(TypeScale.caption).foregroundStyle(t.text.color).lineLimit(1)
                            }
                        }
                        RoofButton("Freeze as v\(next)", .primary) { confirm = true }
                    } else {
                        RoofButton("Preview \(p.new.count) new cases", .primary) { showCases = true }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            repo = set.repoPath ?? ""
            days = set.days ?? 120
            if autoOpen || preview == nil { dry() }
        }
        .alert("v\(next) will be frozen", isPresented: $confirm) {
            Button("Freeze as v\(next)") { freeze() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("It can't be edited; a later build makes v\(next + 1). v\(set.version) and its runs stay as they are.") }
    }

    private func settingRow<V: View>(_ label: String, @ViewBuilder _ v: () -> V) -> some View {
        HStack { Text(label).ui(TypeScale.small).foregroundStyle(t.text2.color); Spacer(); v() }
    }

    private var args: [String] {
        var a = ["evalset", "build", "--name", set.name, "--extend", "--days", String(days)]
        if !repo.isEmpty { a += ["--repo", repo] }
        if !keyFile.isEmpty { a += ["--linear-key-file", keyFile] }
        return a
    }

    private func dry() {
        guard !repo.isEmpty else { error = "Choose the repo this set was built from."; return }
        reading = true; error = nil
        board.ask(args + ["--dry-run"], EvalBuildPreview.self, timeout: 600) { r in
            reading = false
            switch r { case .success(let p): preview = p; showCases = false; case .failure(let e): error = e.message }
        }
    }

    private func freeze() {
        reading = true
        board.ask(args, EvalBuildPreview.self, timeout: 900) { r in
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

/// From a repo's fixed bugs: repo, kind, look back, count, Linear key file → Preview → Freeze as v1.
struct EvalsNewSetSheet: View {
    @ObservedObject var board: EvalsBoard
    var done: (String?) -> Void
    @Environment(\.theme) private var t
    @State private var repo = ""
    @State private var kind = "fix-locator"
    @State private var days = 120
    @State private var count = 20
    @State private var keyFile = Prefs.defaults.string(forKey: "evals.linearKeyFile") ?? ""
    @State private var preview: EvalBuildPreview?
    @State private var error: String?
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("From a repo's fixed bugs").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            HStack {
                Text("Repo").frame(width: 120, alignment: .leading)
                Text(repo.isEmpty ? "none chosen" : (repo as NSString).abbreviatingWithTildeInPath).ui(TypeScale.small, mono: true).lineLimit(1)
                Spacer()
                RoofButton("Choose…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { repo = u.path; preview = nil }
                }
            }
            HStack { Text("Kind").frame(width: 120, alignment: .leading); Segmented(options: [("fix-locator", "Fix locator"), ("triage", "Bug triage")], selection: $kind) }
            HStack { Text("Look back").frame(width: 120, alignment: .leading); Stepper("\(days) days", value: $days, in: 7...720, step: 30) }
            HStack { Text("Cases").frame(width: 120, alignment: .leading); Stepper("\(count)", value: $count, in: 5...100, step: 5) }
            HStack {
                Text("Bug reports from").frame(width: 120, alignment: .leading)
                Text(keyFile.isEmpty ? "commit subjects (no Linear key file set)" : "Linear · key file set").ui(TypeScale.small)
                Spacer()
                RoofButton("Key file…") {
                    let p = NSOpenPanel(); p.canChooseFiles = true; p.showsHiddenFiles = true
                    if p.runModal() == .OK, let u = p.url { keyFile = u.path; Prefs.defaults.set(u.path, forKey: "evals.linearKeyFile") }
                }
            }
            if working { Text("Reading \(days) days of git history…").ui(TypeScale.small).foregroundStyle(t.text2.color) }
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
            if let p = preview {
                Text("\(p.new.count) cases · \(p.leftOutText)").ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(p.new) { c in
                            HStack { Text(c.issue ?? "").ui(TypeScale.caption, mono: true); Text(c.report).ui(TypeScale.caption).lineLimit(1) }
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            HStack {
                Spacer()
                RoofButton("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                if preview == nil || preview?.new.isEmpty == true {
                    RoofButton("Preview", .primary) { build(dry: true) }.disabled(repo.isEmpty || working)
                } else {
                    RoofButton("Freeze as v\(preview?.nextVersion ?? 1)", .primary) { build(dry: false) }.disabled(working)
                }
            }
        }
        .padding(22).frame(width: 600).background(t.surface.color)
    }

    private func build(dry: Bool) {
        working = true; error = nil
        var a = ["evalset", "build", "--repo", repo, "--kind", kind, "--days", String(days), "--count", String(count)]
        if !keyFile.isEmpty { a += ["--linear-key-file", keyFile] }
        if dry { a.append("--dry-run") }
        if dry {
            board.ask(a, EvalBuildPreview.self, timeout: 900) { r in
                working = false
                switch r { case .success(let p): preview = p; case .failure(let e): error = e.message }
            }
        } else {
            board.ask(a, EvalBuildDone.self, timeout: 900) { r in
                working = false
                switch r { case .success(let d): done(d.name); case .failure(let e): error = e.message }
            }
        }
    }
}

private struct EvalBuildDone: Decodable { var name: String; var version: Int }

/// "Coming in a later release" for the two sources the engine does not have yet (EVO-4), each with its Backlog issue.
struct EvalsComingSheet: View {
    let title: String
    let line: String
    let issue: String
    var done: () -> Void
    @Environment(\.theme) private var t
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            Text("Coming in a later release: \(line)").ui(TypeScale.body).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            Text("Tracked as \(issue).").ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color).textSelection(.enabled)
            HStack { Spacer(); RoofButton("Close", .primary) { done() }.keyboardShortcut(.defaultAction) }
        }
        .padding(22).frame(width: 480).background(t.surface.color)
    }
}

/// A judge for prose answers: name, the runs whose answers it grades, your rubric (`judge new`).
struct EvalsNewJudgeSheet: View {
    @ObservedObject var board: EvalsBoard
    var done: (String?) -> Void
    @Environment(\.theme) private var t
    @State private var name = ""
    @State private var runs: Set<String> = []
    @State private var rubric = ""
    @State private var error: String?
    @State private var working = false

    var body: some View {
        let candidates = board.results.filter { $0.status == "done" && !($0.task ?? "").hasPrefix("judge_") && !($0.task ?? "").hasPrefix("labeller_") }
        VStack(alignment: .leading, spacing: 12) {
            Text("A judge for prose answers").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            Text("A model grades answers code can't check, using your rubric. You label some answers pass or fail; the first become its examples, the rest measure how far to trust it.")
                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Name").frame(width: 90, alignment: .leading); TextField("oneroof_triage", text: $name).textFieldStyle(.roundedBorder) }
            Text("Answers from these runs").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(candidates) { r in
                        Toggle(isOn: Binding(get: { runs.contains(r.id) }, set: { on in if on { runs.insert(r.id) } else { runs.remove(r.id) } })) {
                            Text("\(r.task ?? "?") × \(r.contestant?.name ?? r.model ?? "?") · \(EvalModels.when(r.started))").ui(TypeScale.small, mono: true)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .frame(height: 160)
            Text("Rubric").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
            TextEditor(text: $rubric).font(.system(size: 12.5)).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(t.separator.color))
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
            HStack {
                Spacer()
                RoofButton("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                RoofButton(working ? "Making…" : "Make the judge", .primary) { make() }
                    .disabled(name.isEmpty || runs.isEmpty || rubric.trimmingCharacters(in: .whitespaces).isEmpty || working)
            }
        }
        .padding(22).frame(width: 620).background(t.surface.color)
    }

    private func make() {
        working = true
        let slug = name.lowercased().map { $0.isLetter || $0.isNumber ? $0 : "_" }.reduce("") { $0 + String($1) }
        board.ask(["judge", "new", slug, "--runs", runs.sorted().joined(separator: ","), "--rubric", rubric], EvalJudgeMade.self, timeout: 300) { r in
            working = false
            switch r { case .success(let j): done(j.name); case .failure(let e): error = e.message }
        }
    }
}

private struct EvalJudgeMade: Decodable { var name: String }
