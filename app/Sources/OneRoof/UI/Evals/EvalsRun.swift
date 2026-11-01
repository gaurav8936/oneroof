import AppKit
import SwiftUI
import OneRoofCore

/// LAB-2067 · Run (Claude Design 1A-5 = HP E3.1): 1 What × 2 Who × 3 How much, "what this run can tell you", the cost
/// before you start per contestant (agents: a share of the seat's 5-hour window; models: dollars), Start N runs, and the
/// queue at the foot. Replaces 1.9.37's run sheet and Runs tab; their estimate, cap check (grader × 1.5, in the engine)
/// and every field are kept (NO_REGRESSION).
struct EvalsRunTab: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var plan = EvalRunPlan(tasks: [])
    @State private var estimates: [String: EvalEstimate] = [:]
    @State private var estimateErrors: [String: String] = [:]
    @State private var power: EvalPower?
    @State private var pending: DispatchWorkItem?
    @State private var epochsText = ""
    @State private var temperatureText = ""
    @State private var seedText = "42"
    @State private var capText = "2.00"
    @State private var started = false
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            EvalsColumns(breakpoint: 1060, side: 340) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 14) {
                        EvalsRunWhat(board: board, plan: $plan, changed: changed).frame(width: 270)
                        EvalsRunWho(board: board, plan: $plan, changed: changed)
                    }
                    howMuch
                    EvalsQueue(board: board, nav: nav)
                }
            } aside: {
                EvalsCostPanel(board: board, plan: plan, estimates: estimates, errors: estimateErrors, startReason: startReason,
                               start: start)
            }
            .frame(maxWidth: 1560, alignment: .topLeading)
        }
        .background(startKey)
        .onAppear { adopt(nav.draft); board.refreshDoctor() }
        .onChange(of: nav.draft) { _, p in adopt(p) }
        .onChange(of: plan) { _, p in nav.workPlan = p }
    }

    // MARK: 3 · How much

    private var howMuch: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                EvalsLabel("3 · How much")
                HStack(alignment: .top, spacing: 14) {
                    field("Questions") { questions }
                    field("Attempts each") { TextField("1", text: $epochsText).textFieldStyle(.roundedBorder).focused($typing) }
                    field("Temperature") { TextField("default", text: $temperatureText).textFieldStyle(.roundedBorder).focused($typing) }
                    field("Seed") { TextField("42", text: $seedText).textFieldStyle(.roundedBorder).focused($typing) }
                    field("Cap per run") {
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
                if sandbox {
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
                DisclosureGroup {
                    HStack(spacing: 8) {
                        Text("Task args").ui(TypeScale.small).foregroundStyle(t.text2.color)
                        TextField("name=value,name2=value2", text: $plan.taskArgs).textFieldStyle(.roundedBorder).focused($typing).frame(maxWidth: 360)
                        Text("passed to the benchmark as -T name=value").ui(TypeScale.caption).foregroundStyle(t.text3.color)
                    }
                    .padding(.top, 4)
                } label: { Text("••• Advanced").ui(TypeScale.small).foregroundStyle(t.text2.color) }
                canTell
            }
        }
    }

    private func field<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).ui(TypeScale.small).foregroundStyle(t.text2.color)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 5 · All N for a set or a small benchmark; a stepper for big ones or several tasks.
    @ViewBuilder private var questions: some View {
        if let n = totalQuestions, n <= 200, n > 5 {
            Segmented(options: [(5, "5"), (n, "All \(n)")], selection: Binding(get: { plan.limit >= n ? n : 5 },
                                                                            set: { plan.limit = $0; changed() }))
        } else {
            Stepper("\(plan.limit)", value: Binding(get: { plan.limit }, set: { plan.limit = $0; changed() }), in: 1...5000,
                    step: plan.limit < 20 ? 1 : 10)
                .ui(TypeScale.small)
        }
    }

    /// HP CanTellNote: the ± points this run can tell apart (the engine's `power`, mirrored here for an instant redraw).
    private var canTell: some View {
        let p = power ?? EvalPower.mirror(n: plan.limit, epochs: Int(epochsText) ?? 1)
        let own = plan.tasks.allSatisfy(EvalRunPlan.isOwnSet)
        return (Text("What this run can tell you: ").bold() + Text(p.sentence(own: own && !plan.tasks.isEmpty, contestants: plan.contestants.count)))
            .ui(TypeScale.body).foregroundStyle(t.accentText.color)
            .fixedSize(horizontal: false, vertical: true)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(t.accent.color.opacity(0.14)))
            .accessibilityLabel("What this run can tell you")
            .evalHover(.canTell, EvalHover.canTell(points: p.plusMinusPoints))
    }

    // MARK: State

    private var catalog: [EvalBenchmark] { board.catalog?.benchmarks ?? [] }
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

    private var missingKeys: [String] {
        let ready = Set(board.doctor?.readyProviders ?? [])
        let models = plan.models + plan.apiAgents.compactMap { $0.split(separator: "@", maxSplits: 1).last.map(String.init) }
        return Array(Set(models.filter { !EvalModels.isFree($0) }.map(EvalModels.provider).filter { !ready.contains($0) })).sorted()
    }
    private var overCap: Bool {
        estimates.values.contains { !$0.isSeat && ($0.capCheckUSD ?? $0.usd ?? 0) > plan.cap }
    }
    private var fullSeats: [String] {
        Array(Set(estimates.values.filter { $0.isSeat && $0.seatFits == false }.compactMap(\.seat))).sorted()
    }
    private var startReason: String? {
        EvalStartCheck.reason(plan: plan, overCap: overCap, missingKeys: missingKeys, sandbox: sandbox,
                              placeReady: placeReady(plan.place), place: plan.place, fullSeats: fullSeats)
    }

    /// ↩ starts when the cost panel is valid, never while a field is being typed in (HP E3).
    @ViewBuilder private var startKey: some View {
        if !typing && startReason == nil {
            Button("") { start() }.keyboardShortcut(.defaultAction).opacity(0).frame(width: 0, height: 0).accessibilityHidden(true)
        }
    }

    private func adopt(_ p: EvalRunPlan?) {
        if let p {
            plan = p
            nav.draft = nil
        } else if let kept = nav.workPlan {
            plan = kept
        } else if plan.tasks.isEmpty {
            let first = board.sets.first
            plan = EvalRunPlan(tasks: [first?.taskFile ?? "gsm8k"], models: ["mockllm/model"], limit: first?.count ?? 5, cap: 2)
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
    }

    /// Any toggle re-estimates, debounced 300 ms (HP E3 interactions).
    private func changed() {
        sync()
        power = nil
        pending?.cancel()
        let snapshot = plan
        let w = DispatchWorkItem { estimate(snapshot) }
        pending = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: w)
    }

    private func estimate(_ p: EvalRunPlan) {
        let keys = Set(p.tasks.flatMap { t in p.contestants.map { "\(t)|\($0.key)" } })
        estimates = estimates.filter { keys.contains($0.key) }
        estimateErrors = estimateErrors.filter { keys.contains($0.key) }
        for task in p.tasks { for c in p.contestants {
            let k = "\(task)|\(c.key)"
            board.estimate(p.estimateArguments(task: task, contestant: c)) { r in
                guard plan.tasks.contains(task) else { return }
                switch r {
                case .success(let e): estimates[k] = e; estimateErrors[k] = nil
                case .failure(let err): estimates[k] = nil; estimateErrors[k] = err.message
                }
            }
        } }
        board.ask(["power", "--n", String(p.limit), "--epochs", String(p.epochs ?? 1)], EvalPower.self) { r in
            if case .success(let pw) = r, pw.n == plan.limit { power = pw }
        }
    }

    private func start() {
        sync()
        guard startReason == nil else { return }
        board.start(plan, seatLimit: RoutingPolicy.load().skipFiveHour)
    }
}

