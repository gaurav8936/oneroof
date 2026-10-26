import AppKit
import SwiftUI
import OneRoofCore

/// What a pane draws around its terminal (S02 / S06 §1.4): header, summary (strip or card), chapters above the live
/// surface; approval card and hint strip below. Terminal theme; the summary card uses the centre theme.
struct PaneTop: View {
    @ObservedObject var model: AppModel
    let item: BoardItem?
    let focused: Bool
    let split: Bool
    let expanded: Bool
    let raw: Bool
    let openChapter: Int?
    var onToggleSummary: () -> Void
    var onChapter: (Int) -> Void
    var onZoom: () -> Void
    var onClose: () -> Void
    var table = false
    var onTable: (() -> Void)? = nil
    var onNewTerminal: (() -> Void)? = nil
    /// LAB-861: the program the pane's keys go to when it is not the shell or the session's agent, and its Stop.
    var running: String? = nil
    var onStop: (() -> Void)? = nil

    var body: some View {
        let term = model.themes.terminal.tokens
        VStack(spacing: 0) {
            PaneHeader(model: model, item: item, focused: focused, split: split, onZoom: onZoom, onClose: onClose,
                       table: table, onTable: onTable, onNewTerminal: onNewTerminal, running: running, onStop: onStop)
            if let item, item.session.agent.isAgent, item.liveAgent != nil {
                if expanded {
                    SummaryCard(model: model, item: item, openChapter: openChapter, onChapter: onChapter, onCollapse: onToggleSummary)
                        .themed(model.themes.centre)
                } else {
                    SummaryStrip(model: model, item: item, onExpand: onToggleSummary)
                }
                // LAB-1270: no rows of finished steps here any more: each new one grew the band and moved the terminal.
                // The steps (with calls and duration) are in the card's fixed-height step list.
                if !raw {
                    // Rewound to a step (LAB-259): one click back to the live bottom of the terminal.
                    if let open = openChapter, let c = (model.chapters[item.id] ?? []).first(where: { $0.index == open }) {
                        RewindBar(chapter: c) { onChapter(open) }
                    }
                }
            }
        }
        .themed(model.themes.terminal)
        .background(term.terminal.paneHeader.color)
    }
}

