import AppKit
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
    /// LAB-1866 · LAB-1919: loop items (a loop that stopped, a round that asks, Today), after the session asks.
    @ObservedObject private var loopInbox = LoopInboxState.shared
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
        case loop(LoopInbox.Item)
        var id: String {
            switch self {
            case .prompt(let d): return d.id.uuidString
            case .plan(let o): return "plan-" + o.id
            case .loop(let i): return "loop-" + i.id
            }
        }
        var askedAt: Date {
            switch self {
            case .prompt(let d): return d.askedAt
            case .plan(let o): return o.createdAt
            case .loop(let i): return i.when
            }
        }
        var isLoop: Bool { if case .loop = self { return true }; return false }
    }

    private var entries: [Entry] {
        let plans = model.objectives.filter { $0.status == .review && $0.plan != nil }.map(Entry.plan)
        return (model.openDecisions.map(Entry.prompt) + plans).sorted { $0.askedAt < $1.askedAt } + loopInbox.items.map(Entry.loop)
    }

    /// LAB-1831 · what you decided, kept while its session is alive (newest first), under the open asks.
    private var decided: [Decision] { ScrollFeed.decided(model.decisions) { model.item($0) } }

    private var current: Entry? {
        let list = entries
        if let s = selected, let d = decided.first(where: { $0.id.uuidString == s }), !list.contains(where: { $0.id == s }) {
            return .prompt(d)
        }
        return list.first { $0.id == selected } ?? list.first
    }

    var body: some View {
        Group {
            if v2 && showRules { V2ActionLogPage(model: model, win: win) { showRules = false } } else { queue }
        }
        .onDisappear { showRules = false }                                     // back to the queue next time
        .onChange(of: model.needsPick) { _, id in if let id { selected = id } }   // self-test: show this entry
        .onChange(of: model.openDecisions.count) { old, new in if new > old { showRules = false } }   // a new decision shows
    }

    /// LAB-1932 · the list column's width, dragged on its edge (240…560 pt), kept across launches.
    @AppStorage("v2.needsYou.listWidth", store: Prefs.defaults) private var listWidth: Double = V2Layout.needsListDefault
    @State private var dragFrom: Double?

    private var queue: some View {
        GeometryReader { g in
            let w = V2Layout.needsListWidth(saved: listWidth, available: Double(g.size.width))
            queueRow(listWidth: w)
        }
    }

    /// The list's right edge: a 1 pt line with a 9 pt grab area and the resize cursor.
    private func listEdge(current: Double) -> some View {
        Rectangle().fill(t.separator.color).frame(width: 1)
            .overlay(
                Color.clear.frame(width: 9).contentShape(Rectangle())
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                        .onChanged { v in
                            let from = dragFrom ?? current
                            if dragFrom == nil { dragFrom = current }
                            listWidth = min(V2Layout.needsListMax, max(V2Layout.needsListMin, from + Double(v.translation.width)))
                        }
                        .onEnded { _ in dragFrom = nil })
            )
            .accessibilityElement()
            .accessibilityLabel("Needs you list width")
            .accessibilityValue("\(Int(current)) points")
            .accessibilityAdjustableAction { dir in
                listWidth = min(V2Layout.needsListMax, max(V2Layout.needsListMin, current + (dir == .increment ? 20 : -20)))
            }
            .help("Drag to resize the list")
    }

    private func queueRow(listWidth w: Double) -> some View {
        HStack(spacing: 0) {
            list.frame(width: CGFloat(w))
            listEdge(current: w).zIndex(1)
            Group {
                switch current {
                case .prompt(let d) where !d.isOpen: decidedDetail(d)   // LAB-1831
                case .prompt(let d): detail(d)
                case .plan(let o): planDetail(o)
                case .loop(let i): LoopNeedDetail(model: model, item: i, win: win)
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
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(list.filter { !$0.isLoop }) { e in listItem(e) }
                    // LAB-1866 · LAB-1919: loops, never as sessions; Today is what they staged for you.
                    let loops = list.filter(\.isLoop)
                    if !loops.isEmpty {
                        MicroLabel("Loops · Today · \(loops.count)").padding(.horizontal, 6).padding(.top, loops.count == list.count ? 0 : 10)
                        ForEach(loops) { e in listItem(e) }
                    }
                    // LAB-1831: answered asks stay, newest first, while their session is alive: scroll back through them.
                    let done = decided
                    if !done.isEmpty {
                        MicroLabel("Decided · \(done.count)").padding(.horizontal, 6).padding(.top, list.isEmpty ? 0 : 10)
                        ForEach(done, id: \.id) { d in decidedItem(d) }
                    }
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

    /// A decided ask in the list: dimmer, with what you answered and when.
    private func decidedItem(_ d: Decision) -> some View {
        let on = current?.id == d.id.uuidString
        let item = model.item(d.sessionId)
        return Button { withAnimation(Motion.fast) { selected = d.id.uuidString } } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    if let item { AgentBadge(item: item, size: 18, status: false) }
                    Text(item?.session.name ?? "Session").ui(12.5, .semibold).foregroundStyle(t.text2.color).lineLimit(1)
                    Spacer()
                    Text(ageText(d.answeredAt ?? d.askedAt)).ui(11).foregroundStyle(t.text3.color)
                }
                Text(ScrollFeed.askText(d)).ui(12).foregroundStyle(t.text2.color).lineLimit(1)
                Text(ScrollFeed.answerText(d) ?? "").ui(11, .semibold).foregroundStyle(t.text3.color).lineLimit(1)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(on ? t.surface.color : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(on ? t.separatorStrong.color : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Decided: \(ScrollFeed.askText(d)), \(ScrollFeed.answerText(d) ?? "")")
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// LAB-1831 · a decided ask, read only: what was asked, what you answered, when.
    private func decidedDetail(_ d: Decision) -> some View {
        let item = model.item(d.sessionId)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if let item { AgentBadge(item: item, size: 22, status: false) }
                Text(item?.session.name ?? "Session").ui(13).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer()
                Button { if let item { model.reveal(item) } } label: { Text("Open session ⌘↩").ui(12.5).foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain)
            }
            MicroLabel("Asked · " + d.askedAt.formatted(date: .abbreviated, time: .shortened))
            Text(ScrollFeed.askText(d)).ui(22, .semibold).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if !d.isQuestion && !d.isFinished && !d.why.isEmpty {
                Text(d.why).ui(13.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            MicroLabel("You answered" + (d.answeredAt.map { " · " + $0.formatted(date: .abbreviated, time: .shortened) } ?? ""))
            Text(ScrollFeed.answerText(d) ?? "").ui(15, .semibold).foregroundStyle(t.text.color).textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(28)
    }

    @ViewBuilder private func listItem(_ e: Entry) -> some View {
        if case .loop(let i) = e {
            let on = e.id == current?.id
            Button { withAnimation(Motion.fast) { selected = e.id } } label: { LoopNeedRow(item: i, selected: on) }
                .buttonStyle(.plain)
        } else {
            sessionItem(e)
        }
    }

    private func sessionItem(_ e: Entry) -> some View {
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
                    Text(d.command.map { "Run " + $0 } ?? (d.isFinished ? d.why : d.headline)).ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
                    HStack(spacing: 6) {
                        if d.isQuestion {   // LAB-1606: not a permission ask
                            Text("Asked a question").ui(11, .semibold).foregroundStyle(t.accentText.color)
                        } else if d.isFinished {   // LAB-1827
                            Text("Finished · waiting for you").ui(11, .semibold).foregroundStyle(t.accentText.color)
                        } else if d.isMenu {   // LAB-1607 / LAB-1825: a menu, no risk
                            Text("Question").ui(11, .semibold).foregroundStyle(t.accentText.color)
                        } else {
                            RiskPill(risk: d.risk)
                        }
                        Text(item.map { model.window(model.workspaceId(of: $0))?.name ?? "" } ?? "").ui(11.5).foregroundStyle(t.text3.color)
                    }
                case .plan(let o):
                    HStack(spacing: 7) {
                        AgentBadge(AgentMark.claude1, size: 20)
                        Text(o.title).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                        Spacer()
                        Text(ageText(o.createdAt)).ui(11.5).foregroundStyle(t.text3.color)
                    }
                    Text("Approve a \(o.plan?.steps.count ?? 0)-step plan").ui(12.5).foregroundStyle(t.text2.color)
                    HStack(spacing: 6) { RiskPill(risk: .plan); Text(Workspace.repoLabel(for: o.repoPath)).ui(11.5).foregroundStyle(t.text3.color) }
                case .loop: EmptyView()
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
        if d.isQuestion { questionDetail(d) }
        else if d.isFinished { finishedDetail(d) }
        else if d.isMenu { menuDetail(d) }
        else { promptDetail(d) }
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
                .disabled(d.agent.isHosted)
            if d.agent.isHosted {
                Text(d.agent == .opencode ? "Approve in OpenCode's terminal; its selected option is shown by color. Deny here safely sends Escape." : "This is Goose's native approval menu. Unknown or changed menus must be answered in the terminal.")
                    .ui(12).foregroundStyle(t.text2.color)
                if let item { RoofButton("Open native terminal") { model.reveal(item) } }
            }
            if let choices = d.choices, !choices.isEmpty {
                // LAB-1839: every option the prompt shows, in its order and words; each presses that option's key.
                choiceButtons(d, choices)
            }
            HStack(spacing: 10) {
                if d.choices?.isEmpty != false {   // fixed answers only when the prompt's options could not be read
                    RoofButton("Allow once ↩", .primary) { send(d, .allowOnce) }.keyboardShortcut(.defaultAction).disabled(d.agent == .opencode)
                    if !d.pattern.hasPrefix("ask:") && d.agent != .opencode {
                        if v2 {   // A6.1: short label; what it allows is in the tooltip
                            RoofButton("Always allow this") { send(d, .always) }.help("Always allow \(d.pattern) in \(d.repo)")
                        } else {
                            RoofButton("Always allow \(d.pattern) in \(d.repo)") { send(d, .always) }
                        }
                    }
                    RoofButton("Deny esc") { send(d, .deny) }.keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button { step(1) } label: { Text("Next decision ⌘]").ui(12.5).foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain).keyboardShortcut("]", modifiers: .command)
                Button { step(-1) } label: { EmptyView() }.buttonStyle(.plain).keyboardShortcut("[", modifiers: .command).frame(width: 0)
            }
            if v2 {
                Text(d.choices?.isEmpty == false ? "This waits until you choose. ↩ the first option · ⌘] next decision · ⌘[ previous · or answer in the terminal"
                                                 : "This waits until you choose. ↩ allow once · esc deny · ⌘] next decision · ⌘[ previous").ui(11.5).foregroundStyle(t.text3.color)
            }
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
        .onAppear { if d.whyMissing { replyFocused = true } }
    }

    /// LAB-1839 / LAB-1607: one button per option, as the prompt lists them (numbered, the first is ↩). A free-text
    /// option ("No, and tell Claude what to do", "Type something.") sends what is in the reply box, or opens it.
    private func choiceButtons(_ d: Decision, _ choices: [DecisionChoice]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(choices.enumerated()), id: \.offset) { i, c in
                let title = "\(i + 1). \(c.label)" + (i == 0 ? "  ↩" : "")
                Group {
                    if i == 0 { RoofButton(title, .primary) { choose(d, c) }.keyboardShortcut(.defaultAction) }
                    else { RoofButton(title) { choose(d, c) } }
                }
                .disabled(!c.pressable)
                .help(c.pressable ? c.label : "\(c.label): pick this one in the agent's own terminal")
            }
        }
    }

    /// The prompt as the agent draws it: its question and options, in a terminal-coloured box (always Midnight).
    private func screenBox(_ lines: [String]) -> some View {
        Text(lines.joined(separator: "\n")).ui(12.5, mono: true).foregroundStyle(ThemeName.midnight.tokens.terminal.foreground.color)
            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(ThemeName.midnight.tokens.terminal.background.color))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.separator.color))
    }

    private func header(_ d: Decision, _ item: BoardItem?) -> some View {
        HStack(spacing: 8) {
            if let item { AgentBadge(item: item, size: 22, status: false) }
            Text(context(d, item)).ui(13).foregroundStyle(t.text2.color).lineLimit(1)
            Spacer()
            Button { if let item { model.reveal(item) } } label: { Text("Open session ⌘↩").ui(12.5).foregroundStyle(t.text2.color) }
                .buttonStyle(.plain)
        }
    }

    private func nav() -> some View {
        Group {
            Button { step(1) } label: { Text("Next decision ⌘]").ui(12.5).foregroundStyle(t.text2.color) }
                .buttonStyle(.plain).keyboardShortcut("]", modifiers: .command)
            Button { step(-1) } label: { EmptyView() }.buttonStyle(.plain).keyboardShortcut("[", modifiers: .command).frame(width: 0)
        }
    }

    /// LAB-1607 / LAB-1825 · a menu (a question with its own answers, a sign-in menu): the prompt as drawn, its own
    /// choices, no risk and no Allow / Deny; a note in plain words when a choice cannot work.
    private func menuDetail(_ d: Decision) -> some View {
        let item = model.item(d.sessionId)
        let agentName = item.map { $0.account ?? $0.session.agent.displayName } ?? d.agent.displayName
        let choices = d.choices ?? []
        let note = d.touches == DecisionMatcher.geminiSignInRefused ? d.touches : nil
        return VStack(alignment: .leading, spacing: 18) {
            header(d, item)
            MicroLabel("\(agentName) is asking")
            Text(d.headline.replacingOccurrences(of: "\(d.agent.displayName) is asking: ", with: "")).ui(26, .semibold).tracking(-0.3)
                .foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let note {
                Text(note).ui(13.5).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
            }
            if let screen = d.screen, !screen.isEmpty { screenBox(screen) }
            choiceButtons(d, choices)
            if choices.contains(where: \.freeText) {
                TextField("", text: $reply, prompt: Text("Your own answer"))
                    .textFieldStyle(.plain).ui(13.5).focused($replyFocused)
                    .padding(.horizontal, 14).frame(height: 42)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(replyFocused ? t.accent.color : t.separator.color))
                    .onSubmit { send(d, .reply) }
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                RoofButton("Cancel esc") { send(d, .deny) }.keyboardShortcut(.cancelAction)
                Spacer()
                nav()
            }
            Text("Each button presses that option in \(agentName)'s terminal. You can also answer there.").ui(11.5).foregroundStyle(t.text3.color)
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
    }

    /// LAB-1827 · the agent finished its turn and waits for you: what it said last, a reply box (its next message),
    /// Close (end the session) and Set aside (leave Needs you, keep the session).
    private func finishedDetail(_ d: Decision) -> some View {
        let item = model.item(d.sessionId)
        let agentName = item.map { $0.account ?? $0.session.agent.displayName } ?? d.agent.displayName
        return VStack(alignment: .leading, spacing: 20) {
            header(d, item)
            MicroLabel("\(agentName) finished · waiting for you")
            ScrollView {
                Text(d.why).ui(18).foregroundStyle(d.whyMissing ? t.text2.color : t.text.color)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 260)
            Spacer(minLength: 0)
            TextField("", text: $reply, prompt: Text("Next message for \(agentName): continue, or ask it something"))
                .textFieldStyle(.plain).ui(13.5).focused($replyFocused)
                .padding(.horizontal, 14).frame(height: 42)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(replyFocused ? t.accent.color : t.separator.color))
                .onSubmit { if !reply.trimmingCharacters(in: .whitespaces).isEmpty { send(d, .reply) } }
            HStack(spacing: 10) {
                RoofButton("Reply ↩", .primary) { send(d, .reply) }
                    .disabled(reply.trimmingCharacters(in: .whitespaces).isEmpty)
                RoofButton("Set aside") { model.setAside(d); withAnimation(Motion.base) { step(1) } }
                    .help("Nothing more for now: it leaves Needs you, the session stays open")
                if let item {
                    RoofButton("Close session", .danger) { model.closeAgent(item); model.setAside(d); withAnimation(Motion.base) { step(1) } }
                        .help("End this session")
                }
                Spacer()
                nav()
            }
            Text("Your reply goes to \(agentName) as its next message. Typing in the terminal works too.").ui(11.5).foregroundStyle(t.text3.color)
        }
        .padding(.horizontal, 34).padding(.vertical, 26)
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

    /// LAB-1607: pick one of a question's own answers.
    private func choose(_ d: Decision, _ c: DecisionChoice) {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.freeText && text.isEmpty && !d.isMenu { replyFocused = true; return }   // type the instructions first
        model.answer(d, .reply, reply: c.freeText && !text.isEmpty ? text : nil, choice: c)
        reply = ""
        withAnimation(Motion.base) { step(1) }
    }

    private func step(_ delta: Int) {
        let list = entries
        guard !list.isEmpty else { return }
        let i = list.firstIndex { $0.id == current?.id } ?? 0
        selected = list[(i + delta + list.count) % list.count].id
    }
}

// AppModel.decisionRuleCount / removeRule: UI/V2/V2ActionLog.swift (LAB-2048).
