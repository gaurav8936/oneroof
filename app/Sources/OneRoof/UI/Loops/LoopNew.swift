import AppKit
import SwiftUI
import OneRoofCore

// LAB-2295 · 7i New loop (handover 10-7i.png, pages/7i-new-loop): replaces the 2.0.5 editor sheet for a new loop.
// Start from a built-in ▾ (the examples by kind and the two starters) · DESCRIBE IT + Draft it (LoopDrafter: an agent, or
// the rules without one) · four numbered parts, each with ✓ or change: 1 what should stay true (name, goal) · 2 how we'll
// know (the check, Test the check in the loop's folder with its exit and time) · 3 when · who runs it (trigger, repo,
// agent · model, kind) · 4 what it may do (how it acts, rounds · time · same failure, extra instructions). Right: the
// trial it starts with, where it will show, the file it writes. Cancel · Save, off · Start the trial.
//
// Trial (LP-12): One Roof's engine (roofd) has no shadow mode. A new loop's first 3 runs are labelled trial in the
// Library; they work only on the loop's own branch (loop/<name>), and nothing leaves it until you approve in Needs you.
// The card says so. A hosted agent's connection is set in the full editor (one button away), as in 2.0.5.

struct LoopNew: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    @State private var draft: Loop
    @State private var describe = ""
    @State private var drafting = false
    @State private var draftNote: String?
    @State private var notes: [String] = []
    @State private var editing: Set<Int> = []
    @State private var testing = false
    @State private var test: LoopEditor.TestOutcome?
    @State private var template = ""
    @State private var repos: [String] = []
    @State private var kindFromDescription = false

    init(model: AppModel, board: LoopBoard, nav: LoopsNav, actions: LoopsV7Actions, start: LoopDraft) {
        self.model = model; self.board = board; self.nav = nav; self.actions = actions
        _draft = State(initialValue: start.loop)
        // A blank loop opens with every part open; a copy (Duplicate, an example) opens drafted, each part to check.
        _editing = State(initialValue: start.loop.goal.isEmpty ? [1, 2, 3, 4] : [])
    }

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Describe it, or start from one of the kit's loops. Nothing is saved until you press Save.")
                            .ui(12.5).foregroundStyle(t.text2.color)
                        Spacer()
                        startFromMenu
                    }
                    describeCard
                    part1
                    part2
                    part3
                    part4
                    if let p = problem { Text(p).ui(12.5).foregroundStyle(t.needsText.color) }
                }
                .padding(.bottom, 12)
            }
            .defaultScrollAnchor(.top)
            .frame(maxWidth: 820)
            ScrollView { sideColumn }.frame(width: 330)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .onAppear {
            repos = WorkspaceSearch.repos()
            if let d = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_LOOPDESCRIBE"], describe.isEmpty { describe = d; draftIt() }
        }
    }

    // MARK: Start from a built-in

    private var startFromMenu: some View {
        FieldMenu(title: template.isEmpty ? "Start from a built-in" : template, expand: false) {
            ForEach(LoopTemplates.all) { tpl in templateButton(tpl) }
            let byKind = Dictionary(grouping: LoopTemplates.builtInTemplates(), by: { $0.kind ?? "other" })
            ForEach(LoopKinds.all.filter { byKind[$0.id] != nil }) { k in
                Section(k.title + " · " + k.produces) { ForEach(byKind[k.id] ?? []) { tpl in templateButton(tpl) } }
            }
        }
        .accessibilityLabel("Start from a built-in loop")
    }

    private func templateButton(_ tpl: LoopTemplate) -> some View {
        Button(tpl.title + " — " + tpl.summary) {
            template = tpl.title
            draft = tpl.apply(to: draft)
            if let k = tpl.kind { draft.kind = k; kindFromDescription = false }
            draftNote = "Started from \(tpl.title). Check each part; change anything."
            editing = []
            test = nil
        }
    }

    // MARK: Describe it

    private var describeCard: some View {
        LoopCard(padding: 16, shadow: false) {
            VStack(alignment: .leading, spacing: 10) {
                LoopLabel("Describe it")
                GrowingTextArea(text: $describe, placeholder: "e.g. every night at 3 fix one LAB-ONEROOF-BUGS bug per round until `bash tools/loop-checks/oneroof-bugs-check.sh` passes, at most 5 rounds",
                                storageKey: "describe7i", minHeight: 44, label: "Describe the loop")
                    .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separatorStrong.color))
                HStack(spacing: 10) {
                    RoofButton(drafting ? "Drafting…" : (draftNote == nil ? "Draft it" : "Draft it again")) { draftIt() }
                        .disabled(drafting || describe.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .help("An agent drafts the goal, check, trigger and limits (the rules do, without one). Nothing is saved or run.")
                    if let n = draftNote {
                        Text("✓ " + n).ui(12.5).foregroundStyle(LoopLook.tone(.fine, theme: t.name).text.color)
                    }
                }
                ForEach(notes, id: \.self) { n in Text("· " + n).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func draftIt() {
        let text = describe, repo = draft.repoPath
        drafting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let d = LoopDrafter.draft(text, repo: repo)
            DispatchQueue.main.async {
                draft = d.apply(to: draft)
                if let k = LoopsV7Setup.guessKind(text) { draft.kind = k; kindFromDescription = true }
                draftNote = "Drafted below by " + (d.source == "agent" ? "an agent" : "the rules") + ". Check each part; change anything."
                notes = d.notes
                drafting = false
                editing = draft.check.trimmingCharacters(in: .whitespaces).isEmpty ? [2] : []   // no check drafted: open part 2
                test = nil
            }
        }
    }

    // MARK: The four parts

    private var part1: some View {
        let ok = !draft.name.trimmingCharacters(in: .whitespaces).isEmpty && !draft.goal.trimmingCharacters(in: .whitespaces).isEmpty
        return LoopPartCard(n: 1, label: "What should stay true", headline: draft.goal.isEmpty ? "No goal yet" : draft.goal,
                            sub: "The end state, not the task. Every run is told it.", ok: ok, open: editing.contains(1), toggle: { toggle(1) }) {
            LoopFieldGrid {
                LoopField("Name", help: "Names its folder, worktree and branch (loop/<name>).") {
                    TextField("fix-ci", text: $draft.name).textFieldStyle(.roundedBorder)
                }
                LoopField("Goal", help: "The end state, not the task. Example: “main is green on acme/web”.") {
                    GrowingTextArea(text: $draft.goal, placeholder: "main is green on acme/web", storageKey: "goal7i", minHeight: 44, label: "Goal")
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separator.color))
                }
            }
        }
    }

    private var part2: some View {
        LoopPartCard(n: 2, label: "How we'll know", headline: "One command, exit 0 = true",
                     sub: "Run in the loop's worktree with nobody watching.", ok: test?.result.passed == true,
                     status: testStatus, open: editing.contains(2), toggle: { toggle(2) }) {
            VStack(alignment: .leading, spacing: 8) {
                if !editing.contains(2), !draft.check.isEmpty { LoopCodeChip(text: draft.check) }
                if editing.contains(2) {
                    GrowingTextArea(text: $draft.check, placeholder: "e.g. npm test · swift test · pytest -q (exit 0 = done)", mono: true,
                                    storageKey: "check7i", minHeight: 40, label: "Check")
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separator.color))
                }
                LoopCheckTester(loop: draft, testing: $testing, result: $test)
            }
        }
    }

    private var testStatus: String {
        guard let r = test?.result else { return testing ? "testing…" : "not tested" }
        if r.passed { return "✓ tested · passed in \(Int(r.duration.rounded())) s" }
        return r.timedOut ? "✕ tested · timed out" : "✕ tested · fails (exit \(r.exitCode)) in \(Int(r.duration.rounded())) s"
    }

    private var part3: some View {
        let kindTitle = LoopKinds.kind(draft.kind).map { ($0.family?.title ?? "Other") + " · " + $0.title } ?? "Other · no kind"
        return LoopPartCard(n: 3, label: "When · who runs it", headline: LoopEditWords.when(draft.trigger) + " · by One Roof (roofd)",
                            sub: "Runs with the app open or closed. Kind: \(kindTitle)" + (kindFromDescription ? " (from your description)." : "."),
                            ok: true, open: editing.contains(3), toggle: { toggle(3) }) {
            VStack(alignment: .leading, spacing: 10) {
                LoopTriggerPicker(trigger: $draft.trigger)
                if editing.contains(3) {
                    LoopTriggerDetail(trigger: $draft.trigger)
                    LoopFieldGrid {
                        LoopField("Repo") {
                            FieldMenu(title: Workspace.repoLabel(for: draft.repoPath)) {
                                ForEach(repos, id: \.self) { r in Button(Workspace.repoLabel(for: r)) { draft.repoPath = r } }
                            }
                        }
                        LoopField("Kind", help: "The lane it shows in on Loops.") {
                            LoopKindPicker(kind: Binding(get: { draft.kind }, set: { draft.kind = $0; kindFromDescription = false }))
                        }
                        LoopField("Agent · model", help: "Model optional; the CLI default is recorded per run.") {
                            LoopAgentModel(loop: $draft)
                        }
                    }
                    if draft.agent.isHosted {
                        HStack(spacing: 8) {
                            Text("A hosted agent needs a saved connection: set it in the full editor.").ui(12).foregroundStyle(t.text2.color)
                            RoofButton("Open the full editor") { actions.fullEditor(LoopDraft(loop: draft, isNew: true)) }
                        }
                    }
                }
            }
        }
    }

    private var part4: some View {
        LoopPartCard(n: 4, label: "What it may do", headline: "Fix on its branch · " + LoopEditWords.limits(draft.limits),
                     sub: "It never pushes, merges or deploys. A step that asks permission waits in Needs you.", ok: true,
                     open: editing.contains(4), toggle: { toggle(4) }) {
            VStack(alignment: .leading, spacing: 10) {
                LoopActPicker()
                if editing.contains(4) {
                    LoopLimitsFields(loop: $draft)
                    LoopField("Extra instructions for every round", help: "The goal, the check and the last output are always included.") {
                        GrowingTextArea(text: $draft.roundPrompt, placeholder: "Optional, e.g. Fix one bug per round; add a test for it.",
                                        storageKey: "roundPrompt7i", minHeight: 44, label: "Extra instructions")
                            .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separator.color))
                    }
                }
            }
        }
    }

    private func toggle(_ n: Int) { if editing.contains(n) { editing.remove(n) } else { editing.insert(n) } }

    // MARK: The side column

    private var sideColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            trialCard
            LoopSideCard(title: "Where it will show") {
                let fam = LoopKinds.family(ofKind: draft.kind)?.id ?? "other"
                let k = LoopLook.kind(fam, theme: t.name)
                (Text("In the ") + Text(LoopKinds.family(fam)?.title ?? "Other").bold().foregroundColor(k.text.color)
                 + Text(" lane on Loops, as ") + Text(draft.name.isEmpty ? "your loop" : draft.name).bold() + Text(". ")
                 + Text(LoopsV7Setup.laneChange(family: fam, rows: board.rows, turnsOn: true)))
                    .ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            }
            LoopSideCard(title: "The file it writes") {
                let id = draft.name.isEmpty ? "<name>" : Loop.slug(draft.name)
                Text(((LoopStore.defaultRoot as NSString).abbreviatingWithTildeInPath) + "/\(id)/loop.json").ui(12, mono: true)
                    .foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Text("Worktree and branch loop/\(id). It never pushes, merges or deploys.").ui(12.5).foregroundStyle(t.text2.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 8) {
                Spacer()
                RoofButton("Cancel") { nav.back() }.keyboardShortcut(.cancelAction)
                RoofButton("Save, off") { save(on: false) }.disabled(problem != nil)
                    .help("Saves the loop, off. Turn it on from the Library when you are ready.")
                RoofButton("Start the trial", .primary) { save(on: true) }.disabled(problem != nil).keyboardShortcut(.defaultAction)
                    .help(draft.trigger.isArmed ? "Saves it on: its first \(LoopsV7Setup.trialRuns) runs are the trial" : "Saves it and starts its first run (the trial's first)")
            }
        }
    }

    private var trialCard: some View {
        let plan = LoopsV7Setup.trialPlan(draft.trigger, now: Date())
        return VStack(alignment: .leading, spacing: 8) {
            LoopLabel("It starts with a trial")
            Text("\(LoopsV7Setup.trialRuns) trial runs on its own branch: nothing leaves it until you say so.")
                .ui(15, .bold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(plan.enumerated()), id: \.offset) { i, p in
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(p.when).ui(12.5, .semibold).foregroundStyle(t.text.color).frame(width: 64, alignment: .leading)
                        Circle().strokeBorder((i == plan.count - 1 ? t.accent : t.separatorStrong).color, lineWidth: 1.5)
                            .background(Circle().fill(i == plan.count - 1 ? .clear : t.surface2.color))
                            .frame(width: 9, height: 9)
                        Text(p.what).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 7)
                }
            }
            Text("One Roof's engine has no shadow mode yet: these runs work for real, but only on the loop's branch. Each shows in Needs you; go live when they look right. (The kit's own loops run true shadow nights.)")
                .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.text.color, lineWidth: 2))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("It starts with a trial")
    }

    // MARK: Save

    private var problem: String? { LoopEditWords.problem(draft, settings: model.settings) }

    private func save(on: Bool) {
        guard problem == nil else { return }
        var x = draft
        x.name = x.name.trimmingCharacters(in: .whitespacesAndNewlines)
        x.id = LoopStore().newId(for: x.name)
        x.createdAt = Date()
        x.origin = .mine
        board.saveNew(x, on: on)
        nav.stack = []
        nav.setRoot(.library)
        nav.librarySelected = x.id
    }
}