/// Pane header (COMPONENTS PaneHeader): badge 18, name, "Account · model · branch", ticket chip, split hints.
struct PaneHeader: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem?
    let focused: Bool
    let split: Bool
    var onZoom: () -> Void
    var onClose: () -> Void
    /// Table view (LAB-1286, replaced Wrap): nil hides the toggle (no live terminal in the pane).
    var table = false
    var onTable: (() -> Void)? = nil
    /// LAB-745: a new plain terminal in this pane's folder.
    var onNewTerminal: (() -> Void)? = nil
    /// LAB-861: "running: <command>" with Stop (Ctrl-C) while the pane's foreground program is not its shell.
    var running: String? = nil
    var onStop: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let item {
                AgentBadge(item: item, size: 18, status: false)
                Text(item.session.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1).layoutPriority(1)
                if item.session.agent.isAgent {
                    Text(meta(item)).ui(12).foregroundStyle(t.text2.color).lineLimit(1)
                } else {
                    Text((item.session.launchDirectory as NSString).abbreviatingWithTildeInPath).ui(12).foregroundStyle(t.text2.color).lineLimit(1)
                }
                if let tk = item.session.ticket {
                    Text(tk).ui(11, .semibold, mono: true).foregroundStyle(t.accentText.color)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(RoundedRectangle(cornerRadius: 5).fill(t.accent.color.opacity(0.18)))
                }
                if let ws = item.session.workstream { RowChip(text: ws, strong: false) }
            } else {
                Text(split ? "Empty pane" : "No session selected").ui(12.5).foregroundStyle(t.text2.color)
            }
            if let running { RunningChip(command: running, onStop: onStop) }
            Spacer(minLength: 8)
            // LAB-826: no informational shortcut text here; the keys are in the buttons' tooltips and the menus.
            if let onNewTerminal {
                Button(action: onNewTerminal) {
                    Label("Terminal", systemImage: "plus").labelStyle(.titleAndIcon).ui(11.5, .medium).foregroundStyle(t.text2.color)
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help("New terminal: a plain shell in this session's folder, shown here (⌘T opens one in your projects folder; right-click the terminal for more). Split this pane: ⌘D right, ⇧⌘D down")
                .accessibilityLabel("New terminal in this folder")
            }
            if let onTable {
                Button(action: onTable) {
                    HStack(spacing: 4) {
                        Image(systemName: table ? "checkmark" : "tablecells").font(.system(size: 9.5, weight: .bold))
                        Text("Table").ui(11.5, .medium)
                    }
                    .foregroundStyle(table ? t.text.color : t.text2.color)
                    .padding(.vertical, 2).padding(.horizontal, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(table ? t.surface.color : .clear))
                    .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color))
                    .contentShape(Rectangle())
                    .fixedSize()
                }
                .buttonStyle(.plain)
                .help(table ? "Back to the live terminal (Esc while the formatted view has the keyboard)"
                            : FormattedPaneView.tooltip)
                .accessibilityLabel(table ? "Table view on, back to the live terminal" : "Table view")
            }
            Button { NotificationCenter.default.post(name: .panelCommand, object: "focus") } label: { Image(systemName: "rectangle.inset.filled").font(.system(size: 11)).foregroundStyle(t.text2.color) }
                .buttonStyle(.plain).help("Focus: terminal only, both side panels hidden (⌥⌘F); again to bring them back")
                .accessibilityLabel("Focus terminal only")
            if split {
                Button(action: onZoom) { Text("⤢").ui(12).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                    .help("Maximize this pane ⇧⌘↩").accessibilityLabel("Maximize pane")
                Button(action: onClose) { Text("✕").ui(11).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                    .help("Close this pane ⌥⌘W; the session keeps running").accessibilityLabel("Close pane")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(t.terminal.paneHeader.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func meta(_ i: BoardItem) -> String {
        var parts = [i.account ?? i.session.agent.displayName]
        if let m = i.session.model, !m.isEmpty { parts.append(m.capitalized) }
        if let b = model.repoStats[i.session.repoPath]?.branch { parts.append(b) } else { parts.append(i.repoLabel) }
        return parts.joined(separator: " · ")
    }
}

/// One-line summary on the terminal (COMPONENTS SummaryStrip): dot, "Step n of m" + caption, "Summary ▾".
struct SummaryStrip: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem
    var onExpand: () -> Void

    var body: some View {
        let c = model.caption(for: item)
        HStack(spacing: 8) {
            StatusDot(status: item.status, size: 8)
            if let i = c.step, let n = c.steps {
                Text("Step \(i) of \(n)").ui(12.5, .semibold).foregroundStyle(t.text.color)
            }
            Text(c.step != nil ? "· " + c.text : c.text).ui(12.5).foregroundStyle(c.tone == .needs ? t.needsText.color : t.text2.color)
                .lineLimit(1).truncationMode(.tail).help(c.source)
            Spacer(minLength: 8)
            Button(action: onExpand) { Text("Summary ▾").ui(12).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                .accessibilityLabel("Expand summary")
        }
        .padding(.vertical, 8).padding(.horizontal, 14)
        .background(t.terminal.summaryStrip.color)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The expanded summary (COMPONENTS SummaryCard, S02 §1.2): you asked · right now · steps.
struct SummaryCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem
    var openChapter: Int? = nil
    var onChapter: (Int) -> Void = { _ in }
    var onCollapse: () -> Void

    var body: some View {
        let c = model.caption(for: item)
        let asked = item.session.openingMessage.isEmpty ? item.session.objective : item.session.openingMessage
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentBadge(item: item, size: 26, status: false)
                Text(item.session.name).ui(18, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text([item.account, item.session.model?.capitalized, item.repoLabel, item.session.ticket].compactMap { $0 }.joined(separator: " · "))
                    .ui(11.5, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
                Spacer()
                StatusPill(status: item.status, label: StatusPalette.label(item.status) + (item.session.launchedAt.map { " · " + ageText($0) } ?? ""))
                Button(action: onCollapse) { Text("▴").ui(12).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                    .accessibilityLabel("Collapse summary")
            }
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        MicroLabel("You asked" + (item.session.launchedAt.map { " · " + $0.formatted(date: .omitted, time: .shortened) } ?? ""))
                        Text(asked.isEmpty ? "—" : asked).ui(14).foregroundStyle(t.text.color).lineLimit(2, reservesSpace: true)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        let age = ageText(model.lastActiveDate(item))
                        MicroLabel(age.isEmpty ? "Right now" : "Right now · \(age) ago")
                        Text(c.now ?? c.text).ui(14, .medium).foregroundStyle(t.now.color).lineLimit(2, reservesSpace: true)
                            .animation(Motion.fast, value: c.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let steps = stepList(c)
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        MicroLabel(steps.isEmpty ? "Steps" : "Steps · \(c.step ?? 0) of \(c.steps ?? steps.count)")
                        Spacer()
                        if let open = openChapter {
                            Button { onChapter(open) } label: {
                                Label("Current", systemImage: "arrow.down.to.line").ui(11, .medium)
                            }
                            .buttonStyle(.plain).foregroundStyle(t.accent.color)
                            .help("Back to the current step, at the bottom of the terminal")
                        }
                    }
                    // LAB-1270: always the same height (Self.stepRows rows, scrolling past that), so a new step never
                    // moves the terminal below.
                    if steps.isEmpty {
                        Text("No steps yet").ui(13).foregroundStyle(t.text3.color)
                            .frame(maxWidth: .infinity, minHeight: StepList.height(rows: Self.stepRows),
                                   maxHeight: StepList.height(rows: Self.stepRows), alignment: .topLeading)
                    } else if usesChapters {
                        StepList(steps: steps, maxVisible: Self.stepRows, selected: openChapter, onTap: onChapter, fixedHeight: true)
                    } else {
                        StepList(steps: steps, maxVisible: Self.stepRows, fixedHeight: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 20)
        .background(t.surface.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// The steps are the terminal's chapters (not an objective's plan), so they can be rewound to and explained.
    private var usesChapters: Bool { !model.objectives.contains { $0.stepSessions.values.contains(item.id) && $0.plan != nil } }

    private func stepList(_ c: LiveCaption) -> [StepList.Step] {
        if let o = model.objectives.first(where: { $0.stepSessions.values.contains(item.id) }), let p = o.plan {
            let mine = o.stepSessions.first { $0.value == item.id }?.key
            return p.steps.enumerated().map { i, s in
                StepList.Step(id: i, title: s.title, note: nil, state: o.stepResults[s.id]?.ok == true ? .done : (s.id == mine ? .now : .todo))
            }
        }
        let chs = model.chapters[item.id] ?? []
        return chs.map { ch in
            let note = ch.ended.map { "\(ch.toolCalls) calls · " + CaptionEngine.ageText($0.timeIntervalSince(ch.started)) } ?? "in progress"
            return StepList.Step(id: ch.index, title: ch.title, note: note, state: ch.ended == nil ? .now : .done)
        }
    }

    /// LAB-1270: the open card is capped at about seven rows in all (header, then five steps beside you asked / right now).
    static let stepRows = 5
}

/// Shown while the terminal is rewound to a step (LAB-259): which step, and the way back to the live bottom.
struct RewindBar: View {
    @Environment(\.theme) private var t
    let chapter: Chapter
    var onCurrent: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 12, weight: .semibold)).foregroundStyle(t.accent.color)
            Text("Viewing step \(chapter.index + 1) · \(chapter.title)").ui(12.5).foregroundStyle(t.text2.color).lineLimit(1)
            Text("scroll to read on from here").ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
            Spacer()
            Button(action: onCurrent) { Label("Back to current", systemImage: "arrow.down.to.line").ui(12, .medium) }
                .buttonStyle(.plain).foregroundStyle(t.accent.color)
                .help("Scroll to the bottom: the step in progress now")
        }
        .padding(.vertical, 7).padding(.horizontal, 20)
        .background(t.terminal.background.color)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// LAB-825: the same way back as the RewindBar, floating at the bottom of the terminal while an earlier step is shown
/// and the terminal is not at its live bottom (where the eye is after scrolling on through the step).
struct BackToCurrentPill: View {
    @Environment(\.theme) private var t
    var onCurrent: () -> Void

    var body: some View {
        Button(action: onCurrent) {
            Label("Back to current", systemImage: "arrow.down.to.line").ui(12, .medium)
                .foregroundStyle(t.onAccent.color)
                .padding(.vertical, 6).padding(.horizontal, 14)
                .background(Capsule().fill(t.accent.color))
                .overlay(Capsule().strokeBorder(t.separatorStrong.color))
                .shadow(color: t.text.color.opacity(0.25), radius: 6, y: 2)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Scroll to the bottom: the step in progress now")
        .accessibilityLabel("Back to current step")
        .padding(.bottom, 12)
    }
}

/// LAB-861: the pane's keys go to a program, not the shell: "● running: npm run dev  Stop".
struct RunningChip: View {
    @Environment(\.theme) private var t
    let command: String
    var onStop: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(t.statusColor(.running).color).frame(width: 6, height: 6)
            Text("running:").ui(11, mono: true).foregroundStyle(t.text2.color).fixedSize()
            Text(command).ui(11, mono: true).foregroundStyle(t.text.color)
                .lineLimit(1).truncationMode(.middle).frame(minWidth: 40)
            if let onStop {
                Button(action: onStop) {
                    Text("Stop").ui(11, .semibold).foregroundStyle(t.needsText.color)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color))
                        .contentShape(Rectangle())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .help("Stop \(command): sends Ctrl-C (⌃C) to it, as if typed in the terminal")
                .accessibilityLabel("Stop \(command)")
            }
        }
        .padding(.leading, 7).padding(.trailing, onStop == nil ? 7 : 3).padding(.vertical, 2)
        .background(Capsule().fill(t.statusColor(.running).color.opacity(0.16)))
        .help("What you type in this terminal goes to \(command), not to the shell")
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Running \(command)")
    }
}

/// The approval card in a terminal pane (COMPONENTS ApprovalCard): title, risk, why, Allow once · Always allow · Deny ·
/// Reply. LAB-716: the question wraps (up to four lines, the rest in the tooltip); the buttons say what they do (the
/// mock's "y / a / n" letters were not shortcuts and read as gibberish), each with a tooltip; Always allow is left
/// out for a prompt One Roof does not recognise, since it cannot tell which key means "always" there.
struct ApprovalCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let decision: Decision
    @State private var replying = false
    @State private var reply = ""

    var body: some View {
        let title = decision.command.map { "Run " + $0 } ?? decision.headline
        let unread = decision.pattern.hasPrefix("ask:")
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).ui(13, .semibold, mono: decision.command != nil)
                    .foregroundStyle(t.text.color).lineLimit(4).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled).help(title)
                RiskPill(risk: decision.risk).fixedSize()
                Spacer(minLength: 0)
            }
            Text(decision.whyMissing ? "The agent did not say why. Use Reply… to ask it." : "Why: " + decision.why)
                .ui(12.5).foregroundStyle(t.text.color.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
            if !decision.touches.isEmpty {
                Text(decision.touches).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                key("Allow once", primary: true, help: "Yes, this time only: One Roof presses the agent's own \u{201C}yes\u{201D} key for you.") {
                    model.answer(decision, .allowOnce)
                }
                if !unread {
                    key("Always allow", help: "Yes, and the agent stops asking for this (its \u{201C}always\u{201D} / \u{201C}don't ask again\u{201D} option). One Roof also remembers it for \(decision.pattern) in \(decision.repo).") {
                        model.answer(decision, .always)
                        if model.settings.ui2 {   // v2: Undo on the terminal card for 5 s, as in Needs you (CAP-26)
                            let d = decision
                            let w = model.active.id   // the window whose card was clicked
                            model.v2UndoRule = (d, w)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if model.v2UndoRule?.decision == d { model.v2UndoRule = nil } }
                        }
                    }
                }
                key("Deny", help: "No: the agent does not do it and waits for what you say next.") { model.answer(decision, .deny) }
                if replying {
                    TextField("Instructions for the agent", text: $reply, onCommit: { model.answer(decision, .reply, reply: reply) })
                        .textFieldStyle(.plain).ui(12.5).padding(.horizontal, 8).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.surface.color))
                } else {
                    Button { replying = true } label: { Text("Reply…").ui(12.5).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                        .help("No, and tell the agent what to do instead: type it and press Return.")
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.statusColor(.needsYou).color.opacity(0.12)))
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.terminal.background.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.statusColor(.needsYou).color, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decision: \(decision.headline)")
    }

    private func key(_ label: String, primary: Bool = false, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).fontWeight(.semibold)
                .ui(12.5)
                .foregroundStyle(primary ? AgentMark.ink.color : t.text.color)
                .padding(.vertical, 5).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(primary ? t.text.color : t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color))
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(label)
        .accessibilityHint(help)
    }
}

