import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OneRoofCore

// LAB-2042 · LAB-2043 · the Inbox (⌘I, ⌃⌘2): the v2 window's live place, replacing Needs you's queue + detail. A
// column of dark, terminal-style blocks, one per session that needs you (then plans, then loop items), newest at the
// top. Each block shows only the current ask, answered in place: every option the prompt shows, a multi-line reply
// with pasted or dropped images, Open session. The rules live in OneRoofCore/Inbox.swift; this file only draws them.
// The classic window keeps DecisionsView.

extension AppModel {
    /// The Inbox's blocks as the page shows them (also the self-test's `needs` / `needspick`).
    var inboxLayout: InboxLayout {
        let open = openDecisions
        let asking = Set(open.filter { !$0.isFinished }.map(\.sessionId))
        let waiting = sessionItems.filter { $0.status == .needsYou && $0.liveAgent != nil && !asking.contains($0.id) }.map(\.id)
        return Inbox.layout(open: open,
                            plans: objectives.filter { $0.status == .review && $0.plan != nil }.map { ($0.id, $0.createdAt) },
                            loops: loopInbox.map { ($0.id, $0.when) }, waiting: waiting)
    }

    /// What you answered whose session is still alive, newest first (LAB-1831), with the self-test's answered asks.
    var inboxDecided: [Decision] {
        let real = ScrollFeed.decided(decisions) { item($0) }
        guard !selfTestDecisions.isEmpty else { return real }
        return (real + selfTestDecisions.filter { !$0.isOpen }).sorted { ($0.answeredAt ?? $0.askedAt) > ($1.answeredAt ?? $1.askedAt) }
    }

    var inboxDecidedToday: Int {
        (decisions + selfTestDecisions).filter { !$0.isOpen && Calendar.current.isDateInToday($0.answeredAt ?? .distantPast) }.count
    }
}

/// Drafts of the reply boxes (text, attached images, a refused-image note), kept while One Roof runs, per block.
@MainActor final class InboxDrafts: ObservableObject {
    static let shared = InboxDrafts()
    @Published var text: [String: String] = [:]
    @Published var images: [String: [String]] = [:]
    @Published var note: [String: String] = [:]
    @Published var height: [String: CGFloat] = [:]
    /// The block whose reply box should take the keyboard (set, then cleared by the box).
    @Published var focusRequest: String?
    /// The block whose box has the keyboard now.
    @Published var editing: String?

    func attach(_ key: String, _ paths: [String]) {
        let r = Inbox.accept(paths, existing: images[key] ?? []) { p in
            ((try? FileManager.default.attributesOfItem(atPath: p))?[.size] as? NSNumber)?.intValue ?? 0
        }
        images[key] = r.images
        note[key] = r.note
    }

    func clear(_ key: String) { text[key] = nil; images[key] = nil; note[key] = nil; height[key] = nil }
}

extension Notification.Name {
    /// Self-test: ["attach": <png path>] attaches to the focused block; ["decided": true] opens Decided; ["reply": text]
    /// types into the focused block's box and sends it; ["press": n] presses its option n.
    static let inboxSelfTest = Notification.Name("oneroof.inbox.selftest")
}

struct V2InboxPage: View {
    @ObservedObject var engineState = EngineState.shared
    @ObservedObject private var loopInbox = LoopInboxState.shared
    @ObservedObject private var drafts = InboxDrafts.shared
    @Environment(\.theme) private var t
    @Environment(\.textScale) private var scale
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    @State private var focused: String?
    @State private var details: Set<UUID> = []
    @State private var showAll: Set<UUID> = []
    @State private var failed: [String: String] = [:]
    @State private var undoRule: Decision?
    /// A block that just left (answered here or in its terminal): shown folded for 1.5 s, where it was.
    struct Ghost: Equatable { var block: InboxBlock; var index: Int; var line: String }
    @State private var ghosts: [String: Ghost] = [:]
    @State private var lastBlocks: [InboxBlock] = []
    @State private var newAbove = 0
    @FocusState private var keys: Bool

    private static let blockWidth: CGFloat = 1180
    /// LAB-2109: the session card left of each block.
    static let cardWidth: CGFloat = 200

