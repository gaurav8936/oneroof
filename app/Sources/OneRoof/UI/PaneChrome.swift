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

    var body: some View {
        let term = model.themes.terminal.tokens
        VStack(spacing: 0) {
            PaneHeader(model: model, item: item, focused: focused, split: split, onZoom: onZoom, onClose: onClose)
            if let item, item.session.agent.isAgent, item.liveAgent != nil {
                if expanded {
                    SummaryCard(model: model, item: item, onCollapse: onToggleSummary)
                        .themed(model.themes.centre)
                } else {
                    SummaryStrip(model: model, item: item, onExpand: onToggleSummary)
                }
                if !raw {
                    let chs = (model.chapters[item.id] ?? []).filter { $0.ended != nil }
                    ForEach(chs.suffix(expanded ? 3 : 2), id: \.index) { c in
                        ChapterRow(chapter: c, open: openChapter == c.index) { onChapter(c.index) }
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

    var body: some View {
        HStack(spacing: 8) {
            if let item {
                AgentBadge(item: item, size: 18, status: false)
                Text(item.session.name).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
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
            Spacer(minLength: 8)
            Text("⌘D ⇧⌘D ⇧⌘↩").ui(11, mono: true).foregroundStyle(t.text3.color).lineLimit(1)
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
                        Text(asked.isEmpty ? "—" : asked).ui(14).foregroundStyle(t.text.color).lineLimit(3)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        let age = ageText(model.lastActiveDate(item))
                        MicroLabel(age.isEmpty ? "Right now" : "Right now · \(age) ago")
                        Text(c.now ?? c.text).ui(14, .medium).foregroundStyle(t.now.color).lineLimit(2)
                            .animation(Motion.fast, value: c.text)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                let steps = stepList(c)
                if !steps.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        MicroLabel("Steps · \(c.step ?? 0) of \(c.steps ?? steps.count)")
                        StepList(steps: steps)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, 16).padding(.horizontal, 20)
        .background(t.surface.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func stepList(_ c: LiveCaption) -> [StepList.Step] {
        if let o = model.objectives.first(where: { $0.stepSessions.values.contains(item.id) }), let p = o.plan {
            let mine = o.stepSessions.first { $0.value == item.id }?.key
            return p.steps.enumerated().map { i, s in
                StepList.Step(id: i, title: s.title, note: nil, state: o.stepResults[s.id]?.ok == true ? .done : (s.id == mine ? .now : .todo))
            }
        }
        let chs = model.chapters[item.id] ?? []
        return chs.map { ch in StepList.Step(id: ch.index, title: ch.title, note: ch.ended == nil ? "in progress" : nil,
                                             state: ch.ended == nil ? .now : .done) }
    }
}

/// A finished step over the scrollback (COMPONENTS ChapterRow): ✓ · "n · Title" · summary · calls · duration.
struct ChapterRow: View {
    @Environment(\.theme) private var t
    let chapter: Chapter
    let open: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Text("✓").ui(13, .semibold).foregroundStyle(t.statusColor(.done).color).frame(width: 22)
                (Text("\(chapter.index + 1) · \(chapter.title)").foregroundColor(t.text.color).fontWeight(.semibold)
                 + Text(chapter.summary.isEmpty ? "" : " · " + chapter.summary).foregroundColor(t.text2.color))
                    .ui(13).lineLimit(1)
                Spacer()
                Text("\(chapter.toolCalls) calls · \(duration) \(open ? "▾" : "▸")").ui(11.5, mono: true).foregroundStyle(t.text3.color)
            }
            .padding(.vertical, 9).padding(.horizontal, 20)
            .background(t.terminal.background.color)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Chapter \(chapter.index + 1), \(chapter.title), \(chapter.toolCalls) calls")
    }

    private var duration: String {
        guard let e = chapter.ended else { return "" }
        return CaptionEngine.ageText(e.timeIntervalSince(chapter.started))
    }
}

/// The approval card in a terminal pane (COMPONENTS ApprovalCard): title, risk, why, Allow y · Always a · Deny n · Reply.
struct ApprovalCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    let decision: Decision
    @State private var replying = false
    @State private var reply = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(decision.command.map { "Run " + $0 } ?? decision.headline).ui(13, .semibold, mono: decision.command != nil)
                    .foregroundStyle(t.text.color).lineLimit(1)
                RiskPill(risk: decision.risk)
                Spacer()
            }
            Text((decision.whyMissing ? "" : "Why: ") + decision.why + (decision.touches.isEmpty ? "" : "\n" + decision.touches))
                .ui(12.5).foregroundStyle(t.text.color.opacity(0.92)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                key("Allow", "y", primary: true) { model.answer(decision, .allowOnce) }
                key("Always", "a") { model.answer(decision, .always) }
                key("Deny", "n") { model.answer(decision, .deny) }
                if replying {
                    TextField("Instructions for the agent", text: $reply, onCommit: { model.answer(decision, .reply, reply: reply) })
                        .textFieldStyle(.plain).ui(12.5).padding(.horizontal, 8).frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 6).fill(t.surface.color))
                } else {
                    Button { replying = true } label: { Text("Reply…").ui(12.5).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
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

    private func key(_ label: String, _ k: String, primary: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            (Text(label + " ").fontWeight(.semibold) + Text(k).font(.system(size: 11, design: .monospaced)))
                .ui(12.5)
                .foregroundStyle(primary ? AgentMark.ink.color : t.text.color)
                .padding(.vertical, 5).padding(.horizontal, 10)
                .background(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).fill(primary ? t.text.color : t.surface.color))
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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

/// Placeholder states with no surface (S02 §1.6): Planned/Next, Exited, Scheduled, popped out, empty pane.
struct PanePlaceholder: View {
    @Environment(\.theme) private var t
    let item: BoardItem?
    @ObservedObject var model: AppModel
    var emptyPane = false

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            if emptyPane {
                Text("Empty pane").ui(18, .semibold).foregroundStyle(t.text.color)
                Text("Pick a session to show it here, or ⌘T for a new terminal.").ui(13).foregroundStyle(t.text2.color)
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
                        RoofButton("Open handoff") { model.openLatestHandoff(item) }
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
            Text(sub.caption.isEmpty ? "no caption yet" : sub.caption).ui(13).foregroundStyle(t.text.color).lineLimit(3)
        }
        .padding(.vertical, 11).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separator.color))
    }

    static func tokens(_ n: Int) -> String { n >= 1000 ? String(format: "%.1fk", Double(n) / 1000) : "\(n)" }
}

extension AppModel {
    /// Exited placeholder › Open handoff: the newest handoff naming the session's workstream, else the folder.
    func openLatestHandoff(_ item: BoardItem) {
        let dir = settings.sharedFolder + "/docs/next-session-handoff"
        guard Workspace.folderExists(dir) else {
            lastError = "No handoffs folder at \(dir.replacingOccurrences(of: NSHomeDirectory(), with: "~")). Set the shared folder in Settings › Foundations."
            return
        }
        let files = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
        let ws = item.session.workstream?.lowercased()
        if let f = files.last(where: { ws != nil && $0.lowercased().contains(ws!) }) ?? files.last { openInViewer(dir + "/" + f) }
        else { openInViewer(dir) }
    }
}
