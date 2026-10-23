import AppKit
import OneRoofCore

/// Work: workstreams and tickets from Linear, the intake filter, and sessions planned from tickets.
extension AppModel {
    func loadWorkstreams(force: Bool = false) {
        guard force || workstreams.isEmpty, !linearLoading else { return }
        linearLoading = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let ws = try self.linear.workstreams()
                let teams = (try? self.linear.teams()) ?? []
                DispatchQueue.main.async {
                    self.workstreams = ws; self.linearError = nil; self.linearLoading = false
                    if !teams.isEmpty { self.linearTeams = teams }
                }
            } catch {
                DispatchQueue.main.async { self.linearError = "\(error)"; self.linearLoading = false }
            }
        }
    }

    /// A project's issues from Linear: fetched when not loaded yet, when `force`, or when the copy is older than
    /// `maxAge` seconds (LAB-546: a list fetched once at launch never showed issues created later). One fetch per
    /// project at a time.
    func loadIssues(_ w: LinearWorkstream, force: Bool = false, maxAge: TimeInterval = 30) {
        if !force, issues[w.id] != nil, let at = issuesFetchedAt[w.id], Date().timeIntervalSince(at) < maxAge { return }
        guard !issuesLoading.contains(w.id) else { return }
        issuesLoading.insert(w.id)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let list = try self.linear.issues(project: w.id)
                DispatchQueue.main.async {
                    self.issuesLoading.remove(w.id)
                    self.issuesFetchedAt[w.id] = Date()
                    if self.issues[w.id] != list { self.issues[w.id] = list }
                }
            } catch {
                DispatchQueue.main.async { self.issuesLoading.remove(w.id); self.linearError = "\(error)" }
            }
        }
    }

    /// `loadIssues` by project id (the issue picker only knows the id).
    func loadIssues(projectId: String, force: Bool = false, maxAge: TimeInterval = 30) {
        if let w = workstreams.first(where: { $0.id == projectId }) { loadIssues(w, force: force, maxAge: maxAge) }
    }

    func team(_ key: String) throws -> LinearTeam {
        if let t = teams[key] { return t }
        let t = try linear.team(key: key)
        DispatchQueue.main.async { self.teams[key] = t }
        return t
    }

    /// Sessions working on a workstream (by WS id).
    func sessions(in w: LinearWorkstream) -> [BoardItem] {
        guard let id = w.wsId else { return [] }
        return items.filter { $0.session.workstream == id }
    }

    func sessions(for issue: LinearIssue) -> [BoardItem] { items.filter { $0.session.hasTicket(issue.identifier) } }

    /// A planned session for a ticket: name, workstream, objective and opening message filled in.
    @discardableResult
    func planSession(for issue: LinearIssue, in w: LinearWorkstream, agent: AgentKind = .claude) -> Session {
        let d = settings.defaults(for: agent)
        let repo = Workspace.projectsRoot
        let s = Session(name: Intake.sessionName(key: issue.identifier, title: issue.shortTitle), agent: agent, account: d.account, repoPath: repo,
                        workstream: w.wsId,
                        objective: issue.shortTitle + (issue.description.isEmpty ? "" : "\n\n" + String(issue.description.prefix(600))),
                        openingMessage: Intake.anchored(Intake.ticketOpening(key: issue.identifier, title: issue.shortTitle, url: issue.url, project: w.wsId),
                                                        team: w.team, project: w.wsId),
                        lifecycle: .next, model: d.model.isEmpty ? nil : d.model,
                        ticket: issue.identifier, ticketId: issue.id, ticketTeam: w.team)
        createPlanned(s, launchNow: false)
        selectedId = s.id
        return s
    }

    /// Create a ticket after the intake filter; calls back on the main thread. The team is the project's, or, with no
    /// project, the one picked (LAB-237: a ticket always has a team; the project is optional).
    func createTicket(kind: WorkKind, title: String, details: String, in w: LinearWorkstream?, team teamKey: String? = nil,
                      milestone: String?, planSession: Bool, images: [String] = [],
                      done: @escaping (Result<LinearIssue, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                guard let key = (teamKey?.isEmpty == false ? teamKey : nil) ?? w?.team, !key.isEmpty else {
                    throw LinearClient.Failure.api("pick a team first")
                }
                let t = try self.team(key)
                // LAB-462: pasted images go up to Linear and into the description (a failed upload keeps its path).
                let description = ImageAttachments.issueDescription(details, images: self.linear.uploadImages(images))
                let issue = try self.linear.createIssue(team: t, workstream: w, milestone: milestone, title: title,
                                                       description: description, type: kind.rawValue)
                DispatchQueue.main.async {
                    if let w {
                        self.issues[w.id, default: []].append(issue)
                        if planSession { self.planSession(for: issue, in: w) }
                    }
                    done(.success(issue))
                }
            } catch {
                DispatchQueue.main.async { done(.failure(error)) }
            }
        }
    }

    /// Create a Linear project (code · title, milestones) from One Roof (LAB-238); calls back on the main thread.
    func createProject(team: LinearTeamRef, code: String, title: String, summary: String, milestones: [String],
                       done: @escaping (Result<LinearWorkstream, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let p = try self.linear.createProject(team: team, code: code, title: title, summary: summary, milestones: milestones)
                DispatchQueue.main.async {
                    self.workstreams.append(p)
                    self.workstreams.sort { $0.name < $1.name }
                    done(.success(p))
                }
            } catch {
                DispatchQueue.main.async { done(.failure(error)) }
            }
        }
    }

    /// A new project: One Roof creates it in Linear when connected (LAB-238), then plans a session that writes its docs
    /// the workspace way; without Linear the session does every step.
    func planWorkstreamSession(title: String, details: String, project: LinearWorkstream? = nil) {
        let body: String
        if let p = project {
            // LAB-238: the Linear project already exists; the session writes its docs the workspace way.
            let ms = p.milestones.map(\.name).joined(separator: ", ")
            body = """
            Linear project \(p.name) was just created from One Roof (\(p.url))\(ms.isEmpty ? "" : ", milestones: " + ms).
            \(details)
            Follow the workspace's READ-FIRST conventions if it has them: write the project's docs folder (README with goal, milestones and done-when; STATUS), add the first tickets in Linear, and post a first project update.
            """
        } else {
            body = """
            Open a new project for: \(title).
            \(details)
            Follow the workspace's READ-FIRST conventions if it has them: pick a project code, create its docs folder (README with goal, phases, done-when), and, if Linear is connected, create the project, its milestones and the first tickets. Then tell me the code.
            """
        }
        let s = Session(name: "Open project: \(project?.wsId ?? title)", agent: .claude, account: settings.defaults(for: .claude).account,
                        repoPath: Workspace.projectsRoot, workstream: project?.wsId,
                        objective: "Open a new project: \(title)",
                        openingMessage: body,
                        lifecycle: .next, ticketTeam: project?.team)
        createPlanned(s, launchNow: false)
        selectedId = s.id
    }

    /// Move any ticket (from the Work view) to a named state.
    func moveTicket(id: String, team key: String, to state: String) {
        var s = Session(name: "", repoPath: Workspace.projectsRoot)
        s.ticketId = id; s.ticketTeam = key
        moveTicket(of: s, to: state)
    }

    /// Move the session's ticket to a named state, optionally with a comment; refreshes the cached tickets.
    func moveTicket(of session: Session, to state: String, comment: String? = nil, done: ((String?) -> Void)? = nil) {
        guard let id = session.ticketId, let key = session.ticketTeam else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var err: String?
            do {
                let t = try self.team(key)
                if let comment { try self.linear.comment(issue: id, body: comment) }
                try self.linear.setState(issue: id, team: t, named: state)
            } catch { err = "\(error)" }
            DispatchQueue.main.async {
                for (pid, list) in self.issues {
                    if let i = list.firstIndex(where: { $0.id == id }) {
                        self.issues[pid]?[i].state = state
                        self.issues[pid]?[i].stateType = ["Done": "completed", "Canceled": "canceled", "Backlog": "backlog", "Todo": "unstarted"][state] ?? "started"
                    }
                }
                if let err { self.lastError = err }
                done?(err)
            }
        }
    }

    /// Move one of a session's issues (LAB-474: a session can carry several).
    func moveIssue(_ i: SessionIssue, to state: String, comment: String? = nil, done: ((String?) -> Void)? = nil) {
        var s = Session(name: "", repoPath: Workspace.projectsRoot)
        s.ticketId = i.id; s.ticketTeam = i.team
        moveTicket(of: s, to: state, comment: comment, done: done)
    }

    /// Move every issue on the session (close, review): each gets the same session summary.
    func moveTickets(of item: BoardItem, keys: Set<String>? = nil, to state: String) {
        let summary = sessionSummary(item)
        let moved = item.session.allTickets.filter { keys?.contains($0.key) ?? true }
        for i in moved { moveIssue(i, to: state, comment: summary) }
        if state == "In Review" { update(item) { $0.reviewedTickets += moved.map(\.key) } }
    }

    /// Take an issue off a session (LAB-474); it stays in Linear as it is.
    func detachIssue(_ key: String, from item: BoardItem) { update(item) { Intake.detach(key, from: &$0) } }

    /// What the session did, for the ticket comment: agent, account, times, and the newest handoff for its workstream.
    func sessionSummary(_ item: BoardItem) -> String {
        let s = item.session
        var lines = ["Session **\(s.name)** closed in One Roof · \(s.agent.displayName)\(item.account.map { " · \($0)" } ?? "")"]
        if let at = s.launchedAt { lines.append("Ran from \(at.formatted(date: .abbreviated, time: .shortened)) to \(Date().formatted(date: .omitted, time: .shortened)).") }
        if let ws = s.workstream,
           let h = Foundations.handoffs(FoundationPaths(common: settings.sharedFolder), all: true).first(where: { $0.workstream == ws }),
           h.modified > (s.launchedAt ?? .distantPast) {
            lines.append("Handoff: `\(h.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))`")
        }
        if !s.notes.isEmpty { lines.append("Notes: " + s.notes) }
        return lines.joined(separator: "\n\n")
    }

    func ticketStarted(id: String, team key: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self, let t = try? self.team(key) else { return }
            try? self.linear.setState(issue: id, team: t, type: "started")
        }
    }
}