// MARK: - 1 · What

struct EvalsRunWhat: View {
    @ObservedObject var board: EvalsBoard
    @Binding var plan: EvalRunPlan
    var changed: () -> Void
    @Environment(\.theme) private var t
    @State private var picking = false
    @State private var search = ""

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                EvalsLabel("1 · What").padding(.bottom, 4)
                ForEach(board.sets) { s in row(s.taskFile, "\(s.title) v\(s.version)", s.count) }
                ForEach(board.judges.filter { $0.taskFile != nil }) { j in row(j.taskFile!, "\(j.name) · judge", j.items) }
                ForEach(benchmarks, id: \.self) { task in row(task, EvalBenchmark.taskLabel(task), questions(task)) }
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
                Button { picking = true } label: { Text("+ any benchmark…").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).padding(.top, 4)
                    .popover(isPresented: $picking, arrowEdge: .bottom) { picker }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Recently run benchmarks first, then whatever the plan was pre-filled with (Explore's Run this…).
    private var benchmarks: [String] {
        var seen = Set<String>(), out: [String] = []
        let own = Set(board.sets.map(\.taskFile) + board.judges.compactMap(\.taskFile))
        for task in plan.tasks where !own.contains(task) && seen.insert(task).inserted { out.append(task) }
        for r in board.results.sorted(by: { ($0.started ?? "") > ($1.started ?? "") }) {
            guard let task = r.task, r.setName == nil, !task.hasPrefix("judge_"), !task.hasPrefix("labeller_"),
                  !task.hasPrefix("lm-eval"), out.count < 3 else { continue }
            if seen.insert(task).inserted { out.append(task) }
        }
        return out
    }

    private func questions(_ task: String) -> Int? {
        (board.catalog?.benchmarks ?? []).lazy.flatMap(\.tasks).first { $0.name == task }?.samples
    }

    private func row(_ task: String, _ title: String, _ n: Int?) -> some View {
        let on = plan.tasks.contains(task)
        return Button { set(task, !on) } label: {
            HStack(spacing: 8) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 13)).foregroundStyle(on ? t.accentText.color : t.text3.color)
                Text(title).ui(TypeScale.body, on ? .semibold : .regular).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 6)
                if let n { Text("\(n)").ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color) }
            }
            .padding(.vertical, 6).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(on ? t.selection.color : .clear))
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