// MARK: - Shared pieces (7i, 7m)

/// One numbered part: number, label, headline, a line under it, ✓ or change, and its fields.
struct LoopPartCard<Content: View>: View {
    @Environment(\.theme) private var t
    let n: Int
    let label: String
    var headline: String? = nil
    var sub: String? = nil
    var ok = true
    var status: String? = nil
    var open = true
    var toggle: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    /// ✓ green, ✕ red, "change" / "done" as a link, anything else (not tested, testing…) quiet.
    private var statusColour: RGB {
        if open { return t.accentText }
        guard let status else { return ok ? LoopLook.tone(.fine, theme: t.name).text : t.accentText }
        if status.hasPrefix("✓") { return LoopLook.tone(.fine, theme: t.name).text }
        if status.hasPrefix("✕") { return t.needsText }
        return t.text2
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").ui(12.5, .bold).foregroundStyle(t.window.color)
                .frame(width: 24, height: 24).background(Circle().fill(t.text.color))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    LoopLabel(label)
                    Spacer()
                    if let toggle {
                        Button(action: toggle) {
                            Text(open ? "done" : (status ?? (ok ? "✓ looks right" : "change")))
                                .ui(12.5, .semibold)
                                .foregroundStyle(statusColour.color)
                        }
                        .buttonStyle(.plain)
                        .help(open ? "Close this part" : "Change this part")
                        .accessibilityLabel(open ? "Done with \(label)" : "Change \(label)")
                    } else if let status {
                        Text(status).ui(12.5, .semibold).foregroundStyle(t.text2.color)
                    }
                }
                if let headline {
                    Text(headline).ui(15, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                }
                if let sub { Text(sub).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
                content()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Part \(n): \(label)")
    }
}

/// A labelled field with an optional line of help under it.
struct LoopField<C: View>: View {
    @Environment(\.theme) private var t
    let label: String
    var help: String? = nil
    @ViewBuilder var content: () -> C
    init(_ label: String, help: String? = nil, @ViewBuilder content: @escaping () -> C) {
        self.label = label; self.help = help; self.content = content
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ui(12.5, .semibold).foregroundStyle(t.text.color)
            content()
            if let help { Text(help).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Fields two to a row when there is room.
struct LoopFieldGrid<C: View>: View {
    @ViewBuilder var content: () -> C
    var body: some View {
        ViewThatFits(in: .horizontal) {
            LazyVGrid(columns: [GridItem(.flexible(minimum: 220), spacing: 14, alignment: .topLeading),
                                GridItem(.flexible(minimum: 220), spacing: 14, alignment: .topLeading)],
                      alignment: .leading, spacing: 10) { content() }
            VStack(alignment: .leading, spacing: 10) { content() }
        }
    }
}

/// A command in mono on a quiet fill.
struct LoopCodeChip: View {
    @Environment(\.theme) private var t
    let text: String
    var body: some View {
        Text(text).ui(12.5, mono: true).foregroundStyle(t.text.color).textSelection(.enabled).lineLimit(3)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(t.surface2.color))
    }
}

/// A small card in the side column with a micro label.
struct LoopSideCard<C: View>: View {
    @Environment(\.theme) private var t
    let title: String
    @ViewBuilder var content: () -> C
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LoopLabel(title)
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color, lineWidth: 1))
    }
}