    var body: some View {
        // LAB-2110: two tabs — Inbox (only what waits on you now) and Decided (the one paged record). The Action log is
        // gone: its Decisions are Decided, its Rules are in Settings › Permissions.
        Group {
            if win.inboxTab == .decided {
                VStack(spacing: 0) {
                    header(count: model.needsYouBadge, quiet: 0)
                    V2DecidedList(model: model, win: win)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(t.window.color)
            } else { page }
        }
        .onDisappear { win.inboxTab = .inbox }
    }

    // MARK: Page

    private var page: some View {
        let layout = model.inboxLayout
        let decided = model.inboxDecided
        let n = model.needsYouBadge
        let quiet = Inbox.quietCount(liveSessions: model.sessionItems.filter { $0.liveAgent != nil }.map(\.id), shown: layout.all)
        let asks = withGhosts(layout.asks)
        return VStack(spacing: 0) {
            header(count: n, quiet: quiet)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        Color.clear.frame(height: 0).id("inbox-top")
                        if layout.all.isEmpty && ghosts.isEmpty {
                            if loading { loadingState } else { emptyState }
                        }
                        ForEach(asks, id: \.block.id) { e in row(e.block, ghost: e.ghost) }
                        if !layout.loops.isEmpty {
                            MicroLabel("Loops · Today · \(layout.loops.count)").padding(.top, asks.isEmpty ? 0 : 8).padding(.leading, 2)
                            ForEach(layout.loops) { b in row(b, ghost: nil) }
                        }
                        Color.clear.frame(height: 24)
                    }
                    .frame(maxWidth: Self.blockWidth, alignment: .leading)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: focused) { _, id in
                    guard let id else { return }
                    withAnimation(Motion.fast) { proxy.scrollTo(id) }
                    if id == layout.all.first?.id { newAbove = 0 }
                }
                .onChange(of: layout.all.map(\.id)) { _, _ in track(layout.all) }
                .onChange(of: model.needsPick) { _, id in pick(id, layout: layout, decided: decided) }
                .overlay(alignment: .top) {
                    if newAbove > 0 {
                        Button { newAbove = 0; focused = layout.all.first?.id; withAnimation(Motion.base) { proxy.scrollTo("inbox-top", anchor: .top) } } label: {
                            Text(Inbox.newAboveLine(newAbove)).ui(12, .semibold).foregroundStyle(t.onAccent.color)
                                .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(t.accent.color))
                        }
                        .buttonStyle(.plain).padding(.top, 8)
                        .accessibilityLabel(Inbox.newAboveLine(newAbove).replacingOccurrences(of: " ↑", with: ""))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(t.window.color)
        .overlay(alignment: .bottom) { if let u = undoRule { undoToast(u) } }
        .focusable()
        .focusEffectDisabled()
        .focused($keys)
        .onKeyPress(phases: .down) { k in key(k, layout: layout) }
        .background(shortcuts(layout))
        .onAppear {
            lastBlocks = layout.all
            if focused == nil { focused = layout.all.first?.id }
            DispatchQueue.main.async { if drafts.editing == nil { keys = true } }
            if let id = model.needsPick { pick(id, layout: layout, decided: decided) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .inboxSelfTest)) { n in
            if let p = (n.object as? [String: Any])?["attach"] as? String, let id = focused ?? layout.all.first?.id { drafts.attach(id, [p]) }
            if (n.object as? [String: Any])?["decided"] as? Bool == true { win.inboxTab = .decided }
            if let b = current(layout) {
                if let text = (n.object as? [String: Any])?["reply"] as? String { drafts.text[b.id] = text; sendBox(b) }
                if let k = (n.object as? [String: Any])?["press"] as? Int, let d = b.decision,
                   let btn = Inbox.numbered(k, in: Inbox.buttons(d, repo: d.repo)) { press(btn, b) }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Inbox: \(Inbox.waitingLine(n))")
    }

    private var loading: Bool { !model.runtimeOK && model.runtimeState.hasPrefix("Connecting") }

    /// ⌘] / ⌘[ next / previous, ⌘↩ open: key equivalents (never taken from a reply box, which has no use for them).
    private func shortcuts(_ layout: InboxLayout) -> some View {
        ZStack {
            Button("") { move(1, layout) }.keyboardShortcut("]", modifiers: .command)
            Button("") { move(-1, layout) }.keyboardShortcut("[", modifiers: .command)
            Button("") { if let b = current(layout) { open(b) } }.keyboardShortcut(.return, modifiers: .command)
        }
        .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }

    // MARK: Header

    private func header(count n: Int, quiet: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Inbox").ui(24, .semibold).foregroundStyle(t.text.color).accessibilityAddTraits(.isHeader)
                    if n > 0 { Text("\(n)").ui(24, .regular).foregroundStyle(t.text3.color) }
                }
                HStack(spacing: 0) {
                    Text(Inbox.waitingLine(n)).ui(13).foregroundStyle(t.text2.color)
                    if let o = Inbox.othersLine(quiet) {
                        Text(" · ").ui(13).foregroundStyle(t.text3.color)
                        Button { win.open(.sessions) } label: { Text(o).ui(13).foregroundStyle(t.accentText.color) }
                            .buttonStyle(.plain).help("Open Sessions")
                    }
                }
            }
            Spacer()
            tabBar.padding(.top, 4)
        }
        .frame(maxWidth: Self.blockWidth)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
        .frame(maxWidth: .infinity)
        .background(t.window.color)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// LAB-2110: the place's tabs, pinned in the header: Inbox (the count waiting) · Decided (today's count). ⇧⌘I opens
    /// Decided from anywhere (View › Decided); ⌘⌥← / ⌘⌥→ switch tabs here.
    private var tabBar: some View {
        let n = model.needsYouBadge, today = model.inboxDecidedToday
        return HStack(spacing: 2) {
            tabButton(n > 0 ? "Inbox · \(n)" : "Inbox", .inbox, help: "Only what waits on you now")
            tabButton(Decided.tabTitle(today: today), .decided, help: "What you decided, newest first (⇧⌘I)")
        }
        .padding(2)
        .background(Capsule().fill(t.card.color))
        .overlay(Capsule().strokeBorder(t.separatorStrong.color))
        .background(tabKeys)
        .fixedSize()
    }

    private func tabButton(_ title: String, _ tab: InboxTab, help: String) -> some View {
        let on = win.inboxTab == tab
        return Button { win.inboxTab = tab } label: {
            Text(title).ui(12.5, on ? .semibold : .regular).foregroundStyle(on ? t.accentText.color : t.text2.color)
                .padding(.horizontal, 12).frame(height: 26)
                .background(Capsule().fill(on ? t.selection.color : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
    }

    private var tabKeys: some View {
        ZStack {
            Button("") { win.inboxTab = .inbox }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
            Button("") { win.inboxTab = .decided }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        }
        .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }

    // MARK: States

    private var loadingState: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Reading your sessions…").ui(13).foregroundStyle(t.text2.color)
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }

    private var emptyState: some View {
        let working = model.sessionItems.filter { $0.liveAgent != nil }.count
        return VStack(spacing: 8) {
            Text("Nothing waits on you.").ui(20, .semibold).foregroundStyle(t.text.color)
            Text(working == 0 ? "When an agent asks you something, it shows up here, ready to answer."
                 : "\(working) session\(working == 1 ? "" : "s") working. When one asks you something, it shows up here.")
                .ui(13.5).foregroundStyle(t.text2.color)
            HStack(spacing: 0) {
                Text("\(model.inboxDecidedToday) decided today · ").ui(12).foregroundStyle(t.text3.color)
                Button { win.inboxTab = .decided } label: { Text("Decided ›").ui(12).foregroundStyle(t.accentText.color) }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity).padding(.top, 120)
    }

    // MARK: Blocks

    @ViewBuilder private func row(_ b: InboxBlock, ghost: Ghost?) -> some View {
        let critical = ghost == nil && InboxUrgency.of(b) == .critical
        let hue = b.sessionId.map { SessionHue(sessionId: $0, on: t) }
        HStack(alignment: .top, spacing: 10) {
            V2InboxSessionCard(model: model, block: b, hue: hue, loopTitle: loopInbox.items.first { $0.id == b.loopItemId }?.loopTitle)
                .frame(width: Self.cardWidth)
            // LAB-2112: a critical ask (the agent is blocked until you act) gets a bold red border; LAB-2109: the others
            // carry their session's colour on the edge.
            InboxBlockFrame(focused: focused == b.id && ghost == nil, edge: critical ? t.needsText : (hue?.ink ?? t.separatorStrong),
                            ring: t.accent, scale: scale, lineWidth: critical ? 3 : 1.5) {
            VStack(alignment: .leading, spacing: 0) {
                strip(b, critical: critical)
                VStack(alignment: .leading, spacing: 12) {
                    if let g = ghost {
                        Text(g.line).ui(13, .semibold).foregroundStyle(Self.mt.text.color)
                    } else {
                        content(b)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
            }
            }
        }
        .id(b.id)
        .contentShape(Rectangle())
        .onTapGesture { focused = b.id; if drafts.editing == nil { keys = true } }
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            guard let d = b.decision, Inbox.placeholder(d, agentName: who(d)) != nil, !d.agent.isHosted else { return false }
            return drop(providers, into: b.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label(b))
        .transition(.opacity)
    }

    /// Midnight's tokens: blocks are dark in every theme (owner: "dark, terminal-like").
    static let mt = ThemeName.midnight.tokens

    private func who(_ d: Decision) -> String {
        model.item(d.sessionId).map { $0.account ?? $0.session.agent.displayName } ?? d.agent.displayName
    }

    private func label(_ b: InboxBlock) -> String {
        switch b.kind {
        case .plan:
            let o = model.objectives.first { $0.id == b.planId }
            return Inbox.accessibilityLabel(session: o?.title ?? "Plan", kind: .plan, at: b.at, ask: "Approve a \(o?.plan?.steps.count ?? 0)-step plan")
        case .loop:
            let i = loopInbox.items.first { $0.id == b.loopItemId }
            return Inbox.accessibilityLabel(session: "Loop " + (i?.loopTitle ?? ""), kind: .loop, at: b.at, ask: i?.headline ?? "")
        default:
            let name = b.sessionId.flatMap { model.item($0)?.session.name } ?? "Session"
            return Inbox.accessibilityLabel(session: name, kind: b.kind, at: b.at, ask: b.decision.map(ScrollFeed.askText) ?? "Waiting for you")
        }
    }

    /// The 32 pt header strip: badge, name, context, kind tag · age, Open session ↗ ⌘↩.
    private func strip(_ b: InboxBlock, critical: Bool = false) -> some View {
        let m = Self.mt
        return HStack(spacing: 8) {
            switch b.kind {
            case .plan:
                let o = model.objectives.first { $0.id == b.planId }
                AgentBadge(AgentMark.claude1, size: 20)
                Text("Planner").ui(13, .semibold).foregroundStyle(m.text.color).accessibilityAddTraits(.isHeader)
                Text("· " + (o.map { Workspace.repoLabel(for: $0.repoPath) } ?? "")).ui(12).foregroundStyle(m.text2.color).lineLimit(1)
            case .loop:
                let i = loopInbox.items.first { $0.id == b.loopItemId }
                Text("↻").ui(13, .semibold).foregroundStyle(m.accentText.color).frame(width: 20, height: 20)
                    .background(RoundedRectangle(cornerRadius: Radius.squircle20, style: .continuous).fill(m.surface.color)).accessibilityHidden(true)
                Text(i?.loopTitle ?? "Loop").ui(13, .semibold).foregroundStyle(m.text.color).lineLimit(1).accessibilityAddTraits(.isHeader)
                if let i { Text("· " + LoopNeedRow.tag(i)).ui(12).foregroundStyle(m.text2.color).lineLimit(1) }
            default:
                let item = b.sessionId.flatMap { model.item($0) }
                if let item { AgentBadge(item: item, size: 20, status: false) }
                Text(item?.session.name ?? "Session").ui(13, .semibold).foregroundStyle(m.text.color).lineLimit(1).accessibilityAddTraits(.isHeader)
                Text(context(item)).ui(12).foregroundStyle(m.text2.color).lineLimit(1).truncationMode(.tail)
            }
            Text(b.kind.tag).ui(11, .semibold).foregroundStyle(tagColor(b).color).lineLimit(1).fixedSize()
                .padding(.horizontal, 7).frame(height: 18)
                .background(Capsule().fill(m.surface.color))
            if critical {   // LAB-2112
                Text("Needs your decision").ui(11, .bold).foregroundStyle(m.needsText.color).lineLimit(1).fixedSize()
                    .padding(.horizontal, 7).frame(height: 18)
                    .overlay(Capsule().strokeBorder(m.needsText.color))
                    .accessibilityLabel("Critical: needs your decision")
            }
            Spacer(minLength: 8)
            if let more = Inbox.moreLine(b.more) { Text(more).ui(11.5).foregroundStyle(m.text2.color).lineLimit(1).fixedSize() }
            Text(Inbox.age(b.at)).ui(11.5).foregroundStyle(m.text2.color).lineLimit(1).fixedSize()
            if b.sessionId != nil || b.kind == .plan {
                Button { open(b) } label: { Text(b.kind == .plan ? "Open plan ↗" : "Open session ↗ ⌘↩").ui(12, .semibold).foregroundStyle(m.accentText.color).fixedSize() }
                    .buttonStyle(.plain).help(b.kind == .plan ? "Open the plan" : "Open the session's terminal (⌘↩)")
            }
        }
        .padding(.horizontal, 12).frame(height: 32)
        .background(m.terminal.paneHeader.color)
    }

    private func tagColor(_ b: InboxBlock) -> RGB {
        let m = Self.mt
        switch b.kind {
        case .permission: return b.decision?.risk == .high ? m.needsText : m.accentText
        case .loop: return loopInbox.items.first { $0.id == b.loopItemId }?.kind == .failed ? m.needsText : m.accentText
        default: return m.accentText
        }
    }

    private func context(_ item: BoardItem?) -> String {
        guard let item else { return "" }
        var parts: [String] = []
        let w = model.window(model.workspaceId(of: item))?.name ?? ""
        if !w.isEmpty { parts.append(w + " window") }
        if let a = item.account { parts.append(a) }
        if let c = model.captions[item.id], let i = c.step, let n = c.steps { parts.append("step \(i) of \(n)") }
        return parts.isEmpty ? "" : "· " + parts.joined(separator: " · ")
    }

    @ViewBuilder private func content(_ b: InboxBlock) -> some View {
        switch b.kind {
        case .plan:
            if let o = model.objectives.first(where: { $0.id == b.planId }) { planContent(o) }
        case .loop:
            if let i = loopInbox.items.first(where: { $0.id == b.loopItemId }) { LoopNeedDetail(model: model, item: i, win: win, embedded: true) }
        case .waiting:
            Text("Waiting for you. One Roof has not read its prompt yet: open the session to answer it there.")
                .ui(13).foregroundStyle(Self.mt.text2.color)
            if let sid = b.sessionId, let item = model.item(sid) { HStack { RoofButton("Open session ↗", .primary) { model.reveal(item) } } }
        default:
            if let d = b.decision { askContent(b, d) }
        }
    }

    // MARK: An ask

    @ViewBuilder private func askContent(_ b: InboxBlock, _ d: Decision) -> some View {
        let m = Self.mt
        let name = who(d)
        let body = Inbox.body(d, agentName: name)
        let kind = InboxKind.of(d)
        if let h = body.headline {
            Text(h).ui(15, .semibold).foregroundStyle(m.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        if let note = body.note { Text(note).ui(13).foregroundStyle(m.needsText.color).fixedSize(horizontal: false, vertical: true) }
        if !body.lines.isEmpty {
            let text = body.lines.joined(separator: "\n")
            let long = kind == .finished && Inbox.isLong(text)
            let all = showAll.contains(d.id)
            VStack(alignment: .leading, spacing: 6) {
                Text(text).ui(12.5, mono: true)
                    .foregroundStyle((body.dim ? m.text2 : m.terminal.foreground).color)
                    .lineLimit(long && !all ? Inbox.finishedLines : nil)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if long {
                    Button { if all { showAll.remove(d.id) } else { showAll.insert(d.id) } } label: {
                        Text(all ? "Show less ▴" : "Show all ▾").ui(12, .semibold).foregroundStyle(m.accentText.color)
                    }.buttonStyle(.plain)
                }
            }
        }
        if kind == .permission { riskLine(d); detailsPart(d, agentName: name) }
        if let note = Inbox.hostedNote(d) {
            Text(note).ui(12).foregroundStyle(m.text2.color).fixedSize(horizontal: false, vertical: true)
            if let item = model.item(d.sessionId) { HStack { RoofButton("Open native terminal") { model.reveal(item) } } }
        }
        options(b, d)
        if let ph = Inbox.placeholder(d, agentName: name) { replyRow(b, d, placeholder: ph) }
        if let f = failed[b.id] {
            Text(f).ui(12.5, .semibold).foregroundStyle(m.needsText.color).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Send failed: " + f)
        }
        Text(Inbox.footer(d, agentName: name)).ui(11.5).foregroundStyle(m.text3.color).fixedSize(horizontal: false, vertical: true)
    }

    private func riskLine(_ d: Decision) -> some View {
        let s = Inbox.riskSentence(d)
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            RiskPill(risk: d.risk)
            if !s.isEmpty { Text(s).ui(12.5).foregroundStyle(Self.mt.text2.color).fixedSize(horizontal: false, vertical: true) }
        }
    }

    private func detailsPart(_ d: Decision, agentName: String) -> some View {
        let m = Self.mt
        let open = details.contains(d.id)
        return VStack(alignment: .leading, spacing: 10) {
            Button { withAnimation(Motion.fast) { if open { details.remove(d.id) } else { details.insert(d.id) } } } label: {
                Text(open ? "Details ▾" : "Details ▸").ui(12, .semibold).foregroundStyle(m.accentText.color)
            }
            .buttonStyle(.plain).accessibilityLabel(open ? "Hide details" : "Show details")
            if open {
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        reason("Why · in \(agentName)'s words", d.whyMissing ? d.why : "\u{201C}" + d.why + "\u{201D}").gridCellColumns(2)
                    }
                    GridRow { reason("What it touches", d.touches); reason("If you say no", d.ifNo) }
                    GridRow { reason("Where this sits", d.where_.isEmpty ? "—" : d.where_).gridCellColumns(2) }
                }
            }
        }
    }

    private func reason(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            MicroLabel(title)
            Text(body).ui(13).foregroundStyle(Self.mt.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func options(_ b: InboxBlock, _ d: Decision) -> some View {
        let buttons = Inbox.buttons(d, repo: d.repo)
        return FlowLayout(spacing: 8) {
            ForEach(Array(buttons.enumerated()), id: \.offset) { _, btn in
                RoofButton(btn.title, btn.danger ? .danger : btn.primary ? .primary : .secondary) { press(btn, b) }
                    .disabled(!btn.enabled || (btn.action == .closeSession && model.item(d.sessionId) == nil))
                    .help(btn.help)
            }
        }
    }

    private func replyRow(_ b: InboxBlock, _ d: Decision, placeholder: String) -> some View {
        let m = Self.mt
        let images = drafts.images[b.id] ?? []
        let hosted = d.agent.isHosted
        let name = model.item(d.sessionId)?.session.name ?? "the session"
        let editing = drafts.editing == b.id
        return VStack(alignment: .leading, spacing: 6) {
            if !images.isEmpty {
                HStack(spacing: 8) { ForEach(images, id: \.self) { p in chip(p, key: b.id) } }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button { pickImages(b.id) } label: {
                    Image(systemName: "paperclip").font(.system(size: 14, weight: .medium)).foregroundStyle(m.text2.color).frame(width: 28, height: 30)
                }
                .buttonStyle(.plain).disabled(hosted)
                .help("Attach an image (or paste ⌘V, or drop it here)").accessibilityLabel("Attach image…")
                InboxReplyField(key: b.id, placeholder: placeholder, label: "Reply to \(name)",
                                textColor: m.terminal.foreground.nsColor, placeholderColor: m.text3.nsColor, scale: scale,
                                onSend: { sendBox(b) }, onImages: { drafts.attach(b.id, $0) },
                                onLeave: { keys = true })
                    .frame(height: max(22, min(drafts.height[b.id] ?? 22, 6 * 17 * scale + 6)))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(m.window.color))
                    .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder((editing ? m.accent : m.separatorStrong).color))
                    .disabled(hosted).opacity(hosted ? 0.5 : 1)
                if !(InboxKind.of(d) == .question || InboxKind.of(d) == .finished) {
                    RoofButton("Send ↩") { sendBox(b) }
                        .disabled(hosted || ((drafts.text[b.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty))
                        .help("Send what is in the box (↩) · ⇧↩ new line")
                }
            }
            if let note = drafts.note[b.id] { Text(note).ui(11.5).foregroundStyle(m.needsText.color) }
        }
    }

    private func chip(_ path: String, key: String) -> some View {
        let m = Self.mt
        let name = (path as NSString).lastPathComponent
        return ZStack(alignment: .topTrailing) {
            Group {
                if let img = NSImage(contentsOfFile: path) { Image(nsImage: img).resizable().scaledToFill() }
                else { Image(systemName: "photo").foregroundStyle(m.text2.color) }
            }
            .frame(width: 44, height: 44).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(m.separatorStrong.color))
            Button { drafts.images[key]?.removeAll { $0 == path } } label: {
                Text("✕").ui(9, .bold).foregroundStyle(m.text.color).frame(width: 16, height: 16)
                    .background(Circle().fill(m.surface.color))
            }
            .buttonStyle(.plain).offset(x: 5, y: -5)
            .accessibilityLabel("Attached image \(name), remove")
        }
        .help(path)
    }

    private func planContent(_ o: Objective) -> some View {
        let m = Self.mt
        return VStack(alignment: .leading, spacing: 12) {
            Text("Approve the plan for \u{201C}\(o.title)\u{201D}").ui(15, .semibold).foregroundStyle(m.text.color).fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((o.plan?.steps ?? []).enumerated()), id: \.element.id) { i, s in
                    HStack(spacing: 10) {
                        Text("\(i + 1)").ui(12, .semibold, mono: true).foregroundStyle(m.text3.color).frame(width: 18)
                        AgentBadge(AgentMark(agent: s.agentKind, account: s.account), size: 20)
                        Text(s.title).ui(13).foregroundStyle(m.text.color).lineLimit(2)
                        Spacer()
                        Text([s.account, s.model, s.cost].compactMap { $0 }.joined(separator: " · ")).ui(11.5, mono: true).foregroundStyle(m.text2.color)
                    }
                    .padding(.vertical, 7)
                }
            }
            HStack(alignment: .top, spacing: 14) {
                reason("Done when", o.doneWhen.isEmpty ? "—" : o.doneWhen)
                reason("If you say no", "Nothing runs; the planner waits for your edits.")
            }
            FlowLayout(spacing: 8) {
                ForEach(Array(Inbox.planButtons().enumerated()), id: \.offset) { _, btn in
                    RoofButton(btn.title, btn.primary ? .primary : .secondary) { pressPlan(btn, o) }.help(btn.help)
                }
            }
        }
    }

    // MARK: Ghosts, new blocks, picks

    private struct Shown { var block: InboxBlock; var ghost: Ghost? }

    private func withGhosts(_ asks: [InboxBlock]) -> [Shown] {
        var out = asks.map { Shown(block: $0, ghost: nil) }
        for g in ghosts.values.sorted(by: { $0.index < $1.index }) where !asks.contains(where: { $0.id == g.block.id }) {
            out.insert(Shown(block: g.block, ghost: g), at: min(g.index, out.count))
        }
        return out
    }

    /// Blocks that left fold away after 1.5 s with what was answered; new ones arrive at the top without moving the
    /// block you are in ("1 new above ↑" when you are further down).
    private func track(_ now: [InboxBlock]) {
        let before = lastBlocks
        lastBlocks = now
        let ids = Set(now.map(\.id))
        let all = model.decisions + model.selfTestDecisions
        for (i, b) in before.enumerated() where !ids.contains(b.id) && b.kind != .loop {
            let line: String
            if let d = b.decision, let a = all.first(where: { $0.id == d.id }), !a.isOpen { line = Inbox.answeredLine(a) }
            else if b.kind == .plan { line = "You: decided the plan" }
            else { line = "Answered in its terminal" }
            ghosts[b.id] = Ghost(block: b, index: i, line: line)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { withAnimation(Motion.base) { _ = ghosts.removeValue(forKey: b.id) } }
        }
        // Only blocks that landed above the one you are in count as "new above" (newest arrive at the top).
        if let f = focused, let fi = now.firstIndex(where: { $0.id == f }) {
            newAbove += now.prefix(fi).filter { b in !before.contains { $0.id == b.id } }.count
        }
        if focused == nil || !ids.contains(focused ?? "") {   // the block you answered left: the next one takes the focus
            let i = before.firstIndex { $0.id == focused } ?? 0
            let next = now.isEmpty ? nil : now[min(i, now.count - 1)]
            focused = next?.id
            if let next, !before.isEmpty { announce(next) }
        }
    }

    private func announce(_ next: InboxBlock) {
        let name = next.sessionId.flatMap { model.item($0)?.session.name } ?? next.kind.tag
        NSAccessibility.post(element: NSApp.mainWindow as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Answered. Next: \(name)", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    private func pick(_ id: String?, layout: InboxLayout, decided: [Decision]) {
        guard let id else { return }
        if let b = Inbox.block(for: id, in: layout.all) { focused = b.id }
        else if decided.contains(where: { $0.id.uuidString == id }) { win.inboxTab = .decided }   // LAB-2110: Decided is a tab
    }

    private func current(_ layout: InboxLayout) -> InboxBlock? { layout.all.first { $0.id == focused } ?? layout.all.first }

    private func move(_ delta: Int, _ layout: InboxLayout) {
        focused = Inbox.step(from: focused, by: delta, in: layout.all)
    }

    // MARK: Keys

    private func key(_ k: KeyPress, layout: InboxLayout) -> KeyPress.Result {
        guard drafts.editing == nil, k.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
        let b = current(layout)
        switch k.key {
        case .downArrow: move(1, layout); return .handled
        case .upArrow: move(-1, layout); return .handled
        case .tab:
            if let b, let d = b.decision, Inbox.placeholder(d, agentName: who(d)) != nil { drafts.focusRequest = b.id; return .handled }
            return .ignored
        case .return:
            guard let b, let d = b.decision, let btn = Inbox.defaultButton(Inbox.buttons(d, repo: d.repo)) else {
                if let b, b.kind == .plan, let o = model.objectives.first(where: { $0.id == b.planId }) { model.approve(o); return .handled }
                return .ignored
            }
            press(btn, b); return .handled
        case .escape:
            guard let b, let d = b.decision, let btn = Inbox.cancelButton(Inbox.buttons(d, repo: d.repo)) else { return .ignored }
            press(btn, b); return .handled
        default:
            if let c = k.characters.first, let n = c.wholeNumberValue, (1...9).contains(n), let b, let d = b.decision,
               let btn = Inbox.numbered(n, in: Inbox.buttons(d, repo: d.repo)) {
                press(btn, b); return .handled
            }
            return .ignored
        }
    }

    // MARK: Actions

    private func open(_ b: InboxBlock) {
        if b.kind == .plan, let id = b.planId { model.objectiveId = id; return }
        if let sid = b.sessionId, let item = model.item(sid) { model.reveal(item) }
    }

    private func press(_ btn: InboxButton, _ b: InboxBlock) {
        guard let d = b.decision else { return }
        switch btn.action {
        case .choice(let c): handle(Inbox.choose(d, c, text: boxMessage(b)), d, b)
        case .allowOnce: handle(.answer(.allowOnce), d, b)
        case .always: handle(.answer(.always), d, b)
        case .deny, .cancel: handle(.answer(.deny), d, b)
        case .reply:
            let s = Inbox.send(d, text: boxMessage(b))
            handle(s == .nothing ? .focusBox : s, d, b)
        case .setAside: model.setAside(d); drafts.clear(b.id)
        case .closeSession:
            if let item = model.item(d.sessionId) { model.closeAgent(item) }
            model.setAside(d); drafts.clear(b.id)
        case .approvePlan, .editPlan, .rejectPlan: break
        }
    }

    private func pressPlan(_ btn: InboxButton, _ o: Objective) {
        switch btn.action {
        case .approvePlan: model.approve(o)
        case .editPlan: model.objectiveId = o.id
        case .rejectPlan: model.pause(o)
        default: break
        }
    }

    /// The box's text with its images named at the end (one line, as the agent reads it).
    private func boxMessage(_ b: InboxBlock) -> String {
        Inbox.message(drafts.text[b.id] ?? "", images: drafts.images[b.id] ?? [])
    }

    private func sendBox(_ b: InboxBlock) {
        guard let d = b.decision else { return }
        handle(Inbox.send(d, text: boxMessage(b)), d, b)
    }

    private func handle(_ s: InboxSend, _ d: Decision, _ b: InboxBlock) {
        switch s {
        case .nothing: return
        case .focusBox: drafts.focusRequest = b.id; return
        case .reply(let text): deliver(d, b) { model.answer(d, .reply, reply: text) }
        case .choice(let c, let text):
            deliver(d, b) { model.answer(d, .reply, reply: text, choice: c) }
            if c.meaning == .always && !d.isMenu { showUndo(d) }
        case .answer(let a):
            deliver(d, b) { model.answer(d, a) }
            if a == .always { showUndo(d) }
        }
    }

    /// Send, unless the session cannot be reached: then the red line, and the text and images stay.
    private func deliver(_ d: Decision, _ b: InboxBlock, _ run: () -> Void) {
        guard model.canReach(d) else {
            failed[b.id] = Inbox.unreachable(model.item(d.sessionId)?.session.name ?? "the session")
            return
        }
        failed[b.id] = nil
        run()
        drafts.clear(b.id)
        if drafts.editing == b.id { drafts.editing = nil }
        keys = true
    }

    private func showUndo(_ d: Decision) {
        undoRule = d
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if undoRule == d { undoRule = nil } }
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
        .overlay(Capsule().strokeBorder(t.separator.color))
        .padding(.bottom, 18)
    }

    // MARK: Images

    private func pickImages(_ key: String) {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.image]
        p.allowsMultipleSelection = true
        p.canChooseDirectories = false
        p.prompt = "Attach"
        p.message = "Attach images to your reply"
        if p.runModal() == .OK { drafts.attach(key, p.urls.map(\.path)) }
    }

    /// Dropped image files keep their path; dropped image data (from a browser) is saved like a paste.
    private func drop(_ providers: [NSItemProvider], into key: String) -> Bool {
        var took = false
        for p in providers {
            if p.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                took = true
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, ImageAttachments.isImagePath(url.path) else { return }
                    DispatchQueue.main.async { InboxDrafts.shared.attach(key, [url.path]) }
                }
            } else if p.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                took = true
                p.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data, let path = TerminalMouse.saveImage(data: data, in: TerminalMouse.pastedImagesDir) else { return }
                    DispatchQueue.main.async { InboxDrafts.shared.attach(key, [path]) }
                }
            }
        }
        return took
    }
}