// MARK: - 2 · Who

struct EvalsRunWho: View {
    @ObservedObject var board: EvalsBoard
    @Binding var plan: EvalRunPlan
    var changed: () -> Void
    @Environment(\.theme) private var t
    @State private var custom = ""
    @State private var adding = false
    @State private var showAll = false

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    EvalsLabel("2 · Who")
                    Text("An agent is a model plus its harness: tools, file access, retries. Run both to see what the harness adds.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 16) {
                    column("Agents · your seats") { agents }
                    column("Models · API") { models }
                    column("On this Mac · free") { local }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func column<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).ui(TypeScale.body, .semibold).foregroundStyle(t.text.color)
            c()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder private var agents: some View {
        let states = board.doctor?.agents ?? []
        if states.isEmpty { Text("Reading…").ui(TypeScale.small).foregroundStyle(t.text3.color) }
        ForEach(states) { a in
            let ownOnly = !plan.tasks.isEmpty && !plan.tasks.allSatisfy(EvalRunPlan.isOwnSet)
            check(on: plan.agents.contains(a.id), enabled: a.available, help: ownOnly && a.available ? "Agents on your seats answer your own sets" : a.why,
                  set: { on in plan.agents = on ? plan.agents + [a.id] : plan.agents.filter { $0 != a.id }; changed() }) {
                (Text(a.name).foregroundStyle(a.available ? t.text.color : t.text3.color)
                 + Text(" " + (a.available ? a.line : "· " + (a.why ?? ""))).foregroundStyle(t.text3.color))
                    .ui(TypeScale.small)
            }
        }
    }