/// Test the check: in the loop's worktree when it exists, else in the repo; exit and time, and the output's tail.
struct LoopCheckTester: View {
    @Environment(\.theme) private var t
    let loop: Loop
    @Binding var testing: Bool
    @Binding var result: LoopEditor.TestOutcome?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                RoofButton(testing ? "Testing…" : "Test the check") { run() }
                    .disabled(testing || loop.check.trimmingCharacters(in: .whitespaces).isEmpty)
                    .help("Runs the check once now, in the loop's worktree (or the repo before it has one), with nobody watching")
                if let o = result {
                    CheckGlyph(passed: o.result.passed)
                    Text(o.result.passed ? "passes" : (o.result.timedOut ? "timed out" : "fails (exit \(o.result.exitCode))"))
                        .ui(12.5, .semibold).foregroundStyle(t.text.color)
                    Text("in " + (o.folder as NSString).abbreviatingWithTildeInPath + " · \(String(format: "%.1f", o.result.duration)) s")
                        .ui(11.5, mono: true).foregroundStyle(t.text2.color).lineLimit(1)
                }
            }
            if let o = result, !o.result.output.isEmpty {
                ScrollView {
                    Text(LoopCheck.tail(o.result.output)).ui(TypeScale.monoSmall, mono: true).foregroundStyle(t.text.color)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120).padding(8)
                .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface2.color))
            }
        }
    }

    static func folder(_ x: Loop) -> String {
        let wt = x.id.isEmpty ? nil : x.worktreePath
        return wt.flatMap { FileManager.default.fileExists(atPath: $0 + "/.git") ? $0 : nil } ?? x.repoPath
    }

    private func run() {
        let x = loop, folder = Self.folder(x)
        testing = true; result = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let r = LoopCheck.run(x.check, in: folder, timeout: min(x.checkTimeout, 300))
            DispatchQueue.main.async { result = LoopEditor.TestOutcome(result: r, folder: folder); testing = false }
        }
    }
}

