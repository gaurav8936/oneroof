import AppKit
import SwiftUI
import OneRoofCore

// LAB-2288 · 7c One loop · Now (handover 04-7c.png, pages/7c-one-loop): the loop's state dot, name, state chip and facts
// chip (origin · who runs it · schedule · mode), what it does and what is wrong in plain words, the tabs (Now · Results ·
// Track record · How it's set up), the last run step by step (When · Work · Check · Stop · You), its runs from the ledger
// with time per run, and on the right What you can do, Next run and Why it stopped. Header: Run now · Pause · Edit
// definition · ⋯ (Stop, Pin, Duplicate, All settings). Replaces the pop-out as the place a loop opens; the pop-out stays
// reachable (How it's set up, All settings, Set up) for the fields 7h/7m will take. Pure logic: LoopsV7 (OneRoofCore).

struct LoopPage: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var win: WindowState?
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    @ObservedObject private var inbox = LoopInboxState.shared
    let loopId: String
    let actions: LoopsV7Actions
    @State private var confirm: LoopsV7.AskAction?

    var body: some View {
        if let r = board.row(loopId), let l = board.loops.first(where: { $0.id == loopId }) {
            page(r, l)
                .alert(LoopWriteConfirm.title(confirm, board: board), isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                       presenting: confirm) { a in
                    Button(LoopWriteConfirm.button(a)) { LoopWriteConfirm.run(a, board: board, model: model); confirm = nil }
                    Button("Cancel", role: .cancel) { confirm = nil }
                } message: { a in Text(LoopWriteConfirm.message(a, board: board)) }
        } else {
            Text(board.loops.isEmpty ? "Reading the loops…" : "No loop called \(loopId).").ui(13).foregroundStyle(t.text2.color)
        }
    }

    private func page(_ r: LoopRow, _ l: Loop) -> some View {
        let waiting = inbox.items.filter { $0.loopId == loopId }
        let needsSetup = { if case .notConfigured = board.setup[loopId] { return true }; return false }()
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                head(r, l)
                paragraph(r, l)
                tabs(r, waiting: waiting)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 14) {
                        steps(r, l, waiting: waiting)
                        runs(r, l)
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    VStack(alignment: .leading, spacing: 14) {
                        doCard(LoopsV7.whatYouCanDo(r, waiting: waiting, needsSetup: needsSetup, engine: r.engine))
                        nextCard(r, l)
                        if let why = LoopsV7.whyStopped(l.stopReason), l.run == nil, r.state == .failing || l.state == .failed {
                            explainer("Why it stopped", why)
                        }
                    }
                    .frame(width: 320, alignment: .topLeading)
                }
            }
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.top)
        .accessibilityLabel("Loop \(r.name)")
    }

    // MARK: Head

    private func head(_ r: LoopRow, _ l: Loop) -> some View {
        let chip = LoopsV7.stateChip(r)
        let p = LoopLook.tone(chip.tone, theme: t.name)
        let unknown = r.engine == .kit && !board.kitKnown
        return HStack(alignment: .center, spacing: 10) {
            Circle().fill((unknown ? t.text3 : LoopLook.dot(r.state, theme: t.name)).color).frame(width: 10, height: 10).accessibilityHidden(true)
            Text(r.name).ui(26, .semibold).foregroundStyle(t.text.color).lineLimit(1).accessibilityAddTraits(.isHeader)
            Text(unknown ? "kit state unknown" : chip.text).ui(12.5, .semibold).foregroundStyle(p.text.color)
                .padding(.vertical, 3).padding(.horizontal, 9).background(Capsule().fill(p.fill.color)).fixedSize()
            Text(LoopsV7.factsChip(r, kitKnown: board.kitKnown)).ui(12.5, .medium).foregroundStyle(t.text2.color)
                .padding(.vertical, 3).padding(.horizontal, 9).background(Capsule().fill(t.control.color)).lineLimit(1)
                .help("Origin · who runs it · schedule · mode")
            if l.pinned { LoopTagChip(text: "Pinned") }
            Spacer(minLength: 12)
            headerActions(r, l)
        }
    }

    @ViewBuilder private func headerActions(_ r: LoopRow, _ l: Loop) -> some View {
        let kit = r.engine == .kit
        let runReason: String? = kit ? (unknownOrOff(r) ? "It is off (or the kit could not be read): the kit runs only a loop that is on. Turn it on first." : nil)
                                     : LoopLook.disabledReason("Run now", l)
        LoopButton("Run now", reason: runReason) { confirm = .runNow(loopId) }
        if kit {
            LoopButton("Pause", reason: "The kit's loops are turned off with `ae loops off \(loopId)`; that is not connected here yet.") {}
        } else if l.state == .paused || l.state == .stopped && l.run == nil && l.trigger.isArmed {
            RoofButton("Resume") { board.resume(loopId) }.help("Resumes its scheduled runs")
        } else {
            LoopButton("Pause", reason: LoopLook.disabledReason("Pause", l)) { board.pause(loopId) }
        }
        RoofButton(l.specFile != nil ? "Edit the file" : "Edit definition") { actions.edit(loopId) }
            .help(l.specFile != nil ? "The kit owns this loop's file; One Roof shows it in the viewer" : "Change its goal, check, agent, trigger and limits")
        Menu {
            Button(l.pinned ? "Unpin" : "Pin") { board.togglePin(loopId) }
            if !kit {
                Button("Stop" + (LoopLook.disabledReason("Stop", l).map { " (\($0.lowercased()))" } ?? "")) { board.stopLoop(loopId) }
                    .disabled(LoopLook.disabledReason("Stop", l) != nil)
            }
            if l.origin == .builtIn { Button("Duplicate as mine") { actions.startFrom(l) } }
            Divider()
            Button("All settings, outcomes and rounds…") { actions.popout(loopId) }
        } label: {
            Text("⋯").ui(15, .semibold).foregroundStyle(t.text.color).frame(width: 30, height: 28)
                .overlay(RoundedRectangle(cornerRadius: Radius.button, style: .continuous).strokeBorder(t.separatorStrong.color))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Pin, Stop, Duplicate, and every setting (the loop's card)")
        .accessibilityLabel("More actions")
    }

    private func unknownOrOff(_ r: LoopRow) -> Bool { !board.kitKnown || !r.on }

    /// The last run's ledger id (7j opens at it).
    private var lastRunId: String? { board.row(loopId)?.lastRun?.id }

    /// 7e filtered to this loop (its search set to the loop's name).
    private func trackRecord(_ r: LoopRow) {
        nav.filters["7e"] = LoopFilter(query: r.name)
        nav.setRoot(.thisWeek)
    }

    private func paragraph(_ r: LoopRow, _ l: Loop) -> some View {
        let p = LoopsV7.loopParagraph(r, stopReason: l.stopReason)
        return (Text(p.does + " ").foregroundColor(t.text.color) + Text(p.wrong).bold().foregroundColor(t.text.color))
            .ui(14).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 900, alignment: .leading)
            .textSelection(.enabled)
    }

    // MARK: Tabs

    private func tabs(_ r: LoopRow, waiting: [LoopInbox.Item]) -> some View {
        HStack(alignment: .bottom, spacing: 22) {
            tab("Now", selected: true, badge: nil, help: "What it is doing now") {}
            tab("Results", selected: false, badge: waiting.isEmpty ? nil : "\(waiting.count)", help: "What waits for you from this loop (Needs you, this loop)") {
                nav.open(.needsYou(loop: loopId, item: nil))
            }
            tab("Track record", selected: false, badge: nil, help: "This week, filtered to this loop") { trackRecord(r) }
            tab("How it's set up", selected: false, badge: nil, help: "Every field: origin, schedule, kind, goal, check, agent, repo, worktree, limits, output, gates, fences") {
                actions.popout(loopId)
            }
            Spacer(minLength: 0)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(t.separator.color).frame(height: 1) }
    }

    private func tab(_ title: String, selected: Bool, badge: String?, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).ui(14, selected ? .semibold : .regular).foregroundStyle((selected ? t.text : t.text2).color)
                if let badge {
                    let p = LoopLook.tone(.needsYou, theme: t.name)
                    Text(badge).ui(11.5, .semibold).foregroundStyle(p.text.color).padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Capsule().fill(p.fill.color))
                }
            }
            .padding(.bottom, 8)
            .overlay(alignment: .bottom) { if selected { Rectangle().fill(t.accent.color).frame(height: 2) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(title + (badge.map { ", \($0) waiting" } ?? ""))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: Last run, step by step

    private func steps(_ r: LoopRow, _ l: Loop, waiting: [LoopInbox.Item]) -> some View {
        let s = LoopsV7.steps(row: r, agent: l.agent.displayName, branch: l.branch, rounds: board.rounds[loopId] ?? [], waiting: waiting)
        let label: String = {
            guard let last = r.lastRun else { return "Last run" }
            let a = LoopsV7.when(last.started)
            return "Last run, step by step · " + a + (last.ended.map { " → " + LoopsV7.when($0) } ?? " · running")
        }()
        return VStack(alignment: .leading, spacing: 8) {
            LoopLabel(label)
            HStack(alignment: .top, spacing: 10) {
                ForEach(Array(s.enumerated()), id: \.element.id) { i, st in stepCard(i + 1, st) }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepCard(_ n: Int, _ s: LoopsV7.Step) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let tint: LoopLook.Pair? = s.tint == .failed ? LoopLook.tone(.failing, theme: t.name) : s.tint == .you ? LoopLook.tone(.needsYou, theme: t.name) : nil
        return Button { if let id = lastRunId { nav.open(.run(id)) } else { nav.open(.runs) } } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(n) · \(s.label.uppercased())").ui(TypeScale.micro, .semibold).tracking(0.66)
                    .foregroundStyle((tint?.text ?? t.text2).color)
                Text(s.title).ui(13.5, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                Text(s.text).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                if let who = s.who {
                    Text(who.rawValue).ui(10.5, .semibold).foregroundStyle((who == .agent ? t.surface : who == .you ? t.surface : t.text).color)
                        .padding(.horizontal, 7).padding(.vertical, 1.5)
                        .background(Capsule().fill((who == .agent ? t.text : who == .you ? LoopLook.tone(.needsYou, theme: t.name).text : t.control).color))
                        .padding(.top, 2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(shape.fill((tint?.fill ?? t.surface).color))
            .overlay(shape.strokeBorder((tint?.text.opacity(0.5).over(t.surface) ?? LoopLook.cardEdge(t.name)).color, lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(PressStyle(radius: Radius.card))
        .help("This run, step by step, in Runs")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(n), \(s.label): \(s.title). \(s.text)" + (s.who.map { ". By \($0.rawValue)" } ?? ""))
    }

    // MARK: Runs

    private func runs(_ r: LoopRow, _ l: Loop) -> some View {
        // The ledger's 8 days (strips) plus its 10 newest runs of this loop (older ones), one list.
        var all = board.weekRuns.filter { $0.loop == loopId }
        for x in (board.runsByLoop[loopId] ?? []).compactMap(LoopRun7.init) where !all.contains(where: { $0.id == x.id }) { all.append(x) }
        let groups = LoopsV7.runGroups(all)
        let since = all.map(\.started).min().map { LoopsV7.when($0) } ?? ""
        return LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    LoopLabel(all.isEmpty ? "Runs" : "Runs · \(all.count) since \(since)")
                    Spacer()
                    Button { trackRecord(r) } label: { Text("Track record ›").ui(12.5, .medium).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain).help("This week, filtered to this loop")
                }
                if groups.isEmpty {
                    Text(r.on ? "No run recorded yet." : "Never run: it is off.").ui(12.5).foregroundStyle(t.text2.color).padding(.vertical, 4)
                }
                ForEach(groups.prefix(8)) { g in runRow(g) }
            }
        }
    }

    private func runRow(_ g: LoopsV7.RunGroup) -> some View {
        let tone: LoopLook.Tone = g.newest.result == .failed ? .failing : g.newest.result == .trial ? .trial : .fine
        let p = LoopLook.tone(tone, theme: t.name)
        return HStack(spacing: 12) {
            Text(g.dates).ui(12.5).foregroundStyle(t.text.color).frame(width: 110, alignment: .leading).lineLimit(1)
            Text(g.result).ui(11.5, .semibold).foregroundStyle(p.text.color).padding(.horizontal, 7).padding(.vertical, 1)
                .background(Capsule().fill(p.fill.color)).frame(width: 82, alignment: .leading)
            Text(g.line).ui(12.5).foregroundStyle(t.text.color).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .help(g.newest.summary)
            Text(g.time.isEmpty ? "not recorded" : g.time).ui(11.5).foregroundStyle(t.text2.color).frame(width: 82, alignment: .trailing)
                .help("Time per run, from its start and end in the ledger")
            Button { nav.open(.run(g.newest.id)) } label: { Text("Open ↗").ui(12.5, .medium).foregroundStyle(t.accentText.color) }
                .buttonStyle(.plain).help("This run in Runs (its steps and rounds)")
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Right column

    private func doCard(_ items: [LoopsV7.DoItem]) -> some View {
        let amber = LoopLook.tone(.needsYou, theme: t.name).text
        return VStack(alignment: .leading, spacing: 4) {
            Text("What you can do").ui(14, .semibold).foregroundStyle(t.text.color).padding(.bottom, 4)
            if items.isEmpty {
                Text("Nothing: it runs on its own.").ui(12.5).foregroundStyle(t.text2.color)
            }
            ForEach(Array(items.enumerated()), id: \.element.id) { i, d in
                Button { perform(d.action) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Text("\(i + 1)").ui(11, .bold).foregroundStyle(t.surface.color).frame(width: 18, height: 18)
                            .background(Circle().fill(t.text.color))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(d.title).ui(13, .semibold).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                            Text(d.text).ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Text("›").ui(13).foregroundStyle(t.text2.color)
                    }
                    .padding(.vertical, 6).contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(radius: Radius.row))
                .overlay(alignment: .top) { Rectangle().fill(t.separator.color).frame(height: 1) }
                .accessibilityLabel("\(i + 1). \(d.title). \(d.text)")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.surface.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(LoopLook.cardEdge(t.name).color))
        .overlay(alignment: .leading) {
            if !items.isEmpty {
                UnevenRoundedRectangle(topLeadingRadius: Radius.card, bottomLeadingRadius: Radius.card, style: .continuous).fill(amber.color).frame(width: 4)
            }
        }
    }

    private func perform(_ a: LoopsV7.DoAction) {
        switch a {
        case .review(let item): nav.open(.needsYou(loop: loopId, item: item))
        case .reviewAll: nav.open(.needsYou(loop: loopId, item: nil))
        case .runNow: confirm = .runNow(loopId)
        case .turnOn: confirm = .turnOn(loopId)
        case .pause: board.pause(loopId)
        case .setUp, .open: actions.popout(loopId)
        }
    }

    private func nextCard(_ r: LoopRow, _ l: Loop) -> some View {
        let n = LoopsV7.nextRunCard(r, maxRounds: r.engine == .oneRoof ? l.limits.maxRounds : nil,
                                    maxHours: r.engine == .oneRoof ? l.limits.maxDuration / 3600 : nil)
        return LoopCard(padding: 14, shadow: false) {
            VStack(alignment: .leading, spacing: 4) {
                LoopLabel("Next run")
                Text(n.title).ui(18, .semibold).foregroundStyle(t.text.color)
                Text(n.text).ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func explainer(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            LoopLabel(title)
            Text(text).ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).fill(t.control.color))
        .overlay(RoundedRectangle(cornerRadius: Radius.card, style: .continuous).strokeBorder(t.separator.color))
    }
}

// MARK: - Confirm a write (Run now, Turn on): what runs is said before it runs (7b, 7c)

enum LoopWriteConfirm {
    static func isKit(_ id: String, _ board: LoopBoard) -> Bool { board.row(id)?.engine == .kit }
    static func name(_ id: String, _ board: LoopBoard) -> String { board.row(id)?.name ?? id }

    static func title(_ a: LoopsV7.AskAction?, board: LoopBoard) -> String {
        switch a {
        case .runNow(let id)?: return "Run \(name(id, board)) now?"
        case .turnOn(let id)?: return "Turn on \(name(id, board))?"
        default: return ""
        }
    }

    static func button(_ a: LoopsV7.AskAction) -> String {
        if case .turnOn = a { return "Turn on, in trial" }
        return "Run now"
    }

    static func message(_ a: LoopsV7.AskAction, board: LoopBoard) -> String {
        switch a {
        case .runNow(let id):
            return isKit(id, board)
                ? "The kit runs it once now, as its schedule would (`\(KitLoops.command("run", id).dropFirst().joined(separator: " "))`). A loop in trial only writes what it would do. Nothing is pushed or merged."
                : "One Roof starts a run within 30 s: the check first, then rounds in the loop's own worktree. Nothing is pushed or merged."
        case .turnOn(let id):
            return isKit(id, board)
                ? "The kit turns it on (`\(KitLoops.command("on", id).dropFirst().joined(separator: " "))`): it adds the loop to its config and its launchd schedule, and starts with trial runs that only say what they would do. It asks before going live."
                : "One Roof resumes it; roofd runs it on its schedule."
        default: return ""
        }
    }

    static func run(_ a: LoopsV7.AskAction, board: LoopBoard, model: AppModel) {
        switch a {
        case .runNow(let id): board.runNowAny(id)
        case .turnOn(let id): if isKit(id, board) { board.turnOnKit(id) } else { board.resume(id) }
        default: return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { model.refreshLoopInbox() }
    }
}
