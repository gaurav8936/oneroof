import AppKit
import SwiftUI
import OneRoofCore

// LAB-2110 · LAB-2106 · LAB-2342 (Inbox v4.0, 4k): the Decided tab — the one record of every answer, from sessions and
// loops, as the Inbox draws it: a list on the left (the same source filter, search, Answer and time filters, paging),
// the selected answer in full in the console panel on the right. Session answers come from SQL (50 a page, LAB-2082);
// loop decisions from the outcome ledger (only decisions someone made; folded copies are one row).

/// One row of Decided: a session's answer or a (folded) loop decision.
enum DecidedEntry: Identifiable, Equatable {
    case session(ActionLogRow)
    case loop(LoopInbox.DecidedGroup)

    var id: String {
        switch self {
        case .session(let r): return "s-" + r.id.uuidString
        case .loop(let g): return g.id
        }
    }

    var at: Date {
        switch self {
        case .session(let r): return r.decision.answeredAt ?? r.decision.askedAt
        case .loop(let g): return g.at
        }
    }
}

struct V2DecidedList: View {
    @Environment(\.theme) private var t
    @Environment(\.textScale) private var scale
    let model: AppModel
    @ObservedObject var win: WindowState

    @State private var entries: [DecidedEntry] = []
    @State private var sessionTotal = 0
    @State private var loopTotal = 0
    @State private var page = 0
    @State private var search = ""
    @State private var generation = 0
    @State private var loaded = false
    @State private var filter: InboxFilter = .all
    @State private var selected: String?
    // The Action log's filters, kept (LAB-2110): session, answer and date.
    @State private var sessionFilter: Set<String> = []
    @State private var answerFilter: DecidedAnswer?
    @State private var range: DecidedRange = .all
    @State private var sessionNames: [(id: String, name: String)] = []
    @FocusState private var keys: Bool

    enum DecidedAnswer: String, CaseIterable { case allowed = "Allowed", denied = "Denied", replied = "Replied or chose"
        var answers: Set<Answer> { switch self { case .allowed: return [.allowOnce, .always]; case .denied: return [.deny]; case .replied: return [.reply] } }
    }
    enum DecidedRange: String, CaseIterable { case today = "Today", week = "Last 7 days", month = "Last 30 days", all = "All time"
        var since: Date? {
            switch self {
            case .today: return Calendar.current.startOfDay(for: Date())
            case .week: return Date().addingTimeInterval(-7 * 86400)
            case .month: return Date().addingTimeInterval(-30 * 86400)
            case .all: return nil
            }
        }
    }

    private var total: Int { filter == .sessions ? sessionTotal : filter == .loops ? loopTotal : sessionTotal + loopTotal }
    private var counts: InboxCounts { var c = InboxCounts(); c.sessions = sessionTotal; c.loops = loopTotal; c.all = sessionTotal + loopTotal; return c }
    private var current: DecidedEntry? { entries.first { $0.id == selected } ?? entries.first }

