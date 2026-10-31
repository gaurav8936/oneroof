import SwiftUI
import OneRoofCore

/// Decisions (⌘I): every agent waiting on you, oldest first, each with the agent's reason in its own words,
/// what the command touches, the risk, what happens if you say no, and where it sits. Plans waiting for approval
/// (objectives in review) are decisions too. Answers go to the agent as its own keys (y / a / n, or Esc then text).
struct DecisionsView: View {
    /// LAB-1338: captions, feed, chapters and subagents redraw this view (they left AppModel).
    @ObservedObject var engineState = EngineState.shared
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    @State private var selected: String?
    @State private var reply = ""
    @State private var undoRule: Decision?
    @Environment(\.v2Window) private var v2
    @FocusState private var replyFocused: Bool
    /// v2 (C2.2, NEW-19): the rules and today's decisions page, from the footer.
    @State private var showRules = false

    /// A row in the list: an agent's prompt or an objective's plan.
    enum Entry: Identifiable, Equatable {
        case prompt(Decision)
        case plan(Objective)
        var id: String {
            switch self {
            case .prompt(let d): return d.id.uuidString
            case .plan(let o): return "plan-" + o.id
            }
        }
        var askedAt: Date {
            switch self {
            case .prompt(let d): return d.askedAt
            case .plan(let o): return o.createdAt
            }
        }
    }

    private var entries: [Entry] {
        let plans = model.objectives.filter { $0.status == .review && $0.plan != nil }.map(Entry.plan)
        return (model.openDecisions.map(Entry.prompt) + plans).sorted { $0.askedAt < $1.askedAt }
    }

    private var current: Entry? {
        let list = entries
        return list.first { $0.id == selected } ?? list.first
    }

    var body: some View {
        Group {
            if v2 && showRules { V2RulesPage(model: model) { showRules = false } } else { queue }
        }
        .onDisappear { showRules = false }                                     // back to the queue next time
        .onChange(of: model.openDecisions.count) { old, new in if new > old { showRules = false } }   // a new decision shows
    }

