import AppKit
import OneRoofCore

/// The model's side of the v2 engines (EngineHub): what it feeds them each second and what it shows from them.
extension AppModel {
    /// After each herdr poll: every live session, its status and pane revision.
    func feedEngines() {
        let live: [EngineHub.Live] = items.compactMap { i in
            guard i.liveAgent != nil || i.status == .exited else { return nil }
            let st = repoStats[i.session.repoPath]
            let obj = objectives.first { $0.stepSessions.values.contains(i.id) }
            var plan: CaptionPlan?
            if let o = obj, let p = o.plan, let mine = o.stepSessions.first(where: { $0.value == i.id })?.key,
               let idx = p.steps.firstIndex(where: { $0.id == mine }) {
                plan = CaptionPlan(titles: p.steps.map(\.title), current: idx)
            }
            return EngineHub.Live(id: i.id, name: i.session.name, agent: i.session.agent, account: i.account, status: i.status,
                                  pane: i.paneId, revision: revision(of: i), title: i.title, objective: i.session.objective,
                                  repoPath: i.session.repoPath, launchDirectory: i.session.launchDirectory, ticket: i.session.ticket,
                                  launchedAt: i.session.launchedAt, added: st?.added, removed: st?.removed, plan: plan)
        }
        engines.modelAllowed = settings.captionsModel
        engines.tick(live)
    }

    /// Engine results → published state (main thread).
    func applyEngines(captions caps: [String: Caption], feed events: [FeedEvent], decisions ds: [Decision],
                      subagents subs: [String: [Subagent]], chapters chs: [String: [Chapter]], claims: FileClaims) {
        var live: [String: LiveCaption] = [:]
        for (id, c) in caps {
            let tone: LiveCaption.Tone = c.text.hasPrefix("Needs you") ? .needs : .normal
            live[id] = LiveCaption(text: c.text, tone: tone, step: c.step, steps: c.steps, now: c.now, source: c.source.tooltip)
        }
        if live != captions { captions = live }
        let names = Dictionary(items.map { ($0.id, $0.session.name) }, uniquingKeysWith: { a, _ in a })
        let entries = events.reversed().map { e in
            FeedEntry(id: e.id.uuidString, at: e.at, sessionId: e.sessionId, sessionName: names[e.sessionId] ?? "", kind: e.kind.label, text: e.text)
        }
        if entries != feed { feed = Array(entries) }
        if ds != decisions { decisions = ds }
        if subs != subagents { subagents = subs }
        if chs != chapters { chapters = chs }
        fileClaims = claims
        updateDockBadge()
    }

    /// The pane revision herdr reports for a session's agent.
    private func revision(of i: BoardItem) -> Int? {
        lastSnapshotAgents[i.liveAgent ?? ""]?.revision
    }

    // MARK: Decisions

    var openDecisions: [Decision] {
        decisions.filter { d in d.isOpen && item(d.sessionId).map { $0.status == .needsYou } ?? false }
            .sorted { $0.askedAt < $1.askedAt }
    }
    /// Open prompts plus plans waiting for approval (S03 list, toolbar count, Dock badge).
    var openDecisionCount: Int { openDecisions.count + objectives.filter { $0.status == .review && $0.plan != nil }.count }

    func answer(_ d: Decision, _ a: Answer, reply: String? = nil) {
        engines.answer(d, a, reply: reply, pane: item(d.sessionId)?.paneId)
    }

    /// Dock badge = open decisions across all windows, else sessions that need you.
    func updateDockBadge() {
        let n = max(openDecisionCount, items.filter { $0.status == .needsYou }.count)
        NSApp?.dockTile.badgeLabel = n > 0 && settings.dockBadge ? "\(n)" : nil
    }

    // MARK: Subagents

    func subagentCount(_ item: BoardItem) -> Int { subagents[item.id]?.count ?? 0 }
    var runningSubagents: Int { subagents.values.joined().filter { $0.ended == nil }.count }

    // MARK: Schedules (ENGINES §6)

    /// Schedule a planned session for tonight / nightly (S04 Tonight, S09 When).
    func schedule(_ item: BoardItem, hour: Int, minute: Int, nightly: Bool) {
        let s: Schedule = nightly ? .nightly(hour: hour, minute: minute) : .tonight(hour: hour, minute: minute)
        let r = ScheduleRecord(sessionId: item.id, schedule: s)
        scheduleRecords[item.id] = r
        schedules[item.id] = s.timeText
        if !SelfTest.isActive { store?.save(r) }
        if item.status != .next { setLifecycle(item, .next) }
    }

