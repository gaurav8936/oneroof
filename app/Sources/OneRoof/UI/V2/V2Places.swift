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

// LAB-2048: Inbox › Rules (V2RulesPage, two side-by-side cards) became the Action log, UI/V2/V2ActionLog.swift.

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
            fence(false, "Permission prompts come to the Inbox, unless the agent already allows that command itself")
        }
    }
    private func fence(_ enforced: Bool, _ s: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if enforced { CheckGlyph(passed: true) } else { Text("•").ui(12.5, .bold).foregroundStyle(t.text3.color).accessibilityLabel("instruction") }
            Text(s).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
    }
}
