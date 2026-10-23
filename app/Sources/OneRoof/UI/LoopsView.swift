import AppKit
import SwiftUI
import OneRoofCore

extension Notification.Name {
    /// Palette › New loop: the Loops view opens its editor.
    static let newLoop = Notification.Name("oneroof.newLoop")
}

/// The loops on disk (`<shared>/loops`), re-read every 3 s while the Loops view is open: roofd's engine changes them.
/// Owner actions write through LoopStore (file-locked), so they never fight the engine.
final class LoopBoard: ObservableObject {
    @Published private(set) var loops: [Loop] = []
    @Published private(set) var rounds: [String: [LoopRound]] = [:]
    @Published var error: String?
    private var timer: Timer?
    private let io = DispatchQueue(label: "oneroof.loops.io")

    var store: LoopStore { LoopStore() }

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.reload() }
    }

    func stop() { timer?.invalidate(); timer = nil }

    func reload() {
        let s = store
        io.async { [weak self] in
            let ls = s.all()
            let rs = Dictionary(uniqueKeysWithValues: ls.map { ($0.id, s.rounds($0.id)) })
            DispatchQueue.main.async {
                guard let self else { return }
                if self.loops != ls { self.loops = ls }
                if self.rounds != rs { self.rounds = rs }
            }
        }
    }

    private func write(_ what: String, _ body: @escaping (LoopStore) throws -> Void) {
        let s = store
        io.async { [weak self] in
            do { try body(s); DispatchQueue.main.async { self?.error = nil } }
            catch { DispatchQueue.main.async { self?.error = "\(what): \(error)" } }
            self?.reload()
        }
    }

    func runNow(_ id: String) { write("Run now") { try $0.update(id) { $0 = LoopController.runNow($0) } } }
    func pause(_ id: String) { write("Pause") { try $0.update(id) { $0 = LoopController.pause($0) } } }
    func resume(_ id: String) { write("Resume") { try $0.update(id) { $0 = LoopController.resume($0) } } }
    func togglePin(_ id: String) { write("Pin") { try $0.update(id) { $0.pinned.toggle() } } }

    /// Stop: the run ends now (a round's session keeps running for you) and the loop starts nothing until Run now.
    func stopLoop(_ id: String) {
        write("Stop") { s in
            let rounds = s.rounds(id)
            var line: LoopRound?
            try s.update(id) { l in
                if l.run != nil {
                    let (next, ln) = LoopController.ended(l, rounds: rounds, outcome: .stop("Stopped by you"), now: Date(), byOwner: true)
                    l = next; line = ln
                } else {
                    l.state = .stopped; l.runRequested = false
                }
            }
            if let line { try s.append(line, to: id) }
        }
    }

    func pauseAll() {
        write("Pause all") { s in for l in s.all() where l.state.isActive || (l.trigger.isNightly && l.state != .stopped) { try s.update(l.id) { $0 = LoopController.pause($0) } } }
    }

    func resumeAll() {
        write("Resume all") { s in for l in s.all() where l.state == .paused { try s.update(l.id) { $0 = LoopController.resume($0) } } }
    }

    func save(_ loop: Loop, isNew: Bool, run: Bool) {
        write("Save") { s in
            var l = loop
            if isNew {
                l.state = l.trigger.isNightly ? .waiting : .stopped
                try s.save(l)
            } else {
                try s.saveEdit(l)
            }
            if run { try s.update(l.id) { $0 = LoopController.runNow($0) } }
        }
    }

    func delete(_ id: String) { write("Delete") { $0.delete(id) } }
}

