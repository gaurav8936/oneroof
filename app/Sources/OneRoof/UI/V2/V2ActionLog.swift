import AppKit
import SwiftUI
import OneRoofCore

// LAB-2047 · LAB-2048 · the Action log (Inbox › Action log): two tabs. Decisions = one list of what you answered, newest
// first, with date + time, session, ask and answer; search, date range, session and answer filters; click (or ↩) opens
// the whole ask. Rules = the always-allow rules One Roof notes, each with "Stop noting this rule" and Undo. Remove
// exists only there. Copy and filters: OneRoofCore/ActionLog.swift. Replaces V2RulesPage (two side-by-side cards).

extension AppModel {
    var decisionRuleCount: Int { store?.decisionRules().count ?? 0 }

    func removeRule(pattern: String, repo: String) {
        for r in store?.decisionRules() ?? [] where r.pattern == pattern && r.repo == repo { store?.deleteRule(id: r.id) }
    }
    /// LAB-2048: Stop noting this rule (One Roof's note only; the agent's own settings keep theirs).
    func stopNoting(_ r: DecisionRule) { store?.deleteRule(id: r.id) }
    /// Undo: the same rule back, with its id and the date it was added.
    func restoreRule(_ r: DecisionRule) { store?.save(r) }
}

struct V2ActionLogPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var win: WindowState
    var back: () -> Void

    @State private var rows: [ActionLogRow] = []
    @State private var rules: [DecisionRule] = []
    @State private var generation = 0
    @State private var opened: UUID?
    @State private var focusedRow: UUID?
    @State private var search = ""
    @State private var ruleSearch = ""
    @State private var stoppedRule: DecisionRule?
    @State private var sessionPicker = false
    @State private var customPicker = false
    @State private var customFrom = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
    @State private var customTo = Date()
    @FocusState private var searchFocused: Bool
    @FocusState private var keys: Bool

    private var tab: ActionLogTab { win.actionLog ?? .decisions }
    private var query: ActionLogQuery { win.actionLogQuery }
    private var list: [ActionLogRow] { query.apply(rows) }
    private var shownRules: [DecisionRule] {
        let n = ruleSearch.trimmingCharacters(in: .whitespaces).lowercased()
        return rules.filter { n.isEmpty || $0.pattern.lowercased().contains(n) || $0.repo.lowercased().contains(n) }
    }

    var body: some View {
        Group {
            if let id = opened, let r = rows.first(where: { $0.id == id }) { entry(r) } else { page }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
        .overlay(alignment: .bottom) { if let r = stoppedRule { undoToast(r) } }
        .background(shortcuts)
        .focusable()
        .focusEffectDisabled()
        .focused($keys)
        .onKeyPress(phases: .down) { k in key(k) }
        .onAppear { search = win.actionLogQuery.text; reload(); DispatchQueue.main.async { keys = true } }
        .onChange(of: win.actionLogQuery.range) { _, _ in reload() }
        .onChange(of: win.actionLogQuery.sessions) { _, _ in reload() }
        .onChange(of: model.decisions.map(\.answer)) { _, _ in reload() }
        .onChange(of: model.selfTestDecisions.map(\.answer)) { _, _ in reload() }
        .onChange(of: search) { _, s in
            let typed = s
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { if search == typed { win.actionLogQuery.text = typed } }
        }
        .onReceive(NotificationCenter.default.publisher(for: .historyChanged)) { _ in reload() }
        .onReceive(NotificationCenter.default.publisher(for: .actionLogSelfTest)) { n in
            if let i = n.object as? Int, list.indices.contains(i) { opened = list[i].id }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Action log: " + ActionLog.subtitle)
    }

    private func reload() {
        generation += 1
        let gen = generation, q = win.actionLogQuery, store = model.store
        var names: [String: String] = [:]
        for i in model.sessionItems { names[i.id] = i.session.name }
        let mem = (model.decisions + model.selfTestDecisions).filter { !$0.isOpen }
        DispatchQueue.global(qos: .userInitiated).async {
            var byId: [UUID: ActionLogRow] = [:]
            for r in store?.actionLog(q, names: names, limit: 100_000) ?? [] { byId[r.id] = r }
            // The app's own answers not yet read back, and the self-test's asks (no store row).
            for d in mem where byId[d.id] == nil { byId[d.id] = ActionLogRow(decision: d, sessionName: names[d.sessionId], closed: names[d.sessionId] == nil) }
            let all = q.applyAll(Array(byId.values))
            let rs = store?.decisionRulesNewestFirst() ?? []
            DispatchQueue.main.async { if gen == generation { rows = all; rules = rs } }
        }
    }

    // MARK: Page

    private var page: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Button(action: back) { Text("‹ Inbox").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }.buttonStyle(.plain)
                            .help("Back to the Inbox (⌘[ or Esc)")
                        Text("INBOX › ACTION LOG").ui(10.5, .bold).tracking(0.5).foregroundStyle(t.accentText.color)
                    }
                    Text("Action log").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color).accessibilityAddTraits(.isHeader)
                    Text(ActionLog.subtitle).ui(13).foregroundStyle(t.text2.color)
                }
                tabs
                if tab == .decisions { decisionsTab } else { rulesTab }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 26)
            .frame(maxWidth: .infinity)
        }
    }

    private var tabs: some View {
        Picker("", selection: Binding(get: { tab }, set: { win.actionLog = $0; win.actionLogTab = $0; opened = nil })) {
            Text(ActionLog.tabTitle(.decisions, count: list.count)).tag(ActionLogTab.decisions)
            Text(ActionLog.tabTitle(.rules, count: rules.count)).tag(ActionLogTab.rules)
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()
        .accessibilityLabel("Action log tab")
    }

    // MARK: Decisions

    @ViewBuilder private var decisionsTab: some View {
        let list = self.list
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { searchField.frame(width: 300); filterMenus; Spacer(minLength: 0) }
            VStack(alignment: .leading, spacing: 8) { searchField.frame(maxWidth: 380); HStack(spacing: 8) { filterMenus; Spacer(minLength: 0) } }
        }
        chips
        Text(list.isEmpty ? ActionLog.emptyDecisions : ActionLog.resultLine(list.count)).ui(12).foregroundStyle(t.text2.color)
        if list.isEmpty {
            Button { win.actionLogQuery.range = .last30 } label: { Text("Show last 30 days").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain)
        } else {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(Self.days(list), id: \.0) { day, rs in
                    Section {
                        VStack(spacing: 0) {
                            ForEach(Array(rs.enumerated()), id: \.element.id) { n, r in
                                decisionRow(r)
                                if n < rs.count - 1 { Hairline() }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card.color))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separatorStrong.color))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .padding(.bottom, 12)
                    } header: {
                        Text(HistoryFormat.dayHeader(day)).ui(11.5, .bold).tracking(0.4).foregroundStyle(t.text2.color)
                            .padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).background(t.window.color)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
        }
    }

    static func days(_ rows: [ActionLogRow]) -> [(Date, [ActionLogRow])] {
        var out: [(Date, [ActionLogRow])] = []
        for r in rows {
            let d = Calendar.current.startOfDay(for: r.decision.answeredAt ?? r.decision.askedAt)
            if out.last?.0 == d { out[out.count - 1].1.append(r) } else { out.append((d, [r])) }
        }
        return out
    }

    private func decisionRow(_ r: ActionLogRow) -> some View {
        let d = r.decision
        let a = ActionLogAnswer.of(d)
        return Button { opened = r.id } label: {
            HStack(alignment: .center, spacing: 12) {
                Text(HistoryFormat.stamp(d.answeredAt ?? d.askedAt)).ui(11, mono: true).foregroundStyle(t.text2.color)
                    .lineLimit(1).fixedSize().frame(width: 150, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        sessionBadge(r, size: 18)
                        Text(r.shownName).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                    }
                    Text(ScrollFeed.askText(d)).ui(13).foregroundStyle(t.text.color).lineLimit(1)
                }
                Spacer(minLength: 10)
                HStack(spacing: 5) {
                    Text(a?.glyph ?? "").ui(12.5, .bold).foregroundStyle((a?.colour ?? .text2).rgb(t).color)
                    Text(ActionLog.answerLine(d)).ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
                }
                .frame(maxWidth: 300, alignment: .trailing)
                Text("›").ui(14, .semibold).foregroundStyle(t.text2.color)
            }
            .padding(.horizontal, 14).frame(minHeight: 52)
            .background(focusedRow == r.id ? t.rowHover.color : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(ActionLogRowStyle(hover: t.selection))
        .onHover { if $0 { focusedRow = r.id } }
        .accessibilityLabel(ActionLog.rowAccessibility(r))
        .accessibilityHint("Opens the whole ask")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text2.color)
            TextField("", text: $search, prompt: Text("Search asks, answers, sessions").foregroundStyle(t.text2.color))
                .textFieldStyle(.plain).ui(13).foregroundStyle(t.text.color).focused($searchFocused)
                .onKeyPress(.escape) { search = ""; win.actionLogQuery.text = ""; return .handled }
                .accessibilityLabel("Search the action log")
        }
        .padding(.horizontal, 10).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(searchFocused ? t.accent.color : t.separatorStrong.color, lineWidth: searchFocused ? 2 : 1))
    }

    @ViewBuilder private var filterMenus: some View {
        let q = query
        Menu {
            ForEach(HistoryRange.presets, id: \.title) { r in
                Toggle(r.title, isOn: Binding(get: { win.actionLogQuery.range == r }, set: { if $0 { win.actionLogQuery.range = r } }))
            }
            Divider()
            Button("Custom…") { customPicker = true }
        } label: { pill(q.range.title, on: !q.range.isDefault, symbol: "calendar") }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .popover(isPresented: $customPicker, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 10) {
                DatePicker("From", selection: $customFrom, displayedComponents: .date)
                DatePicker("To", selection: $customTo, displayedComponents: .date)
                HStack { Spacer(); Button("Apply") { win.actionLogQuery.range = .custom(from: customFrom, to: customTo); customPicker = false } }
            }.padding(14).frame(width: 250)
        }
        .accessibilityLabel("Date range")
        Button { sessionPicker = true } label: { pill("Session" + (q.sessions.isEmpty ? "" : " · \(q.sessions.count)"), on: !q.sessions.isEmpty) }
            .buttonStyle(.plain)
            .popover(isPresented: $sessionPicker, arrowEdge: .bottom) { sessionPopover }
            .accessibilityLabel("Filter by session")
        Menu {
            ForEach(ActionLogAnswer.allCases, id: \.self) { a in
                Toggle(a.title, isOn: Binding(get: { win.actionLogQuery.answers.contains(a) },
                                              set: { if $0 { win.actionLogQuery.answers.insert(a) } else { win.actionLogQuery.answers.remove(a) } }))
            }
            if !q.answers.isEmpty { Divider(); Button("Any answer") { win.actionLogQuery.answers = [] } }
        } label: { pill("Answer" + (q.answers.isEmpty ? "" : " · \(q.answers.count)"), on: !q.answers.isEmpty) }
        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
        .accessibilityLabel("Filter by answer")
    }

    @State private var sessionFind = ""
    private var sessionPopover: some View {
        // Sessions with a decision in the range (before the session filter), newest answer first.
        var seen: [String: String] = [:]
        var order: [String] = []
        for r in rows where seen[r.decision.sessionId] == nil { seen[r.decision.sessionId] = r.shownName; order.append(r.decision.sessionId) }
        for s in query.sessions where seen[s] == nil { seen[s] = model.item(s)?.session.name ?? s; order.append(s) }
        let n = sessionFind.lowercased()
        return VStack(alignment: .leading, spacing: 8) {
            TextField("Find a session", text: $sessionFind).textFieldStyle(.roundedBorder)
            Button("All sessions") { win.actionLogQuery.sessions = [] }.buttonStyle(.plain)
            Hairline()
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(order.filter { n.isEmpty || (seen[$0] ?? "").lowercased().contains(n) }, id: \.self) { id in
                        Toggle(seen[id] ?? id, isOn: Binding(get: { win.actionLogQuery.sessions.contains(id) },
                                                             set: { if $0 { win.actionLogQuery.sessions.insert(id) } else { win.actionLogQuery.sessions.remove(id) } }))
                            .toggleStyle(.checkbox)
                    }
                }
            }.frame(maxHeight: 280)
        }
        .padding(12).frame(width: 280)
    }

    @ViewBuilder private var chips: some View {
        let cs = query.chips { id in rows.first { $0.decision.sessionId == id }?.shownName ?? model.item(id)?.session.name ?? id }
        if !cs.isEmpty {
            HStack(spacing: 6) {
                ForEach(Array(cs.enumerated()), id: \.offset) { _, c in
                    Button { win.actionLogQuery.remove(c.remove) } label: {
                        HStack(spacing: 5) { Text(c.label).ui(11.5, .semibold).lineLimit(1); Text("×").ui(12, .bold) }
                            .foregroundStyle(t.text.color).padding(.horizontal, 9).frame(height: 22)
                            .background(Capsule().fill(t.selection.color)).overlay(Capsule().strokeBorder(t.separatorStrong.color))
                    }
                    .buttonStyle(.plain).accessibilityLabel("Remove filter: " + c.label.replacingOccurrences(of: ": ", with: " "))
                }
                Button { win.actionLogQuery.clearFilters() } label: { Text("Clear all").ui(11.5, .semibold).foregroundStyle(t.accentText.color) }
                    .buttonStyle(.plain).padding(.leading, 4)
            }
        }
    }

    private func pill(_ title: String, on: Bool, symbol: String? = nil) -> some View {
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

    // MARK: An opened entry

    private func entry(_ r: ActionLogRow) -> some View {
        let d = r.decision
        let item = model.item(d.sessionId)
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Button { opened = nil } label: { Text("‹ Action log").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }.buttonStyle(.plain)
                        .help("Back to the list (⌘[ or Esc); ↑ ↓ step through it")
                    Spacer()
                    Button { step(-1, from: r.id) } label: { Text("↑ Newer").ui(12).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                        .disabled(ActionLog.step(from: r.id, by: -1, in: list) == nil)
                    Button { step(1, from: r.id) } label: { Text("↓ Older").ui(12).foregroundStyle(t.text2.color) }.buttonStyle(.plain)
                        .disabled(ActionLog.step(from: r.id, by: 1, in: list) == nil)
                }
                HStack(spacing: 10) {
                    sessionBadge(r, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.shownName).ui(15, .semibold).foregroundStyle(t.text.color)
                        Text([d.agent.displayName, item.flatMap { $0.account ?? $0.session.account }, item.flatMap { model.window(model.workspaceId(of: $0))?.name }]
                            .compactMap { $0 }.joined(separator: " · ")).ui(12).foregroundStyle(t.text2.color)
                    }
                    Spacer()
                    if let item, item.liveAgent != nil || item.endedShell != nil {
                        Button { model.reveal(item) } label: { Text("Open session ↗").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                            .buttonStyle(.plain).help("Open the session's terminal")
                    }
                }
                section("Asked · " + HistoryFormat.stamp(d.askedAt)) {
                    Text(d.headline).ui(14, .semibold).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    if let c = d.command ?? d.path {
                        Text(c).ui(12.5, mono: true).foregroundStyle(ThemeName.midnight.tokens.text.color).textSelection(.enabled)
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThemeName.midnight.tokens.surface.color))
                    }
                    if let screen = d.screen, !screen.isEmpty {
                        Text(screen.joined(separator: "\n")).ui(12, mono: true).foregroundStyle(ThemeName.midnight.tokens.text.color)
                            .textSelection(.enabled).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(ThemeName.midnight.tokens.window.color))
                    }
                }
                section("The options shown") {
                    if let opts = ActionLog.options(d) {
                        ForEach(Array(opts.enumerated()), id: \.offset) { n, o in
                            HStack(spacing: 8) {
                                Text("\(n + 1).").ui(12.5, mono: true).foregroundStyle(t.text2.color)
                                Text(o.label).ui(13, o.chosen ? .semibold : .regular).foregroundStyle(t.text.color)
                                if o.chosen { Text("← you chose this").ui(12, .semibold).foregroundStyle(t.accentText.color) }
                            }
                        }
                    } else if d.isQuestion || d.isFinished {
                        Text("A question or a finished turn: answered with your own words.").ui(12.5).foregroundStyle(t.text2.color)
                    } else {
                        Text(ActionLog.notRecorded).ui(12.5).foregroundStyle(t.text2.color)
                    }
                }
                section("Why · what it touches · risk") {
                    detail("Why", d.why)
                    detail("What it touches", d.touches)
                    detail("Risk", d.risk.rawValue.capitalized)
                    detail("If you say no", d.ifNo)
                    detail("Where this sits", d.where_)
                }
                section("You answered · " + (d.answeredAt.map { HistoryFormat.stamp($0) } ?? "–")) {
                    let a = ActionLogAnswer.of(d)
                    HStack(spacing: 6) {
                        Text(a?.glyph ?? "").ui(13, .bold).foregroundStyle((a?.colour ?? .text2).rgb(t).color)
                        Text(ActionLog.answerLine(d)).ui(13.5, .semibold).foregroundStyle(t.text.color).textSelection(.enabled)
                    }
                    if let reply = d.replyText, !reply.isEmpty, reply != d.chosen, !["answered in the terminal", "set aside"].contains(reply) {
                        Text(reply).ui(13).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: 980, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 26)
            .frame(maxWidth: .infinity)
        }
        .accessibilityLabel("Decision: " + ActionLog.rowAccessibility(r))
    }

    private func section<C: View>(_ title: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).ui(11.5, .bold).tracking(0.3).foregroundStyle(t.text2.color).accessibilityAddTraits(.isHeader)
            c()
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separatorStrong.color))
    }

    @ViewBuilder private func detail(_ label: String, _ text: String) -> some View {
        if !text.trimmingCharacters(in: .whitespaces).isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(label).ui(12, .semibold).foregroundStyle(t.text2.color).frame(width: 120, alignment: .leading)
                Text(text).ui(13).foregroundStyle(t.text.color).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func step(_ delta: Int, from id: UUID) { if let n = ActionLog.step(from: id, by: delta, in: list) { opened = n } }

    // MARK: Rules

    @ViewBuilder private var rulesTab: some View {
        Text(ActionLog.rulesExplainer).ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(t.text2.color)
            TextField("", text: $ruleSearch, prompt: Text("Search rules").foregroundStyle(t.text2.color)).textFieldStyle(.plain).ui(13)
                .accessibilityLabel("Search rules")
        }
        .padding(.horizontal, 10).frame(width: 300, height: 30)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(t.card.color))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separatorStrong.color))
        let rs = shownRules
        if rs.isEmpty {
            Text(rules.isEmpty ? ActionLog.emptyRules : "No rule matches.").ui(13).foregroundStyle(t.text2.color)
        } else {
            VStack(spacing: 0) {
                ForEach(Array(rs.enumerated()), id: \.element.id) { n, r in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(r.pattern).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                            Text(Workspace.repoLabel(for: r.repo) + " · added " + HistoryFormat.stamp(r.createdAt)).ui(11.5).foregroundStyle(t.text2.color).lineLimit(1)
                        }
                        Spacer()
                        Button { stop(r) } label: {
                            Text(ActionLog.stopRule).ui(12, .semibold).foregroundStyle(t.text.color)
                                .padding(.horizontal, 10).frame(height: 26)
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(t.separatorStrong.color))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Removes One Roof's note only; the agent keeps its own always-allow setting")
                        .accessibilityLabel(ActionLog.stopAccessibility(r))
                    }
                    .padding(.horizontal, 14).frame(minHeight: 52)
                    if n < rs.count - 1 { Hairline() }
                }
            }
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(t.card.color))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(t.separatorStrong.color))
        }
    }

    private func stop(_ r: DecisionRule) {
        model.stopNoting(r)
        withAnimation(Motion.fast) { rules.removeAll { $0.id == r.id } }
        stoppedRule = r
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { if stoppedRule?.id == r.id { withAnimation(Motion.fast) { stoppedRule = nil } } }
    }

    private func undoToast(_ r: DecisionRule) -> some View {
        HStack(spacing: 12) {
            Text(ActionLog.stopped(r)).ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
            Button { model.restoreRule(r); stoppedRule = nil; reload() } label: { Text("Undo").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).frame(height: 38)
        .background(Capsule().fill(t.card.color))
        .overlay(Capsule().strokeBorder(t.separatorStrong.color))
        .padding(.bottom, 18)
    }

    // MARK: Keys

    /// ⌘[ back (an opened entry → the list → the Inbox), ⌘F search, ⌘1 / ⌘2 tabs (key equivalents). ↑ ↓ rows or
    /// entries, ↩ open and Esc back come from the page's own key handler (`key`), so a search field keeps its keys.
    private var shortcuts: some View {
        ZStack {
            Button("") { goBack() }.keyboardShortcut("[", modifiers: .command)
            Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command)
            Button("") { win.actionLog = .decisions; win.actionLogTab = .decisions; opened = nil }.keyboardShortcut("1", modifiers: .command)
            Button("") { win.actionLog = .rules; win.actionLogTab = .rules; opened = nil }.keyboardShortcut("2", modifiers: .command)
        }
        .buttonStyle(.plain).frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
    }

    private func key(_ k: KeyPress) -> KeyPress.Result {
        guard k.modifiers.isEmpty || k.modifiers == .numericPad || k.modifiers == .function else { return .ignored }
        switch k.key {
        case .upArrow: move(-1); return .handled
        case .downArrow: move(1); return .handled
        case .return: if opened == nil, let f = focusedRow { opened = f; return .handled }; return .ignored
        case .escape: goBack(); return .handled
        default: return .ignored
        }
    }

    private func goBack() {
        if opened != nil { opened = nil } else if searchFocused && !search.isEmpty { search = "" } else { back() }
    }

    private func move(_ delta: Int) {
        guard tab == .decisions else { return }
        if let o = opened { step(delta, from: o); return }
        let l = list
        guard !l.isEmpty else { return }
        if let f = focusedRow, let n = ActionLog.step(from: f, by: delta, in: l) { focusedRow = n } else if focusedRow == nil { focusedRow = l.first?.id }
    }

    @ViewBuilder private func sessionBadge(_ r: ActionLogRow, size: CGFloat) -> some View {
        if let i = model.item(r.decision.sessionId) { AgentBadge(item: i, size: size, status: false) }
        else { AgentBadge(SeatMark(agent: r.decision.agent, account: nil), size: size) }
    }
}

/// A row: hover = selection at 50 %, pressed = selection.
struct ActionLogRowStyle: ButtonStyle {
    let hover: RGB
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background(configuration.isPressed ? hover.color : .clear)
    }
}

extension Notification.Name {
    /// Self-test: open the i-th row of the Decisions tab (`actionlog open <i>`).
    static let actionLogSelfTest = Notification.Name("oneroof.actionlog.selftest")
}
