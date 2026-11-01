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
    /// LAB-1918: per loop, from the outcome ledger (`<shared>/loops/ledger.sqlite`, shared with `ae loops ledger`).
    @Published private(set) var outcomes: [LoopLedger.LoopSummary] = []
    /// LAB-1941 · LAB-1922: each loop's outcomes (newest first) and runs from the ledger, for the drill-down and gallery.
    @Published private(set) var outcomesByLoop: [String: [LoopLedger.Outcome]] = [:]
    @Published private(set) var runsByLoop: [String: [LoopLedger.Run]] = [:]
    /// LAB-2100: per kit loop that needs settings or a tool, whether it has them (from the kit's config, read off main).
    @Published private(set) var setup: [String: LoopSetup.Status] = [:]
    /// The kit config path the statuses were read from (Setup box's Open config), nil when there is none.
    @Published private(set) var aeConfigPath: String?
    private var timer: Timer?
    /// Config text cached by modification date, and the tool check by time (the board reloads every 3 s).
    private var configCache: (path: String?, mtime: Date?, text: String?) = (nil, nil, nil)
    private var toolCache: (at: Date, installed: [String: Bool]) = (.distantPast, [:])
    private let io = DispatchQueue(label: "oneroof.loops.io")

    var store: LoopStore { LoopStore() }

    func start() {
        reload()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in self?.reload() }
        timer?.tolerance = 3 * 0.1   // LAB-1323: let the system batch wake-ups
    }

    func stop() { timer?.invalidate(); timer = nil }

    func reload() {
        let s = store
        io.async { [weak self] in
            let ls = s.all()
            let rs = Dictionary(uniqueKeysWithValues: ls.map { ($0.id, s.rounds($0.id)) })
            let path = LoopLedger.defaultPath(loopsRoot: s.root)
            let led = FileManager.default.fileExists(atPath: path) ? try? LoopLedger(path: path) : nil
            let os = led?.summary() ?? []
            let byLoop = Dictionary(grouping: led?.outcomes(limit: 1000) ?? [], by: \.loop)
            let runs = Dictionary(uniqueKeysWithValues: ls.map { ($0.id, led?.runs(loop: $0.id, limit: 10) ?? []) })
            let (setup, cfgPath) = self?.readSetup(ls.map(\.id)) ?? ([:], nil)
            DispatchQueue.main.async {
                guard let self else { return }
                if self.loops != ls { self.loops = ls }
                if self.rounds != rs { self.rounds = rs }
                if self.outcomes != os { self.outcomes = os }
                if self.outcomesByLoop != byLoop { self.outcomesByLoop = byLoop }
                if self.runsByLoop != runs { self.runsByLoop = runs }
                if self.setup != setup { self.setup = setup }
                if self.aeConfigPath != cfgPath { self.aeConfigPath = cfgPath }
            }
        }
    }

    /// LAB-2100 (on the io queue): each loop's setup status. The config is re-read only when its file changes; installed
    /// tools are looked up at most once a minute.
    private func readSetup(_ ids: [String]) -> ([String: LoopSetup.Status], String?) {
        let fm = FileManager.default
        let path = AEConfig.find()
        let mtime = path.flatMap { (try? fm.attributesOfItem(atPath: $0))?[.modificationDate] as? Date }
        if configCache.path != path || configCache.mtime != mtime {
            configCache = (path, mtime, path.flatMap { try? String(contentsOfFile: $0, encoding: .utf8) })
        }
        if Date().timeIntervalSince(toolCache.at) > 60 { toolCache = (Date(), [:]) }
        var out: [String: LoopSetup.Status] = [:]
        for id in ids {
            let st = LoopSetup.status(loop: id, config: configCache.text) { tool in
                if let v = toolCache.installed[tool] { return v }
                let v = LoopSetup.installed(tool)
                toolCache.installed[tool] = v
                return v
            }
            if let st { out[id] = st }
        }
        return (out, path)
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
        write("Pause all") { s in for l in s.all() where l.state.isActive || (l.trigger.isArmed && l.state != .stopped) { try s.update(l.id) { $0 = LoopController.pause($0) } } }
    }

    func resumeAll() {
        write("Resume all") { s in for l in s.all() where l.state == .paused { try s.update(l.id) { $0 = LoopController.resume($0) } } }
    }

    func save(_ loop: Loop, isNew: Bool, run: Bool) {
        write("Save") { s in
            var l = loop
            if isNew {
                l.state = l.trigger.isArmed ? .waiting : .stopped
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
    @State private var gallery = false
    @ObservedObject private var inbox = LoopInboxState.shared
    @Environment(\.v2Window) private var v2
    /// LAB-2055 (v2): Kinds (the four family cards, the default) or Activity (today's outcomes, rounds, list and
    /// Tonight), remembered; a family's page; the loop whose pop-out card is open; the page's width (two columns ≥ 960).
    @AppStorage("loops.view", store: Prefs.viewState) private var savedView = "kinds"
    @State private var viewOverride: String?   // self-test only (never saved)
    @State private var family: String?
    @State private var popout: String?
    @State private var pageWidth: CGFloat = 1100
    @State private var selfTestEmpty = false   // LOOPVIEW=empty: the no-loops card, for captures only
    private var view: String { viewOverride ?? savedView }

    var body: some View {
        FleetPage(title: "Loops", subtitle: subtitle) {
            HStack(spacing: 8) {
                if board.loops.contains(where: { $0.state == .paused }) && !board.loops.contains(where: { $0.state.isActive }) {
                    RoofButton("Resume all") { board.resumeAll() }
                } else {
                    RoofButton("⏸ Pause all") { board.pauseAll() }.disabled(board.loops.isEmpty)
                }
                if v2 {
                    // LAB-2055: Kinds · Activity replaces the Gallery toggle (the gallery's content is in Kinds, a
                    // family's page and the pop-out).
                    Segmented(options: [("kinds", "Kinds"), ("activity", "Activity")],
                              selection: Binding(get: { view }, set: { viewOverride = nil; savedView = $0; family = nil }))
                        .help("Kinds: every loop by what it does · Activity: outcomes, rounds, the list and Tonight")
                        .accessibilityLabel("Loops view")
                } else {
                    RoofButton(gallery ? "‹ Loops" : "Gallery") { gallery.toggle(); selected = nil }
                        .help("The kinds of loops, what each produces, and a real sample of each (LAB-1922)")
                }
                RoofButton("+ New loop", .primary) { editing = LoopDraft.new() }
            }
        } content: {
            if let e = board.error {
                Text(e).ui(12.5).foregroundStyle(t.needsText.color).textSelection(.enabled)
            }
            if gallery {
                // LAB-1951: the gallery scrolls in its own view, opened at its top. It was a plain stack taller than the
                // page, so the page drew it centred: it opened past its own header and first kinds, with no way up.
                ScrollView {
                    LoopGalleryView(board: board, openLoop: { id in gallery = false; selected = id },
                                    startFrom: { l in editing = LoopDraft.duplicate(from: l) })
                        .padding(.bottom, 8)
                }
                .defaultScrollAnchor(.top)
                .id("loop-gallery")
                .accessibilityLabel("Loop gallery")
            } else if v2 {
                // LAB-2055: a loop opens in a pop-out card over the page (the overlay below), never a full-width page.
                Group {
                    if view == "activity" {
                        // v2 (A9, C5.1): the loops beside Tonight, unchanged.
                        HStack(alignment: .top, spacing: 18) {
                            VStack(alignment: .leading, spacing: 14) {
                                if !board.outcomes.isEmpty { LoopOutcomesCard(rows: board.outcomes, setup: board.setup) { popout = $0 } }   // LAB-1918 · LAB-1941
                                LoopRunsView(model: model, board: board)   // LAB-1933: loop rounds live here, not in the session rail
                                if board.loops.isEmpty { empty.frame(maxWidth: .infinity, alignment: .top) } else { list.frame(maxWidth: .infinity) }
                            }
                            V2TonightPanel(model: model, board: board).frame(width: 250)
                        }
                    } else if let f = family {
                        LoopFamilyPage(board: board, familyId: f, width: pageWidth, back: { family = nil },
                                       openLoop: { popout = $0 }, startFrom: { l in editing = LoopDraft.duplicate(from: l) })
                    } else if board.loops.isEmpty || selfTestEmpty {
                        empty.frame(maxWidth: .infinity, alignment: .top)
                    } else {
                        ScrollView {
                            LoopKindsView(board: board, width: pageWidth, openFamily: { family = $0 }, openLoop: { popout = $0 })
                                .padding(.bottom, 8)
                        }
                        .defaultScrollAnchor(.top)
                        .accessibilityLabel("Kinds of loops")
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
            } else if board.loops.isEmpty {
                empty
            } else {
                HStack(alignment: .top, spacing: 18) {
                    list.frame(width: 360)
                    detail.frame(maxWidth: .infinity)
                }
            }
        }
        .overlay {
            // LAB-2055: the pop-out card (Kinds, a family's page, Activity, the Inbox's Open loop all open it).
            if v2, let id = popout, let l = board.loops.first(where: { $0.id == id }) {
                LoopPopout(loop: l, rounds: board.rounds[l.id] ?? [], model: model, board: board, win: win,
                           edit: { editing = LoopDraft(loop: l, isNew: false) },
                           duplicate: { editing = LoopDraft.duplicate(from: l) },
                           delete: { confirmDelete = l },
                           close: { popout = nil })
            }
        }
        .onAppear {
            board.start()
            if let f = inbox.focus { focus(f); inbox.focus = nil }
            if let d = inbox.draftRequest { editing = LoopDraft(loop: d, isNew: true); inbox.draftRequest = nil }
            selfTest()
        }
        .onDisappear { board.stop() }
        .onChange(of: inbox.focus) { _, f in if let f { focus(f); inbox.focus = nil } }
        .onChange(of: inbox.draftRequest) { _, d in if let d { editing = LoopDraft(loop: d, isNew: true); inbox.draftRequest = nil } }
        .onReceive(NotificationCenter.default.publisher(for: .newLoop)) { _ in editing = LoopDraft.new() }
        .sheet(item: $editing) { d in
            LoopEditor(draft: d, settings: model.settings, onSave: { loop, run in
                board.save(loop, isNew: d.isNew, run: run)
                selected = loop.id
                if v2 { popout = loop.id }
                editing = nil
            }, onCancel: { editing = nil })
            .themed(t.name)
        }
        .alert("Delete this loop?", isPresented: Binding(get: { confirmDelete != nil }, set: { if !$0 { confirmDelete = nil } }),
               presenting: confirmDelete) { l in
            Button("Delete", role: .destructive) { board.delete(l.id); if selected == l.id { selected = nil }; if popout == l.id { popout = nil } }
            Button("Cancel", role: .cancel) {}
        } message: { l in
            Text("Its loop.json, state.json and round log are removed. Its worktree \(l.worktreePath) and branch \(l.branch) stay, with any work in them.")
        }
    }

    /// Open a loop from elsewhere (the Inbox's Open loop, a self-test): v2 pops its card out over the page.
    private func focus(_ id: String) {
        if v2 { popout = id } else { selected = id; gallery = false }
    }

    /// LAB-2055 · ONEROOF_SELFTEST_LOOPVIEW=kinds|activity|kind:<family>|loop:<id> (LOOPGALLERY=1 = kinds in v2).
    private func selfTest() {
        let env = ProcessInfo.processInfo.environment
        if env["ONEROOF_SELFTEST_LOOPGALLERY"] == "1" { if v2 { viewOverride = "kinds" } else { gallery = true } }
        guard let v = env["ONEROOF_SELFTEST_LOOPVIEW"] else { return }
        if v == "kinds" || v == "activity" { viewOverride = v }
        else if v == "empty" { viewOverride = "kinds"; selfTestEmpty = true }
        else if v.hasPrefix("kind:") { viewOverride = "kinds"; family = String(v.dropFirst(5)) }
        else if v.hasPrefix("loop:") { viewOverride = "kinds"; focus(String(v.dropFirst(5))) }
    }

    private var subtitle: String {
        let running = board.loops.filter { $0.state == .running }.count
        let needs = board.loops.filter { $0.state == .needsYou }.count
        let mine = board.loops.filter { $0.origin == .mine }.count
        let builtIn = board.loops.filter { $0.origin == .builtIn }.count
        var parts = [builtIn > 0 ? "\(mine) mine · \(builtIn) built-in" : "\(board.loops.count) loop\(board.loops.count == 1 ? "" : "s")"]
        if running > 0 { parts.append("\(running) running") }
        if needs > 0 { parts.append("\(needs) need\(needs == 1 ? "s" : "") you") }
        parts.append("run by roofd with the app open or closed, checked every 30 s")
        return parts.joined(separator: " · ")
    }

    private var empty: some View {
        LoopCard(padding: 20) {
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
        let pinned = board.loops.filter(\.pinned)
        let mine = board.loops.filter { !$0.pinned && $0.origin == .mine }
        let builtIn = board.loops.filter { !$0.pinned && $0.origin == .builtIn }
        return LoopCard(padding: 8) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if !pinned.isEmpty {
                        LoopLabel("Pinned").padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 2)
                        ForEach(pinned) { row($0) }
                    }
                    if !mine.isEmpty {
                        LoopLabel("Mine").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(mine) { row($0) }
                    }
                    if !builtIn.isEmpty {
                        LoopLabel("Built-in").padding(.horizontal, 8).padding(.top, 8).padding(.bottom, 2)
                        ForEach(builtIn) { row($0) }
                    }
                }
            }
        }
    }

    private func row(_ l: Loop) -> some View {
        let rs = board.rounds[l.id] ?? []
        let checks = rs.filter { $0.kind != .stop }
        let last = checks.last
        let isSel = (v2 ? popout : (selected ?? board.loops.first?.id)) == l.id   // v2: nothing open = nothing selected
        return Button { if v2 { popout = l.id } else { selected = l.id } } label: {
            if v2 { v2Row(l, rs, last) } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    StatusDot(status: l.state.pillStatus)
                    Text(l.displayTitle).ui(TypeScale.row, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Text(l.origin.label).ui(10.5, .medium).foregroundStyle(t.text2.color)
                    Spacer(minLength: 4)
                    Text(rowRight(l, rs)).ui(11.5, l.state == .needsYou || l.state == .failed ? .semibold : .regular)
                        .foregroundStyle((l.state == .needsYou || l.state == .failed ? t.text : t.text2).color).lineLimit(1)
                }
                HStack(spacing: 8) {
                    Text(Workspace.repoLabel(for: l.repoPath)).ui(11.5, mono: true).foregroundStyle(t.text2.color).lineLimit(1)
                    Spacer(minLength: 4)
                    HealthStrip(results: checks.suffix(8).map(\.checkPassed))
                    if let last { CheckGlyph(passed: last.checkPassed == true) }
                }
            }
            .padding(.vertical, 7).padding(.horizontal, 8)
            .contentShape(Rectangle())
            }
        }
        .buttonStyle(PressStyle(radius: Radius.row))
        .hoverHighlight(selected: isSel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(l.displayTitle), \(l.origin.label), \(l.state.label), \(rowRight(l, rs))" + (last.map { $0.checkPassed == true ? ", last check passed" : ", last check failed" } ?? ""))
        .accessibilityAddTraits(isSel ? .isSelected : [])
    }

    /// v2 row (A9): name and its limits, then when / where it stands, the last check and the state pill.
    private func v2Row(_ l: Loop, _ rs: [LoopRound], _ last: LoopRound?) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(l.displayTitle).ui(TypeScale.row, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    Text(l.origin.label).ui(10.5, .medium).foregroundStyle(t.text2.color)
                }
                Text([l.externalSchedule.map { "ae · " + $0 } ?? l.trigger.label, l.limits.label, Workspace.repoLabel(for: l.repoPath)].joined(separator: " · "))
                    .ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(rowRight(l, rs)).ui(12).foregroundStyle(t.text2.color).lineLimit(1).frame(width: 150, alignment: .leading)
            HealthStrip(results: rs.filter { $0.kind != .stop }.suffix(8).map(\.checkPassed))
            if let last { CheckGlyph(passed: last.checkPassed == true) }
            LoopStateChip(loop: l).frame(width: 110, alignment: .trailing)   // LAB-2056: Off, never struck through
        }
        .padding(.vertical, 10).padding(.horizontal, 12)
        .contentShape(Rectangle())
    }

    private func rowRight(_ l: Loop, _ rs: [LoopRound]) -> String {
        let used = l.run.map { r in rs.filter { $0.runId == r.id && $0.kind == .round }.count } ?? 0
        switch l.state {
        case .running: return "round \(l.run?.active?.n ?? used) of \(l.limits.maxRounds)"
        case .needsYou: return "needs you"
        case .waiting:
            if let next = LoopController.nextStart(l, rounds: rs, now: Date()) { return "next " + next.formatted(date: .omitted, time: .shortened) }
            if l.run == nil, l.trigger.isQuiet, !l.runRequested { return "waiting for quiet" }       // LAB-1369
            if l.run == nil, let e = l.trigger.event, !l.runRequested { return "waiting for " + e }   // LAB-1865
            return l.runRequested ? "starting" : "waiting"
        case .done:
            let n = rs.last(where: { $0.kind == .stop }).map { s in rs.filter { $0.runId == s.runId && $0.kind == .round }.count } ?? 0
            return "done in \(n) round\(n == 1 ? "" : "s")"
        case .failed: return "stopped at a limit"
        case .paused: return "paused"
        case .stopped: return l.trigger.isArmed ? "off" : "run when you want"   // LAB-2056: Off, as its chip says
        }
    }

    // MARK: Detail

    @ViewBuilder private var detail: some View {
        if let l = board.loops.first(where: { $0.id == (selected ?? board.loops.first?.id) }) {
            LoopDetail(loop: l, rounds: board.rounds[l.id] ?? [], model: model, board: board, win: win,
                       edit: { editing = LoopDraft(loop: l, isNew: false) },
                       duplicate: { editing = LoopDraft.duplicate(from: l) },
                       delete: { confirmDelete = l })
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
                    .fill((r == nil ? LoopLook.unknownBar(t.name) : r == true ? t.statusDone : t.needsText).color)   // LAB-2056: no faded red
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
    var win: WindowState?
    var edit: () -> Void
    var duplicate: () -> Void = {}
    var delete: () -> Void
    /// LAB-2055: set when the detail is the pop-out card (✕ in its header; it grows with its content up to `maxHeight`).
    var close: (() -> Void)? = nil
    var maxHeight: CGFloat? = nil
    @Environment(\.theme) private var t
    @State private var open: Set<String> = []
    @State private var contentHeight: CGFloat = 400
    @Environment(\.v2Window) private var v2

    var body: some View {
        if let maxHeight {
            // The card is as tall as its content, up to maxHeight; past that it scrolls inside.
            LoopCard(padding: 18, shadow: false) {
                ScrollView {
                    content.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .frame(height: max(80, min(contentHeight, maxHeight - 36)))
            }
        } else {
            LoopCard(padding: 18) { ScrollView { content } }
        }
    }

    private var content: some View {
        let l = loop
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                StatusDot(status: l.state.pillStatus, size: 10)
                Text(l.displayTitle).ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                LoopStateChip(loop: l)   // LAB-2056: a plain Off chip, never struck through
                LoopTagChip(text: l.origin.label)
                if l.pinned { LoopTagChip(text: "Pinned") }
                Spacer()
                Text(l.externalSchedule ?? l.trigger.label).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
                if let close {
                    Button { close() } label: {
                        Text("✕").ui(13, .semibold).foregroundStyle(t.text2.color).frame(width: 24, height: 24).contentShape(Rectangle())
                    }
                    .buttonStyle(PressStyle()).help("Close (Esc)").accessibilityLabel("Close")
                }
            }
            facts(l)
            if case .notConfigured(let missing) = board.setup[l.id] { setupBox(l, missing) }   // LAB-2100
            if let why = l.stopReason, l.run == nil {
                Text((l.state == .done ? "✓ " : "✕ ") + why).ui(12.5).foregroundStyle((l.state == .done ? t.text2 : t.text).color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions(l)
            if v2 { V2LoopFences(loop: l) }   // NEW-24: what this loop can and cannot do
            Hairline()
            outcomesTable(l)                  // LAB-1941
            Hairline()
            roundsTable(l)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// LAB-2100 · the loop is on but has nothing to check: what is missing, the settings to add (a starting point to copy)
    /// and where they go. One Roof never edits the kit's config; Open config shows it in the viewer.
    private func setupBox(_ l: Loop, _ missing: [String]) -> some View {
        let snippet = LoopSetup.snippet(l.id)
        let cfg = board.aeConfigPath
        return VStack(alignment: .leading, spacing: 8) {
            Text("Not configured: a run checks nothing yet").ui(13, .semibold).foregroundStyle(t.needsText.color)
            ForEach(missing, id: \.self) { m in
                Text("· " + m).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            if let snippet {
                Text(snippet).ui(TypeScale.monoBody, mono: true).foregroundStyle(t.text.color)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.window.color))
                    .accessibilityLabel("Settings to add: \(snippet)")
            }
            Text(cfg.map { "Add it under loops › settings in \(($0 as NSString).abbreviatingWithTildeInPath), the kit's config. The next run uses it." }
                 ?? "The kit has no config file yet: create ~/.config/ae/config.yaml (ae init writes one) and add it there.")
                .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if let cfg { RoofButton("Open config") { model.openInViewer(cfg) }.help("Show the kit's config in One Roof's viewer") }
                if let snippet {
                    RoofButton("Copy settings") {
                        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(snippet, forType: .string)
                    }
                    .help("Copy the settings above, to paste into the config and fill in")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(t.needsText.color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Not configured")
    }

    private func facts(_ l: Loop) -> some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 14, verticalSpacing: 7) {
            fact("Origin", l.origin == .builtIn ? "Built-in (Agentic Engineering kit · ships off)"
                 : l.isKitFile ? "Mine (an ae loop: \(((l.specFile ?? "") as NSString).lastPathComponent))" : "Mine (saved in _common/loops)")
            if let sched = l.externalSchedule { fact("Schedule", sched + " · run by ae (ae loops on/off); One Roof runs it only on Run now") }
            if let k = LoopKinds.kind(l.kind) { fact("Kind", k.title + (k.family.map { " (" + $0.title + ")" } ?? "") + " · " + k.produces) }
            fact("Goal", l.goal.isEmpty ? "—" : l.goal)
            fact("Check", l.check, mono: true)
            fact("Agent", l.agent.displayName + (l.model.map { " · " + $0 } ?? ""))
            fact("Repo", Workspace.repoLabel(for: l.repoPath))
            fact("Worktree", "\((l.worktreePath as NSString).abbreviatingWithTildeInPath) · branch \(l.branch)", mono: true)
            fact("Limits", l.limits.label)
            fact("Output", LoopKinds.destination(act: l.act))   // LAB-2055: was the gallery's Output line
            fact("Gates", "Never pushes, merges or deploys. A round that asks permission waits in Decisions.")
        }
    }

    private func fact(_ k: String, _ v: String, mono: Bool = false) -> some View {
        GridRow {
            LoopLabel(k)
            Text(v).ui(mono ? TypeScale.monoBody : 13, mono: mono).foregroundStyle(t.text.color)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("\(k): \(v)")
        }
    }

    private func actions(_ l: Loop) -> some View {
        HStack(spacing: 8) {
            // LAB-2056: a disabled button stays legible (no faded red) and says why on hover and to VoiceOver.
            LoopButton("Run now", .primary, reason: LoopLook.disabledReason("Run now", l)) { board.runNow(l.id) }
            if l.state == .paused || l.state == .stopped && l.run == nil && l.trigger.isArmed {
                RoofButton("Resume") { board.resume(l.id) }
            } else {
                LoopButton("Pause", reason: LoopLook.disabledReason("Pause", l)) { board.pause(l.id) }
            }
            LoopButton("Stop", .danger, reason: LoopLook.disabledReason("Stop", l)) { board.stopLoop(l.id) }
            if let file = l.specFile {
                RoofButton("Edit the file") { model.openInViewer(file) }
                    .help("ae owns this loop's file; One Roof shows it and runs it on Run now")
            } else {
                RoofButton("Edit") { edit() }
            }
            if l.origin == .builtIn {
                RoofButton("Duplicate as mine") { duplicate() }
                    .help("Start from this: a copy of this loop that is yours, opened in the editor")
            }
            RoofButton(l.pinned ? "Unpin" : "Pin") { board.togglePin(l.id) }
            Spacer()
            if l.origin == .mine && !l.isKitFile {
                RoofButton("Delete", .danger) { delete() }
            } else if board.store.hasDiskOverride(l.id) {
                RoofButton("Reset") { board.delete(l.id) }
            }
        }
    }

    /// LAB-1941 · what this loop produced (the outcome ledger), each opening where it points; a staged one is approved
    /// or rejected right here (the same decision Today records).
    @ViewBuilder private func outcomesTable(_ l: Loop) -> some View {
        let os = board.outcomesByLoop[l.id] ?? []
        let runs = board.runsByLoop[l.id] ?? []
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                LoopLabel("Outcomes")
                Spacer()
                Text("\(runs.count) run\(runs.count == 1 ? "" : "s") in the ledger · \(os.filter { $0.status == "staged" }.count) staged")
                    .ui(11.5, mono: true).foregroundStyle(t.text2.color)
            }
            if os.isEmpty {
                Text("Nothing produced yet. Each commit a run leaves on \(l.branch), and each issue, PR or report, shows here.")
                    .ui(12.5).foregroundStyle(t.text2.color)
                // LAB-2055: the gallery's "last run" line moved here (a sample is the first outcome row below).
                if let r = runs.first {
                    Text("Last run (\(r.result), \(String(r.started.prefix(10)))): " + (r.summary.isEmpty ? "no summary" : r.summary))
                        .ui(12.5).foregroundStyle(t.text2.color).lineLimit(2).textSelection(.enabled)
                }
            }
            ForEach(os.prefix(30)) { o in
                HStack(spacing: 8) {
                    LoopOutcomeLine(outcome: o, model: model, win: win)
                    if o.status == "staged" {
                        let it = LoopInbox.today([o], titles: [l.id: l.displayTitle]).first
                        if let it, ["commit", "pr"].contains(o.kind) {
                            RoofButton("Approve → PR", .primary) {
                                // One run's commits go together: approve them as Today groups them.
                                let group = LoopInbox.today(os.filter { $0.status == "staged" }, titles: [:]).first { $0.outcomeIds.contains(o.id) } ?? it
                                LoopInboxState.shared.approveAndOpenPR(group) { board.reload(); model.refreshLoopInbox() }
                            }
                        } else if let it {
                            RoofButton("Approve") { LoopInboxState.shared.decide(it, "approved") { board.reload(); model.refreshLoopInbox() } }
                        }
                        if let it { RoofButton("Reject", .danger) { LoopInboxState.shared.decide(it, "rejected") { board.reload(); model.refreshLoopInbox() } } }
                    }
                }
            }
        }
    }

    private func roundsTable(_ l: Loop) -> some View {
        let lines = Array(rounds.suffix(60).reversed())
        let used = l.run.map { r in rounds.filter { $0.runId == r.id && $0.kind == .round }.count }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                LoopLabel("Rounds")
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
                // LAB-1951: "Oct 31, 3:23 AM" on one line (with the year it wrapped in the 150 pt column).
                Text(r.ended.formatted(.dateTime.month(.abbreviated).day().hour().minute())).ui(12, mono: true).foregroundStyle(t.text2.color)
                    .lineLimit(1).frame(width: 150, alignment: .leading)
                if r.kind == .stop {
                    Text(r.note ?? "Run ended").ui(12.5).foregroundStyle(t.text.color).lineLimit(isOpen ? nil : 1)
                } else {
                    HStack(spacing: 3) {
                        Text("check").ui(12.5, .semibold).foregroundStyle(t.text.color)
                        CheckGlyph(passed: r.checkPassed == true)
                    }
                    Text(r.checkPassed == true ? (r.note ?? "") : (r.failureKey ?? "")).ui(12, mono: true).foregroundStyle(t.text2.color).lineLimit(1)
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

    static func duplicate(from src: Loop) -> LoopDraft {
        var l = src
        l.id = ""
        l.origin = .mine
        l.title = nil
        l.name = "my-\(src.name)"
        l.state = .stopped
        l.run = nil
        l.runRequested = false
        l.lastRunAt = nil
        l.stopReason = nil
        return LoopDraft(loop: l, isNew: true)
    }
}

struct LoopEditor: View {
    @State var draft: LoopDraft
    var settings: AppSettings = AppSettings()
    var onSave: (Loop, Bool) -> Void
    var onCancel: () -> Void
    @Environment(\.theme) private var t
    @State private var testing = false
    @State private var testResult: TestOutcome?

    struct TestOutcome { var result: LoopCheckResult; var folder: String }
    @State private var repos: [String] = []
    @State private var template = ""
    /// LAB-1921: the plain-words description, the draft's notes and the dry-run preview.
    @State private var describe = ""
    @State private var drafting = false
    @State private var draftNotes: [String] = []
    @State private var showPreview = false
    /// LAB-1920: the sheet's size, remembered.
    @AppStorage("loops.editor.width", store: Prefs.defaults) private var sheetW: Double = 760
    @AppStorage("loops.editor.height", store: Prefs.defaults) private var sheetH: Double = 820

    private var l: Binding<Loop> { $draft.loop }
    private var nightly: Bool { draft.loop.trigger.isArmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(draft.isNew ? "New loop" : "Edit loop").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Spacer()
                if draft.isNew {
                    // LAB-1921: examples by kind (the kit's library), then the two starters.
                    FieldMenu(title: template.isEmpty ? "Start from an example" : template, expand: false) {
                        ForEach(LoopTemplates.all) { tpl in templateButton(tpl) }
                        let byKind = Dictionary(grouping: LoopTemplates.builtInTemplates(), by: { $0.kind ?? "other" })
                        ForEach(LoopKinds.all.filter { byKind[$0.id] != nil }) { k in
                            Section(k.title + " · " + k.produces) { ForEach(byKind[k.id] ?? []) { tpl in templateButton(tpl) } }
                        }
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if draft.isNew { describeBox }
                    field("Name", help: "A short name; it names the loop's folder, worktree and branch (loop/<name>).") {
                        TextField("fix-ci", text: l.name).textFieldStyle(.roundedBorder)
                    }
                    field("Goal", help: "The end state the loop keeps true, not the task. Example: “main is green on acme/web”. Every round is told it.") {
                        GrowingTextArea(text: l.goal, placeholder: "main is green on acme/web", storageKey: "goal", minHeight: 56, label: "Goal")
                    }
                    field("Repo") {
                        FieldMenu(title: Workspace.repoLabel(for: draft.loop.repoPath)) {
                            ForEach(repos, id: \.self) { r in Button(Workspace.repoLabel(for: r)) { draft.loop.repoPath = r } }
                        }
                        .disabled(!draft.isNew)
                    }
                    if !draft.isNew {
                        Text("The repo is fixed once a loop exists (its worktree lives there).").ui(11.5).foregroundStyle(t.text2.color)
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
                    if draft.loop.agent.isHosted {
                        field("Hosted connection") {
                            FieldMenu(title: draft.loop.hostedConnection?.name ?? "Choose a saved connection") {
                                ForEach(settings.hostedConnections) { c in
                                    Button("\(c.name) · \(c.model)") {
                                        draft.loop.hostedConnection = c; draft.loop.hostedRuntime = settings.hostedRuntime
                                        draft.loop.model = c.model; draft.loop.limits.maxRounds = 1
                                        draft.loop.trigger = .untilDone(everyMinutes: 0)
                                    }
                                }
                            }
                        }
                        Text("Hosted runs use one bounded round with native manual approvals. Select a saved connection; nightly and repeating paid runs remain disabled.")
                            .ui(12).foregroundStyle(t.text2.color)
                    }
                    field("Check", help: "One shell command run in the loop's worktree with nobody watching: exit 0 = the goal holds. Example: “swift test” or “bash tools/loop-checks/docs-check.sh”. Checked on save: no sentence after it, no pasted box edges, the script must exist.") {
                        VStack(alignment: .leading, spacing: 6) {
                            GrowingTextArea(text: l.check, placeholder: "e.g. npm test · swift test · pytest -q (exit 0 = done)", mono: true,
                                            storageKey: "check", minHeight: 44, label: "Check")
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
                            Segmented(options: [(0, "Until done"), (1, "Nightly"), (2, "When quiet"), (3, "On an event")], selection: Binding(
                                get: { Self.triggerIndex(draft.loop.trigger) },
                                set: { i in
                                    guard i != Self.triggerIndex(draft.loop.trigger) else { return }
                                    switch i {
                                    case 1: draft.loop.trigger = .at(hour: 2, minute: 0)
                                    case 2: draft.loop.trigger = .whenQuiet(quietMinutes: 15, fromHour: 1, toHour: 6)
                                    case 3: draft.loop.trigger = .onEvent(LoopTrigger.knownEvents[0])
                                    default: draft.loop.trigger = .untilDone(everyMinutes: 0)
                                    }
                                }))
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
                    field("Round prompt", help: "Optional extra instructions for every round. Example: “Fix one bug per round; add a test for it.”") {
                        VStack(alignment: .leading, spacing: 4) {
                            GrowingTextArea(text: l.roundPrompt, placeholder: "Extra instructions for every round (optional)", storageKey: "roundPrompt",
                                            minHeight: 110, label: "Round prompt")
                            Text("Every round already gets the goal, the check, its worktree and branch, the last check's output and what was tried; it is told never to push, merge or deploy.")
                                .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Toggle("Pinned (top of the list)", isOn: l.pinned).ui(13).foregroundStyle(t.text.color)
                    previewBox
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
        // LAB-1920: a larger sheet you can resize; its size is remembered.
        .frame(minWidth: 640, idealWidth: CGFloat(sheetW), maxWidth: 1600, minHeight: 600, idealHeight: CGFloat(sheetH), maxHeight: 1600)
        .background(GeometryReader { g in
            Color.clear.onChange(of: g.size) { _, sz in
                if sz.width >= 640 { sheetW = Double(sz.width) }
                if sz.height >= 600 { sheetH = Double(sz.height) }
            }
        })
        .background(t.window.color)
        .onAppear {
            repos = WorkspaceSearch.repos()
            if ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_LOOPPREVIEW"] == "1" { showPreview = true }
        }
    }

    private func templateButton(_ tpl: LoopTemplate) -> some View {
        Button(tpl.title + " — " + tpl.summary) {
            template = tpl.title
            draft.loop = tpl.apply(to: draft.loop)
        }
    }

    /// LAB-1921: say what you want; an agent (or the rules, without one) fills the form. Nothing is saved or run.
    private var describeBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("Describe the loop")
            GrowingTextArea(text: $describe, placeholder: "e.g. every night at 3 fix one LAB-ONEROOF-BUGS bug per round until `bash tools/loop-checks/oneroof-bugs-check.sh` passes, at most 5 rounds",
                            storageKey: "describe", minHeight: 56, label: "Describe the loop")
            HStack(spacing: 8) {
                RoofButton(drafting ? "Drafting…" : "Draft it", .primary) { draftIt() }
                    .disabled(drafting || describe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                Text("An agent drafts the goal, check, trigger and limits; you check them below and preview the first run before saving.")
                    .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(draftNotes, id: \.self) { n in Text("· " + n).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.card.color))
    }

    private func draftIt() {
        let text = describe, repo = draft.loop.repoPath
        drafting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let d = LoopDrafter.draft(text, repo: repo)
            DispatchQueue.main.async {
                draft.loop = d.apply(to: draft.loop)
                draftNotes = ["Drafted by " + (d.source == "agent" ? "an agent" : "rules") + ": check every field."] + d.notes
                drafting = false
                showPreview = true
            }
        }
    }

    /// LAB-1921: the dry run: what the first run would do, in order (Test the check runs the check for real).
    private var previewBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { showPreview.toggle() } label: {
                HStack(spacing: 6) {
                    Text(showPreview ? "▾" : "▸").ui(12.5).foregroundStyle(t.text2.color)
                    MicroLabel("Preview the first run (dry run)")
                }
            }
            .buttonStyle(.plain).accessibilityLabel(showPreview ? "Hide the preview of the first run" : "Preview the first run")
            if showPreview {
                let lines = LoopDrafter.preview(draft.loop)
                ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                    Text(line).ui(i == 4 ? TypeScale.monoSmall : 12.5, mono: i == 4).foregroundStyle(t.text.color).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(i == 4 ? 8 : 0)
                        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(i == 4 ? t.card.color : .clear))
                }
            }
        }
    }

    @ViewBuilder private var triggerDetail: some View {
        switch draft.loop.trigger {
        case .untilDone(let every):
            Stepper(every == 0 ? "Next round right after the check" : "Wait \(Schedule.every(every)) between rounds",
                    value: Binding(get: { every }, set: { draft.loop.trigger = .untilDone(everyMinutes: max($0, 0)) }), in: 0...240, step: 5)
                .ui(13).foregroundStyle(t.text.color)
            Text("Starts when you press Run now; rounds go on until the check passes or a limit is hit.").ui(11.5).foregroundStyle(t.text2.color)
        case .at(let h, let m):
            HStack(spacing: 8) {
                Text("Every night at").ui(13).foregroundStyle(t.text.color)
                Stepper(Schedule.clock(h, m), value: Binding(get: { h * 60 + m }, set: { v in
                    let x = (v + 1440) % 1440
                    draft.loop.trigger = .at(hour: x / 60, minute: x % 60)
                }), in: -15...1455, step: 15).ui(13).foregroundStyle(t.text.color)
            }
            Text("Runs only while this Mac is awake (missed nights are skipped). Pause stops it until Resume.").ui(11.5).foregroundStyle(t.text2.color)
        case .whenQuiet(let q, let f, let to):
            Stepper("After \(Schedule.every(q)) with no session of yours working or waiting on you",
                    value: Binding(get: { q }, set: { draft.loop.trigger = .whenQuiet(quietMinutes: max($0, 5), fromHour: f, toHour: to) }),
                    in: 5...240, step: 5).ui(13).foregroundStyle(t.text.color)
            Toggle("Only between", isOn: Binding(get: { f != nil && to != nil },
                                                 set: { draft.loop.trigger = .whenQuiet(quietMinutes: q, fromHour: $0 ? 1 : nil, toHour: $0 ? 6 : nil) }))
                .ui(13).foregroundStyle(t.text.color)
            if let f, let to {
                HStack(spacing: 8) {
                    Stepper(Schedule.clock(f, 0), value: Binding(get: { f }, set: { draft.loop.trigger = .whenQuiet(quietMinutes: q, fromHour: ($0 + 24) % 24, toHour: to) }), in: -1...24)
                    Text("and").ui(13).foregroundStyle(t.text2.color)
                    Stepper(Schedule.clock(to, 0), value: Binding(get: { to }, set: { draft.loop.trigger = .whenQuiet(quietMinutes: q, fromHour: f, toHour: ($0 + 24) % 24) }), in: -1...24)
                }
                .ui(13).foregroundStyle(t.text.color)
            }
            Text("Starts once your own sessions have been quiet that long, at most once " + (f != nil ? "a night" : "a day") + ". A session you start during the run does not stop it. The card shows Waiting for quiet.")
                .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        case .onEvent(let e):
            FieldMenu(title: e, expand: false) {
                ForEach(LoopTrigger.knownEvents, id: \.self) { ev in Button(ev) { draft.loop.trigger = .onEvent(ev) } }
            }
            Text("Starts once per event: `ae loops fire \(e)` records it (a webhook receiver or a git hook calls it), and roofd starts the loop within 30 s.")
                .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
    }

    static func triggerIndex(_ t: LoopTrigger) -> Int {
        switch t {
        case .untilDone: return 0
        case .at: return 1
        case .whenQuiet: return 2
        case .onEvent: return 3
        }
    }

    private func field<C: View>(_ label: String, help: String? = nil, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MicroLabel(label)
            c()
            if let help { Text(help).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }   // LAB-1920
        }
    }

    private var problem: String? {
        if draft.loop.agent.isHosted {
            guard let c = draft.loop.hostedConnection, c.configurationErrors().isEmpty, settings.hostedRuntime != nil else {
                return "Choose a verified hosted connection and configure its runtime in Settings."
            }
        }
        let x = draft.loop
        if x.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the loop a name." }
        if x.check.trimmingCharacters(in: .whitespaces).isEmpty { return "Set a check: the command that exits 0 when the goal is met." }
        if !Workspace.isInsideProjects(x.repoPath) || Workspace.isProjectsRoot(x.repoPath) { return "Pick a repo inside the projects folder." }
        if !FileManager.default.fileExists(atPath: x.repoPath + "/.git") { return "The repo must be a git repo (the loop works in its own worktree)." }
        if let p = LoopSpecLint.checkProblem(x.check, folder: checkFolder(x)) { return p }   // LAB-1846
        return nil
    }

    /// Where the check runs: the loop's worktree when it exists, else the repo.
    private func checkFolder(_ x: Loop) -> String {
        let wt = x.id.isEmpty ? nil : x.worktreePath
        return wt.flatMap { FileManager.default.fileExists(atPath: $0 + "/.git") ? $0 : nil } ?? x.repoPath
    }

    /// Test the check: in the loop's worktree when it exists, else in the repo (read-only use of your checkout:
    /// the check runs there as it is).
    private func test() {
        let x = draft.loop
        let folder = checkFolder(x)
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
        if x.agent.isHosted {
            guard let c = x.hostedConnection, c.configurationErrors().isEmpty, settings.hostedRuntime != nil else { return }
            x.hostedRuntime = settings.hostedRuntime; x.model = c.model
            x.limits.maxRounds = 1; x.trigger = .untilDone(everyMinutes: 0)
        }
        x.name = x.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.isNew { x.id = LoopStore().newId(for: x.name); x.createdAt = Date() }
        onSave(x, run)
    }
}


/// LAB-1918 · LAB-1866: the loops dashboard, from the outcome ledger: every loop's last outcome, streak, runs, cost and
/// what it produced (by kind), with what waits for you (staged). Both engines write the ledger (roofd and `ae loops`).
struct LoopOutcomesCard: View {
    @Environment(\.theme) private var t
    let rows: [LoopLedger.LoopSummary]
    /// LAB-2100: loops with nothing to check show "not configured" in place of their last result.
    var setup: [String: LoopSetup.Status] = [:]
    /// LAB-1941: a row opens its loop (its outcomes, with approve and reject).
    var open: (String) -> Void = { _ in }

    var body: some View {
        LoopCard(padding: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    LoopLabel("Outcomes")
                    Spacer()
                    let staged = rows.reduce(0) { $0 + $1.staged }
                    if staged > 0 { Text("\(staged) waiting for you").ui(11.5, .semibold).foregroundStyle(t.needsText.color) }
                }
                ForEach(rows, id: \.loop) { r in
                    Button { open(r.loop) } label: { HStack(spacing: 10) {
                        Text(r.loop).ui(12.5, .semibold).foregroundStyle(t.text.color).frame(width: 170, alignment: .leading).lineLimit(1)
                        let unset: Bool = { if case .notConfigured = setup[r.loop] { return true }; return false }()
                        Text(unset ? "not configured" : Self.result(r)).ui(12, unset ? .semibold : .regular)
                            .foregroundStyle((unset || Self.bad(r.lastResult) ? t.needsText : t.text2).color)
                            .frame(width: 130, alignment: .leading)
                        Text("\(r.runs) run\(r.runs == 1 ? "" : "s")").ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 60, alignment: .leading)
                        Text(String(format: "$%.2f", r.costUSD)).ui(11.5, mono: true).foregroundStyle(t.text2.color).frame(width: 52, alignment: .trailing)
                        Text(Self.produced(r)).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                        Spacer(minLength: 0)
                        if r.staged > 0 { Text("\(r.staged) staged").ui(11).foregroundStyle(t.accentText.color) }
                        Text("›").ui(12).foregroundStyle(t.text2.color)
                    }.contentShape(Rectangle()) }
                    .buttonStyle(PressStyle(radius: Radius.row))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel("\(r.loop): \(Self.result(r)), \(r.runs) runs, \(Self.produced(r))")
                }
            }
        }
    }

    static func bad(_ r: String) -> Bool { ["fail", "failed", "capped"].contains(r) }

    /// "failed ×2", "done ×3 · shadow".
    static func result(_ r: LoopLedger.LoopSummary) -> String {
        var s = r.lastResult.isEmpty ? "no run yet" : r.lastResult
        if r.streak > 1 { s += " ×\(r.streak)" }
        if r.lastMode == "shadow" { s += " · shadow" }
        return s
    }

    /// "2 commits · 1 issue", or "nothing yet".
    static func produced(_ r: LoopLedger.LoopSummary) -> String {
        let parts = r.outcomes.sorted { $0.key < $1.key }.map { "\($0.value) \($0.key)\($0.value == 1 ? "" : "s")" }
        return parts.isEmpty ? "nothing yet" : parts.joined(separator: " · ")
    }
}
