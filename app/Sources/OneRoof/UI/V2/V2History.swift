import AppKit
import SwiftUI
import OneRoofCore

// LAB-2044 · LAB-2045 · LAB-2046 · History (⌃⌘9, right under the Inbox on the rail): the read-only record of every
// session's important moments, newest first, kept 30 days. No session actions here (asks are answered in the Inbox):
// search, sort and filters only. The rules (kinds, styles, filters, dates) live in OneRoofCore/History.swift.

extension Notification.Name {
    /// The store's History rows changed outside the engine (the self-test seed): History reads them again.
    static let historyChanged = Notification.Name("oneroof.history.changed")
}

/// Reads History's moments: the store (30 days, closed sessions included) with what the app holds in memory on top.
enum HistoryLoader {
    /// Every session History knows: the store's `history_sessions` (loop rounds marked there by the engine), with the
    /// manual sessions' current names over them.
    static func sessions(_ m: AppModel) -> [String: HistorySession] {
        var out = m.store?.historySessions() ?? [:]
        for i in m.sessionItems {
            out[i.id] = HistorySession(id: i.id, name: i.session.name, agent: i.session.agent, account: i.account ?? i.session.account,
                                       isLoop: SessionScope.isLoop(i.session), firstAt: out[i.id]?.firstAt, lastAt: out[i.id]?.lastAt)
        }
        return out
    }

    /// What the app holds in memory (open asks, the newest feed events, live sessions' finished steps).
    static func live(_ m: AppModel) -> (feed: [FeedEvent], chapters: [String: [Chapter]], decisions: [Decision]) {
        let feed = EngineState.shared.feed.map { e in
            FeedEvent(id: UUID(uuidString: e.id) ?? UUID(), at: e.at, sessionId: e.sessionId, kind: e.feedKind, text: e.text)
        }
        return (feed, EngineState.shared.chapters, m.decisions + m.selfTestDecisions)
    }

    /// The moments the query matches, in its order (synchronous: the self-test's `scroll` and tests).
    static func load(_ m: AppModel, query: HistoryQuery, now: Date = Date()) -> [ScrollEntry] {
        let sessions = sessions(m)
        let all = entries(store: m.store, live: live(m), sessions: sessions, range: query.range, now: now)
        return query.apply(all, session: { sessions[$0] }, now: now)
    }

    static func entries(store: SessionStore?, live: (feed: [FeedEvent], chapters: [String: [Chapter]], decisions: [Decision]),
                                     sessions: [String: HistorySession], range: HistoryRange, now: Date) -> [ScrollEntry] {
        let b = range.bounds(now: now)
        guard let store else {
            return HistoryFeed.entries(feed: live.feed, chapters: live.chapters, decisions: live.decisions, events: []) { sessions[$0]?.isLoop }
        }
        return store.historyEntries(from: b.from, to: b.to, live: live) { sessions[$0]?.isLoop }
    }
}

struct V2HistoryPage: View {
    @ObservedObject var engineState = EngineState.shared
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState

    /// Every moment in the query's date range (before search and the other filters), and when it was read.
    @State private var all: [ScrollEntry] = []
    @State private var sessions: [String: HistorySession] = [:]
    @State private var loaded = false
    @State private var slow = false
    @State private var failure: String?
    @State private var generation = 0
    @State private var shown = HistoryPaging.pageSize
    @State private var search = ""
    @State private var atTop = true
    @State private var newCount = 0
    @State private var lastTop: String?
    @State private var sessionPicker = false
    @State private var sessionFilterText = ""
    @State private var customPicker = false
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
    @State private var customTo = Date()
    @FocusState private var searchFocused: Bool

    private var query: HistoryQuery { win.historyQuery }
    private var list: [ScrollEntry] { query.apply(all, session: { sessions[$0] }) }

    var body: some View {
        let list = self.list
        VStack(alignment: .leading, spacing: 0) {
            header(list)
            content(list)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
        .background(keys)
        .onAppear { search = win.historyQuery.text; reload() }
        .onChange(of: win.historyQuery.range) { _, _ in shown = HistoryPaging.pageSize; reload() }
        .onChange(of: win.historyQuery) { _, q in if q.text != search { search = q.text } }
        .onChange(of: search) { _, s in
            // 200 ms debounce: the list follows the last keystroke, not every one.
            let typed = s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if search == typed, win.historyQuery.text != typed { win.historyQuery.text = typed } }
        }
        .onChange(of: engineState.feed.first?.id) { _, _ in reload() }
        .onChange(of: model.decisions.map(\.answer)) { _, _ in reload() }
        .onChange(of: model.decisions.count) { _, _ in reload() }
        .onChange(of: model.selfTestDecisions.count) { _, _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .historyChanged)) { _ in reload() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("History: every session's important moments, newest first")
    }

