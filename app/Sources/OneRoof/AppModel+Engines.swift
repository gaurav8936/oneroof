import AppKit
import OneRoofCore

/// The model's side of the v2 engines (EngineHub): what it feeds them each second and what it shows from them.
extension AppModel {
    /// After each runtime poll: every live session, its status and output seq.
    func feedEngines() {
        let inView = visibleInPanes.union([selectedId].compactMap { $0 })
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
                                  launchedAt: i.session.launchedAt, lastActive: lastActiveDate(i), added: st?.added, removed: st?.removed, plan: plan,
                                  visible: inView.contains(i.id),
                                  question: lastSnapshotSessions[i.liveAgent ?? ""]?.question)
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
        // The engine's buffer is newest first already (LAB-591: reversing it here showed the oldest on top).
        let entries = events.map { e in
            FeedEntry(id: e.id.uuidString, at: e.at, sessionId: e.sessionId, sessionName: names[e.sessionId] ?? "", kind: e.kind.label,
                      feedKind: e.kind, text: e.text)
        }
        if entries != feed { feed = entries }
        if ds != decisions {
            decisions = ds
            Notifier.shared.decisionsChanged(ds, names: names)   // LAB-197: a new question → "needs you"
        }
        if subs != subagents { subagents = subs }
        if chs != chapters { chapters = chs }
        fileClaims = claims
        // LAB-513: keep each session's edited files on the session (claims clear when a turn ends; these stay).
        // LAB-1336: all of them in one save and one rebuild (it was a save and a full rebuild per session, each publish).
        var changedRows: [Session] = []
        for (sid, edits) in claims.editedBy {
            guard let it = item(sid) else { continue }
            let merged = SessionArtifacts.merge(it.session.writtenFiles, edits: edits)
            guard merged != it.session.writtenFiles else { continue }
            var s = it.session
            s.writtenFiles = merged
            if it.adopted { s.lifecycle = .idle }
            if it.agentInTerminal { s.agent = .shell }
            changedRows.append(s)
        }
        saveAll(changedRows)
        updateDockBadge()
    }

    /// The output seq the runtime reports for a session.
    private func revision(of i: BoardItem) -> Int? {
        lastSnapshotSessions[i.liveAgent ?? ""]?.seq
    }

    // MARK: Decisions

    var openDecisions: [Decision] {
        // LAB-1827: a finished turn waits while its session is Ready or Idle (looking at it does not dismiss it).
        // LAB-1933: a loop round's asks reach you through its loop, not Needs you.
        SessionScope.openDecisions(decisions) { item($0) }
    }
    /// Open prompts plus plans waiting for approval (S03 list, toolbar count, Dock badge).
    var openDecisionCount: Int { openDecisions.count + objectives.filter { $0.status == .review && $0.plan != nil }.count }
    /// LAB-1933 · the Needs you badge everywhere (rail, icon row, menu bar, Dock): manual sessions only.
    var needsYouBadge: Int {
        SessionScope.needsYouCount(openAsks: openDecisions.count, plansWaiting: objectives.filter { $0.status == .review && $0.plan != nil }.count, items: items,
                                   loopItems: loopInbox.count)   // LAB-1866 · LAB-1919: loop items, never sessions
    }

    func answer(_ d: Decision, _ a: Answer, reply: String? = nil, choice: DecisionChoice? = nil) {
        engines.answer(d, a, reply: reply, choice: choice, pane: item(d.sessionId)?.paneId)
    }

    /// LAB-1827: a finished turn leaves Needs you without closing the session.
    func setAside(_ d: Decision) { engines.setAside(d) }

    /// Dock badge = open decisions across all windows, else sessions that need you.
    /// LAB-1328: set only when the label changes (it ran after every poll; each set redraws the Dock tile).
    func updateDockBadge() {
        let n = needsYouBadge   // LAB-1933
        let label = n > 0 && settings.dockBadge ? "\(n)" : nil
        if NSApp?.dockTile.badgeLabel != label { NSApp?.dockTile.badgeLabel = label }
    }

    // MARK: Subagents

    func subagentCount(_ item: BoardItem) -> Int { subagents[item.id]?.count ?? 0 }
    var runningSubagents: Int { subagents.values.joined().filter { $0.ended == nil }.count }

    // MARK: Schedules (ENGINES §6)

    /// Schedule a planned session for tonight / nightly (S04 Tonight, S09 When).
    func schedule(_ item: BoardItem, hour: Int, minute: Int, nightly: Bool) {
        let s: Schedule = nightly ? .nightly(hour: hour, minute: minute) : .tonight(hour: hour, minute: minute)
        setSchedule(item, s)
    }

    /// Repeat a session every N minutes (LAB-254): launched if it is not running, its message sent again when it is.
    func repeatEvery(_ item: BoardItem, minutes: Int) { setSchedule(item, .every(minutes: minutes)) }

    /// What a loop round types: the opening message, else the objective; nil when there is nothing to repeat.
    func loopMessage(_ item: BoardItem) -> String? {
        let t = (item.session.openingMessage.isEmpty ? item.session.objective : item.session.openingMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private func setSchedule(_ item: BoardItem, _ s: Schedule) {
        if let reason = ScheduleClock.hostedRefusal(for: item.session.agent) { lastError = reason; return }
        let r = ScheduleRecord(sessionId: item.id, schedule: s)
        scheduleRecords[item.id] = r
        schedules[item.id] = ScheduleClock.rowLabel(r)
        if !SelfTest.isActive { store?.save(r) }
        if !item.status.isLive, item.status != .next { setLifecycle(item, .next) }
    }

    /// The schedule pills from the records (a loop's "next" time moves after every round).
    func refreshScheduleLabels(now: Date = Date()) {
        let labels = scheduleRecords.compactMapValues { ScheduleClock.rowLabel($0, now: now) }
        if labels != schedules { schedules = labels }
    }

    /// A loop round on a live session while the app runs schedules (roofd does the same when it runs them).
    private func loopRound(_ item: BoardItem, _ r: ScheduleRecord, now: Date) {
        guard let agent = item.liveAgent else { return }
        let snap = lastSnapshotSessions[agent]
        var rec = r
        switch ScheduleClock.liveRound(r, status: snap?.status.rawValue, ready: snap?.ready ?? false, now: now) {
        case .wait: return
        case .skip: rec.lastResult = "skipped: busy"
        case .send:
            guard let text = loopMessage(item) else { rec.lastResult = "skipped: no message"; break }
            let rt = runtime
            DispatchQueue.global().async { try? rt.submit(agent, text: text) }
            rec.lastResult = "sent"
        }
        rec.lastRun = now
        scheduleRecords[item.id] = rec
        store?.recordScheduledRun(session: item.id, at: now, result: rec.lastResult ?? "")
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
    var feedKind: FeedKind
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
        let r = runtime
        let key: RuntimeKey = AnswerKeys.interrupt(item.session.agent) == AnswerKeys.escape ? .escape : .ctrlC
        DispatchQueue.global().async { try? r.keys(pane: pane, [key]) }
    }

    /// Session › Send Handoff: ask the agent to write its handoff now (between turns only).
    func askForHandoff(_ item: BoardItem) {
        guard let agent = item.liveAgent else { return }
        guard item.status != .running else { lastError = "\(item.session.name) is working; send the handoff request when it is idle."; return }
        let r = runtime
        DispatchQueue.global().async {
            try? r.submit(agent, text: "Write a next-session handoff for this work now (the workspace handoff skill), then stop.")
        }
    }
}

extension Notification.Name {
    /// ⌘R in a session: fold chapters open (object: workspace id).
    static let rawStream = Notification.Name("oneroof.rawStream")
    /// LAB-1286: the focused pane's Table view on or off (object: window id). It replaced Wrap (LAB-657).
    static let tableView = Notification.Name("oneroof.tableView")
    /// Posted by the terminal area when its focused pane's Table view turns on or off (object: window id, "on": Bool).
    static let tableViewChanged = Notification.Name("oneroof.tableViewChanged")
    static let askAboutSelection = Notification.Name("oneroof.askAboutSelection")
    static let saveFile = Notification.Name("oneroof.saveFile")
    /// v2 Split editor ⌘\ (CAP-18), object = window id.
    static let v2SplitEditor = Notification.Name("oneroof.v2.splitEditor")
}

extension AppModel {
    /// Learn › Use in a session: type "/skill-name" as the session's next message (between turns only).
    func sendSkill(_ skill: String, to item: BoardItem) {
        guard let agent = item.liveAgent else { return }
        guard item.status != .running else { lastError = "\(item.session.name) is working; use the skill when it is idle."; return }
        let r = runtime
        DispatchQueue.global().async { try? r.submit(agent, text: "/" + skill) }
        reveal(item)
    }
}

extension AppModel {
    /// Fire due schedules while One Roof is open (every 30 s): launch the session exactly as Launch does, record the
    /// run, and put "missed · run now?" in the feed when the Mac slept through it. Nothing is merged or committed.
    func tickSchedules(now: Date = Date()) {
        guard !SelfTest.isActive else { return }
        defer { refreshScheduleLabels(now: now) }
        if roofdRunsSchedules {                                   // roofd fires them (Q7); read back its last rounds
            if let rows = store?.schedules() {
                scheduleRecords = Dictionary(rows.map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
            }
            return
        }
        for (id, r) in scheduleRecords {
            guard let item = item(id) else { continue }
            let action = ScheduleClock.action(r, now: now)
            if let reason = ScheduleClock.hostedRefusal(for: item.session.agent), case .run = action {
                var rec = r; rec.lastRun = now; rec.lastResult = "refused: " + reason
                scheduleRecords[id] = rec
                store?.recordScheduledRun(session: id, at: now, result: rec.lastResult!)
                continue
            }
            switch action {
            case .run where r.schedule.interval != nil && item.liveAgent != nil:
                loopRound(item, r, now: now)
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
