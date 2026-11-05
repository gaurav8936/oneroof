import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E5.1 Our tasks (screen lane B): one card per task set — plain name, engine name · version · frozen date,
/// how it is checked (both kinds by code), its real bugs, who has been tested on it per layer, and the next version or
/// the grader's trust — then "+ New task" (from fixed bugs; past sessions and a file of questions are coming) and every
/// grader. Replaces 2.0.3's Your evals sidebar (NO_REGRESSION). Engine: `evalset list`, `judge list|trust`,
/// `evalset build --dry-run` (the next version's real count), `results` (stamps: rules on = full setup).
struct EvalsTasksView: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var trust: [String: EvalJudgeTrust] = [:]
    @State private var next: [String: EvalBuildPreview] = [:]
    @State private var rulesOn: Set<String> = []
    @State private var sheet: Sheet?

    enum Sheet: String, Identifiable { case fromRepo, fromSessions, fromFile, grader; var id: String { rawValue } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if board.sets.isEmpty {
                    hero
                } else {
                    Text("Each task is a set of real bugs from your repo's history, frozen so every setup gets the exact same ones.")
                        .ui(TypeScale.body).foregroundStyle(t.text2.color)
                    ForEach(board.sets) { s in card(s) }
                }
                newTiles
                if !board.judges.isEmpty { graders }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.bottom, 20)
        }
        .onAppear { load(); takeNew() }
        .onChange(of: nav.newRequest) { _, _ in takeNew() }   // "+ New ▾" › New task from fixed bugs / New grader
        .onChange(of: board.judges) { _, _ in loadTrust() }
        .onChange(of: board.sets) { _, _ in loadNext() }
        .sheet(item: $sheet) { s in sheetView(s).themed(t.name) }
    }

    // MARK: Engine

    private func load() { loadTrust(); loadNext(); loadStamps() }

    private func loadTrust() {
        for j in board.judges {
            board.ask(["judge", "trust", j.name], EvalJudgeTrust.self, timeout: 120) { if case .success(let tr) = $0 { trust[j.name] = tr } }
        }
    }

    /// The next version's real count: every usable fix in the set's window (a dry run writes nothing).
    private func loadNext() {
        for s in board.sets where next[s.name] == nil {
            guard let repo = s.repoPath else { continue }
            let a = EvalNextVersion.buildArguments(name: s.name, repo: repo, kind: s.kind, days: 120, extend: false, count: 200,
                                                   keyFile: Prefs.defaults.string(forKey: "evals.linearKeyFile"), dryRun: true)
            board.ask(a, EvalBuildPreview.self, timeout: 600) { if case .success(let p) = $0 { next[s.name] = p } }
        }
    }

    private struct StampRow: Decodable { var id: String; var stamp: EvalStamp? }
    private func loadStamps() {
        board.ask(["results"], [StampRow].self, timeout: 120) { r in
            if case .success(let rows) = r { rulesOn = Set(rows.filter { $0.stamp?.rules == "on" }.map(\.id)) }
        }
    }

    private func takeNew() {
        guard let r = nav.newRequest else { return }
        nav.newRequest = nil
        sheet = r == .task ? .fromRepo : .grader
    }

    private func judge(for s: EvalSetList.Entry) -> EvalJudgeList.Judge? {
        board.judges.first { ($0.task ?? "").hasPrefix("own_\(s.name)_v") } ?? board.judges.first { $0.name == s.name }
    }

    // MARK: A task card

    private func card(_ s: EvalSetList.Entry) -> some View {
        let chips = EvalTaskCoverage.chips(name: s.name, version: s.version, results: board.results, runs: board.runs, rulesOn: rulesOn)
        let j = judge(for: s)
        let tr = j.flatMap { trust[$0.name] }
        return VStack(alignment: .leading, spacing: 0) {
            Button { nav.openTask(s.name) } label: {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(EvalTaskWords.title(kind: s.kind)).ui(15.5, .semibold).foregroundStyle(t.text.color)
                        Text(EvalTaskWords.meta(kind: s.kind, version: s.version, frozen: s.built) + " · \(s.repo)")
                            .ui(TypeScale.caption).foregroundStyle(t.text2.color)
                        Text(EvalTaskWords.howItWorks(kind: s.kind)).ui(TypeScale.small).foregroundStyle(t.text.color)
                            .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                    }
                    Spacer(minLength: 12)
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(s.count)").ui(26, .bold).foregroundStyle(t.text.color)
                        Text("real bugs").ui(TypeScale.caption).foregroundStyle(t.text2.color)
                    }
                    .evalHover(.n, "\(s.count) real bugs, frozen in v\(s.version): every setup gets these exact ones. At \(s.count), a score's range is about ±\(Int(EvalPower.mirror(n: s.count, epochs: 1).plusMinusPoints.rounded())) points.")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(EvalTaskWords.title(kind: s.kind)), \(s.count) real bugs; open it")
            HStack(spacing: 8) { ForEach(chips, id: \.layer) { chip($0) } }.padding(.top, 12)
            if let j, let tr, let banner = EvalGraderWords.banner(tr) {
                graderBanner(j, banner)
            } else {
                footer(s)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
        .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private func chip(_ c: EvalTaskCoverage.Chip) -> some View {
        (Text(c.title + " ").fontWeight(.semibold).foregroundColor(t.text.color)
         + Text(c.text).foregroundColor(c.isGap ? t.needsText.color : c.tested > 0 ? t.diffAddText.color : c.isActiveOnly ? t.accentText.color : t.text2.color))
            .ui(TypeScale.caption)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Capsule().fill(t.control.color))
            .overlay(Capsule().strokeBorder(t.separator.color))
            .help(c.layer == .full ? "Your full setup = an agent with your rules on. No test has recorded one yet." : "\(c.title): \(c.text) on this version")
    }

    @ViewBuilder private func footer(_ s: EvalSetList.Entry) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(t.separator.color).frame(height: 1).padding(.vertical, 12)
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Group {
                    if let p = next[s.name] {
                        Text(EvalNextVersion.headline(p, extend: false) + " A v\(p.nextVersion) would hold them; v\(s.version) stays unchanged so old results still compare.")
                    } else if s.repoPath == nil {
                        Text("Built before One Roof kept the repo's path: choose it on the task page to build the next version.")
                    } else {
                        Text("Reading the repo's fixed bugs for the next version…")
                    }
                }
                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let p = next[s.name], p.total > 0 {
                    link("Preview v\(p.nextVersion)") { nav.openBuild = true; nav.openTask(s.name) }
                }
                link("See the \(s.count) bugs") { nav.openTask(s.name) }
            }
        }
    }

    private func graderBanner(_ j: EvalJudgeList.Judge, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            (Text("The grading model isn't trusted yet. ").fontWeight(.semibold).foregroundColor(t.needsText.color)
             + Text(text).foregroundColor(t.text.color))
                .ui(TypeScale.small).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            link("Check the grader") { nav.openGrader(j.name) }
            link("Start labelling") { nav.openGrader(j.name) }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(t.needsText.color.opacity(0.12))
        .padding(.horizontal, -16).padding(.bottom, -16).padding(.top, 12)
    }

    private func link(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).ui(TypeScale.small, .semibold).foregroundStyle(t.accentText.color) }
            .buttonStyle(.plain).fixedSize()
    }

    // MARK: + New task · graders

    private var newTiles: some View {
        HStack(spacing: 10) {
            tile("+ New task · From fixed bugs in a repo", on: true) { sheet = .fromRepo }
            tile("+ New task · From past sessions (coming)", on: false) { sheet = .fromSessions }
            tile("+ New task · From a file of questions (coming)", on: false) { sheet = .fromFile }
        }
    }

    private func tile(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).ui(TypeScale.small, on ? .semibold : .regular).foregroundStyle(on ? t.accentText.color : t.text3.color)
                .lineLimit(1).minimumScaleFactor(0.85)
                .padding(.horizontal, 12).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(on ? t.accent.color.opacity(0.06) : .clear))
                .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(on ? t.accent.color : t.separatorStrong.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Pick a repo: One Roof turns its fixed bugs into a frozen task (preview first)" : "Coming in a later release")
    }

    private var graders: some View {
        VStack(alignment: .leading, spacing: 6) {
            EvalsLabel("Graders").padding(.top, 6)
            Text("A grading model marks answers code can't check. Before its marks count, check it against your own labels.")
                .ui(TypeScale.small).foregroundStyle(t.text2.color)
            ForEach(board.judges) { j in
                let tr = trust[j.name]
                Button { nav.openGrader(j.name) } label: {
                    HStack(spacing: 10) {
                        Text("The grader for \"\(gradedTitle(j))\"").ui(TypeScale.small, .semibold).foregroundStyle(t.text.color)
                        Text(tr.map { "agrees \(EvalJudgeTrust.pct($0.agreement)) · \(EvalGraderWords.verdictTitle($0).lowercased()) · \($0.labelled) of \($0.items) labelled by you" } ?? "reading…")
                            .ui(TypeScale.small).foregroundStyle(tr?.ready == true ? t.text2.color : t.needsText.color)
                        Spacer()
                        Text("Check the grader ›").ui(TypeScale.small).foregroundStyle(t.accentText.color)
                    }
                    .padding(.vertical, 6).padding(.horizontal, 10).contentShape(Rectangle())
                }
                .buttonStyle(.plain).hoverHighlight()
            }
        }
    }

    private func gradedTitle(_ j: EvalJudgeList.Judge) -> String {
        if let s = board.sets.first(where: { ($0.task(j) ) }) { return EvalTaskWords.title(kind: s.kind) }
        return j.name.replacingOccurrences(of: "_", with: " ")
    }

    private var hero: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Build your first task from a repo's fixed bugs").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("One Roof reads a repo's history for fixes that name an issue, and turns each into a bug: the report and the code as it was before the fix. A setup is right when it names a file the fix changed, checked by code. Versions are frozen, so scores stay comparable.")
                    .ui(TypeScale.body).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                RoofButton("From a repo's fixed bugs…", .primary) { sheet = .fromRepo }
            }
        }
        .frame(maxWidth: 640, alignment: .leading)
    }

    @ViewBuilder private func sheetView(_ s: Sheet) -> some View {
        switch s {
        case .fromRepo: EvalsNewSetSheet(board: board) { name in sheet = nil; if let name { board.refreshOwn(); nav.openTask(name) } }
        case .fromSessions: EvalsComingSheet(title: "From past sessions",
                                             line: "turn real asks from your agents' past sessions into bugs, keep or drop each, then freeze them as a task.",
                                             issue: "LAB-2079") { sheet = nil }
        case .fromFile: EvalsComingSheet(title: "From a file of questions",
                                         line: "pick a CSV or JSONL file of questions and answers, preview it, choose how it's checked, and freeze it as a task.",
                                         issue: "LAB-2078") { sheet = nil }
        case .grader: EvalsNewJudgeSheet(board: board) { name in
            sheet = nil
            if let name { board.refreshOwn(); nav.openGrader(name) }
        }
        }
    }
}