    // MARK: Loading

    private func reload() {
        generation += 1
        let gen = generation, store = model.store, live = HistoryLoader.live(model), names = HistoryLoader.sessions(model)
        let range = win.historyQuery.range
        if store == nil { failure = "the session store isn't open"; loaded = true; return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { if gen == generation, !loaded { slow = true } }
        DispatchQueue.global(qos: .userInitiated).async {
            let entries = HistoryLoader.entries(store: store, live: live, sessions: names, range: range, now: Date())
            DispatchQueue.main.async {
                guard gen == generation else { return }
                noteNew(entries)
                all = entries; sessions = names; loaded = true; slow = false; failure = nil
            }
        }
    }

    /// A moment arrived at the top while you are scrolled down: the "N new ↑" pill counts it; the view stays put.
    private func noteNew(_ entries: [ScrollEntry]) {
        let q = win.historyQuery
        let top = q.apply(entries, session: { sessions[$0] }).first?.id
        defer { lastTop = top }
        guard q.order == .newestFirst, loaded, !atTop, let old = lastTop, let top, top != old else { return }
        let fresh = q.apply(entries, session: { sessions[$0] }).prefix { $0.id != old }.count
        newCount += fresh
    }

    // MARK: Header and controls

    private func header(_ list: [ScrollEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("History").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).accessibilityAddTraits(.isHeader)
                Text(HistoryFormat.subtitle(sessions: Set(list.map(\.sessionId)).count, moments: list.count, order: query.order))
                    .ui(12.5).foregroundStyle(t.text2.color)
                Spacer()
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { searchField.frame(width: 280); sortControl; filterMenus; Spacer(minLength: 0) }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { searchField.frame(maxWidth: 360); sortControl; Spacer(minLength: 0) }
                    HStack(spacing: 8) { filterMenus; Spacer(minLength: 0) }
                }
            }
            chipsRow
            Text(list.isEmpty ? "" : HistoryFormat.resultLine(moments: list.count, sessions: Set(list.map(\.sessionId)).count))
                .ui(12).foregroundStyle(t.text2.color)
        }
        .frame(maxWidth: 1080, alignment: .leading)
        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text2.color)
            TextField("", text: $search, prompt: Text("Search moments, sessions, answers").foregroundStyle(t.text2.color))
                .textFieldStyle(.plain).ui(13).foregroundStyle(t.text.color).focused($searchFocused)
                .onKeyPress(.escape) { search = ""; win.historyQuery.text = ""; return .handled }
                .accessibilityLabel("Search history")
            if !search.isEmpty {
                Button { search = ""; win.historyQuery.text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(t.text2.color) }
                    .buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(searchFocused ? t.accent.color : t.separatorStrong.color, lineWidth: searchFocused ? 2 : 1))
        .help("Search moments, session names and your answers (⌘F; Esc clears)")
    }

    private var sortControl: some View {
        Picker("", selection: Binding(get: { win.historyQuery.order }, set: { win.historyQuery.order = $0 })) {
            ForEach(HistoryOrder.allCases, id: \.self) { o in Text(o.title).tag(o) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        .accessibilityLabel("Sort order")
    }

    @ViewBuilder private var filterMenus: some View {
        let q = query
        menuButton("Session" + (q.sessions.isEmpty ? "" : " · \(q.sessions.count)"), on: !q.sessions.isEmpty) { sessionPicker = true }
            .popover(isPresented: $sessionPicker, arrowEdge: .bottom) { sessionPopover }
            .accessibilityLabel("Filter by session")
        Menu {
            let present = Set(all.compactMap { sessions[$0.sessionId]?.agent })
            if present.isEmpty { Text("No agents in this range") }
            ForEach(AgentKind.allCases.filter { present.contains($0) }, id: \.self) { a in
                Toggle(a.displayName, isOn: toggle(\.agents, a))
            }
            if !q.agents.isEmpty { Divider(); Button("All agents") { win.historyQuery.agents = [] } }
        } label: { menuLabel("Agent" + (q.agents.isEmpty ? "" : " · \(q.agents.count)"), on: !q.agents.isEmpty) }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Filter by agent")
        Menu {
            ForEach(HistoryKindGroup.allCases, id: \.self) { k in
                Toggle(isOn: toggle(\.kinds, k)) { Text(k.title + "  ·  " + k.detail) }
            }
            if !q.kinds.isEmpty { Divider(); Button("All kinds") { win.historyQuery.kinds = [] } }
        } label: { menuLabel("Kind" + (q.kinds.isEmpty ? "" : " · \(q.kinds.count)"), on: !q.kinds.isEmpty) }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Filter by kind")
        Menu {
            ForEach(HistoryRange.presets, id: \.title) { r in
                Toggle(r.title, isOn: Binding(get: { win.historyQuery.range == r }, set: { if $0 { win.historyQuery.range = r } }))
            }
            Divider()
            Button("Custom…") { customPicker = true }
        } label: { menuLabel(q.range.title, on: !q.range.isDefault, symbol: "calendar") }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .popover(isPresented: $customPicker, arrowEdge: .bottom) { customPopover }
        .accessibilityLabel("Date range")
    }

    private func toggle<T: Hashable>(_ path: WritableKeyPath<HistoryQuery, Set<T>>, _ v: T) -> Binding<Bool> {
        Binding(get: { win.historyQuery[keyPath: path].contains(v) },
                set: { on in if on { win.historyQuery[keyPath: path].insert(v) } else { win.historyQuery[keyPath: path].remove(v) } })
    }

    private func menuButton(_ title: String, on: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) { menuLabel(title, on: on) }.buttonStyle(.plain)
    }

    private func menuLabel(_ title: String, on: Bool, symbol: String? = nil) -> some View {
        HStack(spacing: 5) {
            if let symbol { Image(systemName: symbol).font(.system(size: 11)) }
            Text(title).ui(12, on ? .semibold : .regular)
            Image(systemName: "chevron.down").font(.system(size: 8.5, weight: .semibold))
        }
        .foregroundStyle(on ? t.accentText.color : t.text.color)
        .padding(.horizontal, 10).frame(height: 28)
        .background(Capsule().fill(on ? t.selection.color : t.card.color))
        .overlay(Capsule().strokeBorder(on ? t.accent.color : t.separatorStrong.color))
        .contentShape(Capsule())
    }

    /// Session: a searchable multi-select of every session in the range, newest activity first.
    private var sessionPopover: some View {
        let order = Self.sessionsByActivity(all)
        let needle = sessionFilterText.lowercased()
        let shown = order.filter { needle.isEmpty || name($0).lowercased().contains(needle) }
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Find a session", text: $sessionFilterText).textFieldStyle(.roundedBorder).frame(width: 260)
            Button { win.historyQuery.sessions = [] } label: {
                HStack { Text("All sessions").ui(12.5, .semibold); Spacer(); if query.sessions.isEmpty { Text("✓") } }
            }.buttonStyle(.plain).foregroundStyle(t.text.color)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(shown, id: \.self) { id in
                        Toggle(isOn: toggle(\.sessions, id)) {
                            HStack(spacing: 6) {
                                badge(id, size: 16)
                                Text(name(id)).ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                    if shown.isEmpty { Text("No session matches.").ui(12).foregroundStyle(t.text2.color) }
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(12).frame(width: 290)
        .themed(model.themes.centre, scale: win.textScale)
    }

    private var customPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Custom range").ui(13, .semibold).foregroundStyle(t.text.color)
            DatePicker("From", selection: $customFrom, displayedComponents: .date)
            DatePicker("To", selection: $customTo, displayedComponents: .date)
            Text("Both days are included.").ui(11.5).foregroundStyle(t.text2.color)
            HStack { Spacer(); Button("Apply") { win.historyQuery.range = .custom(from: customFrom, to: customTo); customPicker = false }.keyboardShortcut(.defaultAction) }
        }
        .padding(14).frame(width: 260)
    }

    @ViewBuilder private var chipsRow: some View {
        let chips = query.chips(session: name)
        if !chips.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(chips.enumerated()), id: \.offset) { _, c in
                    Button { win.historyQuery.remove(c.remove) } label: {
                        HStack(spacing: 5) {
                            Text(c.label).ui(11.5, .semibold).lineLimit(1)
                            Text("×").ui(12, .bold)
                        }
                        .foregroundStyle(t.text.color)
                        .padding(.horizontal, 9).frame(height: 22)
                        .background(Capsule().fill(t.selection.color))
                        .overlay(Capsule().strokeBorder(t.separatorStrong.color))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Remove filter: " + c.label.replacingOccurrences(of: ": ", with: " "))
                }
                Button { win.historyQuery.clearFilters() } label: { Text("Clear all").ui(11.5, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).padding(.leading, 4)
            }
        }
    }

    /// ⌘F focuses search (a hidden key equivalent; History has no other keys of its own).
    private var keys: some View {
        Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }

    // MARK: Content and states

    @ViewBuilder private func content(_ list: [ScrollEntry]) -> some View {
        if let failure {
            VStack(spacing: 10) {
                Text("History can't be read right now: \(failure).").ui(13).foregroundStyle(t.needsText.color)
                Button { self.failure = nil; reload() } label: { Text("Retry").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }.buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !loaded {
            if slow {
                HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Reading history…").ui(13).foregroundStyle(t.text2.color) }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else { Color.clear }
        } else if list.isEmpty {
            emptyState
        } else {
            listView(list)
        }
    }

    @ViewBuilder private var emptyState: some View {
        VStack(spacing: 8) {
            if all.isEmpty && !query.isFiltered && query.text.isEmpty {
                Text("Nothing yet.").ui(18, .semibold).foregroundStyle(t.text.color)
                Text("As your sessions finish steps, find things and ask you, their moments line up here, newest first.")
                    .ui(13).foregroundStyle(t.text2.color).multilineTextAlignment(.center)
                if query.range != .last30 { last30Button }
            } else if all.isEmpty {
                Text("Nothing in this range.").ui(18, .semibold).foregroundStyle(t.text.color)
                last30Button
            } else {
                Text("No moments match.").ui(18, .semibold).foregroundStyle(t.text.color)
                Button { win.historyQuery.clearFilters(); search = ""; win.historyQuery.text = "" } label: {
                    Text("Clear filters").ui(12.5, .semibold).foregroundStyle(t.accentText.color)
                }.buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(.bottom, 60)
    }

    private var last30Button: some View {
        Button { win.historyQuery.range = .last30 } label: { Text("Show last 30 days").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
            .buttonStyle(.plain)
    }

    private func listView(_ list: [ScrollEntry]) -> some View {
        let page = Array(list.prefix(shown))
        let days = HistoryPaging.days(page)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Color.clear.frame(height: 1).id("history-top")
                        .onAppear { atTop = true; newCount = 0 }
                        .onDisappear { atTop = false }
                    ForEach(days) { day in
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(day.groups) { g in groupCard(g) }
                            }
                            .padding(.bottom, 14)
                        } header: { dayHeader(day.day) }
                    }
                    if list.count > page.count {
                        HStack(spacing: 8) { ProgressView().controlSize(.small); Text("Loading more…").ui(12).foregroundStyle(t.text2.color) }
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .onAppear { shown += HistoryPaging.pageSize }
                    }
                    Color.clear.frame(height: 20)
                }
                .frame(maxWidth: 1080, alignment: .leading)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .top) {
                if newCount > 0 {
                    Button { newCount = 0; withAnimation(Motion.base) { proxy.scrollTo("history-top", anchor: .top) } } label: {
                        Text(HistoryFormat.newPill(newCount)).ui(12, .semibold).foregroundStyle(t.onAccent.color)
                            .padding(.horizontal, 12).frame(height: 26).background(Capsule().fill(t.accent.color))
                    }
                    .buttonStyle(.plain).padding(.top, 8)
                    .accessibilityLabel("\(newCount) new moments. Scroll to the top")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .historySelfTestScroll)) { n in
                if let id = n.object as? String { atTop = false; proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private func dayHeader(_ d: Date) -> some View {
        Text(HistoryFormat.dayHeader(d)).ui(11.5, .bold).tracking(0.4).foregroundStyle(t.text2.color)
            .padding(.vertical, 6).padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(t.window.color)
            .accessibilityAddTraits(.isHeader)
    }

    // MARK: Session cards and rows (LAB-2045)

    private func groupCard(_ g: HistoryGroup) -> some View {
        let s = sessions[g.sessionId]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                badge(g.sessionId, size: 18)
                Text(name(g.sessionId)).ui(13, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(s.map { $0.account ?? $0.agent.displayName } ?? "").ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                Spacer()
            }
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            .contextMenu { Button("Show only this session") { win.historyQuery.sessions = [g.sessionId] } }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Session " + name(g.sessionId))
            ForEach(g.entries) { e in row(e).id(e.id) }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(t.separatorStrong.color))
    }

    @ViewBuilder private func row(_ e: ScrollEntry) -> some View {
        let st = e.kind.style
        if st.treatment == .divider {
            HStack(spacing: 10) {
                Rectangle().fill(st.colour.rgb(t).color.opacity(0.5)).frame(minWidth: 24, maxWidth: .infinity).frame(height: 1)
                Text("\(st.glyph) \(st.word) · \(HistoryFormat.stamp(e.at))" + (e.text.isEmpty ? "" : " · " + e.text))
                    .ui(11.5, .semibold).foregroundStyle(st.colour.rgb(t).color).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(HistoryFormat.full(e.at)).layoutPriority(1)
                Rectangle().fill(st.colour.rgb(t).color.opacity(0.5)).frame(minWidth: 24, maxWidth: .infinity).frame(height: 1)
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HistoryFormat.accessibility(e, session: name(e.sessionId)))
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(HistoryFormat.stamp(e.at)).ui(11, mono: true).foregroundStyle(t.text2.color)
                        .lineLimit(1).fixedSize().frame(width: 150, alignment: .leading).help(HistoryFormat.full(e.at))
                    HStack(spacing: 4) {
                        Text(st.glyph).ui(12, .bold).frame(width: 12)
                        Text(st.word).ui(11, .semibold)
                    }
                    .foregroundStyle(st.colour.rgb(t).color)
                    .frame(width: 96, alignment: .leading)
                    Text(e.text).ui(13).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    Spacer(minLength: 8)
                    if e.needsInput {
                        Text("Waiting in the Inbox").ui(11, .semibold).foregroundStyle(t.accentText.color)
                            .padding(.horizontal, 8).frame(height: 20)
                            .overlay(Capsule().strokeBorder(t.accent.color))
                            .accessibilityAddTraits(.isStaticText)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(st.treatment == .errorFill ? t.historyErrorFill.color : .clear))
                .overlay(alignment: .leading) {
                    switch st.treatment {
                    case .bar(let c): Rectangle().fill(c.bar(t).color).frame(width: 3).padding(.vertical, 3)
                    case .errorFill: Rectangle().fill(t.needsText.color).frame(width: 3).padding(.vertical, 3)
                    default: EmptyView()
                    }
                }
                if let a = e.answer {
                    let y = ScrollEntry.Kind.answerStyle
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(e.answeredAt.map { HistoryFormat.stamp($0) } ?? "").ui(11, mono: true).foregroundStyle(t.text2.color)
                            .lineLimit(1).fixedSize().frame(width: 150, alignment: .leading)
                        Text("\(y.glyph) You: " + a).ui(12.5).foregroundStyle(t.text.color).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.selection.color))
                    .padding(.leading, 28)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("You answered: " + a)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(HistoryFormat.accessibility(e, session: name(e.sessionId)))
        }
    }

    // MARK: Names and badges

    private func name(_ id: String) -> String {
        if let i = model.item(id) { return i.session.name }
        if let s = sessions[id] { return HistoryFormat.closedName(s.name) }
        return HistoryFormat.closedName("Session")
    }

    @ViewBuilder private func badge(_ id: String, size: CGFloat) -> some View {
        if let i = model.item(id) { AgentBadge(item: i, size: size, status: false) }
        else if let s = sessions[id] { AgentBadge(SeatMark(agent: s.agent, account: s.account), size: size) }
        else { RoundedRectangle(cornerRadius: 5).fill(t.separatorStrong.color).frame(width: size, height: size) }
    }

    static func sessionsByActivity(_ entries: [ScrollEntry]) -> [String] {
        var last: [String: Date] = [:]
        for e in entries { last[e.sessionId] = max(last[e.sessionId] ?? .distantPast, e.at) }
        return last.sorted { $0.value > $1.value }.map(\.key)
    }
}

extension Notification.Name {
    /// Self-test: scroll History to the moment with this id (the "N new ↑" pill capture).
    static let historySelfTestScroll = Notification.Name("oneroof.history.selftest.scroll")
}