extension AppModel {
    /// Attach a Linear issue to an existing session (LAB-474): the session takes it as its ticket, Linear moves it to
    /// started once the session has launched, and an idle agent is told about it (a busy one is told nothing; the owner
    /// is warned instead, never interrupted mid-turn).
    func attachIssue(_ issue: LinearIssue, team: String?, project: String?, to item: BoardItem, tellAgent: Bool) {
        var s = item.session
        guard Intake.attach(issue, team: team, project: project, to: &s) else { lastError = "\(issue.identifier) is already on \(item.session.name)."; return }
        update(item) { _ = Intake.attach(issue, team: team, project: project, to: &$0) }
        if item.session.launchedAt != nil || item.liveAgent != nil, let key = team ?? item.session.ticketTeam {
            ticketStarted(id: issue.id, team: key)
        }
        guard tellAgent, let agent = item.liveAgent, item.session.agent.isAgent else { return }
        let text = Intake.attachMessage(key: issue.identifier, title: issue.shortTitle, url: issue.url.isEmpty ? nil : issue.url,
                                        project: project ?? item.session.workstream)
        // A working agent is never interrupted: the message waits and goes in as soon as it is at its prompt.
        guard Session.canDeliver(item.status) else {
            if let fresh = self.item(item.id) { update(fresh) { $0.pendingMessages.append(text) } }
            return
        }
        let r = runtime
        DispatchQueue.global().async { try? r.submit(agent, text: text) }
    }
}

