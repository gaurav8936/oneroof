import AppKit
import SwiftUI
import OneRoofCore

// LAB-2295 · 7m Edit a loop · kit file · delete (handover 14-7m.png, pages/7m-edit): replaces the 2.0.5 editor sheet for
// an existing loop, "Edit the file", the delete alert and Duplicate.
//   One Roof loop: the four parts with every field (name, kind, goal · check, check time limit, the last test · trigger,
//   repo, agent · model, account · rounds · time, same-failure stop, extra round instructions, harvest PR base, pinned);
//   Delete… · Duplicate · Cancel · Save · Save and run; CHANGES THE NEXT RUN.
//   Kit loop: "The kit owns this loop's file and schedule. Change it in the file." with its file, Edit the file ·
//   Turn off in the kit (or Turn on, in trial) · Duplicate as mine.
//   Set kind (LP-2): a kit file through `ae loops edit <name> --set kind=<kind>` (the kit validates and writes it; One Roof
//   never rewrites a kit file), a One Roof loop in its loop.json through LoopStore; a built-in shows its catalog kind.
//   The owner's kinds for the four kind-less loops are pre-selected, never written until Set kind is pressed.

struct LoopEdit: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    let loopId: String
    @State private var draft: Loop?
    @State private var deleting = false
    @State private var testing = false
    @State private var test: LoopEditor.TestOutcome?
    @State private var confirmKit: String?

    private var loop: Loop? { board.loops.first { $0.id == loopId } }

    var body: some View {
        Group {
            if let l = loop {
                switch LoopsV7Setup.kindEdit(l) {
                case .oneRoof: oneRoofPage(l)
                case .kitFile, .builtIn: kitPage(l)
                }
            } else {
                Text("This loop is no longer on disk.").ui(13).foregroundStyle(t.text2.color)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            if ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_LOOPDELETE"] == "1" { deleting = true }
        }
        .sheet(isPresented: $deleting) {
            if let l = loop {
                LoopDeleteDialog(loop: l, staged: board.outcomesByLoop[l.id] ?? []) {
                    deleting = false
                    board.delete(l.id)
                    nav.stack = []
                    nav.setRoot(.library)
                } cancel: { deleting = false }
                .themed(t.name)
            }
        }
        .alert(confirmKit == "off" ? "Turn \(loop?.displayTitle ?? loopId) off in the kit?" : "Turn \(loop?.displayTitle ?? loopId) on?",
               isPresented: Binding(get: { confirmKit != nil }, set: { if !$0 { confirmKit = nil } })) {
            Button(confirmKit == "off" ? "Turn off" : "Turn on, in trial") {
                if confirmKit == "off" { board.turnOffKit(loopId) } else { board.turnOnKit(loopId) }
                confirmKit = nil
            }
            Button("Cancel", role: .cancel) { confirmKit = nil }
        } message: {
            Text(confirmKit == "off"
                 ? "The kit turns it off (`\(KitLoops.command("off", loopId).dropFirst().joined(separator: " "))`): it leaves its config and its launchd schedule. Its file stays."
                 : "The kit turns it on (`\(KitLoops.command("on", loopId).dropFirst().joined(separator: " "))`) and starts with \(LoopsV7Setup.trialRuns) trial nights that only say what they would do. It asks before going live.")
        }
    }

    // MARK: One Roof loop

    @ViewBuilder private func oneRoofPage(_ l: Loop) -> some View {
        // The working copy starts as the loop on disk and keeps the owner's changes until Save or Cancel.
        let d = Binding<Loop>(get: { draft ?? l }, set: { draft = $0 })
        Group {
            HStack(alignment: .top, spacing: 20) {
                VStack(spacing: 10) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Spacer()
                                LoopTagChip(text: "Mine · One Roof (roofd)")
                            }
                            part1(d, l)
                            part2(d, l)
                            part3(d)
                            part4(d)
                        }
                        .padding(.bottom, 8)
                    }
                    .defaultScrollAnchor(.top)
                    footer(d.wrappedValue, l)
                }
                .frame(maxWidth: 820)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        LoopSideCard(title: "Changes the next run") {
                            Text("Saved edits apply from the next run. A run in progress keeps the settings it started with.")
                                .ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        }
                        LoopSideCard(title: "Its folder") {
                            Text(((LoopStore().folder(l.id) + "/loop.json") as NSString).abbreviatingWithTildeInPath).ui(12, mono: true)
                                .foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                            Text("Worktree \((l.worktreePath as NSString).abbreviatingWithTildeInPath) · branch \(l.branch)").ui(12, mono: true)
                                .foregroundStyle(t.text2.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        }
                        LoopSideCard(title: "Tells you") {
                            Text("Failures and limits show in Needs you; Slack gets one line when a run stops at a limit (as in 2.0.5).")
                                .ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        }
                        V2LoopFences(loop: l)   // the pop-out's fences: what this loop can and cannot do
                    }
                }
                .frame(width: 320)
            }
        }
    }

    private func part1(_ d: Binding<Loop>, _ l: Loop) -> some View {
        LoopPartCard(n: 1, label: "What should stay true") {
            LoopFieldGrid {
                LoopField("Name", help: "Names its folder, worktree and branch (loop/<name>); the folder keeps its first name.") {
                    TextField("name", text: d.name).textFieldStyle(.roundedBorder).font(.system(size: 13, design: .monospaced))
                }
                LoopField("Kind", help: LoopsV7Setup.suggestionLine(l) ?? "The lane it shows in on Loops.") {
                    LoopSetKindControl(board: board, loop: l)
                }
            }
            LoopField("Goal", help: "The end state, not the task. Every round is told it.") {
                TextField("main is green on acme/web", text: d.goal, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...4)
            }
        }
    }

    private func part2(_ d: Binding<Loop>, _ l: Loop) -> some View {
        LoopPartCard(n: 2, label: "How we'll know") {
            LoopField("Check", help: "Exit 0 = the goal holds." + lastTest(l)) {
                TextField("npm test", text: d.check, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...3)
                    .font(.system(size: 12.5, design: .monospaced))
            }
            LoopCheckTester(loop: d.wrappedValue, testing: $testing, result: $test)
            LoopField("Check time limit", help: "Longer counts as failed.") {
                Stepper(Schedule.every(Int(d.wrappedValue.checkTimeout / 60)),
                        value: Binding(get: { Int(d.wrappedValue.checkTimeout / 60) }, set: { d.wrappedValue.checkTimeout = TimeInterval(max($0, 1) * 60) }),
                        in: 1...120).ui(13).foregroundStyle(t.text.color)
            }
        }
    }

    /// " ✓ Last check Nov 5: exit 1 (bugs remain), 3 s." from the loop's own round log.
    private func lastTest(_ l: Loop) -> String {
        guard let r = (board.rounds[l.id] ?? []).last(where: { $0.checkPassed != nil }) else { return " Not checked yet." }
        let f = DateFormatter(); f.dateFormat = "MMM d"
        let secs = Int(r.ended.timeIntervalSince(r.started).rounded())
        return " Last check \(f.string(from: r.ended)): " + (r.checkPassed == true ? "passed" : "exit \(r.exitCode.map(String.init) ?? "≠0")")
            + (r.failureKey.flatMap { $0.hasPrefix("exit") ? nil : " (\($0.prefix(40)))" } ?? "") + ", \(secs) s."
    }

    private func part3(_ d: Binding<Loop>) -> some View {
        LoopPartCard(n: 3, label: "When · who does the work") {
            VStack(alignment: .leading, spacing: 10) {
                LoopTriggerDetail(trigger: d.trigger)
                LoopFieldGrid {
                    LoopField("Repo", help: "Fixed once a loop exists (its worktree lives there).") {
                        Text(Workspace.repoLabel(for: d.wrappedValue.repoPath)).ui(13).foregroundStyle(t.text.color)
                            .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface2.color))
                    }
                    LoopField("Agent · model", help: "Model optional; the CLI default is recorded per run.") {
                        LoopAgentModel(loop: d)
                    }
                    LoopField("Account", help: "Empty = the agent's default account.") {
                        TextField("default", text: Binding(get: { d.wrappedValue.account ?? "" }, set: { d.wrappedValue.account = $0.isEmpty ? nil : $0 }))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                LoopTriggerPicker(trigger: d.trigger)
                if d.wrappedValue.agent.isHosted {
                    HStack(spacing: 8) {
                        Text("A hosted agent's connection is set in the full editor.").ui(12).foregroundStyle(t.text2.color)
                        RoofButton("Open the full editor") { actions.fullEditor(LoopDraft(loop: d.wrappedValue, isNew: false)) }
                    }
                }
            }
        }
    }

    private func part4(_ d: Binding<Loop>) -> some View {
        LoopPartCard(n: 4, label: "What it may do · limits",
                     sub: "Rounds commit on its own branch. It never pushes, merges or deploys. A step that asks permission waits in Needs you.") {
            VStack(alignment: .leading, spacing: 10) {
                LoopLimitsFields(loop: d, checkLimit: false)
                LoopField("Extra instructions for every round", help: "The goal, the check and the last output are always included.") {
                    TextField("Pick the oldest open bug.", text: d.roundPrompt, axis: .vertical).textFieldStyle(.roundedBorder).lineLimit(1...6)
                }
                LoopFieldGrid {
                    LoopField("Harvest PR to", help: "The branch an approved run's pull request goes to; empty = the repo's default.") {
                        TextField("develop", text: Binding(get: { d.wrappedValue.harvestBase ?? "" },
                                                           set: { d.wrappedValue.harvestBase = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }))
                            .textFieldStyle(.roundedBorder)
                    }
                    LoopField("Pinned", help: "Pinned loops sort first in their lane.") {
                        Toggle("Pinned", isOn: d.pinned).toggleStyle(.switch).labelsHidden()
                    }
                }
            }
        }
    }

    private func footer(_ x: Loop, _ l: Loop) -> some View {
        let problem = LoopEditWords.problem(x, settings: model.settings)
        return VStack(alignment: .leading, spacing: 6) {
            if let problem { Text(problem).ui(12.5).foregroundStyle(t.needsText.color) }
            HStack(spacing: 8) {
                RoofButton("Delete…", .danger) { deleting = true }
                    .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.needsText.color, lineWidth: 1))
                    .help("Remove this loop's files (its worktree and branch stay)")
                RoofButton("Duplicate") { nav.newLoop(LoopDraft.duplicate(from: l)) }
                Spacer()
                RoofButton("Cancel") { nav.back() }.keyboardShortcut(.cancelAction)
                RoofButton("Save") { save(x, run: false) }.disabled(problem != nil)
                RoofButton("Save and run", .primary) { save(x, run: true) }.disabled(problem != nil).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func save(_ x: Loop, run: Bool) {
        var y = x
        y.name = y.name.trimmingCharacters(in: .whitespacesAndNewlines)
        board.save(y, isNew: false, run: run)
        nav.back()
    }

    // MARK: Kit loop (and built-ins)

    private func kitPage(_ l: Loop) -> some View {
        let row = board.row(l.id)
        let file = LoopsLibrary.file(l)
        return HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LoopPartCard(n: 1, label: "What should stay true", headline: l.goal.isEmpty ? l.displayTitle : l.goal.trimmingCharacters(in: CharacterSet(charactersIn: "'\" "))) {
                        LoopField("Kind", help: kindHelp(l)) { LoopSetKindControl(board: board, loop: l) }
                    }
                    LoopPartCard(n: 2, label: "How we'll know", headline: "The kit's check") {
                        LoopCodeChip(text: l.check)
                    }
                    LoopPartCard(n: 3, label: "When · who runs it",
                                 headline: LoopsV7Setup.whoRuns(when: row.map { LoopsV7Setup.when($0, loop: l) } ?? (l.externalSchedule ?? "manual"), engine: .kit)) {
                        if let r = row { LoopLibraryStateChip(label: LoopsV7Setup.state(r, needsSetup: false, kitKnown: board.kitKnown).label,
                                                              tone: LoopsV7Setup.state(r, needsSetup: false, kitKnown: board.kitKnown).tone) }
                    }
                    LoopPartCard(n: 4, label: "What it may do", headline: LoopsV7Setup.mayActSentence(LoopsV7Setup.mayAct(act: l.act, kind: l.kind, engine: .kit))) {
                        Text("Stops after " + LoopEditWords.limits(l.limits) + ". It never pushes, merges or deploys.").ui(12.5).foregroundStyle(t.text2.color)
                    }
                }
                .padding(.bottom, 8)
            }
            .defaultScrollAnchor(.top)
            .frame(maxWidth: 820)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    kitCard(l, row: row, file: file)
                    V2LoopFences(loop: l)
                }
            }
            .frame(width: 340)
        }
    }

    private func kindHelp(_ l: Loop) -> String {
        switch LoopsV7Setup.kindEdit(l) {
        case .builtIn: return "A built-in loop shows its catalog kind; Duplicate as mine to give a copy another."
        default: return (LoopsV7Setup.suggestionLine(l).map { $0 + " " } ?? "") + "Set kind asks the kit to write it (`ae loops edit \(l.id) --set kind=…`), which checks the file first."
        }
    }

    private func kitCard(_ l: Loop, row: LoopRow?, file: String?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            LoopLabel(l.origin == .builtIn ? "A built-in kit loop · " + l.displayTitle : "A kit loop · " + l.displayTitle)
            Text("The kit owns this loop's file and schedule. Change it in the file.").ui(15, .bold).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true)
            Text("One Roof shows it, runs it on Run now and reads its on/off and mode from the kit. Saving the file updates every screen.")
                .ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            if let file, let excerpt = Self.excerpt(file) {
                Text(excerpt).ui(12, mono: true).foregroundStyle(t.text.color).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
                    .accessibilityLabel("From the loop's file: \(excerpt)")
            }
            LoopsWrap(spacing: 8) {
                if let file { RoofButton("Edit the file", .primary) { model.openInViewer(file) } }
                if let r = row, board.kitKnown {
                    if r.on { RoofButton("Turn off in the kit") { confirmKit = "off" } }
                    else { RoofButton("Turn on (\(LoopsV7Setup.trialRuns) trial runs)") { confirmKit = "on" } }
                }
                RoofButton("Duplicate as mine") { nav.newLoop(LoopDraft.duplicate(from: l)) }
                    .help("A copy that is yours (a One Roof loop), opened in New loop")
                if l.origin == .builtIn && board.store.hasDiskOverride(l.id) {
                    RoofButton("Reset") { board.delete(l.id) }   // the pop-out's Reset: drop One Roof's run state for it
                        .help("Forget One Roof's saved state for this built-in loop (its pin and run state); the kit's file is untouched")
                }
            }
            if let file {
                Text((file as NSString).abbreviatingWithTildeInPath).ui(11.5, mono: true).foregroundStyle(t.text2.color)
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.text.color, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("A kit loop: the kit owns its file")
    }

    /// The file's kind, schedule, trigger and stop lines (the parts a person changes), else its first lines.
    static func excerpt(_ path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\n")
        var out: [String] = []
        var inBlock = false
        for l in lines {
            let top = !l.hasPrefix(" ") && !l.hasPrefix("-")
            if top { inBlock = ["kind:", "schedule:", "trigger:", "stop:", "act:"].contains { l.hasPrefix($0) } }
            if inBlock && !l.trimmingCharacters(in: .whitespaces).isEmpty { out.append(l) }
        }
        if out.isEmpty { out = Array(lines.prefix(12)) }
        return out.prefix(18).joined(separator: "\n")
    }
}