/// A block's frame: Midnight fill, radius 10, the page theme's strong edge, a 2 pt accent ring when focused.
struct InboxBlockFrame<Content: View>: View {
    let focused: Bool
    let edge: RGB
    let ring: RGB
    let scale: Double
    var lineWidth: CGFloat = 1
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(V2InboxPage.mt.terminal.background.color))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(edge.color, lineWidth: lineWidth))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(focused ? ring.color : .clear, lineWidth: 2).padding(-3))
            .themed(.midnight, scale: scale)
    }
}

/// The block's reply box: an NSTextView (↩ sends, ⇧↩ new line, grows 1–6 lines), ⌘V of an image or a dropped image
/// attaches it, Esc clears the box (an empty box hands the keys back to the page).
struct InboxReplyField: NSViewRepresentable {
    let key: String
    let placeholder: String
    let label: String
    let textColor: NSColor
    let placeholderColor: NSColor
    let scale: Double
    var onSend: () -> Void
    var onImages: ([String]) -> Void
    var onLeave: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        let tv = scroll.documentView as! NSTextView
        let box = InboxTextView(frame: tv.frame, textContainer: tv.textContainer)
        box.autoresizingMask = tv.autoresizingMask
        box.minSize = tv.minSize; box.maxSize = tv.maxSize
        box.isVerticallyResizable = true; box.isHorizontallyResizable = false
        box.textContainer?.widthTracksTextView = true
        box.drawsBackground = false
        box.isRichText = false
        box.importsGraphics = false
        box.allowsUndo = true
        box.isAutomaticQuoteSubstitutionEnabled = false; box.isAutomaticDashSubstitutionEnabled = false
        box.textContainerInset = NSSize(width: 0, height: 2)
        box.delegate = context.coordinator
        box.coordinator = context.coordinator
        box.registerForDraggedTypes([.fileURL, .png, .tiff])
        scroll.documentView = box
        context.coordinator.box = box
        MainActor.assumeIsolated { box.string = InboxDrafts.shared.text[key] ?? "" }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let c = context.coordinator
        c.parent = self
        guard let box = c.box else { return }
        let font = NSFont.systemFont(ofSize: 13 * scale)
        if box.font != font { box.font = font }
        box.textColor = textColor
        box.insertionPointColor = textColor
        box.placeholder = NSAttributedString(string: placeholder, attributes: [.foregroundColor: placeholderColor, .font: font])
        box.setAccessibilityLabel(label)
        box.setAccessibilityPlaceholderValue(placeholder)
        MainActor.assumeIsolated {
            let d = InboxDrafts.shared
            if c.key != key { c.key = key; box.string = d.text[key] ?? "" }
            else if (d.text[key] ?? "") != box.string, box.window?.firstResponder !== box { box.string = d.text[key] ?? "" }   // cleared after a send
            else if d.text[key] == nil, !box.string.isEmpty { box.string = "" }
            if d.focusRequest == key {
                DispatchQueue.main.async { box.window?.makeFirstResponder(box); d.focusRequest = nil }
            }
        }
        box.needsDisplay = true
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: InboxReplyField
        weak var box: InboxTextView?
        var key: String
        init(_ p: InboxReplyField) { parent = p; key = p.key }