extension AppModel {
    /// Every minute (LAB-474): sessions launched in the last 3 days with issues not yet in review are matched against
    /// new commits in the workspace repos; an issue whose key is in a commit subject moves to In Review once, with the
    /// commit in the comment. Issues already Done or Canceled are only marked, never moved back.
    func tickCommitWatch(now: Date = Date()) {
        guard !SelfTest.isActive, !commitWatchBusy, linear.hasKey else { return }
        let watched = items.filter { CommitWatch.watches($0.session, now: now) }
        guard let since = watched.compactMap(\.session.launchedAt).min() else { return }
        commitWatchBusy = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let commits = Workspace.listRepos().flatMap { repo in
                CommitWatch.parseLog(Foundations.run(GitDiff.git, CommitWatch.logArgs(repo: repo, since: since.addingTimeInterval(-60)), timeout: 10).1, repo: repo)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.commitWatchBusy = false
                for w in watched {
                    guard let item = self.item(w.id) else { continue }
                    let found = CommitWatch.matches(item.session, in: commits)
                    guard !found.isEmpty else { continue }
                    let finished = Set(self.issues.values.joined().filter { ["completed", "canceled"].contains($0.stateType) }.map(\.id))
                    for (issue, c) in found where !finished.contains(issue.id ?? "") {
                        let where_ = Workspace.repoLabel(for: c.repo)
                        self.moveIssue(issue, to: "In Review",
                                       comment: "Committed in `\(c.sha)` (\(where_)): \(c.subject)\n\nSession **\(item.session.name)** in One Roof moved this to In Review.")
                    }
                    self.update(item) { $0.reviewedTickets += found.map(\.0.key) }
                }
            }
        }
    }
}