    @ViewBuilder private var models: some View {
        let ready = Set(board.doctor?.readyProviders ?? [])
        // The chosen ones and the first keyed suggestions (6 rows at most), the rest folded: the page fits without a scroll.
        let chosen = apiModels.filter { plan.models.contains($0) }
        let keyed = apiModels.filter { ready.contains(EvalModels.provider($0)) && !plan.models.contains($0) }
        let main = apiModels.filter { chosen.contains($0) || keyed.prefix(max(0, 6 - chosen.count)).contains($0) }
        let rest = apiModels.filter { !main.contains($0) }
        ForEach(showAll ? main + rest : main, id: \.self) { m in
            let key = ready.contains(EvalModels.provider(m))
            check(on: plan.models.contains(m), enabled: key || plan.models.contains(m),
                  help: key ? m : "No key yet: roof eval providers set \(EvalModels.provider(m)) --key-file PATH",
                  set: { on in toggleModel(m, on) }) {
                (Text(EvalModels.short(m)).foregroundStyle(key ? t.text.color : t.text3.color)
                 + Text(key ? "" : " · no key").foregroundStyle(t.text3.color))
                    .ui(TypeScale.small, mono: true)
            }
        }
        if !rest.isEmpty {
            Button { showAll.toggle() } label: {
                Text(showAll ? "fewer" : "\(rest.count) more ▸").ui(TypeScale.small).foregroundStyle(t.text3.color)
            }
            .buttonStyle(.plain).help("More suggested models; a provider with no key yet says so (roof eval providers set <provider> --key-file PATH)")
        }
        ForEach(plan.apiAgents, id: \.self) { a in
            check(on: true, enabled: true, help: "An agent on an API model: billed in dollars, shown as Agent", set: { on in
                if !on { plan.apiAgents.removeAll { $0 == a }; changed() }
            }) { Text(apiAgentName(a)).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color) }
        }
        Menu {
            ForEach(EvalAgents.onAPI, id: \.self) { ag in
                Menu(EvalAgents.name(ag)) {
                    ForEach(apiModels.filter { ready.contains(EvalModels.provider($0)) }, id: \.self) { m in
                        Button(EvalModels.short(m)) {
                            let k = ag + "@" + m
                            if !plan.apiAgents.contains(k) { plan.apiAgents.append(k); changed() }
                        }
                    }
                }
            }
        } label: { Text("agent on an API model…").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .help("The agent's CLI on an API model, run in the benchmark's sandbox; billed per token like a model")
    }

    @ViewBuilder private var local: some View {
        ForEach(localModels, id: \.self) { m in
            check(on: plan.models.contains(m), enabled: true, help: m, set: { on in toggleModel(m, on) }) {
                Text(m).ui(TypeScale.small, mono: true).foregroundStyle(t.text.color)
            }
        }
        Button { adding = true } label: { Text("+ any model id…").ui(TypeScale.small).foregroundStyle(t.accentText.color) }
            .buttonStyle(.plain)
            .popover(isPresented: $adding, arrowEdge: .bottom) {
                HStack {
                    TextField("any model, e.g. fireworks/accounts/fireworks/models/…", text: $custom).textFieldStyle(.roundedBorder)
                        .frame(width: 320).onSubmit(addCustom)
                    RoofButton("Add", .primary, action: addCustom)
                }
                .padding(12)
            }
    }