private extension EvalSetList.Entry {
    /// The grader studies this task's notes.
    func task(_ j: EvalJudgeList.Judge) -> Bool { (j.task ?? "").hasPrefix("own_\(name)_v") || j.name == name }
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
            Text("New task from fixed bugs in a repo").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            HStack {
                Text("Repo").frame(width: 120, alignment: .leading)
                Text(repo.isEmpty ? "none chosen" : (repo as NSString).abbreviatingWithTildeInPath).ui(TypeScale.small, mono: true).lineLimit(1)
                Spacer()
                RoofButton("Choose…") {
                    let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false
                    if p.runModal() == .OK, let u = p.url { repo = u.path; preview = nil }
                }
            }
            HStack {
                Text("Kind").frame(width: 120, alignment: .leading)
                Segmented(options: [("fix-locator", EvalTaskWords.title(kind: "fix-locator")), ("triage", EvalTaskWords.title(kind: "triage"))], selection: $kind)
            }
            HStack { Text("Look back").frame(width: 120, alignment: .leading); Stepper("\(days) days", value: $days, in: 7...720, step: 30) }
            HStack { Text("Bugs").frame(width: 120, alignment: .leading); Stepper("\(count)", value: $count, in: 5...100, step: 5) }
            HStack {
                Text("Bug reports from").frame(width: 120, alignment: .leading)
                Text(keyFile.isEmpty ? "commit subjects (no Linear key file set)" : "Linear · key file set").ui(TypeScale.small)
                Spacer()
                RoofButton("Key file…") {
                    let p = NSOpenPanel(); p.canChooseFiles = true; p.showsHiddenFiles = true
                    if p.runModal() == .OK, let u = p.url { keyFile = u.path; Prefs.defaults.set(u.path, forKey: "evals.linearKeyFile") }
                }
            }
            Text("Checked by code: right when the answer names a file the fix changed.").ui(TypeScale.caption).foregroundStyle(t.text2.color)
            if working { Text("Reading \(days) days of git history…").ui(TypeScale.small).foregroundStyle(t.text2.color) }
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
            if let p = preview {
                Text("\(p.new.count) bugs · \(p.leftOutText)").ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
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
                Text("Also from the command line: roof eval evalset build --repo <path>").ui(TypeScale.caption, mono: true).foregroundStyle(t.text3.color)
                    .textSelection(.enabled)
                Spacer()
                RoofButton("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                if preview == nil || preview?.new.isEmpty == true {
                    RoofButton("Preview", .primary) { build(dry: true) }.disabled(repo.isEmpty || working)
                } else {
                    RoofButton("Freeze as v\(preview?.nextVersion ?? 1)", .primary) { build(dry: false) }.disabled(working)
                }
            }
        }
        .padding(22).frame(width: 640).background(t.surface.color)
    }

    private func build(dry: Bool) {
        working = true; error = nil
        var a = ["evalset", "build", "--repo", repo, "--kind", kind, "--days", String(days), "--count", String(count)]
        if !keyFile.isEmpty { a += ["--linear-key-file", keyFile] }
        if dry {
            board.ask(a + ["--dry-run"], EvalBuildPreview.self, timeout: 900) { r in
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

struct EvalBuildDone: Decodable { var name: String; var version: Int }

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

/// A grader for prose answers: name, the runs whose answers it grades, your rule (`judge new`).
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
            Text("New grader").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            Text("A grading model marks answers code can't check, using your rule. You label some answers good or bad; the first become its examples, the rest measure how far to trust it.")
                .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack { Text("Name").frame(width: 90, alignment: .leading); TextField("oneroof_triage", text: $name).textFieldStyle(.roundedBorder) }
            Text("Answers from these tests").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
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
            Text("The rule it grades by").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
            TextEditor(text: $rubric).font(.system(size: 12.5)).frame(height: 80)
                .overlay(RoundedRectangle(cornerRadius: Radius.field).strokeBorder(t.separator.color))
            if let e = error { Text(e).ui(TypeScale.small).foregroundStyle(t.needsText.color) }
            HStack {
                Spacer()
                RoofButton("Cancel") { done(nil) }.keyboardShortcut(.cancelAction)
                RoofButton(working ? "Making…" : "Make the grader", .primary) { make() }
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