extension AppModel {
    /// Every 3 s: send each live session's waiting messages once its agent is at its prompt (LAB-474), as one message.
    func deliverPendingMessages() {
        for item in items where !item.session.pendingMessages.isEmpty {
            guard let agent = item.liveAgent else { continue }
            guard Session.canDeliver(item.status) else { continue }
            let text = item.session.pendingMessages.joined(separator: "\n\n")
            update(item) { $0.pendingMessages = [] }
            let r = runtime
            DispatchQueue.global().async { try? r.submit(agent, text: text) }
        }
    }
}

extension AppModel {
    /// Every 3 s (LAB-518): apply what agents asked for with `roofd issue` — a comment and/or In Progress / In Review on
    /// one of their own session's issues — with the owner's Linear key, then answer the waiting agent. A request for an
    /// issue that is not on the session, or for another state, is refused with the reason.
    func applyIssueRequests() {
        guard let roofd = runtime as? RoofdRuntime else { return }
        let live = lastSnapshotSessions
        for item in items {
            guard let rid = item.resourceKey, let st = live[rid], !st.issueRequests.isEmpty else { continue }
            for r in st.issueRequests {
                let tag = "\(rid):\(r.seq)"
                guard !issueRequestsInFlight.contains(tag) else { continue }
                issueRequestsInFlight.insert(tag)
                // Applied at most once: the tag is forgotten only after roofd took the answer (and dropped the request).
                // If roofd cannot take it (an older daemon), the tag stays, so Linear never gets the same update twice.
                func answer(_ err: String?) {
                    DispatchQueue.global(qos: .utility).async { [weak self] in
                        guard (try? roofd.issueDone(rid, seq: r.seq, error: err)) != nil else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { self?.issueRequestsInFlight.remove(tag) }
                    }
                }
                switch r.check(against: item.session) {
                case .failure(let e): answer(e.description)
                case .success(let issue):
                    guard linear.hasKey else { answer("One Roof has no Linear key (Settings › Linear)"); continue }
                    let comment = r.comment.map { $0 + "\n\n— \(item.session.agent.displayName) in One Roof session **\(item.session.name)**" }
                    if let state = r.canonicalState {
                        moveIssue(issue, to: state, comment: comment) { err in answer(err) }
                        if state == "In Review" { update(item) { if !$0.reviewedTickets.contains(issue.key) { $0.reviewedTickets.append(issue.key) } } }
                    } else if let comment, let id = issue.id {
                        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                            var err: String?
                            do { try self?.linear.comment(issue: id, body: comment) } catch { err = "\(error)" }
                            answer(err)
                        }
                    }
                }
            }
        }
    }
}