    private var apiModels: [String] {
        let suggested = EvalModels.suggestions.filter { $0.group != "Free" && $0.group != "On this Mac" }.flatMap(\.models)
        return suggested + plan.models.filter { m in !suggested.contains(m) && !EvalModels.isFree(m) }
    }
    private var localModels: [String] {
        let base = (EvalModels.suggestions.first { $0.group == "On this Mac" }?.models ?? []) + ["mockllm/model"]
        return base + plan.models.filter { m in EvalModels.isFree(m) && !base.contains(m) }
    }
    private func apiAgentName(_ k: String) -> String {
        let p = k.split(separator: "@", maxSplits: 1).map(String.init)
        return p.count == 2 ? "\(EvalAgents.name(p[0])) · \(EvalModels.short(p[1]))" : k
    }
    private func toggleModel(_ m: String, _ on: Bool) {
        plan.models = on ? plan.models + [m] : plan.models.filter { $0 != m }
        changed()
    }
    private func addCustom() {
        let m = custom.trimmingCharacters(in: .whitespaces)
        if m.contains("/") && !plan.models.contains(m) { plan.models.append(m); changed() }
        custom = ""; adding = false
    }

    private func check<L: View>(on: Bool, enabled: Bool, help: String?, set: @escaping (Bool) -> Void, @ViewBuilder label: () -> L) -> some View {
        Button { if enabled { set(!on) } } label: {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: on ? "checkmark.square.fill" : "square").font(.system(size: 12)).foregroundStyle(on ? t.accentText.color : t.text3.color)
                label().fixedSize(horizontal: false, vertical: true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help ?? "")
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

// MARK: - Cost before you start (right, 340 pt)

struct EvalsCostPanel: View {
    @ObservedObject var board: EvalsBoard
    let plan: EvalRunPlan
    let estimates: [String: EvalEstimate]
    let errors: [String: String]
    let startReason: String?
    var start: () -> Void
    @Environment(\.theme) private var t

    private struct Line: Identifiable { var id: String; var who: String; var mono: Bool; var calls: String; var est: String; var red: Bool; var note: String? }

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Cost before you start").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                VStack(spacing: 0) {
                    HStack { EvalsLabel("Contestant"); Spacer(); EvalsLabel("Calls").frame(width: 70, alignment: .leading); EvalsLabel("Est.").frame(width: 64, alignment: .trailing) }
                        .padding(.bottom, 6)
                    ForEach(lines) { l in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(l.who).ui(TypeScale.small, mono: l.mono).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                                Spacer(minLength: 6)
                                Text(l.calls).ui(TypeScale.small).foregroundStyle(t.text2.color).frame(width: 70, alignment: .leading)
                                Text(l.est).ui(TypeScale.small, .semibold, mono: true).foregroundStyle(l.red ? t.needsText.color : t.text.color)
                                    .frame(width: 64, alignment: .trailing)
                            }
                            if let n = l.note { Text(n).ui(TypeScale.micro).foregroundStyle(l.red ? t.needsText.color : t.text3.color).lineLimit(3) }
                        }
                        .padding(.vertical, 7)
                        .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                    }
                    if lines.isEmpty {
                        Text("Pick what and who: the cost shows here before anything starts.").ui(TypeScale.small).foregroundStyle(t.text3.color)
                            .padding(.vertical, 8)
                    }
                }
                if let seats = seatSentence {
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    seats.ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    Rectangle().fill(t.separator.color).frame(height: 1)
                    Text("Agents work in a fresh worktree per case, at the commit before the fix, with read-only tools. Nothing is pushed.")
                        .ui(TypeScale.small).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                Rectangle().fill(t.separator.color).frame(height: 1)
                HStack {
                    Text("Total API estimate").ui(TypeScale.body).foregroundStyle(t.text.color)
                    Spacer()
                    Text(total.map { String(format: "$%.2f", $0) } ?? "…").ui(TypeScale.body, .semibold, mono: true).foregroundStyle(t.text.color)
                }
                Text(String(format: "Each run is capped at $%.2f (the grader counted ×1.5). Prices from OpenRouter's list; answer length from this Mac's earlier runs.", plan.cap))
                    .ui(TypeScale.caption).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
                Button(action: start) {
                    Text("Start \(plan.runCount) run\(plan.runCount == 1 ? "" : "s")").ui(TypeScale.body, .semibold)
                        .foregroundStyle(t.onAccent.color).frame(maxWidth: .infinity).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(t.accent.color))
                }
                .buttonStyle(.plain)
                .disabled(startReason != nil || board.busy != nil)
                .opacity(startReason != nil ? 0.4 : 1)
                .accessibilityLabel("Start \(plan.runCount) runs")
                if let r = startReason { Text(r).ui(TypeScale.small).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true) }
                else { Text("Runs start in the background, two at a time; closing One Roof does not stop them.").ui(TypeScale.caption).foregroundStyle(t.text3.color) }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var lines: [Line] {
        var out: [Line] = []
        for c in plan.contestants { for task in plan.tasks {
            let k = "\(task)|\(c.key)"
            let who = c.name + (plan.tasks.count > 1 ? " · " + EvalBenchmark.taskLabel(task) : "")
            let mono: Bool = { if case .model = c { return true }; return false }()
            if let e = estimates[k] {
                if e.isSeat {
                    out.append(Line(id: k, who: who, mono: mono, calls: "\(e.calls) tasks", est: "seat", red: e.seatFits == false,
                                    note: e.seatFits == false ? "\(e.seat ?? "") would pass its \(Int(e.seatLimit ?? 90)) % limit" : nil))
                } else {
                    let over = (e.capCheckUSD ?? e.usd ?? 0) > plan.cap
                    out.append(Line(id: k, who: who, mono: mono, calls: "\(e.calls)", est: e.usd.map { String(format: "$%.3f", $0) } ?? "?",
                                    red: over || e.usd == nil, note: e.usd == nil ? (e.note ?? "price unknown") : over ? "over the cap" : nil))
                }
            } else {
                out.append(Line(id: k, who: who, mono: mono, calls: "", est: errors[k] == nil ? "…" : "–", red: errors[k] != nil, note: errors[k]))
            }
        } }
        return out
    }

    private var total: Double? {
        let paid = plan.contestants.filter { !$0.isSeat }.flatMap { c in plan.tasks.map { "\($0)|\(c.key)" } }
        let vals = paid.compactMap { estimates[$0]?.usd }
        return vals.count == paid.count ? vals.reduce(0, +) : nil
    }

    /// "Agents run on your subscriptions, not API credit. They use about 6 % of C1's 5-hour window and 4 % of CX's."
    private var seatSentence: Text? {
        let seats = plan.contestants.compactMap { c -> (String, Double, String?)? in
            guard case .seat(let a) = c else { return nil }
            let es = plan.tasks.compactMap { estimates["\($0)|\(c.key)"] }
            guard let s = EvalAgents.seat(a) else { return nil }
            return (s, es.compactMap(\.seatShare).reduce(0, +), es.first?.seatBasis)
        }
        guard !seats.isEmpty else { return nil }
        var t = Text("Agents run on your subscriptions, not API credit. They use about ")
        for (i, s) in seats.enumerated() {
            if i > 0 { t = t + Text(i == seats.count - 1 ? " and " : ", ") }
            let pct = Text("\(max(Int((s.1 * 100).rounded()), s.1 > 0 ? 1 : 0)) % of \(s.0)'s").bold()
            t = t + pct + (i == 0 ? Text(" 5-hour window").bold() : Text(""))
        }
        let guess = seats.contains { $0.2 == "guess" }
        let states = board.doctor?.agents ?? []
        let unknown = seats.map(\.0).filter { s in states.first { $0.seat == s }.map { $0.stale || $0.fiveHour == nil } ?? true }
        var tail = Text("One Roof waits if a seat runs low.")
        if !unknown.isEmpty {   // QA (M9): unknown use never passes silently
            let who = unknown.joined(separator: " and ")
            tail = Text("\(who)'s use is unknown right now: before each case the run waits until One Roof can see it under 90 %, or until you press Run anyway on that run.").foregroundStyle(self.t.needsText.color)
        }
        if plan.agents.contains("codex_cli") {
            tail = tail + Text(" Codex can still read files outside the case folder: its read-only sandbox blocks writes, not reads.")
        }
        return t + Text(guess ? " (a guess until this Mac has measured a run). " : ". ") + tail
    }
}