/// Until done · Nightly · When quiet · On an event.
struct LoopTriggerPicker: View {
    @Binding var trigger: LoopTrigger
    var body: some View {
        Segmented(options: [(0, "Until done"), (1, "Nightly"), (2, "When quiet"), (3, "On an event")], selection: Binding(
            get: { LoopEditor.triggerIndex(trigger) },
            set: { i in
                guard i != LoopEditor.triggerIndex(trigger) else { return }
                switch i {
                case 1: trigger = .at(hour: 2, minute: 0)
                case 2: trigger = .whenQuiet(quietMinutes: 15, fromHour: 1, toHour: 6)
                case 3: trigger = .onEvent(LoopTrigger.knownEvents[0])
                default: trigger = .untilDone(everyMinutes: 0)
                }
            }))
        .fixedSize()
        .accessibilityLabel("When it runs")
    }
}

/// The trigger's own settings: wait between rounds, the night's time, the quiet window, the event.
struct LoopTriggerDetail: View {
    @Environment(\.theme) private var t
    @Binding var trigger: LoopTrigger
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            switch trigger {
            case .untilDone(let every):
                Stepper(every == 0 ? "Next round right after the check" : "Wait \(Schedule.every(every)) between rounds",
                        value: Binding(get: { every }, set: { trigger = .untilDone(everyMinutes: max($0, 0)) }), in: 0...240, step: 5)
                note("Starts when you press Run now; rounds go on until the check passes or a limit is hit.")
            case .at(let h, let m):
                HStack(spacing: 8) {
                    Text("Nightly at").foregroundStyle(t.text.color)
                    Stepper(Schedule.clock(h, m), value: Binding(get: { h * 60 + m }, set: { v in
                        let x = (v + 1440) % 1440
                        trigger = .at(hour: x / 60, minute: x % 60)
                    }), in: -15...1455, step: 15)
                }
                note("Runs only while this Mac is awake (missed nights are skipped). Pause stops it until Resume.")
            case .whenQuiet(let q, let f, let to):
                Stepper("After \(Schedule.every(q)) with no session of yours working or waiting on you",
                        value: Binding(get: { q }, set: { trigger = .whenQuiet(quietMinutes: max($0, 5), fromHour: f, toHour: to) }), in: 5...240, step: 5)
                Toggle("Only between", isOn: Binding(get: { f != nil && to != nil },
                                                     set: { trigger = .whenQuiet(quietMinutes: q, fromHour: $0 ? 1 : nil, toHour: $0 ? 6 : nil) }))
                if let f, let to {
                    HStack(spacing: 8) {
                        Stepper(Schedule.clock(f, 0), value: Binding(get: { f }, set: { trigger = .whenQuiet(quietMinutes: q, fromHour: ($0 + 24) % 24, toHour: to) }), in: -1...24)
                        Text("and").foregroundStyle(t.text2.color)
                        Stepper(Schedule.clock(to, 0), value: Binding(get: { to }, set: { trigger = .whenQuiet(quietMinutes: q, fromHour: f, toHour: ($0 + 24) % 24) }), in: -1...24)
                    }
                }
                note("Starts once your own sessions have been quiet that long, at most once " + (f != nil ? "a night" : "a day") + ".")
            case .onEvent(let e):
                FieldMenu(title: e, expand: false) {
                    ForEach(LoopTrigger.knownEvents, id: \.self) { ev in Button(ev) { trigger = .onEvent(ev) } }
                }
                note("Starts once per event: `ae loops fire \(e)` records it (a webhook receiver or a git hook calls it), and roofd starts the loop within 30 s.")
            }
        }
        .ui(13).foregroundStyle(t.text.color)
    }
    private func note(_ s: String) -> some View { Text(s).ui(11.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true) }
}