/// Loops (I12 slice 1, LAB-678): every loop, pinned first, with its state, rounds and last check; the detail shows the
/// rounds of its runs and Run now / Pause / Resume / Stop; the editor makes or changes a loop and tests its check.
struct LoopsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @StateObject private var board = LoopBoard()
    @Environment(\.theme) private var t
    @State private var selected: String?
    @State private var editing: LoopDraft?
    @State private var confirmDelete: Loop?

    var body: some View {
        FleetPage(title: "Loops", subtitle: subtitle) {
            HStack(spacing: 8) {
                if board.loops.contains(where: { $0.state == .paused }) && !board.loops.contains(where: { $0.state.isActive }) {
                    RoofButton("Resume all") { board.resumeAll() }
                } else {
                    RoofButton("⏸ Pause all") { board.pauseAll() }.disabled(board.loops.isEmpty)
                }
                RoofButton("+ New loop", .primary) { editing = LoopDraft.new() }
            }
        } content: {
            if let e = board.error {
                Text(e).ui(12.5).foregroundStyle(t.needsText.color).textSelection(.enabled)
            }
            if board.loops.isEmpty {
                empty
            } else {
                HStack(alignment: .top, spacing: 18) {
                    list.frame(width: 360)
                    detail.frame(maxWidth: .infinity)
                }
            }
        }
        .onAppear { board.start() }
        .onDisappear { board.stop() }
        .onReceive(NotificationCenter.default.publisher(for: .newLoop)) { _ in editing = LoopDraft.new() }
        .sheet(item: $editing) { d in
            LoopEditor(draft: d, onSave: { loop, run in
                board.save(loop, isNew: d.isNew, run: run)
                selected = loop.id
                editing = nil
            }, onCancel: { editing = nil })
            .themed(t.name)
        }
        .alert("Delete this loop?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
               presenting: confirmDelete) { l in
            Button("Delete", role: .destructive) { board.delete(l.id); if selected == l.id { selected = nil } }
            Button("Cancel", role: .cancel) {}
        } message: { l in
            Text("Its loop.json and round log are removed. Its worktree \(l.worktreePath) and branch \(l.branch) stay, with any work in them.")
        }
    }

    private var subtitle: String {
        let running = board.loops.filter { $0.state == .running }.count
        let needs = board.loops.filter { $0.state == .needsYou }.count
        var parts = ["\(board.loops.count) loop\(board.loops.count == 1 ? "" : "s")"]
        if running > 0 { parts.append("\(running) running") }
        if needs > 0 { parts.append("\(needs) need\(needs == 1 ? "s" : "") you") }
        parts.append("run by roofd with the app open or closed, checked every 30 s")
        return parts.joined(separator: " · ")
    }

    private var empty: some View {
        Card(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("No loops yet").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("A loop repeats work until a check passes, or runs every night: One Roof runs the check, counts the rounds and stops at the limits; an agent does the work in the loop's own worktree, never your checkout. Nothing is pushed or merged.")
                    .ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    ForEach(LoopTemplates.all) { tpl in
                        RoofButton(tpl.title) { editing = LoopDraft.new(template: tpl) }
                    }
                    RoofButton("+ New loop", .primary) { editing = LoopDraft.new() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: List

    private var list: some View {
        let pinned = board.loops.filter(\.pinned), other = board.loops.filter { !$0.pinned }
        return Card(padding: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !pinned.isEmpty {
                        MicroLabel("Pinned").padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
                        ForEach(pinned) { row($0) }
                    }
                    if !other.isEmpty {
                        MicroLabel(pinned.isEmpty ? "Loops" : "Other").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(other) { row($0) }
                    }
                }
            }
        }
    }

    private func row(_ l: Loop) -> some View {
        let rs = board.rounds[l.id] ?? []
        let checks = rs.filter { $0.kind != .stop }
        let last = checks.last
        let isSel = (selected ?? board.loops.first?.id) == l.id
        return Button { selected = l.id } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    StatusDot(status: l.state.pillStatus)
                    Text(l.name).ui(TypeScale.row, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Spacer(minLength: 4)
                    Text(rowRight(l, rs)).ui(11.5, l.state == .needsYou || l.state == .failed ? .semibold : .regular)
                        .foregroundStyle((l.state == .needsYou || l.state == .failed ? t.text : t.text2).color).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(Workspace.repoLabel(for: l.repoPath)).ui(11.5, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
                    Spacer(minLength: 4)
                    HealthStrip(results: checks.suffix(8).map(\.checkPassed))
                    if let last { CheckGlyph(passed: last.checkPassed == true) }
                }
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .hoverHighlight(selected: isSel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(l.name), \(l.state.label), \(rowRight(l, rs))" + (last.map { $0.checkPassed == true ? ", last check passed" : ", last check failed" } ?? ""))
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    private func rowRight(_ l: Loop, _ rs: [LoopRound]) -> String {
        let used = l.run.map { r in rs.filter { $0.runId == r.id && $0.kind == .round }.count } ?? 0
        switch l.state {
        case .running: return "round \(l.run?.active?.n ?? used) of \(l.limits.maxRounds)"
        case .needsYou: return "needs you"
        case .waiting:
            if let next = LoopController.nextStart(l, rounds: rs, now: Date()) { return "next " + next.formatted(date: .omitted, time: .shortened) }
            return l.runRequested ? "starting" : "waiting"
        case .done:
            let n = rs.last(where: { $0.kind == .stop }).map { s in rs.filter { $0.runId == s.runId && $0.kind == .round }.count } ?? 0
            return "done in \(n) round\(n == 1 ? "" : "s")"
        case .failed: return "stopped at a limit"
        case .paused: return "paused"
        case .stopped: return l.trigger.isNightly ? "not running" : "run when you want"
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let l = board.loops.first(where: { $0.id == (selected ?? board.loops.first?.id) }) {
            LoopDetail(loop: l, rounds: board.rounds[l.id] ?? [], model: model, board: board,
                       edit: { editing = LoopDraft(loop: l, isNew: false) }, delete: { confirmDelete = l })
        }
    }
}

/// ✓ / ✕ for a check result: a coloured glyph (3:1 on cards in every theme); the words around it stay text colour.
struct CheckGlyph: View {
    @Environment(\.theme) private var t
    let passed: Bool
    var body: some View {
        Text(passed ? "✓" : "✕").ui(12.5, .bold).foregroundStyle((passed ? t.statusDone : t.needsText).color)
            .accessibilityLabel(passed ? "passed" : "failed")
    }
}

/// Pass/fail of the last checks, oldest first: one small bar each.
struct HealthStrip: View {
    @Environment(\.theme) private var t
    let results: [Bool?]
    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(results.enumerated()), id: \.offset) { _, r in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill((r == true ? t.statusDone : t.needsText).color.opacity(r == nil ? 0.3 : 1))
                    .frame(width: 4, height: 10)
            }
        }
        .accessibilityHidden(true)
    }
}

struct LoopDetail: View {
    let loop: Loop
    let rounds: [LoopRound]
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    var edit: () -> Void
    var delete: () -> Void
    @Environment(\.theme) private var t
    @State private var open: Set<String> = []

    var body: some View {
        let l = loop
        Card(padding: 18) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        StatusDot(status: l.state.pillStatus, size: 10)
                        Text(l.name).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        StatusPill(status: l.state.pillStatus, label: l.state.label)
                        if l.pinned { StatusPill(status: .idle, label: "Pinned") }
                        Spacer()
                        Text(l.trigger.label).ui(12.5).foregroundStyle(t.text2.color)
                    }
                    facts(l)
                    if let why = l.stopReason, l.run == nil {
                        Text((l.state == .done ? "✓ " : "✕ ") + why).ui(12.5).foregroundStyle((l.state == .done ? t.text2 : t.text).color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    actions(l)
                    Hairline()
                    roundsTable(l)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func facts(_ l: Loop) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
            fact("Goal", l.goal.isEmpty ? "—" : l.goal)
            fact("Check", l.check, mono: true)
            fact("Agent", l.agent.displayName + (l.model.map { " · " + $0 } ?? ""))
            fact("Repo", Workspace.repoLabel(for: l.repoPath))
            fact("Worktree", "\((l.worktreePath as NSString).abbreviatingWithTildeInPath) · branch \(l.branch)", mono: true)
            fact("Limits", l.limits.label)
            fact("Gates", "Never pushes, merges or deploys. A round that asks permission waits in Decisions.")
        }
    }

    private func fact(_ k: String, _ v: String, mono: Bool = false) -> some View {
        GridRow {
            MicroLabel(k)
            Text(v).ui(mono ? TypeScale.monoBody : 13, mono: mono).foregroundStyle(t.text.color)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(k): \(v)")
        }
    }

    private func actions(_ l: Loop) -> some View {
        HStack(spacing: 8) {
            RoofButton("Run now", .primary) { board.runNow(l.id) }
                .disabled(l.state == .running || l.state == .needsYou || l.runRequested)
            if l.state == .paused || l.state == .stopped && l.run == nil && l.trigger.isNightly {
                RoofButton("Resume") { board.resume(l.id) }
            } else {
                RoofButton("Pause") { board.pause(l.id) }.disabled(!(l.state.isActive || (l.trigger.isNightly && l.state != .stopped)))
            }
            RoofButton("Stop", .danger) { board.stopLoop(l.id) }.disabled(l.run == nil && !l.runRequested && l.state == .stopped)
            RoofButton("Edit") { edit() }
            RoofButton(l.pinned ? "Unpin" : "Pin") { board.togglePin(l.id) }
            Spacer()
            RoofButton("Delete", .danger) { delete() }
        }
    }

    private func roundsTable(_ l: Loop) -> some View {
        let lines = Array(rounds.suffix(60).reversed())
        let used = l.run.map { r in rounds.filter { $0.runId == r.id && $0.kind == .round }.count }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                MicroLabel("Rounds")
                Spacer()
                if let used { Text("this run \(used)/\(l.limits.maxRounds)").ui(11.5, mono: true).foregroundStyle(t.text2.color) }
            }
            if let a = l.run?.active {
                HStack(spacing: 8) {
                    Text("#\(a.n)").ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color)
                    Text(a.started.formatted(date: .omitted, time: .shortened)).ui(12.5, mono: true).foregroundStyle(t.text2.color)
                    Text(l.state == .needsYou ? "the agent asks something" : "the agent is working").ui(12.5)
                        .foregroundStyle((l.state == .needsYou ? t.text : t.text2).color)
                    Spacer()
                    openButton(a.sessionId)
                }
                .padding(.vertical, 4)
            }
            if lines.isEmpty && l.run?.active == nil {
                Text("No rounds yet. Run now runs the check first: if it already passes, no round is needed.")
                    .ui(12.5).foregroundStyle(t.text2.color)
            }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, r in roundRow(r) }
        }
    }

    private func roundRow(_ r: LoopRound) -> some View {
        let key = "\(r.runId)-\(r.kind.rawValue)-\(r.n)-\(r.ended.timeIntervalSince1970)"
        let isOpen = open.contains(key)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(r.kind == .stop ? "■" : r.kind == .check ? "check" : "#\(r.n)").ui(12.5, .semibold, mono: true)
                    .foregroundStyle(t.text.color).frame(width: 46, alignment: .leading)
                Text(r.ended.formatted(date: .abbreviated, time: .shortened)).ui(12, mono: true).foregroundStyle(t.text2.color)
                    .frame(width: 150, alignment: .leading)
                if r.kind == .stop {
                    Text(r.note ?? "Run ended").ui(12.5).foregroundStyle(t.text.color).lineLimit(isOpen ? nil : 1)
                } else {
                    HStack(spacing: 3) {
                        Text("check").ui(12.5, .semibold).foregroundStyle(t.text.color)
                        CheckGlyph(passed: r.checkPassed == true)
                    }
                    Text(r.checkPassed == true ? (r.note ?? "") : (r.failureKey ?? "")).ui(12, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
                }
                Spacer()
                if let s = r.sessionId { openButton(s) }
                Button { if isOpen { open.remove(key) } else { open.insert(key) } } label: {
                    Text(isOpen ? "▾" : "▸").ui(12.5).foregroundStyle(t.text2.color).frame(width: 18, height: 18)
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel(isOpen ? "Hide output" : "Show output")
            }
            if isOpen && !r.checkOutput.isEmpty {
                Text(r.checkOutput).ui(TypeScale.monoSmall, mono: true).foregroundStyle(t.text.color).textSelection(.enabled)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(r.kind == .stop ? "Run ended: \(r.note ?? "")" : "Round \(r.n), check \(r.checkPassed == true ? "passed" : "failed")")
    }

    @ViewBuilder private func openButton(_ sessionId: String) -> some View {
        if let item = model.item(sessionId) {
            RoofButton("Open ↗", .plain) { model.reveal(item) }
        }
    }
}

// MARK: Editor

/// The editor's working copy.
struct LoopDraft: Identifiable {
    var id: String { loop.id }
    var loop: Loop
    var isNew: Bool

    static func new(template: LoopTemplate? = nil) -> LoopDraft {
        let repo = WorkspaceSearch.repos().first ?? Workspace.projectsRoot
        var l = Loop(id: "", name: "", repoPath: repo)
        if let template { l = template.apply(to: l) }
        return LoopDraft(loop: l, isNew: true)
    }
}

struct LoopEditor: View {
    @State var draft: LoopDraft
    var onSave: (Loop, Bool) -> Void
    var onCancel: () -> Void
    @Environment(\.theme) private var t
    @State private var testing = false
    @State private var testResult: TestOutcome?

    struct TestOutcome { var result: LoopCheckResult; var folder: String }
    @State private var repos: [String] = []
    @State private var template = ""

    private var l: Binding<Loop> { $draft.loop }
    private var nightly: Bool { draft.loop.trigger.isNightly }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(draft.isNew ? "New loop" : "Edit loop").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Spacer()
                if draft.isNew {
                    FieldMenu(title: template.isEmpty ? "Start from a template" : template, expand: false) {
                        ForEach(LoopTemplates.all) { tpl in
                            Button(tpl.title + " — " + tpl.summary) {
                                template = tpl.title
                                draft.loop = tpl.apply(to: draft.loop)
                            }
                        }
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    field("Name") { TextField("fix-ci", text: l.name).textFieldStyle(.roundedBorder) }
                    field("Goal") { TextField("main is green on acme/web", text: l.goal, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder) }
                    field("Repo") {
                        FieldMenu(title: Workspace.repoLabel(for: draft.loop.repoPath)) {
                            ForEach(repos, id: \.self) { r in Button(Workspace.repoLabel(for: r)) { draft.loop.repoPath = r } }
                        }
                        .disabled(!draft.isNew)
                    }
                    if !draft.isNew {
                        Text("The repo is fixed once a loop exists (its worktree lives there).").ui(11.5).foregroundStyle(t.text3.color)
                    }
                    field("Agent") {
                        HStack(spacing: 8) {
                            FieldMenu(title: draft.loop.agent.displayName, expand: false) {
                                ForEach(AgentKind.allCases.filter(\.isAgent)) { a in Button(a.displayName) { draft.loop.agent = a } }
                            }
                            TextField("model (optional)", text: Binding(get: { draft.loop.model ?? "" },
                                                                         set: { draft.loop.model = $0.isEmpty ? nil : $0 }))
                                .textFieldStyle(.roundedBorder).frame(width: 200)
                        }
                    }
                    field("Check") {
                        VStack(alignment: .leading, spacing: 6) {
                            TextField("e.g. npm test · swift test · pytest -q (exit 0 = done)", text: l.check, axis: .vertical)
                                .lineLimit(1...3).font(.system(size: 12.5, design: .monospaced)).textFieldStyle(.roundedBorder)
                            HStack(spacing: 8) {
                                RoofButton(testing ? "Testing…" : "Test the check") { test() }
                                    .disabled(testing || draft.loop.check.trimmingCharacters(in: .whitespaces).isEmpty)
                                if let o = testResult {
                                    let r = o.result, folder = o.folder
                                    CheckGlyph(passed: r.passed)
                                    Text(r.passed ? "passes" : (r.timedOut ? "timed out" : "fails (exit \(r.exitCode))"))
                                        .ui(12.5, .semibold).foregroundStyle(t.text.color)
                                    Text("in " + (folder as NSString).abbreviatingWithTildeInPath + " · \(String(format: "%.1f", r.duration)) s")
                                        .ui(11.5, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
                                }
                            }
                            if let o = testResult, !o.result.output.isEmpty {
                                ScrollView {
                                    Text(LoopCheck.tail(o.result.output)).ui(TypeScale.monoSmall, mono: true).foregroundStyle(t.text.color)
                                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 140)
                                .padding(8)
                                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.card.color))
                            }
                        }
                    }
                    field("Runs") {
                        VStack(alignment: .leading, spacing: 8) {
                            Segmented(options: [(false, "Until done"), (true, "Nightly")], selection: Binding(
                                get: { nightly },
                                set: { draft.loop.trigger = $0 ? .at(hour: 2, minute: 0) : .untilDone(everyMinutes: 0) }))
                            triggerDetail
                        }
                    }
                    field("Limits") {
                        VStack(alignment: .leading, spacing: 6) {
                            Stepper("At most \(draft.loop.limits.maxRounds) rounds", value: l.limits.maxRounds, in: 1...50)
                            Stepper("At most \(Schedule.every(Int(draft.loop.limits.maxDuration / 60))) per run",
                                    value: Binding(get: { Int(draft.loop.limits.maxDuration / 60) },
                                                   set: { draft.loop.limits.maxDuration = TimeInterval($0 * 60) }),
                                    in: 15...1440, step: 15)
                            Stepper(draft.loop.limits.sameFailureStop == 0 ? "Never stop on a repeated failure"
                                    : "Stop when the same failure repeats \(draft.loop.limits.sameFailureStop)×",
                                    value: l.limits.sameFailureStop, in: 0...5)
                            Stepper("Check may run \(Schedule.every(Int(draft.loop.checkTimeout / 60)))",
                                    value: Binding(get: { Int(draft.loop.checkTimeout / 60) },
                                                   set: { draft.loop.checkTimeout = TimeInterval(max($0, 1) * 60) }),
                                    in: 1...120)
                        }
                        .ui(13).foregroundStyle(t.text.color)
                    }
                    field("Round prompt") {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Extra instructions for every round (optional)", text: l.roundPrompt, axis: .vertical)
                                .lineLimit(2...6).textFieldStyle(.roundedBorder)
                            Text("Every round already gets the goal, the check, its worktree and branch, the last check's output and what was tried; it is told never to push, merge or deploy.")
                                .ui(11.5).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Toggle("Pinned (top of the list)", isOn: l.pinned).ui(13).foregroundStyle(t.text.color)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let problem { Text(problem).ui(12).foregroundStyle(t.needsText.color) }
            HStack(spacing: 8) {
                Spacer()
                RoofButton("Cancel") { onCancel() }.keyboardShortcut(.cancelAction)
                if nightly {
                    RoofButton("Save", .primary) { save(run: false) }.disabled(problem != nil).keyboardShortcut(.defaultAction)
                } else {
                    RoofButton("Save") { save(run: false) }.disabled(problem != nil)
                    RoofButton("Save and run", .primary) { save(run: true) }.disabled(problem != nil).keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 640, height: 720)
        .background(t.window.color)
        .onAppear { repos = WorkspaceSearch.repos() }
    }

    @ViewBuilder private var triggerDetail: some View {
        switch draft.loop.trigger {
        case .untilDone(let every):
            Stepper(every == 0 ? "Next round right after the check" : "Wait \(Schedule.every(every)) between rounds",
                    value: Binding(get: { every }, set: { draft.loop.trigger = .untilDone(everyMinutes: max($0, 0)) }), in: 0...240, step: 5)
                .ui(13).foregroundStyle(t.text.color)
            Text("Starts when you press Run now; rounds go on until the check passes or a limit is hit.").ui(11.5).foregroundStyle(t.text3.color)
        case .at(let h, let m):
            HStack(spacing: 8) {
                Text("Every night at").ui(13).foregroundStyle(t.text.color)
                Stepper(Schedule.clock(h, m), value: Binding(get: { h * 60 + m }, set: { v in
                    let x = (v + 1440) % 1440
                    draft.loop.trigger = .at(hour: x / 60, minute: x % 60)
                }), in: -15...1455, step: 15).ui(13).foregroundStyle(t.text.color)
            }
            Text("Runs only while this Mac is awake (missed nights are skipped). Pause stops it until Resume.").ui(11.5).foregroundStyle(t.text3.color)
        }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MicroLabel(label)
            c()
        }
    }

    private var problem: String? {
        let x = draft.loop
        if x.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the loop a name." }
        if x.check.trimmingCharacters(in: .whitespaces).isEmpty { return "Set a check: the command that exits 0 when the goal is met." }
        if !Workspace.isInsideProjects(x.repoPath) || Workspace.isProjectsRoot(x.repoPath) { return "Pick a repo inside the projects folder." }
        if !FileManager.default.fileExists(atPath: x.repoPath + "/.git") { return "The repo must be a git repo (the loop works in its own worktree)." }
        return nil
    }

    /// Test the check: in the loop's worktree when it exists, else in the repo (read-only use of your checkout:
    /// the check runs there as it is).
    private func test() {
        let x = draft.loop
        let wt = x.id.isEmpty ? nil : x.worktreePath
        let folder = wt.flatMap { FileManager.default.fileExists(atPath: $0 + "/.git") ? $0 : nil } ?? x.repoPath
        testing = true
        testResult = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = LoopCheck.run(x.check, in: folder, timeout: min(x.checkTimeout, 300))
            DispatchQueue.main.async { testResult = TestOutcome(result: r, folder: folder); testing = false }
        }
    }

    private func save(run: Bool) {
        guard problem == nil else { return }
        var x = draft.loop
        x.name = x.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isNew { x.id = LoopStore().newId(for: x.name); x.createdAt = Date() }
        onSave(x, run)
    }
}
