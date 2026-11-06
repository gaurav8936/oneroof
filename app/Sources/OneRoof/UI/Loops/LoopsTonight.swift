import AppKit
import SwiftUI
import OneRoofCore

// LAB-2292 · 7g Tonight · schedule a session (handover 08-7g.png, pages/7g-tonight): one sentence (how many things run
// tonight, from when to when; nothing pushes, merges or deploys), one list in time order of tonight's loop runs (from
// their real schedules) and scheduled sessions, and the Schedule a session card: a one-off agent session started later
// on its own (what it should do, repo · agent, when). It is 2.0.5's "+ Schedule a session" with a new session: the
// session is created Planned and scheduled with the same AppModel.schedule (roofd's Scheduler starts it); a planned
// session can still be picked from the menu. Stop after and When quiet are not connected yet and say so. The status
// bar keeps Tonight · N and the V2 Tonight panel (owner default for LPO-5).

struct LoopsTonight: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    @ObservedObject var board: LoopBoard
    @ObservedObject var nav: LoopsNav
    let actions: LoopsV7Actions
    @State private var form = true

    var body: some View {
        let now = Date()
        let list = LoopsV7.tonight(rows: board.rows, crons: board.crons, sessions: sessions(now), now: now)
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        (Text(LoopsV7.tonightHeadline(list.items)).bold()
                            + Text(list.items.isEmpty ? " Loops that run every few minutes keep going as usual." : " Nothing pushes, merges or deploys; you'll find the results in the morning."))
                            .ui(14.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        if !form { RoofButton("+ Schedule a session", .primary) { form = true } }
                    }
                    if !list.items.isEmpty {
                        LoopCard(padding: 6, shadow: false) {
                            VStack(spacing: 0) {
                                ForEach(Array(list.items.enumerated()), id: \.element.id) { i, item in
                                    if i > 0 { Rectangle().fill(t.separator.color).frame(height: 1).padding(.horizontal, 10) }
                                    row(item)
                                }
                            }
                        }
                    }
                    if !list.frequent.isEmpty {
                        Text("Loops that run more than once a night (" + list.frequent.joined(separator: ", ") + ") aren't listed one by one; they run through the night as usual.")
                            .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                VStack(alignment: .leading, spacing: 12) {
                    if form {
                        LoopScheduleSessionCard(model: model, newLoop: actions.newLoop, close: { form = false })
                    }
                    LoopCard(padding: 14, shadow: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            LoopLabel("Where else it shows")
                            Text("The status bar's Tonight · N, the Today clock as hollow dots for loops, and Sessions once a session starts. The Tonight panel in the status bar keeps working as before.")
                                .ui(12.5).foregroundStyle(t.text.color).fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(width: 400)
            }
            .padding(.bottom, 8)
        }
        .defaultScrollAnchor(.top)
        .accessibilityLabel("Tonight")
    }

    /// Tonight and Nightly sessions with their next start.
    private func sessions(_ now: Date) -> [LoopsV7.TonightSession] {
        model.scheduleRecords.values.compactMap { r -> LoopsV7.TonightSession? in
            guard let i = model.item(r.sessionId), let at = ScheduleClock.nextFire(r, now: now) else { return nil }
            let nightly: Bool
            switch r.schedule { case .tonight: nightly = false; case .nightly: nightly = true; default: return nil }
            return LoopsV7.TonightSession(id: i.id, name: i.session.name,
                                          line: i.session.agent.displayName + " in " + Workspace.repoLabel(for: i.session.repoPath),
                                          at: at, nightly: nightly)
        }
    }

    private func row(_ i: LoopsV7.TonightItem) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(LoopsV7.when(i.at, now: i.at)).ui(13, .semibold, mono: true).foregroundStyle(t.text.color).frame(width: 56, alignment: .leading)
            Group {
                if i.tag == .trial { Circle().strokeBorder(LoopLook.tone(.trial, theme: t.name).text.color, lineWidth: 1.4) }
                else { Circle().fill(LoopLook.dot(i.dot, theme: t.name).color) }
            }
            .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(i.name).ui(13.5, .semibold).foregroundStyle(t.text.color).lineLimit(1)
                Text(i.line).ui(12).foregroundStyle(t.text2.color).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(i.by).ui(12).foregroundStyle(t.text2.color).frame(width: 90, alignment: .leading)
            tag(i.tag).frame(width: 96, alignment: .leading)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .contentShape(Rectangle())
        .onTapGesture {
            if i.isSession, let it = model.item(String(i.id.dropFirst("session-".count))) { model.reveal(it) }
            else if let l = i.loops.first { actions.openLoop(l) }
        }
        .contextMenu {
            if i.isSession, let it = model.item(String(i.id.dropFirst("session-".count))) {
                Button("On Demand (unschedule)") { model.unschedule(it) }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(i.isSession ? "Opens the session" : "Opens the loop")
    }

    @ViewBuilder private func tag(_ g: LoopsV7.TonightItem.Tag?) -> some View {
        if let g {
            let (words, tone): (String, LoopLook.Tone) = {
                switch g {
                case .trial: return ("trial", .trial)
                case .failing: return ("failing", .failing)
                case .oneOff: return ("one-off session", .running)
                case .nightlySession: return ("nightly session", .running)
                }
            }()
            let p = LoopLook.tone(tone, theme: t.name)
            Text(words).ui(11, .semibold).foregroundStyle(p.text.color).lineLimit(2)
                .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(p.fill.color))
        } else { Color.clear.frame(height: 1) }
    }
}