/// Report only · Open an issue · Fix on its branch. One Roof's engine acts one way: rounds fix on the loop's branch.
/// The other two are drawn and say "not connected" (AGENT_RULES §6), never faked.
struct LoopActPicker: View {
    @Environment(\.theme) private var t
    var body: some View {
        HStack(spacing: 2) {
            option("Report only", on: false, help: "Not connected for One Roof's own loops: roofd's rounds always work on the loop's branch. The kit's loops can report only.")
            option("Open an issue", on: false, help: "Not connected for One Roof's own loops yet. The kit's loops open issues (act: issue).")
            option("Fix on its branch", on: true, help: "Rounds commit on loop/<name>; a pull request opens only after you approve in Needs you.")
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.control.color.opacity(t.isDark ? 1 : 0.7)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
        .fixedSize()
    }
    private func option(_ s: String, on: Bool, help: String) -> some View {
        Text(s + (on ? "" : " · not connected")).ui(12.5, .medium).foregroundStyle((on ? t.text : t.text2).color)
            .padding(.vertical, 5).padding(.horizontal, 11)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? t.surface.color : .clear))
            .help(help)
            .accessibilityLabel(s + (on ? ", selected" : ", not connected"))
    }
}

/// The agent and its model.
struct LoopAgentModel: View {
    @Binding var loop: Loop
    var body: some View {
        HStack(spacing: 8) {
            FieldMenu(title: loop.agent.displayName, expand: false) {
                ForEach(AgentKind.allCases.filter(\.isAgent)) { a in Button(a.displayName) { loop.agent = a } }
            }
            TextField("model (optional)", text: Binding(get: { loop.model ?? "" }, set: { loop.model = $0.isEmpty ? nil : $0 }))
                .textFieldStyle(.roundedBorder)
        }
    }
}