// MARK: - Queue (the foot of Run)

struct EvalsQueue: View {
    @ObservedObject var board: EvalsBoard
    @ObservedObject var nav: EvalsNav
    @Environment(\.theme) private var t
    @State private var all = false

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Queue").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                    Spacer()
                    Text("two at a time").ui(TypeScale.small).foregroundStyle(t.text2.color)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                if board.runs.isEmpty {
                    Text("No runs yet. Pick what and who above; the cost shows before anything starts.")
                        .ui(TypeScale.small).foregroundStyle(t.text3.color).padding(14)
                }
                ForEach(shown) { r in row(r) }
                if board.runs.count > shown.count || all {
                    Button { all.toggle() } label: {
                        Text(all ? "Show fewer" : "Show all \(board.runs.count) runs").ui(TypeScale.small).foregroundStyle(t.accentText.color)
                    }
                    .buttonStyle(.plain).padding(14)
                }
            }
        }
    }

    /// Going now first, then the newest finished ones.
    private var shown: [EvalRunRow] {
        let active = board.runs.filter(\.isActive)
        let rest = board.runs.filter { !$0.isActive }
        return all ? active + rest : active + rest.prefix(max(0, 8 - active.count))
    }

    private func row(_ r: EvalRunRow) -> some View {
        HStack(spacing: 12) {
            Button { nav.openRun(r.id) } label: {
                Text("\(EvalBenchmark.taskLabel(r.task ?? "?")) × \(r.contestant?.name ?? EvalModels.short(r.model ?? "?"))")
                    .ui(TypeScale.small).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain).help("Open this run, question by question")
            status(r).frame(width: 220, alignment: .leading)
            Text(r.progress).ui(TypeScale.small, mono: true).foregroundStyle(t.text2.color).frame(width: 60, alignment: .trailing)
            HStack(spacing: 6) {
                if r.waitsForUnknownSeat {
                    RoofButton("Run anyway", .plain) { board.runAnyway(r.id) }
                        .help("Go on without knowing how much of \(r.seat ?? "the seat")'s 5-hour window is used (recorded in this run)")
                }
                if r.isActive { RoofButton("Cancel", .plain) { board.cancel(r.id) } }
                if r.canResume { RoofButton("Resume", .plain) { board.resume(r.id) } }
                if r.status == "done" { RoofButton("Results", .plain) { nav.showResults(key: r.setName.map { "\($0)@v\(r.setVersion ?? 1)" } ?? (r.task ?? "")) } }
            }
            .frame(width: 200, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(r.task ?? "") \(r.status ?? "") \(r.progress)")
    }

    @ViewBuilder private func status(_ r: EvalRunRow) -> some View {
        if r.status == "running", let f = r.fraction {
            ProgressView(value: f).tint(t.accent.color)
        } else if r.status == "waiting" {
            Text(r.waiting ?? "waiting for a seat").ui(TypeScale.small).foregroundStyle(t.needsText.color).lineLimit(2).help(r.waiting ?? "")
        } else if r.status == "failed" {
            Text("failed: " + (r.error ?? "see the run")).ui(TypeScale.small).foregroundStyle(t.needsText.color).lineLimit(2)
                .help([r.error, r.hint.map { "What to do: " + $0 }].compactMap { $0 }.joined(separator: "\n"))
        } else {
            Text(r.status ?? "").ui(TypeScale.small).foregroundStyle(r.status == "done" ? t.diffAddText.color : t.text2.color)
        }
    }
}