    var body: some View {
        HStack(spacing: 0) {
            list.frame(width: V2InboxPage.listWidth).background(t.surface2.color)
            Rectangle().fill(t.separator.color).frame(width: 1)
            panel.padding(.horizontal, 24).padding(.vertical, 16).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .focusable().focusEffectDisabled().focused($keys)
        .onKeyPress(phases: .down) { k in
            guard k.modifiers.intersection([.command, .control, .option]).isEmpty else { return .ignored }
            switch k.key {
            case .downArrow, .upArrow: step(k.key == .downArrow ? 1 : -1); return .handled
            case .return: if let e = current { open(e) }; return .handled
            default: return .ignored
            }
        }
        .background(filterKeys)
        .onAppear { reload(); DispatchQueue.main.async { keys = true } }
        .onChange(of: page) { _, _ in reload() }
        .onChange(of: filter) { _, _ in page = 0; selected = nil; reload() }
        .onChange(of: sessionFilter) { _, _ in page = 0; reload() }
        .onChange(of: answerFilter) { _, _ in page = 0; reload() }
        .onChange(of: range) { _, _ in page = 0; reload() }
        .onReceive(model.$selfTestDecisions.map { $0.filter { !$0.isOpen }.count }.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)) { _ in reload() }
        .onChange(of: search) { _, s in
            let typed = s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if search == typed { page = 0; reload() } }
        }
        .onReceive(model.$decisions.map { $0.filter { !$0.isOpen }.count }.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)) { _ in reload() }
        .onReceive(LoopInboxState.shared.$items.map(\.count).removeDuplicates().dropFirst().receive(on: DispatchQueue.main)) { _ in reload() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decided: what you answered, newest first")
    }

    private var filterKeys: some View {
        ZStack {
            Button("") { filter = .all }.keyboardShortcut("1", modifiers: .command)
            Button("") { filter = .sessions }.keyboardShortcut("2", modifiers: .command)
            Button("") { filter = .loops }.keyboardShortcut("3", modifiers: .command)
        }
        .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }

    private func step(_ d: Int) {
        guard !entries.isEmpty else { return }
        let i = entries.firstIndex { $0.id == selected } ?? 0
        selected = entries[(i + d + entries.count) % entries.count].id
    }

    // MARK: List

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    InboxSourceFilter(filter: filter, counts: counts, red: false) { filter = $0 }
                    Text("⌘1 All · ⌘2 Sessions · ⌘3 Loops · ↑↓ move").ui(11).foregroundStyle(t.text3.color).padding(.bottom, 4)
                    HStack(spacing: 6) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text2.color)
                            TextField("", text: $search, prompt: Text("Search what you decided").foregroundStyle(t.text2.color))
                                .textFieldStyle(.plain).ui(13).accessibilityLabel("Search decided")
                        }
                        .padding(.horizontal, 10).frame(height: 30)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.card.color))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separatorStrong.color))
                        filters
                    }
                    .padding(.bottom, 4)
                    if loaded && entries.isEmpty {
                        Text(search.isEmpty ? "Nothing decided yet." : "Nothing you decided matches.").ui(13).foregroundStyle(t.text2.color)
                            .frame(maxWidth: .infinity).padding(.top, 40)
                    }
                    ForEach(entries) { e in row(e).id(e.id) }
                    if total > 0 {
                        HStack(spacing: 6) {
                            Text(countLine).ui(12).foregroundStyle(t.text2.color)
                            pager
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(12)
            }
            .onChange(of: selected) { _, id in if let id { withAnimation(Motion.fast) { proxy.scrollTo(id) } } }
        }
    }

    private var filters: some View {
        HStack(spacing: 6) {
            if filter != .loops {
                Menu {
                    Button("All sessions") { sessionFilter = [] }
                    Divider()
                    ForEach(sessionNames, id: \.id) { s in
                        Toggle(s.name, isOn: Binding(get: { sessionFilter.contains(s.id) },
                                                     set: { on in if on { sessionFilter.insert(s.id) } else { sessionFilter.remove(s.id) } }))
                    }
                } label: { chip("Session" + (sessionFilter.isEmpty ? "" : " · \(sessionFilter.count)"), on: !sessionFilter.isEmpty) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("Filter by session")
                Menu {
                    Button("Any answer") { answerFilter = nil }
                    Divider()
                    ForEach(DecidedAnswer.allCases, id: \.self) { a in Button(a.rawValue) { answerFilter = a } }
                } label: { chip(answerFilter?.rawValue ?? "Answer", on: answerFilter != nil) }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("Filter by answer")
            }
            Menu {
                ForEach(DecidedRange.allCases, id: \.self) { r in Button(r.rawValue) { range = r } }
            } label: { chip(range.rawValue, on: range != .all) }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize().accessibilityLabel("Date range")
        }
    }

    private func chip(_ title: String, on: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title).ui(12, on ? .semibold : .regular)
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .semibold))
        }
        .foregroundStyle(on ? t.accentText.color : t.text.color)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(on ? t.selection.color : t.card.color))
        .overlay(Capsule().strokeBorder(on ? t.accent.color : t.separatorStrong.color))
    }

    private var countLine: String {
        let from = page * Decided.pageSize + 1, to = min(total, page * Decided.pageSize + entries.count)
        return "\(from)–\(to) of \(total)" + (range == .today ? " today" : "") + " ·"
    }

    private var pager: some View {
        HStack(spacing: 6) {
            Button { page = max(0, page - 1) } label: { Text("‹ Newer").ui(12, .semibold).foregroundStyle((page > 0 ? t.accentText : t.text3).color) }
                .buttonStyle(.plain).disabled(page == 0).accessibilityLabel("Newer decisions")
            Button { page += 1 } label: {
                Text("Older ›").ui(12, .semibold).foregroundStyle((total > (page + 1) * Decided.pageSize ? t.accentText : t.text3).color)
            }
            .buttonStyle(.plain).disabled(total <= (page + 1) * Decided.pageSize).accessibilityLabel("Older decisions")
        }
    }

    private func row(_ e: DecidedEntry) -> some View {
        let k = t.console, sel = current?.id == e.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                InboxPostmarkView(text: postmark(e), ink: ink(e))
                Spacer(minLength: 8)
                Text(Inbox.age(e.at)).ui(11, mono: true).foregroundStyle(k.dim.color)
            }
            Text(title(e)).ui(13).foregroundStyle(k.text.color).lineLimit(1)
            Text(answer(e)).ui(11.5, mono: true).foregroundStyle(k.dim.color).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((sel ? k.selected : k.ground).color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder((sel ? k.selectedEdge : k.rowEdge).color, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onTapGesture { selected = e.id; keys = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title(e)). \(answer(e))")
        .accessibilityAddTraits(sel ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Words

    private func sessionName(_ r: ActionLogRow) -> String {
        model.item(r.decision.sessionId)?.session.name ?? r.sessionName.map(HistoryFormat.closedName) ?? HistoryFormat.closedName("Session")
    }

    private func title(_ e: DecidedEntry) -> String {
        switch e {
        case .session(let r): return sessionName(r) + " · " + InboxRowText.ask(r.decision)
        case .loop(let g): return g.title
        }
    }

    private func answer(_ e: DecidedEntry) -> String {
        switch e {
        case .session(let r): return Decided.answer(r.decision)
        case .loop(let g): return g.answer
        }
    }

    private func postmark(_ e: DecidedEntry) -> String {
        switch e {
        case .session(let r):
            let item = model.item(r.decision.sessionId)
            return Postmark.line(.session, sender: item.map { $0.account ?? $0.session.agent.displayName } ?? r.decision.agent.displayName)
        case .loop(let g):
            let p: Postmark
            switch g.first.kind {
            case "commit", "pr": p = .commits
            case "file": p = .fileUpdate
            case "report", "slack": p = .report
            default: p = .proposal
            }
            return Postmark.line(p, sender: g.first.loop, copies: g.outcomes.count)
        }
    }

    private func ink(_ e: DecidedEntry) -> RGB {
        switch e {
        case .session(let r):
            let item = model.item(r.decision.sessionId)
            return t.console.agentInk(SeatMark(agent: item?.session.agent ?? r.decision.agent, account: item?.account ?? item?.session.account))
        case .loop: return t.console.loop
        }
    }

    // MARK: Panel

    @ViewBuilder private var panel: some View {
        if let e = current {
            let k = t.console
            InboxBlockFrame(focused: false, edge: k.edge, ring: t.accent, scale: scale, lineWidth: 1.5) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        InboxPostmarkView(text: postmark(e), ink: ink(e)).fixedSize()
                        Text(stripName(e)).ui(13, .semibold).foregroundStyle(k.text.color).lineLimit(1)
                        Text(kindTag(e)).ui(12, .semibold).foregroundStyle(k.link.color).fixedSize()
                        Spacer(minLength: 8)
                        Text(Inbox.age(e.at)).ui(11.5).foregroundStyle(k.dim.color).fixedSize()
                        Button { open(e) } label: { Text(openLabel(e)).ui(12, .semibold).foregroundStyle(k.link.color).fixedSize() }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7).background(k.strip.color)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) { detail(e) }
                            .padding(.horizontal, 16).padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Text("Decided is the one record of every answer, from sessions and loops. Same source filter as the Inbox.")
                        .ui(11.5).foregroundStyle(k.dim.color).padding(.horizontal, 16).padding(.bottom, 12)
                }
                .frame(maxHeight: .infinity, alignment: .top)
            }
        } else if loaded {
            Text("Nothing decided yet.").ui(20, .semibold).foregroundStyle(t.text.color).frame(maxWidth: .infinity).padding(.top, 120)
        }
    }

    private func stripName(_ e: DecidedEntry) -> String {
        switch e { case .session(let r): return sessionName(r); case .loop(let g): return g.first.loop }
    }

    private func kindTag(_ e: DecidedEntry) -> String {
        switch e {
        case .session(let r): return InboxKind.of(r.decision).tag
        case .loop(let g):
            switch g.first.kind { case "commit", "pr": return "Commits → PR"; case "report": return "Report"; case "file": return "File update"
            case "issue": return "Issue"; default: return "Proposal" }
        }
    }

    private func openLabel(_ e: DecidedEntry) -> String { if case .session = e { return "Open conversation ↗" }; return "Open ↗" }

    @ViewBuilder private func detail(_ e: DecidedEntry) -> some View {
        let k = t.console
        switch e {
        case .session(let r):
            let d = r.decision
            Text(ScrollFeed.askText(d)).ui(15, .semibold).foregroundStyle(k.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let c = d.command { Text("$ " + c).ui(12, mono: true).foregroundStyle(k.text.color).textSelection(.enabled) }
            kv("Answer", Decided.answer(d))
            kv("By", TerminalReply.typed(d.replyText) != nil ? "You · in its terminal" : "You · from the Inbox")
            kv("Was", InboxTier.of(d) == .p0 ? "Needed your decision" : "Waited for you")
            if let a = d.answeredAt { kv("When", a.formatted(date: .abbreviated, time: .shortened)) }
        case .loop(let g):
            Text(g.title).ui(15, .semibold).foregroundStyle(k.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            if let ev = g.doc?.evidence, !ev.isEmpty {
                VStack(alignment: .leading, spacing: 2) { ForEach(Array(ev.prefix(8).enumerated()), id: \.offset) { _, l in Text(l).ui(12, mono: true).foregroundStyle(k.text.color) } }
                    .textSelection(.enabled)
            }
            kv("Answer", g.answer)
            kv("By", g.first.decidedBy.map { $0.hasPrefix("One Roof") ? $0 : "You (\($0))" } ?? "—")
            kv("When", g.at.formatted(date: .abbreviated, time: .shortened))
            if g.outcomes.count > 1 { kv("Copies", "\(g.outcomes.count) filings, decided together") }
        }
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).ui(12.5).foregroundStyle(t.console.dim.color).frame(width: 110, alignment: .leading)
            Text(value).ui(12.5).foregroundStyle(t.console.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func open(_ e: DecidedEntry) {
        switch e {
        case .session(let r): openConversation(r.decision)
        case .loop(let g):
            if let p = g.doc?.path { model.openInViewer(p) } else { LoopOutcomeLine.open(g.first, loopId: g.first.loop, model: model, win: win) }
        }
    }

    // MARK: Load

    private func reload() {
        generation += 1
        let gen = generation, store = model.store, q = search, offset = page * Decided.pageSize, f = filter
        let sessions = sessionFilter, answers = answerFilter?.answers ?? [], since = range.since
        let live = model.sessionItems.map { ($0.id, $0.session.name) }
        let mem = (model.decisions + model.selfTestDecisions).filter { !$0.isOpen }
        DispatchQueue.global(qos: .userInitiated).async {
            var r = f == .loops ? [] : (store?.decided(search: q, sessions: sessions, answers: answers, since: since, offset: offset) ?? [])
            var n = store?.decidedCount(search: q, sessions: sessions, answers: answers, since: since) ?? 0
            // Page one also shows the app's newest answers not yet read back, and the self-test's asks (no store row):
            // only those newer than the page's newest stored row, or never stored, so nothing is counted twice.
            if offset == 0 {
                let have = Set(r.map(\.id)), newest = r.first?.decision.answeredAt ?? .distantPast
                let needle = q.trimmingCharacters(in: .whitespaces).lowercased()
                let extra = mem.filter { d in
                    guard !have.contains(d.id), d.replyText != "set aside", (d.answeredAt ?? .distantPast) > newest else { return false }
                    if !sessions.isEmpty, !sessions.contains(d.sessionId) { return false }
                    if !answers.isEmpty, !(d.answer.map(answers.contains) ?? false) { return false }
                    if let since, (d.answeredAt ?? .distantPast) < since { return false }
                    guard !needle.isEmpty else { return true }
                    return [ScrollFeed.askText(d), d.pattern, d.why, d.command ?? "", d.replyText ?? "", d.chosen ?? ""].contains { $0.lowercased().contains(needle) }
                }
                if !extra.isEmpty {
                    if f != .loops {
                        r = Array((extra.map { ActionLogRow(decision: $0, sessionName: nil, closed: false) } + r)
                            .sorted { ($0.decision.answeredAt ?? .distantPast) > ($1.decision.answeredAt ?? .distantPast) }.prefix(Decided.pageSize))
                    }
                    n += extra.count
                }
            }
            // LAB-2342 (IB-11): loop decisions someone made (answers and session filters are session-only).
            let led = LoopInboxState.ledger()
            let loopFiltered = !sessions.isEmpty || !answers.isEmpty
            let loopRows = (f == .sessions || loopFiltered) ? [] : (led?.decidedByPeople(since: since, search: q, limit: Decided.pageSize, offset: offset) ?? [])
            let ln = loopFiltered ? 0 : (led?.decidedByPeopleCount(since: since, search: q) ?? 0)
            let groups = LoopInbox.foldDecided(loopRows, proposals: loopRows.isEmpty ? [:] : LoopInboxState.proposalDocs())
            let merged = (r.map(DecidedEntry.session) + groups.map(DecidedEntry.loop)).sorted { $0.at > $1.at }
            let page = Array(merged.prefix(Decided.pageSize))
            var names = Dictionary(live, uniquingKeysWith: { a, _ in a })
            for (id, s) in store?.historySessions() ?? [:] where names[id] == nil { names[id] = HistoryFormat.closedName(s.name) }
            let list = names.map { (id: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async {
                guard gen == generation else { return }
                entries = page; sessionTotal = n; loopTotal = ln; loaded = true; sessionNames = list
                if let s = selected, !page.contains(where: { $0.id == s }) { selected = nil }
            }
        }
    }

    /// LAB-2106: a live session opens its terminal; a closed one opens History on that session at that moment.
    private func openConversation(_ d: Decision) {
        if let item = model.item(d.sessionId) { model.reveal(item); return }
        V2Conversation.openInHistory(win: win, sessionId: d.sessionId, momentId: "ask-" + d.id.uuidString)
    }
}

/// LAB-2339 · the source filter on top of the Inbox and Decided lists: All · Active sessions · Loops with counts
/// (red when the filter holds something blocked on you).
struct InboxSourceFilter: View {
    @Environment(\.theme) private var t
    let filter: InboxFilter
    let counts: InboxCounts
    var red = true
    let set: (InboxFilter) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(InboxFilter.allCases, id: \.self) { x in
                let on = x == filter, isRed = red && counts.p0(x) > 0 && x != .all
                Button { set(x) } label: {
                    HStack(spacing: 6) {
                        Text(x.title).ui(13, on ? .semibold : .regular).foregroundStyle((on ? t.text : t.text2).color)
                        Text("\(counts.count(x))").ui(11, .bold).foregroundStyle(t.onAccent.color)
                            .padding(.horizontal, 6).frame(minWidth: 20, minHeight: 16)
                            .background(Capsule().fill((isRed ? t.needsText : t.text2).color))
                    }
                    .padding(.horizontal, 12).frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(on ? t.window.color : .clear)
                        .shadow(color: .black.opacity(on ? 0.12 : 0), radius: 1, y: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("\(x.title) (⌘\(InboxFilter.allCases.firstIndex(of: x)! + 1))")
                .accessibilityLabel("\(x.title), \(counts.count(x))")
                .accessibilityAddTraits(on ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(t.selection.color))
        .fixedSize()
    }
}

/// LAB-2106: open a conversation in History — that session only, scrolled to the moment.
enum V2Conversation {
    static func openInHistory(win: WindowState, sessionId: String, momentId: String) {
        win.historyQuery.sessions = [sessionId]
        win.historyQuery.range = .last30
        win.open(.trace)   // LAB-2332: History is inside Trace
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NotificationCenter.default.post(name: .historySelfTestScroll, object: momentId) }
    }
}