/// Rounds · time · same failure · check time limit.
struct LoopLimitsFields: View {
    @Environment(\.theme) private var t
    @Binding var loop: Loop
    var checkLimit = true
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper("At most \(loop.limits.maxRounds) round\(loop.limits.maxRounds == 1 ? "" : "s")", value: $loop.limits.maxRounds, in: 1...50)
            Stepper("At most \(Schedule.every(Int(loop.limits.maxDuration / 60))) per run",
                    value: Binding(get: { Int(loop.limits.maxDuration / 60) }, set: { loop.limits.maxDuration = TimeInterval($0 * 60) }),
                    in: 15...1440, step: 15)
            Stepper(loop.limits.sameFailureStop == 0 ? "Never stop on a repeated failure"
                    : "Stop when the same failure repeats \(loop.limits.sameFailureStop)×", value: $loop.limits.sameFailureStop, in: 0...5)
            if checkLimit {
                Stepper("Check may run \(Schedule.every(Int(loop.checkTimeout / 60)))",
                        value: Binding(get: { Int(loop.checkTimeout / 60) }, set: { loop.checkTimeout = TimeInterval(max($0, 1) * 60) }), in: 1...120)
            }
        }
        .ui(13).foregroundStyle(t.text.color)
    }
}

/// A kind from the catalog's ten, by family; "Other · not set" when none.
struct LoopKindPicker: View {
    @Binding var kind: String?
    var body: some View {
        let title = LoopKinds.kind(kind).map { ($0.family?.title ?? "Other") + " · " + $0.title } ?? "Other · not set"
        FieldMenu(title: title) {
            ForEach(LoopKinds.families) { f in
                Section(f.title) {
                    ForEach(f.kinds, id: \.self) { k in
                        if let kk = LoopKinds.kind(k) { Button(kk.title + " — " + kk.purpose) { kind = k } }
                    }
                }
            }
        }
        .accessibilityLabel("Kind: " + title)
    }
}

