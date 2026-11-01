import AppKit
import SwiftUI
import OneRoofCore

// LAB-2109 · LAB-2110 · LAB-2106: the Inbox's session card (left of each block) and the Decided tab — the one paged
// record of what you decided (50 per page from SQL, LAB-2082), each row in its session's colour with what you answered
// and Open conversation.

/// The coloured card left of an Inbox block: the session's name, what it's about, its agent + account, window, folder
/// and age. One colour per session (SessionHue), the same as its History card and Decided rows.
struct V2InboxSessionCard: View {
    @Environment(\.theme) private var t
    let model: AppModel
    let block: InboxBlock
    let hue: SessionHue?
    let loopTitle: String?

    var body: some View {
        let item = block.sessionId.flatMap { model.item($0) }
        VStack(alignment: .leading, spacing: 5) {
            switch block.kind {
            case .plan:
                Text("Plan").ui(13, .semibold).foregroundStyle(t.text.color)
                Text("A plan waits for your approval.").ui(11.5).foregroundStyle(t.text2.color).lineLimit(3)
            case .loop:
                Text(loopTitle ?? "Loop").ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(2)
                Text("A loop stopped and needs a call.").ui(11.5).foregroundStyle(t.text2.color).lineLimit(3)
            default:
                Text(item?.session.name ?? "Session").ui(13, .semibold).foregroundStyle((hue?.ink ?? t.text).color).lineLimit(2)
                if let about = about(item) { Text(about).ui(11.5).foregroundStyle(t.text.color).lineLimit(3).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 6) {
                    if let item { AgentBadge(item: item, size: 16, status: false) }
                    Text(seat(item)).ui(11.5, .medium).foregroundStyle(t.text2.color).lineLimit(1)
                }
                if let item { Text(place(item)).ui(11).foregroundStyle(t.text2.color).lineLimit(2) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((hue?.fill ?? t.card).color))
        .overlay(alignment: .leading) {
            if let hue { UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10, style: .continuous).fill(hue.ink.color).frame(width: 4) }
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separatorStrong.color))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Session " + (item?.session.name ?? block.kind.tag) + ", " + seat(item))
    }

    /// What the session is about: its caption, else its objective or opening task.
    private func about(_ item: BoardItem?) -> String? {
        guard let item else { return nil }
        if let c = model.captions[item.id]?.text, !c.isEmpty { return c }
        let o = item.session.objective.isEmpty ? item.session.openingMessage : item.session.objective
        let line = o.split(separator: "\n").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? nil : String(line.prefix(140))
    }

    /// "Claude · Claude1", "Codex · CX".
    private func seat(_ item: BoardItem?) -> String {
        guard let item else { return block.decision?.agent.displayName ?? "" }
        let a = item.account ?? item.session.account
        return item.session.agent.displayName + (a.map { " · " + $0 } ?? "")
    }

    /// "Main window · oneroof · 2 h".
    private func place(_ item: BoardItem) -> String {
        var parts: [String] = []
        if let w = model.window(model.workspaceId(of: item))?.name, !w.isEmpty { parts.append(w) }
        if !item.session.repoPath.isEmpty { parts.append((item.session.repoPath as NSString).lastPathComponent) }
        parts.append(Inbox.age(item.session.launchedAt ?? item.session.createdAt))
        return parts.joined(separator: " · ")
    }
}

/// The Decided tab: what you answered, newest first, 50 at a time (SQL), searchable; each row in its session's colour
/// with your words (LAB-2106) and Open conversation.
struct V2DecidedList: View {
    @Environment(\.theme) private var t
    let model: AppModel
    @ObservedObject var win: WindowState

