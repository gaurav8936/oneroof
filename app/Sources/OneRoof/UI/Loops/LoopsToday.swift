import AppKit
import SwiftUI
import OneRoofCore

// LAB-2292 · 7f Today (by the hour) (handover 07-7f.png, pages/7f-today): one sentence (overnight runs, failures,
// misses; what ran since 8:00), the filter bar and Today · Last 24 h, a 24 h clock with one lane per loop that is on
// (runs as dots, missed slots dashed, times still to come hollow from the schedule, a band for loops that run every few
// minutes, the now line), NEXT UP (each loop's next run) and WHILE YOU SLEPT (failures and misses, with Open / Run now,
// and last night's scheduled sessions: 2.0.5's Tonight panel › Last night). Tonight (7g) is one click away.

struct LoopsToday: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    @ObservedObject private var inbox = LoopInboxState.shared
    let actions: LoopsV7Actions
    /// A day picked on This week (nil = today).
    let day: Date?
    /// The loop whose lane is marked (from a This week cell).
    let focus: String?
    @State private var last24 = false
    @State private var older: [String: [LoopRun7]]?
    @State private var confirmRun: String?

    private var isToday: Bool { day.map { Calendar.current.isDateInToday($0) } ?? true }

    var body: some View {
        let cal = Calendar.current
        let now = Date()
        let f = nav.filter("7f")
        let dayStart = cal.startOfDay(for: day ?? now)
        let window = last24 && isToday ? (now.addingTimeInterval(-86400), now) : (dayStart, cal.date(byAdding: .day, value: 1, to: dayStart)!)
        let fresh = dayStart > now.addingTimeInterval(-7 * 86400)
        let runs = fresh ? Dictionary(grouping: board.weekRuns, by: \.loop) : (older ?? [:])
        let rows = LoopsV7.filter(board.rows, f.wrappedValue)
        let loopLanes = LoopsV7.dayLanes(rows: rows, runs: runs, crons: board.crons, start: window.0, end: window.1, now: now)
        let lanes = loopLanes + (f.wrappedValue.isEmpty ? [LoopsV7.sessionLane(scheduledSessions(now), start: window.0, end: window.1)].compactMap { $0 } : [])
        let head = LoopsV7.dayHeadline(lanes: lanes, start: window.0, end: window.1, now: now, last24h: last24 && isToday)
        let night = (dayStart, cal.date(bySettingHour: 8, minute: 0, second: 0, of: dayStart)!)
        let nightLanes = last24 ? LoopsV7.dayLanes(rows: rows, runs: runs, crons: board.crons, start: night.0, end: night.1, now: now) : lanes
        let slept = LoopsV7.whileYouSlept(lanes: nightLanes, from: night.0, to: night.1)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                (Text(head.lead + " ").foregroundColor(t.text.color) + Text(head.bold).bold().foregroundColor(t.text.color)
                    + Text(head.rest).foregroundColor(t.text.color))
                    .ui(14.5).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    LoopFilterBar(filter: f)
                    Spacer(minLength: 8)
                    if isToday {
                        Segmented(options: [(false, "Today"), (true, "Last 24 h")], selection: $last24)
                            .help("Today: midnight to midnight · Last 24 h: the 24 hours ending now")
                            .accessibilityLabel("Window")
                    }
                }
                LoopCard(padding: 0, shadow: false) {
                    VStack(spacing: 0) {
                        if lanes.isEmpty {
                            HStack(spacing: 10) {
                                Text(f.wrappedValue.isEmpty ? "No loop is on, and none ran." : LoopsV7.emptyLine(f.wrappedValue)).ui(13).foregroundStyle(t.text2.color)
                                if !f.wrappedValue.isEmpty { RoofButton("Clear", .plain) { f.wrappedValue = LoopFilter() } }
                                Spacer()
                            }
                            .padding(16)
                        } else {
                            LoopDayClock(lanes: lanes, start: window.0, end: window.1, now: now, focus: focus,
                                         openRun: { nav.open(.run($0)) })
                        }
                        legend
                    }
                }
                HStack(alignment: .top, spacing: 14) {
                    nextUp(now: now)
                    sleptCard(slept)
                }
            }
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.top)
        .onAppear { if !fresh { load(dayStart) } }
        .alert(confirmRun.map { "Run \(board.row($0)?.name ?? $0) now?" } ?? "", isPresented: Binding(get: { confirmRun != nil }, set: { if !$0 { confirmRun = nil } })) {
            Button("Run now") { if let id = confirmRun { board.runNowAny(id); DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() } }; confirmRun = nil }
            Button("Cancel", role: .cancel) { confirmRun = nil }
        } message: {
            Text(confirmRun.flatMap { board.row($0) }.map { $0.engine == .kit
                ? "The kit runs it once now (`\(KitLoops.command("run", $0.id).dropFirst().joined(separator: " "))`). A loop in trial only writes what it would do."
                : "One Roof starts a run within 30 s: the check first, then rounds in the loop's own worktree." } ?? "")
        }
        .accessibilityLabel("Loops today")
    }

    private func load(_ d: Date) {
        let path = LoopLedger.defaultPath(loopsRoot: board.store.root)
        DispatchQueue.global(qos: .userInitiated).async {
            let led = try? LoopLedger(readingOnly: path)
            let runs = LoopsV7.runsByLoop(led, from: d.addingTimeInterval(-8 * 86400), to: d.addingTimeInterval(86400))
            DispatchQueue.main.async { older = runs }
        }
    }

    private var legend: some View {
        VStack(spacing: 0) {
            Rectangle().fill(t.separator.color).frame(height: 1)
            HStack(spacing: 14) {
                ForEach([LoopRun7.Result.passed, .failed, .trial, .toCome, .missed], id: \.self) { r in
                    HStack(spacing: 5) {
                        LoopDayDot(result: r)
                        Text(r == .toCome ? "to come" : r.rawValue).ui(12).foregroundStyle(t.text2.color)
                    }
                }
                Spacer()
                Text("Click a dot to open that run").ui(12).foregroundStyle(t.text2.color)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
        }
    }

    // MARK: Next up

    private func nextUp(now: Date) -> some View {
        let next = LoopsV7.departures(rows: LoopsV7.filter(board.rows, nav.filter("7f").wrappedValue), crons: board.crons, now: now)
        return LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    LoopLabel("Next up")
                    Spacer()
                    Button { nav.open(.tonight) } label: { Text("Tonight ›").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain).help("What runs tonight, and + Schedule a session")
                        .accessibilityLabel("Open Tonight")
                }
                if next.isEmpty { Text("Nothing is scheduled.").ui(12.5).foregroundStyle(t.text2.color) }
                ForEach(next) { d in
                    HStack(spacing: 10) {
                        Text(LoopsV7.when(d.at, now: now)).ui(12.5, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 84, alignment: .leading)
                        Text(d.name + " · " + (d.engine == .kit ? "kit" : "One Roof")).ui(12.5).foregroundStyle(t.text.color).lineLimit(1)
                        Spacer()
                        let p = LoopLook.tone(d.trial ? .trial : .off, theme: t.name)
                        Text(d.tag).ui(11, .semibold).foregroundStyle(p.text.color)
                            .padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(p.fill.color))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: While you slept (+ last night's sessions)

    private func sleptCard(_ s: (items: [LoopsV7.SleptItem], span: (Date, Date)?)) -> some View {
        let sessions = lastNightSessions
        return LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 8) {
                LoopLabel("While you slept" + (s.span.map { " · " + LoopsV7.when($0.0) + " – " + LoopsV7.when($0.1) } ?? ""))
                if s.items.isEmpty && sessions.isEmpty { Text("Nothing failed or was missed overnight.").ui(12.5).foregroundStyle(t.text2.color) }
                ForEach(s.items) { i in
                    HStack(alignment: .center, spacing: 10) {
                        Circle().fill((i.kind == .failed ? t.needsText : LoopLook.tone(.needsYou, theme: t.name).text).color).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(i.name).ui(13, .semibold).foregroundStyle(t.text.color)
                            Text(i.line).ui(12).foregroundStyle(t.text2.color).lineLimit(2)
                        }
                        Spacer()
                        if i.kind == .failed {
                            RoofButton("Open") { if let r = i.runId { nav.open(.run(r)) } else { actions.openLoop(i.loop) } }
                                .help("The run, its steps and its report")
                        } else {
                            RoofButton("Run now") { confirmRun = i.loop }.disabled(inbox.busy.contains(i.loop))
                        }
                    }
                }
                ForEach(sessions, id: \.0) { id, line in
                    HStack(spacing: 10) {
                        Circle().fill(t.accentText.color).frame(width: 7, height: 7)
                        Text(line).ui(12.5).foregroundStyle(t.text.color).lineLimit(2)
                        Spacer()
                        if let it = model.item(id) { RoofButton("Open ↗", .plain) { model.reveal(it) } }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Tonight and Nightly sessions with their next start (7g's list; hollow dots here).
    private func scheduledSessions(_ now: Date) -> [LoopsV7.TonightSession] {
        model.scheduleRecords.values.compactMap { r -> LoopsV7.TonightSession? in
            guard let i = model.item(r.sessionId), let at = ScheduleClock.nextFire(r, now: now) else { return nil }
            switch r.schedule { case .tonight, .nightly: break; default: return nil }
            return LoopsV7.TonightSession(id: i.id, name: i.session.name, line: "", at: at, nightly: r.schedule.kind == "nightly")
        }
    }

    /// 2.0.5's Tonight panel › Last night: Tonight and Nightly sessions that ran since yesterday 18:00.
    private var lastNightSessions: [(String, String)] {
        let cal = Calendar.current
        let since = cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: -1, to: Date()) ?? Date()) ?? Date()
        return model.scheduleRecords.values.compactMap { r -> (String, String)? in
            switch r.schedule { case .tonight, .nightly: break; default: return nil }
            guard let d = r.lastRun, d > since, let i = model.item(r.sessionId) else { return nil }
            return (i.id, "Session · " + i.session.name + " ran " + LoopsV7.when(d) + (r.lastResult.map { " · " + $0 } ?? ""))
        }
        .sorted { $0.1 < $1.1 }
    }
}

// MARK: - The clock

struct LoopDayClock: View {
    @Environment(\.theme) private var t
    let lanes: [LoopsV7.DayLane]
    let start: Date
    let end: Date
    let now: Date
    let focus: String?
    var openRun: (String) -> Void
    static let nameWidth: CGFloat = 210, laneHeight: CGFloat = 25

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.nameWidth)
                GeometryReader { g in axis(g.size.width) }.frame(height: 22)
            }
            .padding(.horizontal, 16).padding(.top, 10)
            ForEach(lanes) { l in lane(l) }
        }
        .padding(.bottom, 6)
    }

    private func x(_ d: Date, _ w: CGFloat) -> CGFloat {
        CGFloat(d.timeIntervalSince(start) / end.timeIntervalSince(start)) * w
    }

    /// Ticks every 3 h on the hour, and the now label.
    private func axis(_ w: CGFloat) -> some View {
        let cal = Calendar.current
        var ticks: [Date] = []
        var d = cal.dateInterval(of: .hour, for: start)?.start ?? start
        if d < start { d = d.addingTimeInterval(3600) }
        while d <= end { if cal.component(.hour, from: d) % 3 == 0 { ticks.append(d) }; d = d.addingTimeInterval(3600) }
        return ZStack(alignment: .topLeading) {
            ForEach(ticks, id: \.self) { tk in
                let isEnd = abs(tk.timeIntervalSince(end)) < 1
                Text(isEnd && cal.component(.hour, from: tk) == 0 ? "24" : LoopsV7.when(tk, now: tk))
                    .ui(11.5, mono: true).foregroundStyle(t.text2.color).fixedSize()
                    .position(x: min(max(x(tk, w), 14), w - 10), y: 8)
            }
            if now >= start && now <= end {
                Text("now " + LoopsV7.when(now, now: now)).ui(11.5, .bold).foregroundStyle(t.accentText.color).fixedSize()
                    .padding(.horizontal, 3).background(t.surface.color)
                    .position(x: min(max(x(now, w), 34), w - 34), y: 8)
            }
        }
    }

    private func lane(_ l: LoopsV7.DayLane) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(LoopLook.kind(l.row.family, theme: t.name).text.color).frame(width: 7, height: 7)
                Text(l.row.name).ui(12.5, .semibold).foregroundStyle(t.text.color).lineLimit(1).truncationMode(.tail)
                Text(l.row.engine == .kit ? "kit" : "One Roof").ui(11).foregroundStyle(t.text2.color).fixedSize()
                Spacer(minLength: 4)
            }
            .frame(width: Self.nameWidth, alignment: .leading)
            .help((l.row.engine == .kit ? "Run by the kit" : "Run by One Roof") + " · " + l.row.schedule + (l.row.mode == .shadow ? " · in trial" : ""))
            GeometryReader { g in track(l, g.size.width) }.frame(height: Self.laneHeight)
        }
        .padding(.horizontal, 16)
        .background(focus == l.row.id ? t.selection.color.opacity(0.6) : .clear)
        .overlay(alignment: .top) { Rectangle().fill(t.separator.color.opacity(0.6)).frame(height: 1).padding(.leading, 16) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(l.row.name + ": " + "\(l.marks.filter { $0.runId != nil }.count) runs")
    }

    private func track(_ l: LoopsV7.DayLane, _ w: CGFloat) -> some View {
        let h = Self.laneHeight
        let nowX = x(now, w)
        return ZStack(alignment: .topLeading) {
            // The past, shaded.
            Rectangle().fill(t.surface2.color.opacity(0.7)).frame(width: max(0, min(w, nowX)), height: h)
            band(l, w)
            ForEach(l.marks) { m in mark(l, m, w) }
            if now >= start && now <= end {
                Rectangle().fill(t.accent.color).frame(width: 2, height: h).offset(x: nowX - 1)
            }
        }
        .clipped()
    }

    @ViewBuilder private func band(_ l: LoopsV7.DayLane, _ w: CGFloat) -> some View {
        if let b = l.band, let from = l.bandFrom {
            let x0 = x(from, w)
            let h = Self.laneHeight
            Capsule().fill(LoopLook.tone(.running, theme: t.name).fill.color).frame(width: max(0, w - x0 - 2), height: 6)
                .offset(x: x0 + 2, y: h / 2 - 3)
            Text(b).ui(11.5, .semibold).foregroundStyle(t.accentText.color).fixedSize()
                .padding(.horizontal, 4).background(t.surface.color.opacity(0.9))
                .offset(x: x0 + 30, y: h / 2 - 8)
        }
    }

    @ViewBuilder private func mark(_ l: LoopsV7.DayLane, _ m: LoopsV7.DayMark, _ w: CGFloat) -> some View {
        let mx = x(m.at, w)
        let h = Self.laneHeight
        let when = LoopsV7.when(m.at, now: now)
        dot(l, m, when).position(x: mx, y: h / 2)
        if let label = m.label {
            Text(label).ui(11.5, .semibold).foregroundStyle(labelTone(m.result).color).fixedSize()
                .offset(x: min(mx + 9, w - 160), y: h / 2 - 8)
        }
    }

    @ViewBuilder private func dot(_ l: LoopsV7.DayLane, _ m: LoopsV7.DayMark, _ when: String) -> some View {
        let word: String = m.result == .toCome ? "to come" : m.result.rawValue
        let label: String = l.row.name + " " + word + " at " + when
        if let id = m.runId {
            let hint: String = when + " · " + word + " · open the run"
            Button { openRun(id) } label: { LoopDayDot(result: m.result).frame(width: 14, height: 14).contentShape(Rectangle()) }
                .buttonStyle(.plain).help(hint).accessibilityLabel(label)
        } else {
            let why: String = m.result == .toCome ? "from its schedule" : "missed: no run was recorded"
            let hint: String = when + " · " + why
            LoopDayDot(result: m.result).frame(width: 14, height: 14).help(hint).accessibilityLabel(label)
        }
    }

    private func labelTone(_ r: LoopRun7.Result) -> RGB {
        switch r {
        case .failed: return t.needsText
        case .missed: return LoopLook.tone(.needsYou, theme: t.name).text
        case .toCome: return t.text2
        case .trial: return LoopLook.tone(.trial, theme: t.name).text
        default: return t.text
        }
    }
}

/// A dot on the clock: passed green, failed red, trial grey, to come hollow, missed dashed amber.
struct LoopDayDot: View {
    @Environment(\.theme) private var t
    let result: LoopRun7.Result
    var body: some View {
        switch result {
        case .passed: Circle().fill(t.statusDone.color).frame(width: 8, height: 8)
        case .failed: Circle().fill(t.needsText.color).frame(width: 9, height: 9)
        case .trial: Circle().fill(LoopLook.tone(.trial, theme: t.name).text.color.opacity(0.75)).frame(width: 8, height: 8)
        case .toCome: Circle().strokeBorder(t.text2.color, lineWidth: 1.2).frame(width: 10, height: 10)
        case .missed, .notRun: Circle().strokeBorder(LoopLook.tone(.needsYou, theme: t.name).text.color, style: StrokeStyle(lineWidth: 1.2, dash: [2, 1.5]))
            .frame(width: 10, height: 10)
        }
    }
}
