import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2242 · E7 Set up a test (screen lane B): a sheet over any tab — 1 which task · 2 which setups (LAB-2261, v3 D4:
/// One-shot · Agent, then the setups: an agent and its model picked together, where it runs, Rules: with our rules @ hash
/// (default) or clean) · 3 how many,
/// with what the test can tell you (`power`) before what it costs · Before you start (API cost from `estimate`, seat
/// notes from the engine — never an invented share — and what is recorded with each result) · Start N tests · Running
/// and recent (the queue's only home; the header's Running · N opens it). Nothing starts until Start; ↩ starts when
/// valid, Esc closes. Replaces 2.0.3's Run tab: every field, the estimate, the cap check (grader ×1.5, in the engine),
/// the Hugging Face gate, the sandbox choice and the queue are kept (NO_REGRESSION). Engine flags: CONTRACT §2.
struct EvalsSetupSheet: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var plan = EvalRunPlan(tasks: [])
    @State private var rows: [SetupRow] = []
    /// LAB-2261 · step 2's switch: One-shot · Agent (+ Rules). Maps onto the 2.0.4 layer, so the setups are unchanged.
    @State private var pick = EvalSetupKindChoice.default
    private var layer: EvalStamp.Layer { pick.layer }
    @State private var estimates: [String: EvalEstimate] = [:]
    @State private var extras: [String: EvalSetupEstimate] = [:]
    @State private var estimateErrors: [String: String] = [:]
    @State private var power: EvalPower?
    @State private var pending: DispatchWorkItem?
    @State private var epochsText = ""
    @State private var temperatureText = ""
    @State private var seedText = "42"
    @State private var capText = "2.00"
    @State private var rules: (repo: String, hash: String?, files: [String])?
    @FocusState private var typing: Bool
    @ObservedObject private var hf = HFAccount.shared   // LAB-2117

    /// One line in 2 · Which setups (kept when unticked, so a model menu choice survives).
    struct SetupRow: Identifiable, Equatable {
        var id = UUID()
        var choice: EvalSetupChoice
        var on: Bool
    }
    /// What the sheet showed, kept while it is closed (nav.workPlan keeps the plan; the setups live here).
    private static var keptRows: [SetupRow]?
    /// Test again without a readable stamp (re-review #6): the pre-filled setups whose model and rules are flagged
    /// "pick again — not recorded" until the owner changes them.
    @State private var unrecorded: [EvalSetupChoice]?

    private var choices: [EvalSetupChoice] {
        var seen = Set<String>()
        return rows.filter(\.on).map(\.choice).filter { seen.insert($0.id).inserted }
    }
    private var testCount: Int { plan.tasks.count * choices.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)
            Rectangle().fill(t.separator.color).frame(height: 1)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    howOneTestWorks
                    // "Before you start" stays on the right down to the sheet's 980 pt; task and setups stack when narrow.
                    EvalsColumns(breakpoint: 900, side: 320) {
                        VStack(alignment: .leading, spacing: 14) {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 14) {
                                    EvalsTaskPicker(board: board, plan: $plan, changed: changed).frame(width: 290)
                                    setupsCard.frame(minWidth: 540)
                                }
                                VStack(alignment: .leading, spacing: 14) {
                                    EvalsTaskPicker(board: board, plan: $plan, changed: changed)
                                    setupsCard
                                }
                            }
                            howMany
                        }
                    } aside: { beforeYouStart }
                    EvalsQueueTable(board: board, nav: nav)
                }
                .padding(20)
                .frame(maxWidth: 1560, alignment: .topLeading)
            }
        }
        .frame(minWidth: 980, idealWidth: 1240, minHeight: 620, idealHeight: 840, alignment: .topLeading)
        .background(startKey)
        .onAppear { adopt(nav.draft); board.refreshDoctor() }
        .onChange(of: nav.draft) { _, p in adopt(p) }
        .onChange(of: plan) { _, p in nav.workPlan = p }
        .onChange(of: rows) { _, r in Self.keptRows = r; changed() }
    }

    // MARK: Header + how one test works

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 10) {
                    Text("Set up a test").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                    if EvalsDraft.isDraft { EvalsDraftTag() }
                }
                Text("Test setups on a task. Opened from Our tests, a question, a benchmark or New test or task. Nothing starts until you press Start.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
            }
            Spacer()
            RoofButton("Close") { nav.sheet = nil }.help("Close (Esc)")
        }
    }

    /// The "how one test works" strip: shown once, here (v2 design review §4).
    private var howOneTestWorks: some View {
        let own = !plan.tasks.isEmpty && plan.tasks.allSatisfy(EvalRunPlan.isOwnSet)
        let steps: [(String, String)] = own ? [
            ("1 · The task", "A real bug report and the code as it was before the fix"),
            ("2 · The setup", "Agent: an agent and its model, with our rules or clean. One-shot: a model on its own"),
            ("3 · The check", "Code checks whether the answer names a file the fix changed"),
            ("4 · The score", "Right on N bugs, with the range you can expect on new ones"),
        ] : [
            ("1 · The task", "The benchmark's questions, the same for every setup"),
            ("2 · The setup", "One-shot: a model on its own. Agent: an agent using a model"),
            ("3 · The check", "The benchmark's own marking: exact match, tests or a judge"),
            ("4 · The score", "Right on N questions, with its 95 % range"),
        ]
        return HStack(spacing: 8) {
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.0).ui(TypeScale.caption, .semibold).foregroundStyle(t.text.color)
                    Text(s.1).ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.surface2.color))
                if i < steps.count - 1 { Text("→").ui(TypeScale.small).foregroundStyle(t.text3.color) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How one test works")
    }

    // MARK: 2 · Which setups

    private var agents: [EvalAgentState] { board.doctor?.agents ?? [] }
    private var seatAgents: [EvalAgentState] { agents.filter { EvalAgents.seat($0.id) != nil } }
    private var ownOnly: Bool { !plan.tasks.isEmpty && plan.tasks.allSatisfy(EvalRunPlan.isOwnSet) }

    private var setupsCard: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                EvalsLabel("2 · Which setups")
                Text("One-shot: a model answers once, no tools. Agent: an agent and its model, picked together.")
                    .ui(TypeScale.small).foregroundStyle(t.text2.color)
                Segmented(options: EvalJobKind.allCases.map { ($0, $0.short + count($0)) }, selection: $pick.kind)
                    .accessibilityLabel("Kind of job")
                if pick.kind == .agent { rulesPicker }
                switch layer {
                case .model: modelRows
                case .agentModel, .full: agentRows(full: layer == .full)
                }
                if !ownOnly && layer != .model && !plan.tasks.isEmpty {
                    Text(pick.rules == .withRules
                         ? "Agents on your seats answer your own tasks only; for a public benchmark, pick Clean (no rules) and use an agent on an API key."
                         : "Agents on your seats answer your own tasks only; for a public benchmark, use an agent on an API key below.")
                        .ui(TypeScale.caption).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
                }
                notYet
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Rules for an agent (D4): with our rules (default, the repo's CLAUDE.md / AGENTS.md at HEAD, read-only) or clean.
    private var rulesPicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Rules").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
                Segmented(options: EvalSetupRules.allCases.map { ($0, $0.title + count($0)) }, selection: $pick.rules)
                    .accessibilityLabel("Rules")
            }
            Text(pick.rules == .withRules ? "Our CLAUDE.md and AGENTS.md go into every case, read-only: the agent as we use it."
                 : "No CLAUDE.md or AGENTS.md in the case: the agent out of the box.")
                .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func count(_ k: EvalJobKind) -> String {
        let n = EvalSetupKindChoice.count(choices, kind: k)
        return n > 0 ? " · \(n)" : ""
    }
    private func count(_ r: EvalSetupRules) -> String {
        let n = EvalSetupKindChoice.count(choices, rules: r)
        return n > 0 ? " · \(n)" : ""
    }

    @ViewBuilder private var modelRows: some View {
        let ready = Set(board.doctor?.readyProviders ?? [])
        let api = EvalModels.suggestions.filter { $0.group != "Free" && $0.group != "On this Mac" }.flatMap(\.models)
        let local = (EvalModels.suggestions.first { $0.group == "On this Mac" }?.models ?? []) + ["mockllm/model"]
        let custom = rows.compactMap { $0.choice.agent == nil ? $0.choice.model : nil }.filter { !api.contains($0) && !local.contains($0) }
        let keyed = api.filter { ready.contains(EvalModels.provider($0)) }
        let all = (keyed + custom + local + api.filter { !keyed.contains($0) })
        VStack(alignment: .leading, spacing: 4) {
            ForEach(all, id: \.self) { m in
                let key = EvalModels.isFree(m) || ready.contains(EvalModels.provider(m))
                let c = EvalSetupChoice.model(m)
                let on = rows.contains { $0.on && $0.choice == c }
                checkRow(on: on, enabled: key || on, help: key ? m : "No key yet: roof eval providers set \(EvalModels.provider(m)) --key-file PATH") {
                    toggle(c, !on)
                } label: {
                    Text(c.label).ui(TypeScale.small).foregroundStyle(key ? t.text.color : t.text3.color)
                } trailing: {
                    Text(key ? c.runsOnText : "no key · " + EvalModels.provider(m)).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
            }
            EvalsAnyModelButton { m in toggle(.model(m), true) }
        }
    }

    @ViewBuilder private func agentRows(full: Bool) -> some View {
        let shown = rows.filter { $0.choice.layer == (full ? .full : .agentModel) }
        VStack(alignment: .leading, spacing: 6) {
            if agents.isEmpty { Text("Reading which agents are installed…").ui(TypeScale.small).foregroundStyle(t.text3.color) }
            ForEach(seatAgents) { a in
                let mine = shown.filter { $0.choice.agent == a.id && $0.choice.isSeat }
                ForEach(mine.isEmpty ? [SetupRow(choice: .seat(a.id, rules: full), on: false)] : mine) { r in agentRow(r, state: a, full: full) }
                if a.available {
                    Button { rows.append(SetupRow(choice: .seat(a.id, model: nextModel(a.id, full: full), rules: full), on: true)) } label: {
                        Text("+ \(a.name) with another model").ui(TypeScale.caption).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain).padding(.leading, 22)
                }
            }
            if !full {
                ForEach(shown.filter { !$0.choice.isSeat }) { r in
                    checkRow(on: r.on, enabled: true, help: "An agent on an API model: billed in dollars, in the benchmark's sandbox") {
                        set(r.id, on: !r.on)
                    } label: {
                        Text(r.choice.label).ui(TypeScale.small).foregroundStyle(t.text.color)
                    } trailing: {
                        Text(r.choice.runsOnText).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    }
                }
                apiAgentMenu
            } else {
                Text(rules.map { r in r.files.isEmpty ? "Your rules: no CLAUDE.md or AGENTS.md is tracked in \((r.repo as NSString).lastPathComponent) at HEAD."
                    : "Your rules: \(r.files.count) file\(r.files.count == 1 ? "" : "s") from \((r.repo as NSString).lastPathComponent) at HEAD @ \(r.hash ?? "?"), read-only, the same bytes for every bug." }
                     ?? "Your rules: the repo's CLAUDE.md and AGENTS.md at HEAD, copied into every bug (read-only).")
                    .ui(TypeScale.caption).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    .help(rules?.files.joined(separator: "\n") ?? "")
            }
        }
    }

    private func agentRow(_ r: SetupRow, state a: EvalAgentState, full: Bool) -> some View {
        let enabled = a.available && (ownOnly || plan.tasks.isEmpty)
        return checkRow(on: r.on, enabled: enabled, help: !a.available ? a.why : !enabled ? "Agents on your seats answer your own tasks" : nil) {
            if rows.contains(where: { $0.id == r.id }) { set(r.id, on: !r.on) } else { rows.append(SetupRow(choice: r.choice, on: true)) }
        } label: {
            HStack(spacing: 6) {
                Text(a.name).ui(TypeScale.small, .semibold).foregroundStyle(a.available ? t.text.color : t.text3.color)
                Menu {
                    ForEach(EvalSetupChoice.models(for: a.id), id: \.self) { m in
                        Button(m.map { EvalTaskWords.model($0) } ?? "CLI default (recorded as the model that answered)") { setModel(r, m) }
                    }
                } label: {
                    Text(r.choice.model.map { "using " + EvalTaskWords.model($0) } ?? "on its CLI default model")
                        .ui(TypeScale.small).foregroundStyle(a.available ? t.accentText.color : t.text3.color)
                }
                .menuStyle(.borderlessButton).fixedSize().disabled(!a.available)
                .help("The model the agent's CLI is asked to use (--model). CLI default passes none; the stamp records what answered.")
                if full { Text("· rules on").ui(TypeScale.caption).foregroundStyle(t.text2.color) }
            }
        } trailing: {
            Text(a.available ? seatLine(a) : (a.why ?? "not available")).ui(TypeScale.caption)
                .foregroundStyle(a.available && (a.stale || a.fiveHour == nil) ? t.needsText.color : t.text3.color).lineLimit(1)
        }
    }

    /// "seat C1 · use unknown" or "seat C1 · 9 % used" (the seat's own reading; never a guessed share of this test).
    private func seatLine(_ a: EvalAgentState) -> String {
        guard let s = a.seat ?? EvalAgents.seat(a.id) else { return "" }
        if a.stale || a.fiveHour == nil { return "seat \(s) · use unknown" }
        return "seat \(s) · \(Int((a.fiveHour ?? 0).rounded())) % used"
    }

    private var apiAgentMenu: some View {
        let ready = Set(board.doctor?.readyProviders ?? [])
        let api = EvalModels.suggestions.filter { $0.group != "Free" && $0.group != "On this Mac" }.flatMap(\.models).filter { ready.contains(EvalModels.provider($0)) }
        return Menu {
            ForEach(EvalAgents.onAPI, id: \.self) { ag in
                Menu(EvalAgents.name(ag)) {
                    ForEach(api, id: \.self) { m in Button(EvalTaskWords.model(m)) { toggle(.apiAgent(ag, model: m), true) } }
                }
            }
        } label: { Text("+ an agent on an API key…").ui(TypeScale.caption).foregroundStyle(t.accentText.color) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("The agent's CLI on an API model, run in the benchmark's sandbox; billed per token like a model")
    }

    private var notYet: some View {
        let shownNot = agents.filter { !$0.available && EvalAgents.seat($0.id) == nil }
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(shownNot) { a in
                Text("\(a.name): \(a.why ?? "can't run tests yet")").ui(TypeScale.caption).foregroundStyle(t.text3.color).lineLimit(1)
            }
            let listed = Set(shownNot.map(\.name))
            let rest = ["Kimi", "Gemini CLI", "Antigravity", "OpenCode", "Goose"].filter { !listed.contains($0) }
            if listed.isEmpty {
                Text(EvalSetupChoice.notYetLine).ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
            } else if !rest.isEmpty {
                Text(rest.joined(separator: ", ") + ": can't run tests yet (no verified headless mode).").ui(TypeScale.caption).foregroundStyle(t.text3.color)
            }
        }
    }

    private func nextModel(_ agent: String, full: Bool) -> String? {
        let used = Set(rows.filter { $0.choice.agent == agent && $0.choice.rules == full }.map { $0.choice.model ?? "" })
        return EvalSetupChoice.models(for: agent).compactMap { $0 }.first { !used.contains($0) }
    }

    private func checkRow<L: View, T: View>(on: Bool, enabled: Bool, help: String?, action: @escaping () -> Void,
                                            @ViewBuilder label: () -> L, @ViewBuilder trailing: () -> T) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { if enabled { action() } } label: {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 13)).foregroundStyle(on ? t.accentText.color : t.text3.color)
            }
            .buttonStyle(.plain).disabled(!enabled).accessibilityLabel(on ? "Chosen" : "Not chosen")
            label()
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
        .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(on ? t.accent.color.opacity(0.6) : t.separator.color))
        .opacity(enabled ? 1 : 0.6)
        .help(help ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func toggle(_ c: EvalSetupChoice, _ on: Bool) {
        if let i = rows.firstIndex(where: { $0.choice == c }) { rows[i].on = on } else if on { rows.append(SetupRow(choice: c, on: true)) }
    }
    private func set(_ id: UUID, on: Bool) { if let i = rows.firstIndex(where: { $0.id == id }) { rows[i].on = on } }
    private func setModel(_ r: SetupRow, _ m: String?) {
        var c = r.choice; c.model = m
        if let i = rows.firstIndex(where: { $0.id == r.id }) { rows[i].choice = c; rows[i].on = true } else { rows.append(SetupRow(choice: c, on: true)) }
    }

    // MARK: 3 · How many

    private var howMany: some View {
        let own = ownOnly
        return Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                EvalsLabel("3 · How many")
                HStack(alignment: .top, spacing: 14) {
                    field(own ? "Bugs" : "Questions") { questions }
                    field("Tries each") { TextField("1", text: $epochsText).textFieldStyle(.roundedBorder).focused($typing) }
                    field("Temperature") { TextField("default", text: $temperatureText).textFieldStyle(.roundedBorder).focused($typing) }
                    field("Seed") { TextField("42", text: $seedText).textFieldStyle(.roundedBorder).focused($typing) }
                    field("Stop at, per test") {
                        HStack(spacing: 2) {
                            Text("$").ui(TypeScale.small).foregroundStyle(t.text2.color)
                            TextField("2.00", text: $capText).textFieldStyle(.roundedBorder).focused($typing)
                        }
                    }
                }
                .onChange(of: epochsText) { _, _ in changed() }
                .onChange(of: capText) { _, _ in changed() }
                .onChange(of: seedText) { _, _ in sync() }
                .onChange(of: temperatureText) { _, _ in sync() }
                if sandbox { whereItRuns }
                DisclosureGroup {
                    HStack(spacing: 8) {
                        Text("Task args").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        TextField("name=value,name2=value2", text: $plan.taskArgs).textFieldStyle(.roundedBorder).focused($typing).frame(maxWidth: 360)
                        Text("passed to the benchmark as -T name=value").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    }
                    .padding(.top, 4)
                } label: { Text("Advanced").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                canTell
                if !choices.filter(\.isSeat).isEmpty {
                    Text("Agents on seats ignore temperature and seed (their CLI picks them); the seed is still recorded.")
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color)
                }
            }
        }
    }

    @ViewBuilder private var whereItRuns: some View {
        HStack(spacing: 8) {
            Text("Where its code runs").ui(TypeScale.small, .semibold).foregroundStyle(t.text2.color)
            Segmented(options: EvalDoctor.placeOrder.map { ($0, EvalDoctor.placeTitle($0) + (placeReady($0) ? "" : " · not set up")) },
                      selection: $plan.place)
                .onChange(of: plan.place) { _, _ in changed() }
        }
        if !placeReady(plan.place) {
            Text(plan.place == "modal" ? "Sign in once in a terminal: python3 -m modal setup"
                 : plan.place == "local" ? "Start Docker first." : "Add a key file: roof eval providers set \(plan.place) --key-file PATH")
                .ui(TypeScale.caption).foregroundStyle(t.needsText.color)
        }
        Text("Cloud sandboxes bill per second of sandbox time; the estimate includes it (1 vCPU + 2 GiB, prices checked 2026-10-31).")
            .ui(TypeScale.caption).foregroundStyle(t.text3.color)
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ui(TypeScale.small).foregroundStyle(t.text2.color)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var questions: some View {
        if let n = totalQuestions, n <= 200, n > 5 {
            Segmented(options: [(5, "5"), (n, "all \(n)")], selection: Binding(get: { plan.limit >= n ? n : 5 }, set: { plan.limit = $0; changed() }))
        } else {
            Stepper("\(plan.limit)", value: Binding(get: { plan.limit }, set: { plan.limit = $0; changed() }), in: 1...5000, step: plan.limit < 20 ? 1 : 10)
                .ui(TypeScale.small)
        }
    }

    /// What this test can tell you (`power`; mirrored for an instant redraw), before the cost.
    private var canTell: some View {
        let p = power ?? EvalPower.mirror(n: plan.limit, epochs: Int(epochsText) ?? 1)
        return (Text("What this test can tell you: ").bold() + Text(EvalCanTell.line(p, own: ownOnly, setups: choices.count)))
            .ui(TypeScale.body).foregroundStyle(t.accentText.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.accent.color.opacity(0.14)))
            .accessibilityLabel("What this test can tell you")
            .evalHover(.canTell, EvalHover.canTell(points: p.plusMinusPoints))
    }

    // MARK: Before you start

    private var beforeYouStart: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Before you start").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                if choices.isEmpty || plan.tasks.isEmpty {
                    Text("Pick a task and a setup: what each costs shows here before anything starts.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                }
                ForEach(costLines, id: \.id) { l in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(l.who).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(2)
                            Spacer(minLength: 6)
                            Text(l.cost).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(l.red ? t.needsText.color : t.text.color)
                        }
                        if let n = l.note { Text(n).ui(TypeScale.micro).foregroundStyle(l.red ? t.needsText.color : t.text3.color).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.vertical, 5)
                    .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                }
                HStack {
                    Text("API cost").ui(TypeScale.body).foregroundStyle(t.text.color)
                    Spacer()
                    Text(total.map { String(format: "$%.2f", $0) } ?? "…").ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color)
                        .evalHover(.cost, "API cost: the engine's estimate from the provider's prices and this Mac's earlier answers. Agents on seats cost no API credit.")
                }
                Text(String(format: "Each test stops at $%.2f (the grader counted ×1.5). Prices from OpenRouter's list; answer length from this Mac's earlier tests.", plan.cap))
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                if let w = seatWarning {
                    w.ui(TypeScale.small).fixedSize(horizontal: false, vertical: true)
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.needsText.color.opacity(0.12)))
                }
                if let u = unrecorded, u == choices {
                    Text(EvalRunPlan.notRecordedNote).ui(TypeScale.small, .semibold).foregroundStyle(t.needsText.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.needsText.color.opacity(0.12)))
                }
                if !choices.isEmpty { stampBox }
                Button(action: start) {
                    Text("Start \(testCount) test\(testCount == 1 ? "" : "s")").ui(TypeScale.body, .semibold)
                        .foregroundStyle(t.onAccent.color).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.accent.color))
                }
                .buttonStyle(.plain)
                .disabled(startReason != nil || board.busy != nil)
                .opacity(startReason != nil ? 0.4 : 1)
                .accessibilityLabel("Start \(testCount) tests")
                if let r = startReason { Text(r).ui(TypeScale.small).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true) }
                else { Text("Two at a time, in the background. Closing One Roof doesn't stop them.").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
                if choices.contains(where: \.isSeat) {
                    Text("Agents work in a fresh worktree per bug, at the commit before the fix, with read-only tools. Nothing is pushed."
                         + (choices.contains { $0.agent == "codex_cli" && $0.isSeat } ? " Codex can still read files outside the bug's folder: its read-only sandbox blocks writes, not reads." : ""))
                        .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var stampBox: some View {
        let version = plan.tasks.compactMap { task in board.sets.first { $0.taskFile == task }?.version }.first
        return VStack(alignment: .leading, spacing: 4) {
            Text("Recorded with each result").ui(TypeScale.caption, .semibold).foregroundStyle(t.text.color)
            ForEach(choices) { c in
                Text(c.stampPreview(taskVersion: version, rulesHash: rules?.hash, rulesFiles: c.rules ? rules?.files ?? [] : []))
                    .ui(TypeScale.micro).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            if plan.repeatRulesHash != nil, choices.contains(where: \.rules) {   // review P2 #6: a rules-on repeat
                Text(EvalSetupChoice.repeatRulesNote(old: plan.repeatRulesHash, now: rules?.hash))
                    .ui(TypeScale.micro, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            }
            Text("This is what lets Changes compare before and after.").ui(TypeScale.micro).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.diffAddFill.color))
    }

    private struct CostLine { var id: String; var who: String; var cost: String; var red: Bool; var note: String? }

    private var costLines: [CostLine] {
        var out: [CostLine] = []
        for c in choices { for task in plan.tasks {
            let k = "\(task)|\(c.id)"
            let who = c.label + (plan.tasks.count > 1 ? " · " + taskName(task) : "")
            if let e = estimates[k] {
                if e.isSeat {
                    let x = extras[k]
                    let share = x?.measuredShare.map { "≈ \(max(Int(($0 * 100).rounded()), 1)) % of \(e.seat ?? "")'s 5 h" }
                    out.append(CostLine(id: k, who: who, cost: share ?? "seat \(e.seat ?? "")", red: e.seatFits == false,
                                        note: e.seatFits == false ? "\(e.seat ?? "") would pass its \(Int(e.seatLimit ?? 90)) % limit" : x?.seatNote ?? "No API cost; its share of the seat is not measured yet."))
                } else {
                    let over = (e.capCheckUSD ?? e.usd ?? 0) > plan.cap
                    out.append(CostLine(id: k, who: who, cost: e.usd.map { String(format: "$%.3f", $0) } ?? "?", red: over || e.usd == nil,
                                        note: e.usd == nil ? (e.note ?? "price unknown") : over ? "over Stop at" : "\(e.calls) calls"))
                }
            } else {
                out.append(CostLine(id: k, who: who, cost: estimateErrors[k] == nil ? "…" : "–", red: estimateErrors[k] != nil, note: estimateErrors[k]))
            }
        } }
        return out
    }

    private var total: Double? {
        let paid = choices.filter { !$0.isSeat }.flatMap { c in plan.tasks.map { "\($0)|\(c.id)" } }
        let vals = paid.compactMap { estimates[$0]?.usd }
        return vals.count == paid.count ? vals.reduce(0, +) : nil
    }

    /// QA (M9): unknown seat use never passes silently.
    private var seatWarning: Text? {
        let seats = Set(choices.compactMap(\.seat))
        let unknown = seats.filter { s in agents.first { ($0.seat ?? EvalAgents.seat($0.id)) == s }.map { $0.stale || $0.fiveHour == nil } ?? true }.sorted()
        guard !unknown.isEmpty else { return nil }
        let who = unknown.joined(separator: " and ")
        return Text("\(who)'s use is unknown. ").bold().foregroundColor(t.needsText.color)
            + Text("The test will wait until One Roof can see room under 90 %, or until you press Run anyway. A test that waits this way stops after 6 hours.")
                .foregroundColor(t.text.color)
    }

    // MARK: State

    private var catalog: [EvalBenchmark] { board.catalog?.benchmarks ?? [] }
    private func taskName(_ task: String) -> String {
        if let s = board.sets.first(where: { $0.taskFile == task }) { return EvalTaskWords.title(kind: s.kind) }
        return EvalBenchmark.taskLabel(task)
    }
    private var totalQuestions: Int? {
        guard plan.tasks.count == 1, let task = plan.tasks.first else { return nil }
        if let s = board.sets.first(where: { $0.taskFile == task }) { return s.count }
        if let j = board.judges.first(where: { $0.taskFile == task }) { return j.items }
        return catalog.lazy.flatMap(\.tasks).first { $0.name == task }?.samples
    }
    private var sandbox: Bool {
        plan.benchmark?.sandbox == true || plan.tasks.contains { t in catalog.contains { $0.sandbox && $0.tasks.contains { $0.name == t } } }
    }
    private func placeReady(_ p: String) -> Bool { board.doctor?.places[p] ?? (p == "local") }

    private var startReason: String? {
        if let g = EvalGate.startReason(tasks: plan.tasks, folderOf: { t in catalog.first { $0.tasks.contains { $0.name == t } }?.folder },
                                        signedIn: hf.signedIn, accepted: hf.accepted) { return g }
        let missing = EvalSetupCheck.missingKeys(choices, ready: Set(board.doctor?.readyProviders ?? []))
        let blocked: String? = sandbox && !placeReady(plan.place)
            ? (plan.place == "local" ? "Docker is stopped: start Docker first" : "\(EvalDoctor.placeTitle(plan.place)) is not set up") : nil
        let full = Array(Set(estimates.values.filter { $0.isSeat && $0.seatFits == false }.compactMap(\.seat))).sorted()
        let over = estimates.values.contains { !$0.isSeat && ($0.capCheckUSD ?? $0.usd ?? 0) > plan.cap }
        return EvalSetupCheck.reason(tasks: plan.tasks, choices: choices, isOwn: EvalRunPlan.isOwnSet, missingKeys: missing,
                                     sandboxBlocked: blocked, fullSeats: full, overCap: over)
    }

    /// ↩ starts when valid, never while a field is being typed in.
    @ViewBuilder private var startKey: some View {
        if !typing && startReason == nil {
            Button("") { start() }.keyboardShortcut(.defaultAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    private func adopt(_ p: EvalRunPlan?) {
        if let p {
            plan = p
            rows = EvalSetupChoice.from(p).map { SetupRow(choice: $0, on: true) }
            unrecorded = p.notRecorded ? EvalSetupChoice.from(p) : nil
            if let o = EvalSetupKindChoice.opening(rows.map(\.choice)) { pick = o }   // agents → Agent (+ their rules); models → One-shot
            nav.draft = nil
        } else if let kept = nav.workPlan {
            plan = kept
            rows = Self.keptRows ?? EvalSetupChoice.from(kept).map { SetupRow(choice: $0, on: true) }
            if let o = EvalSetupKindChoice.opening(rows.filter(\.on).map(\.choice)) { pick = o }
        } else if plan.tasks.isEmpty {
            let first = board.sets.first
            plan = EvalRunPlan(tasks: [first?.taskFile ?? "gsm8k"], models: [], limit: first?.count ?? 5, cap: 2)
            rows = Self.keptRows ?? []
        }
        if rows.isEmpty {   // QA m4: a valid default, never "Start 0 tests"
            let d = EvalSetupKindChoice.defaults(task: plan.tasks.first, seatAgents: seatAgents.filter(\.available).map(\.id))
            rows = d.choices.map { SetupRow(choice: $0, on: true) }
            pick = d.choice
        }
        epochsText = plan.epochs.map(String.init) ?? ""
        temperatureText = plan.temperature.map { String($0) } ?? ""
        seedText = plan.seed.map(String.init) ?? ""
        capText = String(format: "%.2f", plan.cap)
        changed()
    }

    private func sync() {
        plan.epochs = Int(epochsText)
        plan.temperature = Double(temperatureText)
        plan.seed = seedText.isEmpty ? nil : Int(seedText)
        plan.cap = Double(capText.replacingOccurrences(of: "$", with: "")) ?? plan.cap
        // The 2.0.3 plan fields follow the setups (nav.workPlan, Test again, the self-test pre-fill).
        let cs = choices
        plan.agents = cs.filter(\.isSeat).compactMap(\.agent)
        plan.apiAgents = cs.filter { $0.agent != nil && !$0.isSeat }.compactMap { c in c.model.map { (c.agent ?? "") + "@" + $0 } }
        plan.models = cs.filter { $0.agent == nil }.compactMap(\.model)
        plan.setups = cs   // the exact setups (seat model, rules) travel with the plan (nav.workPlan, Test again)
    }

    /// Any change re-estimates, debounced 300 ms; the rules hash is read for the task's repo.
    private func changed() {
        sync()
        power = nil
        pending?.cancel()
        let snapshot = plan, cs = choices
        let w = DispatchWorkItem { estimate(snapshot, cs) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
        readRules()
    }

    private func estimate(_ p: EvalRunPlan, _ cs: [EvalSetupChoice]) {
        let keys = Set(p.tasks.flatMap { t in cs.map { "\(t)|\($0.id)" } })
        estimates = estimates.filter { keys.contains($0.key) }
        extras = extras.filter { keys.contains($0.key) }
        estimateErrors = estimateErrors.filter { keys.contains($0.key) }
        let seatLimit = RoutingPolicy.load().skipFiveHour
        for task in p.tasks { for c in cs {
            let k = "\(task)|\(c.id)"
            let args = c.estimateArguments(task: task, plan: p, seatLimit: seatLimit)
            board.estimate(args) { r in
                guard plan.tasks.contains(task) else { return }
                switch r {
                case .success(let e): estimates[k] = e; estimateErrors[k] = nil
                case .failure(let err): estimates[k] = nil; estimateErrors[k] = err.message
                }
            }
            if c.isSeat {
                board.ask(Array(args.dropLast()), EvalSetupEstimate.self, timeout: 120) { if case .success(let x) = $0 { extras[k] = x } }
            }
        } }
        board.ask(["power", "--n", String(p.limit), "--epochs", String(p.epochs ?? 1)], EvalPower.self) { r in
            if case .success(let pw) = r, pw.n == plan.limit { power = pw }
        }
    }

    /// The rules hash the stamp will record (CONTRACT §1: the instruction files tracked at HEAD, in path order).
    private func readRules() {
        guard let repo = plan.tasks.compactMap({ task in board.sets.first { $0.taskFile == task }?.repoPath }).first else { rules = nil; return }
        if rules?.repo == repo { return }
        DispatchQueue.global(qos: .utility).async {
            let files = EvalRulesHash.files(lsTree: Self.git(repo, ["ls-tree", "-r", "--name-only", "HEAD"]).map { String(decoding: $0, as: UTF8.self) } ?? "")
            let blobs = files.compactMap { Self.git(repo, ["show", "HEAD:" + $0]) }
            let hash = EvalRulesHash.short(blobs)
            DispatchQueue.main.async { rules = (repo, hash, files) }
        }
    }

    private static func git(_ repo: String, _ args: [String]) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", repo] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let d = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return p.terminationStatus == 0 ? d : nil
    }

    private func start() {
        sync()
        guard startReason == nil else { return }
        board.startSetups(plan, choices: choices, seatLimit: RoutingPolicy.load().skipFiveHour)
    }
}

// MARK: - Starting setups (CONTRACT §2), the 2.0.3 board.start with the setup's own arguments

extension EvalsBoard {
    func startSetups(_ plan: EvalRunPlan, choices: [EvalSetupChoice], seatLimit: Double = 90) {
        let n = plan.tasks.count * choices.count
        busy = "Starting \(n) test\(n == 1 ? "" : "s")…"
        io.async {
            var errors: [String] = []
            for task in plan.tasks { for c in choices {
                let a = c.runArguments(task: task, plan: plan, seatLimit: seatLimit)
                if case .failure(let e) = EvalEngine.decode(Started.self, EvalEngine.run(a, timeout: 300)) {
                    errors.append("\(EvalBenchmark.taskLabel(task)) × \(c.label): \(e.message)")
                }
            } }
            DispatchQueue.main.async {
                self.busy = nil
                self.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
                self.tab = .runs
                self.refreshRuns()
                self.started += 1
            }
        }
    }
}

// MARK: - 1 · Which task

struct EvalsTaskPicker: View {
    @ObservedObject var board: EvalsBoard
    @Binding var plan: EvalRunPlan
    var changed: () -> Void
    @Environment(\.theme) private var t
    @State private var picking = false
    @State private var search = ""

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                EvalsLabel("1 · Which task").padding(.bottom, 4)
                ForEach(board.sets) { s in row(s.taskFile, EvalTaskWords.title(kind: s.kind), "v\(s.version) · \(s.repo)", s.count, unit: "bugs") }
                ForEach(board.judges.filter { $0.taskFile != nil }) { j in row(j.taskFile!, "The grader for \(j.name.replacingOccurrences(of: "_", with: " "))", "measures the grader", j.items, unit: "notes") }
                ForEach(benchmarks, id: \.self) { task in row(task, EvalBenchmark.taskLabel(task), "public benchmark", questions(task), unit: "") }
                if let b = plan.benchmark, b.tasks.count > 1 {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tasks in \(b.shortName)").ui(TypeScale.caption, .semibold).foregroundStyle(t.text3.color)
                        ForEach(b.tasks, id: \.name) { task in
                            Toggle(isOn: Binding(get: { plan.tasks.contains(task.name) }, set: { set(task.name, $0) })) {
                                Text(task.name + (task.samples.map { " · \($0)" } ?? "")).ui(TypeScale.small, mono: true)
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                    .padding(.leading, 18)
                }
                Button { picking = true } label: { Text("+ a public benchmark…").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).padding(.top, 4)
                    .popover(isPresented: $picking, arrowEdge: .bottom) { picker }
                ForEach(sources, id: \.folder) { s in EvalsSourceLine(source: s).padding(.top, 4) }   // LAB-2117
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sources: [EvalDataSource] {
        let cat = board.catalog?.benchmarks ?? []
        var seen = Set<String>()
        return plan.tasks.compactMap { t in cat.first { $0.tasks.contains { $0.name == t } } }
            .filter { seen.insert($0.folder).inserted }
            .compactMap { EvalSources.source(folder: $0.folder) }
    }

    /// Recently run benchmarks first, then whatever the plan was pre-filled with.
    private var benchmarks: [String] {
        var seen = Set<String>(), out: [String] = []
        let own = Set(board.sets.map(\.taskFile) + board.judges.compactMap(\.taskFile))
        for task in plan.tasks where !own.contains(task) && seen.insert(task).inserted { out.append(task) }
        for r in board.results.sorted(by: { ($0.started ?? "") > ($1.started ?? "") }) {
            guard let task = r.task, r.setName == nil, !task.hasPrefix("judge_"), !task.hasPrefix("labeller_"), !task.hasPrefix("own_"),
                  !task.hasPrefix("lm-eval"), out.count < 3 else { continue }
            if seen.insert(task).inserted { out.append(task) }
        }
        return out
    }

    private func questions(_ task: String) -> Int? {
        (board.catalog?.benchmarks ?? []).lazy.flatMap(\.tasks).first { $0.name == task }?.samples
    }

    private func row(_ task: String, _ title: String, _ sub: String, _ n: Int?, unit: String) -> some View {
        let on = plan.tasks.contains(task)
        return Button { set(task, !on) } label: {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 13)).foregroundStyle(on ? t.accentText.color : t.text3.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).ui(TypeScale.small, on ? .semibold : .regular).foregroundStyle(t.text.color).lineLimit(2).truncationMode(.middle)
                    Text(sub).ui(TypeScale.micro).foregroundStyle(t.text3.color).lineLimit(1)
                }
                Spacer(minLength: 6)
                if let n { Text("\(n)" + (unit.isEmpty ? "" : " " + unit)).ui(TypeScale.caption, mono: true).foregroundStyle(t.text2.color) }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
            .overlay(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).strokeBorder(on ? t.accent.color.opacity(0.6) : t.separator.color))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title + (on ? ", chosen" : ""))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func set(_ task: String, _ on: Bool) {
        plan.tasks = on ? plan.tasks + [task] : plan.tasks.filter { $0 != task }
        if on, plan.tasks.count == 1 {
            if let s = board.sets.first(where: { $0.taskFile == task }) { plan.limit = s.count }
            else if let j = board.judges.first(where: { $0.taskFile == task }) { plan.limit = j.items }
        }
        changed()
    }

    private var picker: some View {
        let all = (board.catalog?.benchmarks ?? []).filter { !$0.isOwn }
        let shown = EvalExploreFilter(search: search).apply(all).prefix(40)
        return VStack(alignment: .leading, spacing: 6) {
            TextField("Search benchmarks", text: $search).textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(shown)) { b in
                        Button {
                            plan.benchmark = b.tasks.count > 1 ? b : plan.benchmark
                            set(b.defaultTask, true)
                            picking = false
                        } label: {
                            HStack {
                                Text(b.shortName).ui(TypeScale.small).foregroundStyle(t.text.color)
                                Spacer()
                                Text(b.category).ui(TypeScale.caption).foregroundStyle(t.text3.color)
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(height: 260)
        }
        .padding(12).frame(width: 320)
    }
}

/// "+ any model id…": a model id typed in (fireworks/…, together/…, a local server's model).
struct EvalsAnyModelButton: View {
    var add: (String) -> Void
    @Environment(\.theme) private var t
    @State private var adding = false
    @State private var custom = ""
    var body: some View {
        Button { adding = true } label: { Text("+ any model id…").ui(TypeScale.caption).foregroundStyle(t.accentText.color) }
            .buttonStyle(.plain)
            .popover(isPresented: $adding, arrowEdge: .bottom) {
                HStack {
                    TextField("any model, e.g. fireworks/accounts/fireworks/models/…", text: $custom).textFieldStyle(.roundedBorder)
                        .frame(width: 320).onSubmit(commit)
                    RoofButton("Add", .primary, action: commit)
                }
                .padding(12)
            }
    }
    private func commit() {
        let m = custom.trimmingCharacters(in: .whitespaces)
        if m.contains("/") { add(m) }
        custom = ""; adding = false
    }
}

// MARK: - Running and recent (the queue's only home)

struct EvalsQueueTable: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var all = false
    @State private var expired: [String: String] = [:]

    private struct Lite: Decodable { var id: String; var status: String?; var expiredReason: String? }

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Running and recent").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Text("two at a time").ui(TypeScale.small).foregroundStyle(t.text2.color)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                if board.runs.isEmpty {
                    Text("No tests yet. Pick a task and setups above; what it can tell you and the cost show before anything starts.")
                        .ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                }
                ForEach(shown) { r in row(r) }
                if board.runs.count > shown.count || all {
                    Button { all.toggle() } label: {
                        Text(all ? "Show fewer" : "Show all \(board.runs.count) ›").ui(TypeScale.small).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain).padding(14)
                }
            }
        }
        .onAppear(perform: readExpired)
        .onChange(of: board.runs) { _, _ in readExpired() }
    }

    /// LAB-2237: a seat test that waited 6 h with its use unknown is "expired"; its reason comes from `status`.
    private func readExpired() {
        guard board.runs.contains(where: { $0.status == "expired" }) else { return }
        board.ask(["status"], [Lite].self, timeout: 60) { r in
            if case .success(let rows) = r { expired = Dictionary(rows.compactMap { l in l.expiredReason.map { (l.id, $0) } }, uniquingKeysWith: { a, _ in a }) }
        }
    }

    /// Going now first, then the newest finished ones.
    private var shown: [EvalRunRow] {
        let active = board.runs.filter(\.isActive)
        let rest = board.runs.filter { !$0.isActive }
        return all ? active + rest : active + rest.prefix(max(0, 8 - active.count))
    }

    private func name(_ r: EvalRunRow) -> String {
        let task = board.sets.first { EvalTaskCoverage.matches(task: r.task, setName: r.setName, setVersion: r.setVersion, name: $0.name, version: r.setVersion ?? $0.version) }
            .map { EvalTaskWords.title(kind: $0.kind) } ?? EvalBenchmark.taskLabel(r.task ?? "?")
        return "\(task) · \(r.contestant.map { EvalTaskWords.contestant($0.name) } ?? EvalModels.short(r.model ?? "?"))"
    }

    private func row(_ r: EvalRunRow) -> some View {
        HStack(spacing: 12) {
            Button { nav.openRun(r.id) } label: {
                Text(name(r)).ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).help("Open this test, bug by bug")
            status(r).frame(width: 240, alignment: .leading)
            Text(r.progress).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color).frame(width: 70, alignment: .trailing)
            HStack(spacing: 6) {
                if r.waitsForUnknownSeat {
                    RoofButton("Run anyway", .plain) { board.runAnyway(r.id) }
                        .help("Go on without knowing how much of \(r.seat ?? "the seat")'s 5-hour window is used (recorded in this test)")
                }
                if r.isActive { RoofButton("Cancel", .plain) { board.cancel(r.id) } }
                if r.canResume || r.status == "expired" { RoofButton("Resume", .plain) { board.resume(r.id) } }
                if r.status == "done" { RoofButton("Results", .plain) { nav.openRun(r.id) } }
            }
            .frame(width: 210, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(name(r)) \(r.status ?? "") \(r.progress)")
    }

    @ViewBuilder private func status(_ r: EvalRunRow) -> some View {
        if r.status == "running", let f = r.fraction {
            ProgressView(value: f).tint(t.accent.color)
        } else if r.status == "waiting" {
            Text(r.waitsForUnknownSeat ? "waiting: \(r.seat ?? "seat") use unknown" : (r.waiting ?? "waiting for a seat"))
                .ui(TypeScale.small).foregroundStyle(t.needsText.color).lineLimit(2).help(r.waiting ?? "")
        } else if r.status == "expired" {
            Text("expired: " + (expired[r.id] ?? "waited 6 h without knowing the seat's use")).ui(TypeScale.small).foregroundStyle(t.needsText.color)
                .lineLimit(2).help("Resume puts it back in the queue")
        } else if r.status == "failed" {
            Text("failed: " + (r.error ?? "see the test")).ui(TypeScale.small).foregroundStyle(t.needsText.color).lineLimit(2)
                .help([r.error, r.hint.map { "What to do: " + $0 }].compactMap { $0 }.joined(separator: "\n"))
        } else {
            Text(r.status ?? "").ui(TypeScale.small).foregroundStyle(r.status == "done" ? t.diffAddText.color : t.text2.color)
        }
    }
}