// MARK: - Set kind

/// The kind picker with the owner's suggestion pre-selected and a Set kind button that writes it (kit file: through the
/// kit; One Roof loop: its loop.json). A built-in shows its catalog kind.
struct LoopSetKindControl: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    let loop: Loop
    @State private var choice: String?
    @State private var pending = false

    var body: some View {
        let current = LoopKinds.kind(loop.kind)
        switch LoopsV7Setup.kindEdit(loop) {
        case .builtIn(let k):
            Text(LoopKinds.kind(k).map { ($0.family?.title ?? "Other") + " · " + $0.title + " (catalog)" } ?? "Other · none in the catalog")
                .ui(13).foregroundStyle(t.text.color)
                .padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface2.color))
                .help("A built-in loop shows its catalog kind; it is not editable here")
        default:
            HStack(spacing: 8) {
                LoopKindPicker(kind: Binding(get: { choice ?? loop.kind }, set: { choice = $0 }))
                let target = choice ?? (current == nil ? LoopsV7Setup.suggestedKind(loop) : nil)
                if let target, target != loop.kind {
                    RoofButton(pending ? "Setting…" : "Set kind", .primary) {
                        pending = true
                        board.setKind(loop.id, kind: target)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { pending = false; board.reload() }
                    }
                    .disabled(pending)
                    .help(Self.what(loop, target))
                }
            }
            .onAppear { if choice == nil, current == nil { choice = LoopsV7Setup.suggestedKind(loop) } }
            .onChange(of: loop.kind) { _, _ in pending = false; choice = nil }
        }
    }

    static func what(_ l: Loop, _ kind: String) -> String {
        if case .kitFile = LoopsV7Setup.kindEdit(l) {
            return "The kit writes it: `" + LoopsV7Setup.setKindCommand(name: l.id, kind: kind).dropFirst().joined(separator: " ") + "` (checked before saving)"
        }
        return "Writes kind: \(kind) to this loop's loop.json"
    }
}

