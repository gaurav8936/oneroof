import AppKit
import SwiftUI
import OneRoofCore

/// Loops › Tonight (handover A9): what runs tonight (Tonight and Nightly schedules), last night's results, and
/// + Schedule a session (planned sessions, Tonight 2:00 AM — the same as the row's Schedule menu).
struct V2TonightPanel: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard

    /// Nightly loops (stopped ones don't run).
    private var nightlyLoops: [Loop] { board.loops.filter { $0.trigger.isNightly && $0.state != .stopped && $0.state != .paused } }

    /// Since yesterday 6 PM: the last stop line of each loop, with its result.
    private var loopsLastNight: [(Loop, LoopRound)] {
        let cal = Calendar.current
        let since = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()) ?? Date()
        return board.loops.compactMap { l in
            (board.rounds[l.id] ?? []).last(where: { $0.kind == .stop && $0.ended > since }).map { (l, $0) }
        }
    }

    private var tonight: [(BoardItem, ScheduleRecord)] {
        model.scheduleRecords.values.compactMap { r -> (BoardItem, ScheduleRecord)? in
            switch r.schedule { case .tonight, .nightly: return model.item(r.sessionId).map { ($0, r) }; default: return nil }
        }.sorted { $0.0.session.name < $1.0.session.name }
    }

    /// Tonight / Nightly session runs since yesterday 6 PM.
    private var lastNight: [(BoardItem, ScheduleRecord)] {
        let cal = Calendar.current
        let since = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()) ?? Date()
        return model.scheduleRecords.values.compactMap { r -> (BoardItem, ScheduleRecord)? in
            switch r.schedule { case .tonight, .nightly: break; default: return nil }
            guard let d = r.lastRun, d > since, let i = model.item(r.sessionId) else { return nil }
            return (i, r)
        }.sorted { ($0.1.lastRun ?? .distantPast) > ($1.1.lastRun ?? .distantPast) }
    }

    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                scheduled
                scheduleMenu
                Hairline().padding(.vertical, 4)
                lastNightSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var scheduled: some View {
        let list = tonight, loops = nightlyLoops
        Text("Tonight").ui(15, .semibold).foregroundStyle(t.text.color)
        Text(list.isEmpty && loops.isEmpty ? "0 scheduled. Schedule any session from its right-click menu, or here." : "\(list.count + loops.count) scheduled.")
            .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
        ForEach(list, id: \.0.id) { i, r in
            row(i.session.name, r.schedule.label)
                .contentShape(Rectangle())
                .onTapGesture { model.reveal(i) }
                .contextMenu { Button("On Demand (unschedule)") { model.unschedule(i) } }
        }
        ForEach(loops) { l in row(l.name, l.trigger.label) }
    }

    private func row(_ name: String, _ when: String) -> some View {
        HStack {
            Text(name).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
            Spacer()
            Text(when).ui(11.5).foregroundStyle(t.text2.color)
        }
    }

    /// Planned and Next sessions (as the row's Schedule › Tonight 2:00 AM).
    private var scheduleMenu: some View {
        let planned = model.sessionItems.filter { ($0.status == .planned || $0.status == .next) && $0.session.agent.isAgent && model.scheduleRecords[$0.id] == nil }
        return Menu {
            if planned.isEmpty { Text("No planned sessions to schedule") }
            ForEach(planned) { i in Button(i.session.name) { model.schedule(i, hour: 2, minute: 0, nightly: false) } }
        } label: { Text("+ Schedule a session") }
        .fixedSize()
        .help("Run a planned session tonight at 2:00 AM")
    }

    @ViewBuilder private var lastNightSection: some View {
        let ln = lastNight, lln = loopsLastNight
        MicroLabel("Last night")
        if ln.isEmpty && lln.isEmpty { Text("Nothing ran.").ui(12).foregroundStyle(t.text3.color) }
        ForEach(lln, id: \.0.id) { l, r in line(Self.loopLine(l, r)) }
        ForEach(ln, id: \.0.id) { i, r in line(i.session.name + (r.lastResult.map { " · " + $0 } ?? "")) }
    }

    private func line(_ s: String) -> some View { Text(s).ui(12).foregroundStyle(t.text.color).lineLimit(2) }

    static func loopLine(_ l: Loop, _ r: LoopRound) -> String {
        var s = l.name + " · finished " + r.ended.formatted(date: .omitted, time: .shortened)
        if let n = r.note, !n.isEmpty { s += " · " + n }
        return s
    }
}