/// Schedule a session: a one-off agent session that starts later on its own (not a loop: it runs once, with no check
/// and no rounds). Creates a Planned session and schedules it with AppModel.schedule (the 2.0.5 path).
struct LoopScheduleSessionCard: View {
    @Environment(\.theme) private var t
    @ObservedObject var model: AppModel
    var newLoop: () -> Void
    var close: () -> Void
    enum When: Hashable { case tonight, quiet, at }
    @State private var prompt = ""
    @State private var repo = ""
    @State private var agent: AgentKind = .claude
    @State private var when: When = .tonight
    @State private var time = Calendar.current.date(bySettingHour: 2, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var pick = ""
    @State private var done: String?
    @State private var repos: [String] = []

    private var agents: [AgentKind] { AgentKind.allCases.filter { $0.isAgent && !$0.isHosted } }

    var body: some View {
        LoopCard(padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Schedule a session").ui(TypeScale.section, .semibold).foregroundStyle(t.text.color)
                Text("A one-off agent session that starts later, on its own. Not a loop: it runs once, with no check and no rounds.")
                    .ui(12.5).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                field("What should it do?") {
                    TextField("e.g. Tidy CHANGELOG.md for the next release: group by area, plain words", text: $prompt, axis: .vertical)
                        .textFieldStyle(.plain).ui(13).lineLimit(3...6)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).fill(t.surface.color))
                        .overlay(RoundedRectangle(cornerRadius: Radius.field, style: .continuous).strokeBorder(t.separatorStrong.color))
                        .accessibilityLabel("What should it do")
                    Text("One prompt, as you'd type it in a session.").ui(11.5).foregroundStyle(t.text2.color)
                }
                field("Repo · agent") {
                    HStack(spacing: 8) {
                        Picker("Repo", selection: $repo) {
                            ForEach(repos, id: \.self) { r in Text(Workspace.repoLabel(for: r)).tag(r) }
                        }
                        .labelsHidden().frame(maxWidth: .infinity)
                        Picker("Agent", selection: $agent) {
                            ForEach(agents) { a in Text(a.displayName).tag(a) }
                        }
                        .labelsHidden().frame(width: 130)
                    }
                }
                field("Stop after") {
                    Text("Not connected yet: the session runs until its agent stops. Nothing is pushed.")
                        .ui(12).foregroundStyle(LoopLook.disabledLabel(t.name).color).fixedSize(horizontal: false, vertical: true)
                }
                Segmented(options: [(When.tonight, "Tonight at " + LoopsV7.when(time)), (.quiet, "When quiet"), (.at, "At a time…")], selection: $when)
                    .accessibilityLabel("When")
                if when == .at {
                    DatePicker("Start at", selection: $time, displayedComponents: .hourAndMinute).datePickerStyle(.field)
                        .ui(12.5).fixedSize()
                } else if when == .quiet {
                    Text("Not connected yet: When quiet (start when the Mac and the seats are idle) is a loop trigger today. Pick a time, or make it a loop.")
                        .ui(12).foregroundStyle(t.text2.color).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 4) {
                    Text("Want it every night, or until something is true?").ui(12.5).foregroundStyle(t.text.color)
                    Button { newLoop() } label: { Text("Make it a loop instead ›").ui(12.5, .semibold).foregroundStyle(t.accentText.color) }
                        .buttonStyle(.plain).accessibilityLabel("Make it a loop instead")
                }
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.row, style: .continuous).fill(LoopLook.tone(.running, theme: t.name).fill.color))
                if let d = done { Text(d).ui(12).foregroundStyle(t.statusDone.color).fixedSize(horizontal: false, vertical: true) }
                if let e = model.lastError, done == nil, !e.isEmpty { Text(e).ui(12).foregroundStyle(t.needsText.color).fixedSize(horizontal: false, vertical: true) }
                HStack(spacing: 8) {
                    plannedMenu
                    Spacer()
                    RoofButton("Cancel") { close() }.keyboardShortcut(.cancelAction)
                    RoofButton("Schedule", .primary) { schedule() }
                        .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || repo.isEmpty || when == .quiet)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            if repos.isEmpty {
                repos = WorkspaceSearch.repos()
                if repo.isEmpty { repo = repos.first { $0.hasSuffix("/labs/oneroof") } ?? repos.first ?? "" }
            }
        }
        .onExitCommand { close() }
    }

    private func field<C: View>(_ label: String, @ViewBuilder _ c: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).ui(12.5, .semibold).foregroundStyle(t.text.color)
            c()
        }
    }

    /// 2.0.5's path, kept: a Planned or Next session already in the list, tonight at 2:00 AM.
    private var plannedMenu: some View {
        let planned = model.sessionItems.filter { ($0.status == .planned || $0.status == .next) && $0.session.agent.isAgent && model.scheduleRecords[$0.id] == nil }
        return Menu {
            if planned.isEmpty { Text("No planned sessions to schedule") }
            ForEach(planned) { i in Button(i.session.name) { model.schedule(i, hour: 2, minute: 0, nightly: false); done = "Scheduled " + i.session.name + " for tonight at 2:00." } }
        } label: { Text("A planned session ▾").ui(12.5, .medium).foregroundStyle(t.text.color) }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Run a planned session tonight at 2:00 AM")
    }

    private func schedule() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let words = text.split(separator: " ").prefix(6).joined(separator: " ")
        let s = Session(name: words.count > 48 ? String(words.prefix(46)) + "…" : words, agent: agent, repoPath: repo, objective: text, openingMessage: text)
        model.lastError = nil
        model.createPlanned(s, launchNow: false)
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        guard let item = model.item(s.id) else { done = nil; return }
        model.schedule(item, hour: c.hour ?? 2, minute: c.minute ?? 0, nightly: false)
        if model.scheduleRecords[s.id] != nil {
            done = "Scheduled: \(s.name) at " + Schedule.clock(c.hour ?? 2, c.minute ?? 0) + ". It shows in Tonight, the Today clock and Sessions."
            prompt = ""
        }
    }
}