    private var queue: some View {
        HStack(spacing: 0) {
            list.frame(width: 340)
            Rectangle().fill(t.separator.color).frame(width: 1)
            Group {
                switch current {
                case .prompt(let d): detail(d)
                case .plan(let o): planDetail(o)
                case nil: empty
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(t.window.color)
        }
        .background(t.window.color)
        .overlay(alignment: .bottom) { if let u = undoRule { undoToast(u) } }
    }

    // MARK: List

    private var list: some View {
        let list = entries
        let today = model.decisions.filter { !$0.isOpen && Calendar.current.isDateInToday($0.answeredAt ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(v2 ? "Needs you" : "Decisions").ui(24, .semibold).foregroundStyle(t.text.color)
                if !list.isEmpty {
                    if v2 { Text("\(list.count)").ui(24, .regular).foregroundStyle(t.text3.color) }   // A6.1 "Needs you 1"
                    else { Text("\(list.count) waiting").ui(13, .semibold).foregroundStyle(t.needsText.color) }
                }
            }
            .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 14)
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(list) { e in listItem(e) }
                }
                .padding(.horizontal, 12)
            }
            Hairline().padding(.horizontal, 12)
            if v2 {
                Button { showRules = true } label: {
                    Text("Earlier today · \(today.count) decided · \(model.decisionRuleCount) rules learned ›").ui(12).foregroundStyle(t.accentText.color)
                }
                .buttonStyle(.plain).help("Your always-allow rules and what you decided today")
                .padding(.horizontal, 18).padding(.vertical, 12)
            } else {
                Text("Earlier today · \(today.count) decided · \(model.decisionRuleCount) rules learned").ui(12).foregroundStyle(t.text3.color)
                    .padding(.horizontal, 18).padding(.vertical, 12)
            }
        }
        .background(t.sidebar.color)
    }

    private func listItem(_ e: Entry) -> some View {
        let on = e.id == current?.id
        return Button { withAnimation(Motion.fast) { selected = e.id } } label: {
            VStack(alignment: .leading, spacing: 5) {
                switch e {
                case .prompt(let d):
                    let item = model.item(d.sessionId)
                    HStack(spacing: 7) {
                        if let item { AgentBadge(item: item, size: 20, status: false) }
                        Text(item?.session.name ?? "Session").ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Spacer()
                        Text(ageText(d.askedAt)).ui(11.5).foregroundStyle(t.text3.color)
                    }
                    Text(d.command.map { "Run " + $0 } ?? d.headline).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
                    HStack(spacing: 6) {
                        if d.isQuestion {   // LAB-1606: not a permission ask
                            Text("Asked a question").ui(11, .semibold).foregroundStyle(t.accentText.color)
                        } else {
                            RiskPill(risk: d.risk)
                        }
                        Text(item.map { model.window(model.workspaceId(of: $0))?.name ?? "" } ?? "").ui(11.5).foregroundStyle(t.text3.color)
                    }
                case .plan(let o):
                    HStack(spacing: 7) {
                        AgentBadge(.claude1, size: 20)
                        Text(o.title).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Spacer()
                        Text(ageText(o.createdAt)).ui(11.5).foregroundStyle(t.text3.color)
                    }
                    Text("Approve a \(o.plan?.steps.count ?? 0)-step plan").ui(12.5).foregroundStyle(t.text2.color)
                    HStack(spacing: 6) { RiskPill(risk: .plan); Text(Workspace.repoLabel(for: o.repoPath)).ui(11.5).foregroundStyle(t.text3.color) }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? t.surface.color : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? t.separatorStrong.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    // MARK: Detail

    @ViewBuilder private func detail(_ d: Decision) -> some View {
        if d.isQuestion { questionDetail(d) } else { promptDetail(d) }
    }

    /// LAB-1606 · the agent ended its turn with a question: what it asked, and a reply box. Nothing to allow or deny;
    /// the reply goes to its input box (or answer it in the terminal: the card leaves either way).
    private func questionDetail(_ d: Decision) -> some View {
        let item = model.item(d.sessionId)
        let agentName = item.map { $0.account ?? $0.session.agent.displayName } ?? d.agent.displayName
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                if let item { AgentBadge(item: item, size: 22, status: false) }
                Text(context(d, item)).ui(13).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer()
                Button { if let item { model.reveal(item) } } label: { Text("Open session ⌘↩").ui(12.5).foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain)
            }
            MicroLabel("\(agentName) asked a question")
            Text(d.why).ui(26, .semibold).tracking(-0.3).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            Spacer(minLength: 0)
            TextField("", text: $reply, prompt: Text("Your answer"))
                .textFieldStyle(.plain).ui(13.5).focused($replyFocused)
                .padding(.horizontal, 14).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(replyFocused ? t.accent.color : t.separator.color))
                .onSubmit { if !reply.trimmingCharacters(in: .whitespaces).isEmpty { send(d, .reply) } }
            HStack(spacing: 10) {
                RoofButton("Reply ↩", .primary) { send(d, .reply) }
                    .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                Button { step(1) } label: { Text("Next decision ⌘]").ui(12.5).foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain).keyboardShortcut("]", modifiers: .command)
                Button { step(-1) } label: { EmptyView() }.buttonStyle(.plain).keyboardShortcut("[", modifiers: .command).frame(width: 0)
            }
            Text("Your answer goes to \(agentName) as its next message. You can also answer in the terminal.").ui(11.5).foregroundStyle(t.text3.color)
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
        .onAppear { replyFocused = true }
    }

    private func promptDetail(_ d: Decision) -> some View {
        let item = model.item(d.sessionId)
        let agentName = item.map { $0.account ?? $0.session.agent.displayName } ?? d.agent.displayName
        return VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 8) {
                if let item { AgentBadge(item: item, size: 22, status: false) }
                Text(context(d, item)).ui(13).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer()
                Button { if let item { model.reveal(item) } } label: { Text("Open session ⌘↩").ui(12.5).foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain)
            }
            Text(d.headline.replacingOccurrences(of: d.agent.displayName, with: agentName)).ui(30, .semibold).tracking(-0.4)
                .foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
            if let c = d.command ?? d.path {
                // The box is always Midnight, so its text is too (Daylight's terminal text is dark: unreadable on it).
                Text(c).ui(14, mono: true).foregroundStyle(ThemeName.midnight.tokens.terminal.foreground.color).textSelection(.enabled)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ThemeName.midnight.tokens.terminal.background.color))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.separator.color))
            }
            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    reason("Why · in \(agentName)'s words", d.whyMissing ? d.why : "\u{201C}" + d.why + "\u{201D}", big: true)
                        .gridCellColumns(2)
                }
                GridRow {
                    reason("What it touches", d.touches)
                    riskCard(d)
                }
                GridRow {
                    reason("If you say no", d.ifNo)
                    reason("Where this sits", d.where_.isEmpty ? "—" : d.where_)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            TextField("", text: $reply, prompt: Text(d.whyMissing ? "Ask it: why do you want to do this?" : "Or reply with instructions: \u{201C}Run them, but skip the snapshot tests\u{201D}"))
                .textFieldStyle(.plain).ui(13.5).focused($replyFocused)
                .padding(.horizontal, 14).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(replyFocused ? t.accent.color : t.separator.color))
                .onSubmit { send(d, .reply) }
            HStack(spacing: 10) {
                RoofButton("Allow once ↩", .primary) { send(d, .allowOnce) }.keyboardShortcut(.defaultAction)
                if !d.pattern.hasPrefix("ask:") {
                    if v2 {   // A6.1: short label; what it allows is in the tooltip
                        RoofButton("Always allow this") { send(d, .always) }.help("Always allow \(d.pattern) in \(d.repo)")
                    } else {
                        RoofButton("Always allow \(d.pattern) in \(d.repo)") { send(d, .always) }
                    }
                }
                RoofButton("Deny esc") { send(d, .deny) }.keyboardShortcut(.cancelAction)
                Spacer()
                Button { step(1) } label: { Text("Next decision ⌘]").ui(12.5).foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain).keyboardShortcut("]", modifiers: .command)
                Button { step(-1) } label: { EmptyView() }.buttonStyle(.plain).keyboardShortcut("[", modifiers: .command).frame(width: 0)
            }
            if v2 {
                Text("This waits until you choose. ↩ allow once · esc deny · ⌘] next decision · ⌘[ previous").ui(11.5).foregroundStyle(t.text3.color)
            }
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
        .onAppear { if d.whyMissing { replyFocused = true } }
    }

    private func context(_ d: Decision, _ item: BoardItem?) -> String {
        var parts: [String] = []
        if let item {
            parts.append(item.session.name)
            parts.append((model.window(model.workspaceId(of: item))?.name ?? "") + " window")
            if let a = item.account { parts.append(a) }
            if let c = model.captions[item.id], let i = c.step, let n = c.steps { parts.append("step \(i) of \(n)") }
        }
        parts.append("asked \(ageText(d.askedAt)) ago")
        return parts.joined(separator: " · ")
    }

    private func reason(_ title: String, _ body: String, big: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            MicroLabel(title)
            Text(body).ui(big ? 15 : 13.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
    }

    private func riskCard(_ d: Decision) -> some View {
        let word: (String, RGB) = {
            switch d.risk {
            case .low: return ("Low.", t.statusDone)
            case .plan: return ("Plan.", StatusPalette.scheduledPill(theme: t.name).text)
            case .high: return ("High.", t.needsText)
            }
        }()
        var sentence = d.history.similarAllowed > 0 ? " Same command you allowed \(d.history.similarAllowed) time\(d.history.similarAllowed == 1 ? "" : "s") this week." : ""
        if let s = d.history.ruleSuggestion { sentence += " " + s + "." }
        return VStack(alignment: .leading, spacing: 8) {
            MicroLabel("Risk")
            (Text(word.0).foregroundColor(word.1.color).fontWeight(.semibold) + Text(sentence).foregroundColor(t.text.color))
                .ui(13.5).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
    }

    // MARK: Plan approval (S03 §1.4)

    private func planDetail(_ o: Objective) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Planner · \(Workspace.repoLabel(for: o.repoPath)) · asked \(ageText(o.createdAt)) ago").ui(13).foregroundStyle(t.text2.color)
            Text("Approve the plan for \u{201C}\(o.title)\u{201D}").ui(30, .semibold).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((o.plan?.steps ?? []).enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").ui(12, .semibold, mono: true).foregroundStyle(t.text3.color).frame(width: 18)
                        AgentBadge(AgentMark(agent: s.agentKind, account: s.account), size: 20)
                        Text(s.title).ui(13.5).foregroundStyle(t.text.color).lineLimit(2)
                        Spacer()
                        Text([s.account, s.model, s.cost].compactMap { $0 }.joined(separator: " · ")).ui(11.5, mono: true).foregroundStyle(t.text3.color)
                    }
                    .padding(.vertical, 9).padding(.horizontal, 14)
                    .overlay(alignment: .bottom) { Hairline() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
            HStack(spacing: 14) {
                reason("Done when", o.doneWhen.isEmpty ? "—" : o.doneWhen)
                reason("If you say no", "Nothing runs; the planner waits for your edits.")
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack(spacing: 10) {
                RoofButton("Approve plan", .primary) { model.approve(o) }
                RoofButton("Edit plan") { model.objectiveId = o.id }
                RoofButton("Reject") { model.pause(o) }
                Spacer()
            }
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
    }

    // MARK: Empty, undo, actions

    private var empty: some View {
        let today = model.decisions.filter { !$0.isOpen && Calendar.current.isDateInToday($0.answeredAt ?? .distantPast) }.count
        return VStack(spacing: 8) {
            Spacer()
            Text("Nothing waiting.").ui(20, .semibold).foregroundStyle(t.text.color)
            Text("Agents will ask here, with their reasons.").ui(13.5).foregroundStyle(t.text2.color)
            Text("\(today) decided today").ui(12).foregroundStyle(t.text3.color)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func undoToast(_ d: Decision) -> some View {
        HStack(spacing: 12) {
            Text("Always allow \(d.pattern) in \(d.repo)").ui(12.5).foregroundStyle(t.text.color)
            Button { model.removeRule(pattern: d.pattern, repo: d.repo); undoRule = nil } label: {
                Text("Undo").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Capsule().fill(t.surface.color).shadow(color: .black.opacity(0.15), radius: 8, y: 3))
        .padding(.bottom, 18)
    }

    private func send(_ d: Decision, _ a: Answer) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if a == .reply && text.isEmpty {
            if let item = model.item(d.sessionId) { model.reveal(item) }   // ⌘↩ with no text opens the session
            return
        }
        model.answer(d, a, reply: a == .reply ? text : nil)
        reply = ""
        if a == .always {
            undoRule = d
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if undoRule == d { undoRule = nil } }
        }
        withAnimation(Motion.base) { step(1) }
    }

    private func step(_ delta: Int) {
        let list = entries
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == current?.id } ?? 0
        selected = list[(i + delta + list.count) % list.count].id
    }
}

extension AppModel {
    var decisionRuleCount: Int { store?.decisionRules().count ?? 0 }

    func removeRule(pattern: String, repo: String) {
        for r in store?.decisionRules() ?? [] where r.pattern == pattern && r.repo == repo { store?.deleteRule(id: r.id) }
    }
}