/// The loops a Set kind sheet is for.
struct LoopSetKindRequest: Identifiable { let ids: [String]; var id: String { ids.joined(separator: ",") } }

/// Set kind for several loops (the landing's Other lane, the Library): each with its picker, the owner's suggestion
/// pre-selected, and its own Set kind button. Nothing is written until a button is pressed.
struct LoopSetKindSheet: View {
    @Environment(\.theme) private var t
    @ObservedObject var board: LoopBoard
    let ids: [String]
    var done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Set a kind").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
            Text("A kind puts a loop in its lane on Loops. The suggestions are pre-selected; nothing changes until you press Set kind.")
                .ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(ids, id: \.self) { id in
                    if let l = board.loops.first(where: { $0.id == id }) {
                        Rectangle().fill(t.separator.color).frame(height: 1)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(l.displayTitle).ui(13.5, .semibold).foregroundStyle(t.text.color)
                                Text((l.isKitFile ? "mine · by kit" : l.origin == .builtIn ? "built-in · by kit" : "mine · by One Roof")
                                     + " · now " + (LoopKinds.kind(l.kind)?.title ?? "no kind"))
                                    .ui(11.5).foregroundStyle(t.text2.color)
                            }
                            .frame(width: 230, alignment: .leading)
                            LoopSetKindControl(board: board, loop: l)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            Text("Kit loops are changed by the kit (`ae loops edit <name> --set kind=<kind>`), which validates the file; One Roof's own loops in their loop.json.")
                .ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            if let e = board.error { Text(e).ui(12).foregroundStyle(t.needsText.color).textSelection(.enabled) }
            HStack { Spacer(); RoofButton("Done", .primary) { done() }.keyboardShortcut(.defaultAction) }
        }
        .padding(22)
        .frame(width: 640)
        .background(t.window.color)
    }
}