    @State private var rows: [ActionLogRow] = []
    @State private var total = 0
    @State private var page = 0
    @State private var search = ""
    @State private var generation = 0
    @State private var loaded = false
    // The Action log's filters, kept (LAB-2110): session, answer and date.
    @State private var sessionFilter: Set<String> = []
    @State private var answerFilter: DecidedAnswer?
    @State private var range: DecidedRange = .all
    @State private var sessionNames: [(id: String, name: String)] = []

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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text2.color)
                    TextField("", text: $search, prompt: Text("Search what you decided").foregroundStyle(t.text2.color))
                        .textFieldStyle(.plain).ui(13).accessibilityLabel("Search decided")
                }
                .padding(.horizontal, 10).frame(width: 300, height: 30)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.card.color))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separatorStrong.color))
                filters
                Text(countLine).ui(12).foregroundStyle(t.text2.color)
                Spacer()
                pager
            }
            .frame(maxWidth: 1180).padding(.horizontal, 24).padding(.vertical, 12).frame(maxWidth: .infinity)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if loaded && rows.isEmpty {
                        Text(search.isEmpty ? "Nothing decided yet." : "Nothing you decided matches.").ui(14).foregroundStyle(t.text2.color).padding(.top, 60)
                            .frame(maxWidth: .infinity)
                    }
                    ForEach(rows) { r in row(r) }
                    if total > (page + 1) * Decided.pageSize { HStack { Spacer(); pager; Spacer() }.padding(.vertical, 10) }
                }
                .frame(maxWidth: 1180, alignment: .leading).padding(.horizontal, 24).padding(.bottom, 20).frame(maxWidth: .infinity)
            }
        }
        .onAppear { reload() }
        .onChange(of: page) { _, _ in reload() }
        .onChange(of: sessionFilter) { _, _ in page = 0; reload() }
        .onChange(of: answerFilter) { _, _ in page = 0; reload() }
        .onChange(of: range) { _, _ in page = 0; reload() }
        .onReceive(model.$selfTestDecisions.map { $0.filter { !$0.isOpen }.count }.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)) { _ in reload() }
        .onChange(of: search) { _, s in
            let typed = s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if search == typed { page = 0; reload() } }
        }
        .onReceive(model.$decisions.map { $0.filter { !$0.isOpen }.count }.removeDuplicates().dropFirst().receive(on: DispatchQueue.main)) { _ in reload() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Decided: what you answered, newest first")
    }

    private var filters: some View {
        HStack(spacing: 6) {
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
        guard total > 0 else { return "" }
        let from = page * Decided.pageSize + 1, to = min(total, (page + 1) * Decided.pageSize)
        return "\(from)–\(to) of \(total)"
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

    private func reload() {
        generation += 1
        let gen = generation, store = model.store, q = search, offset = page * Decided.pageSize
        let sessions = sessionFilter, answers = answerFilter?.answers ?? [], since = range.since
        let live = model.sessionItems.map { ($0.id, $0.session.name) }
        let mem = (model.decisions + model.selfTestDecisions).filter { !$0.isOpen }
        DispatchQueue.global(qos: .userInitiated).async {
            var r = store?.decided(search: q, sessions: sessions, answers: answers, since: since, offset: offset) ?? []
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
                    r = Array((extra.map { ActionLogRow(decision: $0, sessionName: nil, closed: false) } + r)
                        .sorted { ($0.decision.answeredAt ?? .distantPast) > ($1.decision.answeredAt ?? .distantPast) }.prefix(Decided.pageSize))
                    n += extra.count
                }
            }
            var names = Dictionary(live, uniquingKeysWith: { a, _ in a })
            for (id, s) in store?.historySessions() ?? [:] where names[id] == nil { names[id] = HistoryFormat.closedName(s.name) }
            let list = names.map { (id: $0.key, name: $0.value) }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            DispatchQueue.main.async { if gen == generation { rows = r; total = n; loaded = true; sessionNames = list } }
        }
    }

    private func row(_ r: ActionLogRow) -> some View {
        let d = r.decision, item = model.item(d.sessionId), hue = SessionHue(sessionId: d.sessionId, on: t)
        let name = item?.session.name ?? r.sessionName.map(HistoryFormat.closedName) ?? HistoryFormat.closedName("Session")
        let critical = InboxUrgency.of(d) == .critical
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let item { AgentBadge(item: item, size: 16, status: false) } else { AgentBadge(SeatMark(agent: d.agent, account: nil), size: 16) }
                    Text(name).ui(12.5, .semibold).foregroundStyle(hue.ink.color).lineLimit(1)
                    Text("· " + d.agent.displayName).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                    if critical { Text("Needed your decision").ui(10.5, .semibold).foregroundStyle(t.needsText.color) }
                }
                Text(ScrollFeed.askText(d)).ui(12, mono: true).foregroundStyle(t.text.color).lineLimit(2).textSelection(.enabled)
                Text(Decided.answer(d)).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(3).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                Text(Inbox.age(d.answeredAt ?? d.askedAt)).ui(11).foregroundStyle(t.text2.color)
                    .help("Answered " + (d.answeredAt ?? d.askedAt).formatted(date: .abbreviated, time: .shortened))
                Button { openConversation(d) } label: { Text("Open conversation ↗").ui(12, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).help(item == nil ? "The session is closed: opens its moments in History" : "Opens the session's terminal")
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(t.card.color))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 9, bottomLeadingRadius: 9, style: .continuous).fill(hue.ink.color).frame(width: 4) }
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(t.separatorStrong.color))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(name): \(ScrollFeed.askText(d)). \(Decided.answer(d))")
    }

    /// LAB-2106: a live session opens its terminal; a closed one opens History on that session at that moment.
    private func openConversation(_ d: Decision) {
        if let item = model.item(d.sessionId) { model.reveal(item); return }
        V2Conversation.openInHistory(win: win, sessionId: d.sessionId, momentId: "ask-" + d.id.uuidString)
    }
}

/// LAB-2106: open a conversation in History — that session only, scrolled to the moment.
enum V2Conversation {
    static func openInHistory(win: WindowState, sessionId: String, momentId: String) {
        win.historyQuery.sessions = [sessionId]
        win.historyQuery.range = .last30
        win.open(.history)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { NotificationCenter.default.post(name: .historySelfTestScroll, object: momentId) }
    }
}