/// Risk pill (tokens.json `risk`: low = done, plan = scheduled, high = needs).
struct RiskPill: View {
    @Environment(\.theme) private var t
    let risk: Risk
    var body: some View {
        let s: PillStyle = {
            switch risk {
            case .low: return t.pill(.done)
            case .plan: return StatusPalette.scheduledPill(theme: t.name)
            case .high: return t.pill(.needsYou)
            }
        }()
        Text(risk == .low ? "Low risk" : risk == .plan ? "Plan" : "High risk").ui(10.5, .semibold)
            .foregroundStyle(s.text.color)
            .padding(.vertical, 1).padding(.horizontal, 7)
            .background(Capsule().fill((s.fill ?? t.surface).color))
            .fixedSize()
    }
}

/// The strip under an agent's terminal (S02 §1.5): hints only; the CLI's own prompt stays in the terminal.
struct HintStrip: View {
    @Environment(\.theme) private var t
    let item: BoardItem
    var raw: Bool
    var onRaw: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("❯").ui(12).foregroundStyle(t.accentText.color)
            Text("Message \(item.account ?? item.session.agent.displayName) · ⌃↩ run as shell · @ file · / skill · ⌘. interrupt")
                .ui(12.5).foregroundStyle(t.text3.color).lineLimit(1)
            Spacer()
            Button(action: onRaw) {
                Text(raw ? "Chapters ⌘R" : "Raw stream ⌘R").ui(11, mono: true).foregroundStyle(t.text2.color)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(t.surface2.color))
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.separatorStrong.color).padding(.horizontal, 12).padding(.vertical, 4))
        .frame(height: 46)
        .background(t.terminal.background.color)
    }
}