    func unschedule(_ item: BoardItem) {
        guard schedules[item.id] != nil else { return }
        schedules[item.id] = nil
        scheduleRecords[item.id] = nil
        if !SelfTest.isActive { store?.deleteSchedule(session: item.id) }
    }
}

/// One FYI event as the views show it.
struct FeedEntry: Identifiable, Equatable {
    var id: String
    var at: Date
    var sessionId: String
    var sessionName: String
    /// "step done" · "finding" · "choice" · "subagents" · "done" · "rotated" · "error".
    var kind: String
    var text: String
}

extension FeedKind {
    /// The words the feed shows (S01 §4).
    var label: String {
        switch self {
        case .stepDone: return "step done"
        case .finding: return "finding"
        case .choice: return "choice"
        case .subagents: return "subagents"
        case .done: return "done"
        case .rotated: return "rotated"
        case .error: return "error"
        }
    }
}

extension AppModel {
    /// The feed without muted windows and sessions.
    var visibleFeed: [FeedEntry] {
        feed.filter { e in
            !mutedSessions.contains(e.sessionId) && !(item(e.sessionId).map { mutedWindows.contains(workspaceId(of: $0)) } ?? false)
        }
    }

    func toggleMute(window id: String) {
        if mutedWindows.contains(id) { mutedWindows.remove(id) } else { mutedWindows.insert(id) }
    }

    func toggleMute(session id: String) {
        let on = !mutedSessions.contains(id)
        if on { mutedSessions.insert(id) } else { mutedSessions.remove(id) }
        engines.mute(session: id, on: on)
    }

    /// Interrupt the agent (⌘.): Esc for Claude, Ctrl-C for the others.
    func interrupt(_ item: BoardItem) {
        guard let pane = item.paneId else { return }
        let h = herdr.herdrPath
        let isEsc = AnswerKeys.interrupt(item.session.agent) == AnswerKeys.escape
        DispatchQueue.global().async {
            if isEsc { _ = Foundations.run(h, ["pane", "send-keys", pane, "esc"], timeout: 5) }
            else { _ = Foundations.run(h, ["pane", "send-keys", pane, "ctrl-c"], timeout: 5) }
        }
    }

    /// Session › Send Handoff: ask the agent to write its handoff now (between turns only).
    func askForHandoff(_ item: BoardItem) {
        guard let agent = item.liveAgent else { return }
        guard item.status != .running else { lastError = "\(item.session.name) is working; send the handoff request when it is idle."; return }
        let h = herdr
        DispatchQueue.global().async {
            try? h.prompt(agent: agent, text: "Write a next-session handoff for this work now (the workspace handoff skill), then stop.")
        }
    }
}

extension Notification.Name {
    /// ⌘R in a session: fold chapters open (object: workspace id).
    static let rawStream = Notification.Name("oneroof.rawStream")
    static let askAboutSelection = Notification.Name("oneroof.askAboutSelection")
    static let saveFile = Notification.Name("oneroof.saveFile")
}

extension AppModel {
    /// Learn › Use in a session: type "/skill-name" as the session's next message (between turns only).
    func sendSkill(_ skill: String, to item: BoardItem) {
        guard let agent = item.liveAgent else { return }
        guard item.status != .running else { lastError = "\(item.session.name) is working; use the skill when it is idle."; return }
        let h = herdr
        DispatchQueue.global().async { try? h.prompt(agent: agent, text: "/" + skill) }
        reveal(item)
    }
}

extension AppModel {
    /// Fire due schedules while One Roof is open (every 30 s): launch the session exactly as Launch does, record the
    /// run, and put "missed · run now?" in the feed when the Mac slept through it. Nothing is merged or committed.
    func tickSchedules(now: Date = Date()) {
        guard !SelfTest.isActive else { return }
        for (id, r) in scheduleRecords {
            guard let item = item(id) else { continue }
            switch ScheduleClock.action(r, now: now) {
            case .run:
                var rec = r
                rec.lastRun = now
                rec.lastResult = "started"
                scheduleRecords[id] = rec
                store?.recordScheduledRun(session: id, at: now, result: "started")
                if item.liveAgent == nil { launch(item) }
                if case .tonight = r.schedule { schedules[id] = nil }
            case .missed(let due):
                var rec = r
                rec.lastRun = now
                rec.lastResult = "missed"
                scheduleRecords[id] = rec
                store?.recordScheduledRun(session: id, at: now, result: "missed")
                lastError = "\(item.session.name) was scheduled for \(due.formatted(date: .omitted, time: .shortened)) but the Mac was asleep. Launch it from its row (Run now)."
            case .nothing:
                continue
            }
        }
    }
}