// MARK: - Delete

/// The delete dialog (exact 2.0.5 copy) with what is still waiting for you. Esc cancels.
struct LoopDeleteDialog: View {
    @Environment(\.theme) private var t
    let loop: Loop
    let staged: [LoopLedger.Outcome]
    var delete: () -> Void
    var cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Delete this loop?").ui(TypeScale.section + 1, .bold).foregroundStyle(t.text.color)
            Text(LoopsV7Setup.deleteMessage(worktree: (loop.worktreePath as NSString).abbreviatingWithTildeInPath, branch: loop.branch))
                .ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let w = LoopsV7Setup.stagedWarning(staged) {
                Text(w).ui(13).foregroundStyle(LoopLook.tone(.needsYou, theme: t.name).text.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                RoofButton("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
                Button(action: delete) {
                    // The failing pair (text 4.5:1 on its fill in every look), with a red edge.
                    let p = LoopLook.tone(.failing, theme: t.name)
                    Text("Delete").ui(TypeScale.small, .bold).foregroundStyle(p.text.color)
                        .padding(.vertical, 6).padding(.horizontal, 14)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(p.fill.color))
                        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(p.text.color, lineWidth: 1))
                }
                .buttonStyle(PressStyle())
                .accessibilityLabel("Delete the loop")
            }
        }
        .padding(20)
        .frame(width: 380)
        .background(t.surface.color)
    }
}