/// Needs you › Rules (handover C2.2, NEW-19): every always-allow rule with Remove, and what you decided today.
struct V2RulesPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var back: () -> Void
    @State private var tick = 0   // the rules live in the store; redraw after a Remove

    var body: some View {
        let rules = (model.store?.decisionRules() ?? []).sorted { $0.createdAt > $1.createdAt }
        let today = model.decisions.filter { !$0.isOpen && Calendar.current.isDateInToday($0.answeredAt ?? .distantPast) }
            .sorted { ($0.answeredAt ?? .distantPast) > ($1.answeredAt ?? .distantPast) }
        let _ = tick
        VStack(alignment: .leading, spacing: 14) {
            Button(action: back) { Text("‹ Needs you").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }.buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command).help("Back to the queue (⌘[)")
            VStack(alignment: .leading, spacing: 4) {
                Text("What you've allowed, and what you decided today").ui(TypeScale.title, .semibold).foregroundStyle(t.text.color)
                Text("One Roof notes when a new decision in the same repo matches one of these; it never answers for you. Always allow also told the agent not to ask again, and the agent keeps that in its own settings: removing a rule here only removes One Roof's note.").ui(13).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            HStack(alignment: .top, spacing: 14) {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        MicroLabel("Always allow · \(rules.count) rule\(rules.count == 1 ? "" : "s")").padding(.bottom, 8)
                        if rules.isEmpty { Text("None yet. Always allow on a decision adds one.").ui(12.5).foregroundStyle(t.text3.color) }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(rules) { r in
                                    HStack(spacing: 10) {
                                        CheckGlyph(passed: true)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(r.pattern).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color).lineLimit(1)
                                            Text(Workspace.repoLabel(for: r.repo) + " · added " + r.createdAt.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                                                .ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
                                        }
                                        Spacer()
                                        RoofButton("Remove") { model.removeRule(pattern: r.pattern, repo: r.repo); tick += 1 }
                                    }
                                    .padding(.vertical, 7)
                                    Hairline()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        MicroLabel("Today · \(today.count) decided").padding(.bottom, 8)
                        if today.isEmpty { Text("Nothing decided today.").ui(12.5).foregroundStyle(t.text3.color) }
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(today) { d in
                                    HStack(spacing: 10) {
                                        if d.answer == .deny { CheckGlyph(passed: false) } else if d.answer?.isAllow == true { CheckGlyph(passed: true) } else { Text("·").ui(12.5).foregroundStyle(t.text3.color) }
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(Self.verb(d) + " · " + (d.command ?? d.headline)).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                                            Text((model.item(d.sessionId)?.session.name ?? "") + " · " + (d.answeredAt?.formatted(date: .omitted, time: .shortened) ?? ""))
                                                .ui(11.5).foregroundStyle(t.text3.color).lineLimit(1)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 7)
                                    Hairline()
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28).padding(.top, 22).padding(.bottom, 26)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(t.window.color)
    }

    static func verb(_ d: Decision) -> String {
        switch d.answer {
        case .allowOnce: return "Allowed once"
        case .always: return "Always allowed"
        case .deny: return "Denied"
        case .reply: return "Replied" + (d.replyText.map { " · " + $0 } ?? "")
        case nil: return "Decided"
        }
    }
}

/// A loop's fences (NEW-24, C5.1), worded as what is enforced (✓) and what the loop is only told (•), from
/// roofd's LoopEngine and the round prompt (OneRoofCore/Loops.swift): no claim stronger than the code.
struct V2LoopFences: View {
    @Environment(\.theme) private var t
    let loop: Loop
    var body: some View {
        let mins = Int(loop.limits.maxDuration / 60)
        VStack(alignment: .leading, spacing: 6) {
            MicroLabel("Fences")
            fence(true, "Stops at \(loop.limits.maxRounds) rounds or \(Schedule.every(mins))" + (loop.limits.sameFailureStop > 0 ? ", or after \(loop.limits.sameFailureStop) rounds with the same failure" : ""))
            fence(true, "Each round starts in its own worktree, \(Workspace.repoLabel(for: loop.worktreePath)) on \(loop.branch)")
            fence(false, "Told never to push, merge or deploy, and never to touch your checkout (an instruction, not a technical block)")
            fence(false, "Permission prompts come to Needs you, unless the agent already allows that command itself")
        }
    }
    private func fence(_ enforced: Bool, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if enforced { CheckGlyph(passed: true) } else { Text("•").ui(12.5, .bold).foregroundStyle(t.text3.color).accessibilityLabel("instruction") }
            Text(s).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}