        func textDidChange(_ n: Notification) {
            guard let box else { return }
            let text = box.string, key = key
            var h: CGFloat = 22
            if let lm = box.layoutManager, let tc = box.textContainer {
                lm.ensureLayout(for: tc)
                h = max(22, ceil(lm.usedRect(for: tc).height) + 4)
            }
            MainActor.assumeIsolated {
                let d = InboxDrafts.shared
                d.text[key] = text.isEmpty ? nil : text
                if d.height[key] != h { d.height[key] = h }
            }
        }
        func textDidBeginEditing(_ n: Notification) { let k = key; MainActor.assumeIsolated { InboxDrafts.shared.editing = k } }
        func textDidEndEditing(_ n: Notification) {
            let k = key
            MainActor.assumeIsolated { if InboxDrafts.shared.editing == k { InboxDrafts.shared.editing = nil } }
        }

        func textView(_ tv: NSTextView, doCommandBy sel: Selector) -> Bool {
            let mods = NSApp.currentEvent?.modifierFlags ?? []
            switch sel {
            case #selector(NSResponder.insertNewline(_:)):
                if mods.contains(.shift) || mods.contains(.option) { tv.insertText("\n", replacementRange: tv.selectedRange()); return true }
                textDidChange(Notification(name: NSText.didChangeNotification))
                parent.onSend()
                return true
            case #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                tv.insertText("\n", replacementRange: tv.selectedRange()); return true
            case #selector(NSResponder.cancelOperation(_:)):
                if tv.string.isEmpty { tv.window?.makeFirstResponder(nil); parent.onLeave() }
                else { tv.string = ""; textDidChange(Notification(name: NSText.didChangeNotification)) }
                return true
            default: return false
            }
        }
    }
}