/// LAB-299: over a just-launched agent's live terminal, until the agent is up (the login shell runs first, then the
/// CLI draws). The terminal itself is already there and takes typing.
struct StartingStrip: View {
    @Environment(\.theme) private var t
    let item: BoardItem

    /// Starting (roofd has the session, the agent is not in the foreground yet), or seen but not ready in its first 8 s.
    static func shows(_ item: BoardItem, now: Date = Date()) -> Bool {
        guard item.session.agent.isAgent else { return false }
        if item.starting { return true }
        return !item.ready && item.session.launchedAt.map { now.timeIntervalSince($0) < 8 } == true
    }

    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                ProgressView().controlSize(.mini)
                Text(item.starting ? "Starting \(item.session.agent.displayName)… your login shell runs first"
                                   : "\(item.session.agent.displayName) is starting…")
                    .ui(12).foregroundStyle(t.text2.color).lineLimit(1)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Capsule().fill(t.surface.color))
            .overlay(Capsule().strokeBorder(t.separatorStrong.color))
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(item.session.agent.displayName) is starting")
        }
        .padding(.horizontal, 16).padding(.bottom, 10)
    }
}

/// Placeholder states with no surface (S02 §1.6): Planned/Next, Exited, Scheduled, popped out, empty pane.
struct PanePlaceholder: View {
    @Environment(\.theme) private var t
    let item: BoardItem?
    @ObservedObject var model: AppModel
    var emptyPane = false
    /// LAB-745: start a plain terminal from the centre.
    var onNewTerminal: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            if emptyPane {
                Text("Empty pane").ui(18, .semibold).foregroundStyle(t.text.color)
                Text("Pick a session to show it here, or ⌘T for a new terminal.").ui(13).foregroundStyle(t.text2.color)
                if let onNewTerminal { RoofButton("New terminal", .primary, action: onNewTerminal).help("A plain shell in your projects folder, shown in this pane (⌘T)") }
            } else if let item, let agent = item.liveAgent, model.poppedOut.contains(agent) {
                Text("Open in its own window").ui(18, .semibold).foregroundStyle(t.text.color)
                HStack {
                    RoofButton("Show window") { PopOutWindowController.popOut(item, model: model) }
                    RoofButton("Bring back here", .primary) { PopOutWindowController.bringBack(agent) }
                }
            } else if let item {
                if let time = model.schedules[item.id] {
                    Text("Runs tonight at \(time)").ui(18, .semibold).foregroundStyle(t.text.color)
                    Text(item.session.name).ui(13).foregroundStyle(t.text2.color)
                    HStack {
                        RoofButton("Run now", .primary) { model.unschedule(item); model.launch(item) }
                        RoofButton("Change schedule") { model.unschedule(item) }
                    }
                } else if item.starting || model.busy.contains(item.id) {
                    ProgressView().controlSize(.small)
                    Text(item.session.agent.isAgent ? "Starting \(item.session.agent.displayName)…" : "Starting the terminal…")
                        .ui(18, .semibold).foregroundStyle(t.text.color)
                    Text(item.session.name).ui(13).foregroundStyle(t.text2.color)
                } else if item.status == .exited {
                    Text("This agent has exited").ui(18, .semibold).foregroundStyle(t.text.color)
                    Text(item.session.name).ui(13).foregroundStyle(t.text2.color)
                    if !item.session.objective.isEmpty {
                        Text(item.session.objective).ui(12.5).foregroundStyle(t.text3.color).multilineTextAlignment(.center).frame(maxWidth: 440)
                    }
                    HStack {
                        RoofButton("Relaunch", .primary) { model.launch(item) }
                        // Only this session's own handoff, named for what it is (LAB-250); none → no button.
                        if let h = model.handoffMatch(for: item) {
                            RoofButton("Open \(h.key) handoff") { model.openInViewer(h.path) }
                        }
                    }
                } else if item.status == .doNotUse {
                    Text("Parked · do not use").ui(18, .semibold).foregroundStyle(t.text.color)
                    RoofButton("Use again") { model.toggleSticker(item, "dnu") }
                } else {
                    Text("Not started yet").ui(18, .semibold).foregroundStyle(t.text.color)
                    Text(item.session.name).ui(13).foregroundStyle(t.text2.color)
                    if !item.session.objective.isEmpty {
                        Text(item.session.objective).ui(12.5).foregroundStyle(t.text3.color).multilineTextAlignment(.center).frame(maxWidth: 440)
                    }
                    if model.busy.contains(item.id) {
                        ProgressView("Starting \(item.session.agent.displayName)…").controlSize(.small)
                    } else {
                        RoofButton("Launch \(item.session.agent.displayName)", .primary) { model.launch(item) }
                            .keyboardShortcut(.return, modifiers: .command)
                    }
                }
            } else {
                Text("One Roof").ui(22, .semibold).foregroundStyle(t.text.color)
                Text("Pick a session, or press ⌘N for a new one.").ui(13).foregroundStyle(t.text2.color)
                if let onNewTerminal { RoofButton("New terminal", action: onNewTerminal).help("A plain shell in your projects folder, shown here (⌘T)") }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(t.terminal.background.color)
    }
}