/// Words shared by 7i and 7m.
enum LoopEditWords {
    static func when(_ t: LoopTrigger) -> String {
        switch t {
        case .untilDone(let m): return m <= 0 ? "Until done, on Run now" : "Until done, every " + Schedule.every(m)
        case .at(let h, let m): return "Nightly " + Schedule.clock(h, m)
        case .whenQuiet: return "When quiet"
        case .onEvent(let e): return "On " + e
        }
    }

    static func limits(_ l: LoopLimits) -> String {
        "\(l.maxRounds) round\(l.maxRounds == 1 ? "" : "s") · " + Schedule.every(Int(l.maxDuration / 60))
    }

    /// What stops a save (the 2.0.5 editor's checks, unchanged).
    static func problem(_ x: Loop, settings: AppSettings) -> String? {
        if x.agent.isHosted {
            guard let c = x.hostedConnection, c.configurationErrors().isEmpty, settings.hostedRuntime != nil else {
                return "A hosted agent needs a verified connection: set it in the full editor."
            }
        }
        if x.name.trimmingCharacters(in: .whitespaces).isEmpty { return "Give the loop a name." }
        if x.check.trimmingCharacters(in: .whitespaces).isEmpty { return "Set a check: the command that exits 0 when the goal is met." }
        if !Workspace.isInsideProjects(x.repoPath) || Workspace.isProjectsRoot(x.repoPath) { return "Pick a repo inside the projects folder." }
        if !FileManager.default.fileExists(atPath: x.repoPath + "/.git") { return "The repo must be a git repo (the loop works in its own worktree)." }
        if let p = LoopSpecLint.checkProblem(x.check, folder: LoopCheckTester.folder(x)) { return p }
        return nil
    }
}