final class InboxTextView: NSTextView {
    weak var coordinator: InboxReplyField.Coordinator?
    var placeholder: NSAttributedString?

    /// ⌘V with an image (a screenshot, image files from Finder) attaches it; text pastes as usual.
    override func paste(_ sender: Any?) {
        if let paths = ImageAttachments.pastedImages(from: .general) { coordinator?.parent.onImages(paths); return }
        pasteAsPlainText(sender)
    }

    private func images(_ pb: NSPasteboard) -> [String]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let imgs = urls.map(\.path).filter(ImageAttachments.isImagePath)
            return imgs.isEmpty ? nil : imgs
        }
        if pb.availableType(from: [.png, .tiff]) != nil, let p = TerminalMouse.saveImage(from: pb, in: TerminalMouse.pastedImagesDir) { return [p] }
        return nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let pb = sender.draggingPasteboard
        let hasImage = (pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.contains { ImageAttachments.isImagePath($0.path) } == true
            || pb.availableType(from: [.png, .tiff]) != nil
        return hasImage ? .copy : super.draggingEntered(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let paths = images(sender.draggingPasteboard) { coordinator?.parent.onImages(paths); return true }
        return super.performDragOperation(sender)
    }

    override func draw(_ r: NSRect) {
        super.draw(r)
        if string.isEmpty, let placeholder { placeholder.draw(at: NSPoint(x: textContainerInset.width + 5, y: textContainerInset.height)) }
    }
}

/// LAB-2047: the Action log capsule's halves: pressed = the selection token (hover is the capsule's 50 % fill).
struct InboxCapsuleStyle: ButtonStyle {
    let fill: RGB
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? fill.color : .clear)
    }
}