/// The Subagents column beside the terminal when the Plan panel is closed (S02 §1.7), and its list in the Plan panel.
struct SubagentList: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem
    var onTrace: () -> Void

    var body: some View {
        let subs = model.subagents[item.id] ?? []
        let running = subs.filter { $0.ended == nil }.count
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Subagents").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("\(subs.count) · \(running) running").ui(12).foregroundStyle(t.text3.color)
                Spacer()
                Button(action: onTrace) { Text("Trace ▸").ui(12).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
            }
            if subs.isEmpty {
                Text(item.session.agent == .claude ? "No subagents yet." : "Subagents are read from Claude transcripts; other agents show inferred children only.")
                    .ui(12.5).foregroundStyle(t.text3.color)
            }
            ForEach(subs, id: \.id) { s in SubagentCard(sub: s).padding(.leading, CGFloat(s.depth) * 16) }
            let touched = Dictionary(subs.flatMap(\.touched).map { ($0.path, $0) }, uniquingKeysWith: { a, b in
                FileTouch(path: a.path, added: a.added + b.added, removed: a.removed + b.removed, read: a.read && b.read) })
            if !touched.isEmpty {
                Spacer(minLength: 8)
                MicroLabel("Files touched")
                ForEach(touched.values.sorted { $0.path < $1.path }, id: \.path) { f in
                    Button { model.openInViewer(f.path) } label: {
                        HStack {
                            Text((f.path as NSString).lastPathComponent).ui(12, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                            Spacer()
                            if f.read && f.added + f.removed == 0 { Text("read").ui(11.5, mono: true).foregroundStyle(t.text3.color) }
                            if f.added > 0 { Text("+\(f.added)").ui(11.5, mono: true).foregroundStyle(t.diffAddText.color) }
                            if f.removed > 0 { Text("−\(f.removed)").ui(11.5, mono: true).foregroundStyle(t.diffDelText.color) }
                        }
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// A subagent (COMPONENTS SubagentCard): dot, name, model, tokens · time, asked, caption.
struct SubagentCard: View {
    @Environment(\.theme) private var t
    let sub: Subagent

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill((sub.ended == nil ? t.now : t.statusColor(.done)).color).frame(width: 7, height: 7)
                Text(sub.name).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                Text(sub.model).ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
                if sub.inferred { Text("inferred").ui(10.5).foregroundStyle(t.text3.color) }
                Spacer()
                Text("\(Self.tokens(sub.tokens)) · \(ageText(sub.started, now: sub.ended ?? Date()))").ui(11.5, mono: true).foregroundStyle(t.text3.color)
            }
            if !sub.asked.isEmpty { Text("Asked: " + sub.asked).ui(12).foregroundStyle(t.text2.color).lineLimit(2) }
            Text(SubagentDetail.summary(sub).text).ui(13).foregroundStyle(t.text.color).lineLimit(3)   // LAB-695
        }
        .padding(.vertical, 11).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
    }

    static func tokens(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }
}

extension AppModel {
    /// Exited placeholder › Open … handoff: the newest handoff written during this session (LAB-510) naming one of its issues or its project, and the
    /// id it named (the button says which), else none.
    func handoffMatch(for item: BoardItem) -> (path: String, key: String)? {
        Workspace.handoffMatch(in: settings.sharedFolder + "/docs/next-session-handoff",
                               project: item.session.workstream, tickets: item.session.allTickets.map(\.key),
                               since: item.session.launchedAt ?? item.session.createdAt)
    }
}

/// Step review in the right panel (LAB-260): a model's reading of one step of the selected session (what was asked,
/// what happened, decisions, risks). It follows the step the terminal is rewound to; otherwise it is the latest finished
/// step. It is read on its own, without a click, once per step.
struct StepReviewSection: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let item: BoardItem

    var body: some View {
        let on = model.settings.stepReview
        let chs = (model.chapters[item.id] ?? []).filter { $0.ended != nil }
        let picked = model.reviewStep[item.id].flatMap { i in chs.first { $0.index == i } }
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("Step review").ui(12, .semibold).foregroundStyle(t.text2.color)
                if on, !chs.isEmpty {
                    Text(picked == nil ? "latest" : "selected").ui(10.5, .medium).foregroundStyle(t.text3.color)
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(t.control.color))
                }
                Spacer()
                Toggle("", isOn: $model.settings.stepReview).toggleStyle(.switch).controlSize(.mini).labelsHidden()
                    .help(on ? "Turn off: no more model calls for step reviews" : "Turn on: Claude reads each step (one model call per step)")
                    .accessibilityLabel("Step review")
            }
            if !on {
                // Off by default: say what turning it on costs (owner, LAB-260).
                Text("Off. Turn it on to have Claude (\(StepExplainer.model)) read each finished step and say what was asked, what happened, the decisions and the risks. Each step it reviews is one more model call on your Claude account, so it is off until you want it.")
                    .ui(11.5).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
            } else if let ch = picked ?? chs.last {
                reviewBody(ch, picked: picked != nil)
            } else {
                Text("No finished step yet.").ui(11.5).foregroundStyle(t.text3.color)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separator.color))
    }

    @ViewBuilder private func reviewBody(_ ch: Chapter, picked: Bool) -> some View {
        let key = AppModel.stepKey(item, ch)
        let state = model.stepExplanations[key]
        HStack(spacing: 6) {
            Text("Step \(ch.index + 1) · \(ch.title)").ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(2)
            Spacer()
            if picked {
                Button("Latest") { model.reviewStep[item.id] = nil }.buttonStyle(.plain).ui(11, .medium)
                    .foregroundStyle(t.accent.color).help("Review the latest finished step")
            }
            Button { model.explainStep(item, ch) } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
                .buttonStyle(.plain).foregroundStyle(t.text3.color).help("Read this step again (one more model call)")
                .disabled(state == .working)
        }
        Group {
            switch state {
            case .done(let e)?:
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        part("What was asked", e.question)
                        part("What happened", e.happened)
                        part("Decisions", e.decisions)
                        part("Risks", e.risks)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 6)
                }
                .frame(height: 230)
            case .failed(let why)?:
                Text(why).ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true)
            default:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Reading the step…").ui(12).foregroundStyle(t.text2.color)
                }
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            }
        }
        .task(id: key) { if model.stepExplanations[key] == nil { model.explainStep(item, ch) } }
        Text("By Claude (\(StepExplainer.model)) from the terminal text, one call per step. Click a step above the terminal to review it.")
            .ui(10.5).foregroundStyle(t.text3.color).fixedSize(horizontal: false, vertical: true)
    }

    private func part(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title.uppercased()).ui(9.5, .semibold).tracking(0.6).foregroundStyle(t.text3.color)
            Text(.init(body.isEmpty ? "None" : body)).ui(12.5).foregroundStyle(t.text.color)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }
}
