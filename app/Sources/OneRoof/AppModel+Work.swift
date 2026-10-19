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
                DispatchQueue.main.async { self.workstreams = ws; self.linearError = nil; self.linearLoading = false }
            } catch {
                DispatchQueue.main.async { self.linearError = "\(error)"; self.linearLoading = false }
            }
        }
    }

    func loadIssues(_ w: LinearWorkstream, force: Bool = false) {
        guard force || issues[w.id] == nil else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let list = try self.linear.issues(project: w.id)
                DispatchQueue.main.async { self.issues[w.id] = list }
            } catch {
                DispatchQueue.main.async { self.linearError = "\(error)" }
            }
        }
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

    func sessions(for issue: LinearIssue) -> [BoardItem] { items.filter { $0.session.ticket == issue.identifier } }

    /// A planned session for a ticket: name, workstream, objective and opening message filled in.
    @discardableResult
    func planSession(for issue: LinearIssue, in w: LinearWorkstream, agent: AgentKind = .claude) -> Session {
        let d = settings.defaults(for: agent)
        let repo = Workspace.projectsRoot
        let s = Session(name: issue.shortTitle, agent: agent, account: d.account, repoPath: repo,
                        workstream: w.wsId,
                        objective: issue.shortTitle + (issue.description.isEmpty ? "" : "\n\n" + String(issue.description.prefix(600))),
                        openingMessage: "Work on \(issue.identifier) (\(w.wsId ?? w.name)): \(issue.shortTitle). Read the ticket \(issue.url) and the workstream docs first; commit as `\(issue.identifier) · [\((w.wsId ?? "").lowercased())] …`.",
                        lifecycle: .next, model: d.model.isEmpty ? nil : d.model,
                        ticket: issue.identifier, ticketId: issue.id, ticketTeam: w.team)
        createPlanned(s, launchNow: false)
        selectedId = s.id
        return s
    }

    /// Create a ticket after the intake filter; calls back on the main thread.
    func createTicket(kind: WorkKind, title: String, details: String, in w: LinearWorkstream, milestone: String?,
                      planSession: Bool, done: @escaping (Result<LinearIssue, Error>) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            do {
                let t = try self.team(w.team)
                let issue = try self.linear.createIssue(team: t, workstream: w, milestone: milestone, title: title,
                                                       description: details, type: kind.rawValue)
                DispatchQueue.main.async {
                    self.issues[w.id, default: []].append(issue)
                    if planSession { self.planSession(for: issue, in: w) }
                    done(.success(issue))
                }
            } catch {
                DispatchQueue.main.async { done(.failure(error)) }
            }
        }
    }

    /// A new workstream is tracker-first (WS id registry, tracker pane, docs README, linear_sync): an agent does
    /// those steps the workspace way, so tracker and Linear never drift. One Roof plans that session.
    func planWorkstreamSession(title: String, details: String) {
        let s = Session(name: "Open workstream: \(title)", agent: .claude, account: settings.defaults(for: .claude).account,
                        repoPath: Workspace.projectsRoot,
                        objective: "Open a new workstream: \(title)",
                        openingMessage: """
                        Open a new workstream for: \(title).
                        \(details)
                        Follow the workspace's READ-FIRST and tracker conventions if it has them: pick a workstream id, add it to the tracker, create docs/workstreams/<id>/README.md (goal, phases, done-when), and, if Linear is connected, create the project, its phase milestones and the first tickets. Then tell me the id.
                        """,
                        lifecycle: .next)
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
