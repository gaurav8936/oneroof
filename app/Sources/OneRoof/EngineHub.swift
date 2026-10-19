import Foundation
import OneRoofCore

/// Runs the v2 engines (ENGINES §1–§6) off the main thread and publishes their results to the model:
/// captions (heuristic first, the on-device model when it answers), the FYI feed, decisions with their "why",
/// Claude subagents from the transcript, chapters, and file claims. Input each second from the herdr poll: which
/// sessions are live, their status and their pane revision (a cheap "new output" signal); terminal text comes from
/// `herdr pane read` (read-only). Every engine has a deterministic fallback, so the UI never waits on a model.
final class EngineHub {
    struct Live: Sendable {
        var id: String
        var name: String
        var agent: AgentKind
        var account: String?
        var status: SessionStatus
        var pane: String?
        var revision: Int?
        var title: String?
        var objective: String
        var repoPath: String
        var launchDirectory: String
        var ticket: String?
        var launchedAt: Date?
        var added: Int?
        var removed: Int?
        var plan: CaptionPlan?
    }

    private let q = DispatchQueue(label: "oneroof.engines", qos: .utility)
    private weak var model: AppModel?
    private let store: SessionStore?
    private let herdrPath: String
    private var scheduler = CaptionScheduler()
    private var revisions: [String: Int] = [:]
    private var statuses: [String: SessionStatus] = [:]
    private var feed = FeedBuffer()
    private var claims = FileClaims()
    private var prompts: [String: PromptMatch] = [:]
    private var openDecision: [String: UUID] = [:]
    private var decisions: [Decision] = []
    private var chapters: [String: [Chapter]] = [:]
    private var lastSubagentScan: [String: Date] = [:]
    private var subagents: [String: [Subagent]] = [:]
    private var lastCaption: [String: Caption] = [:]
    private let modelClient = CaptionModelClient()
    private var modelUp = false
    private var lastModelCheck = Date.distantPast
    /// Tests and self-tests can feed text instead of reading herdr.
    var textOverride: ((String) -> String?)?

    init(model: AppModel, store: SessionStore?, herdrPath: String) {
        self.model = model
        self.store = store
        self.herdrPath = herdrPath
        q.async { [weak self] in self?.loadFromStore() }
    }

    // MARK: Load

    private func loadFromStore() {
        guard let store else { return }
        store.pruneFeed()
        for e in store.recentFeed().reversed() { _ = feed.add(e) }
        lastCaption = store.allCaptions()
        decisions = store.openDecisions() + store.decisions(since: Date().addingTimeInterval(-86_400)).filter { !$0.isOpen }
        for d in decisions where d.isOpen { openDecision[d.sessionId] = d.id }
        publishAll()
    }

    // MARK: Tick (called after every herdr poll)

    func tick(_ live: [Live]) {
        q.async { [weak self] in self?.step(live, now: Date()) }
    }

    private func step(_ live: [Live], now: Date) {
        let ids = Set(live.map(\.id))
        for (id, _) in revisions where !ids.contains(id) { scheduler.remove(id); revisions[id] = nil }
        var changed = false
        for s in live {
            let old = statuses[s.id]
            if old != s.status {
                statuses[s.id] = s.status
                if old != nil {
                    scheduler.noteStatusChange(s.id, at: now)
                    for e in FeedSignals.statusChange(from: old, to: s.status, sessionId: s.id, name: s.name, caption: lastCaption[s.id], at: now) {
                        changed = add(e) || changed
                    }
                    if s.status == .exited || s.status == .done { claims.endSession(sessionId: s.id) }
                }
                if s.status == .needsYou { buildDecision(s, now: now); changed = true }
                else if old == .needsYou, let open = openDecision[s.id] { closeDecision(open, answeredInTerminal: true); changed = true }
            }
            if let r = s.revision, revisions[s.id] != r {
                if revisions[s.id] != nil || old == nil { scheduler.noteOutput(s.id, at: now) }
                revisions[s.id] = r
            }
        }
        let due = scheduler.take(now: now)
        let byId = Dictionary(live.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for id in due {
            defer { scheduler.finish(id) }
            guard let s = byId[id] else { continue }
            caption(s, now: now)
            changed = true
        }
        // Claude subagents: scan the transcript every 5 s while the session is live.
        for s in live where s.agent == .claude && s.status.isLive && now.timeIntervalSince(lastSubagentScan[s.id] ?? .distantPast) > 5 {
            lastSubagentScan[s.id] = now
            if scanSubagents(s, now: now) { changed = true }
        }
        if changed { publishAll() }
    }

    // MARK: Captions (ENGINES §1)

    private func text(_ s: Live, lines: Int = 300) -> String {
        if let o = textOverride?(s.id) { return o }
        guard let pane = s.pane else { return "" }
        let (rc, out) = Foundations.run(herdrPath, ["pane", "read", pane, "--source", "recent", "--lines", "\(lines)"], timeout: 4)
        return rc == 0 ? out : ""
    }

    private func caption(_ s: Live, now: Date) {
        let t = text(s)
        let input = CaptionInput(text: t, agent: s.agent, status: s.status, objective: s.objective, plan: s.plan,
                                 lastActivity: s.launchedAt, now: now)
        let heur = CaptionEngine.heuristic(input)
        var reply: String?
        if checkModel(now) { reply = modelClient.reply(for: input, timeout: 6) }
        let (cap, events) = CaptionEngine.resolve(heuristic: heur, modelReply: reply, input: input, sessionId: s.id)
        if let cap {
            lastCaption[s.id] = cap
            store?.saveCaption(cap, session: s.id)
        }
        for e in events { _ = add(e) }
        // File claims from the tool calls in view (S07 claim banner).
        _ = claims.observe(text: t, sessionId: s.id, repo: s.repoPath, step: cap?.step, at: now)
        // Chapters: steps in the terminal, never a copy of the output.
        if s.agent.isAgent {
            chapters[s.id] = ChapterSplitter.chapters(t, previous: chapters[s.id] ?? [], sessionStarted: s.launchedAt ?? now,
                                                      now: now, finished: s.status == .done || s.status == .exited)
        }
    }

    /// The on-device caption model is optional: ask llama-server's health once a minute.
    /// Settings › Captions › on-device model (read on the main thread's copy each tick).
    var modelAllowed = true

    private func checkModel(_ now: Date) -> Bool {
        guard modelAllowed else { return false }
        guard now.timeIntervalSince(lastModelCheck) > 60 else { return modelUp }
        lastModelCheck = now
        let (rc, _) = Foundations.run("/usr/bin/curl", ["-s", "-m", "1", "http://127.0.0.1:\(LocalModel.port)/health"], timeout: 2)
        modelUp = rc == 0
        return modelUp
    }

    @discardableResult
    private func add(_ e: FeedEvent) -> Bool {
        guard feed.add(e) else { return false }
        store?.append(e)
        return true
    }

    // MARK: Decisions (ENGINES §3)

    private func buildDecision(_ s: Live, now: Date) {
        guard openDecision[s.id] == nil else { return }
        let t = text(s, lines: 120)
        prompts[s.id] = DecisionMatcher.match(t, agent: s.agent)
        let ctx = DecisionContext(sessionId: s.id, agent: s.agent, terminalText: t, repoPath: s.repoPath,
                                  objective: s.objective.isEmpty ? nil : s.objective, ticket: s.ticket,
                                  step: s.plan.map { $0.current + 1 }, steps: s.plan?.titles.count,
                                  added: s.added, removed: s.removed, past: decisions, now: now)
        var d = DecisionBuilder.build(ctx) ?? Decision.fallback(sessionId: s.id, agent: s.agent, text: t, repo: s.repoPath, now: now)
        if let h = store?.decisionHistory(pattern: d.pattern, repo: d.repo, now: now) { d.history = h }
        decisions.append(d)
        openDecision[s.id] = d.id
        store?.save(d)
        if let rule = store?.decisionRules().first(where: { $0.matches(d) }) {
            // An "Always allow" rule the owner set: the decision is still shown (humans stay in the loop), marked.
            d.history.ruleSuggestion = "Matches your rule: always allow \(rule.pattern) in \(rule.repo)"
        }
    }

    private func closeDecision(_ id: UUID, answeredInTerminal: Bool) {
        guard let i = decisions.firstIndex(where: { $0.id == id }) else { return }
        if decisions[i].answer == nil {
            decisions[i].answer = .reply
            decisions[i].answeredAt = Date()
            decisions[i].replyText = answeredInTerminal ? "answered in the terminal" : nil
            store?.answer(decision: id, .reply, reply: decisions[i].replyText)
        }
        openDecision[decisions[i].sessionId] = nil
    }

    /// Answer a decision: the agent's own keys via herdr (y / a / n or the CLI's numbers; Esc then text for Reply).
    func answer(_ d: Decision, _ a: Answer, reply: String? = nil, pane: String?) {
        q.async { [weak self] in
            guard let self, let pane else { return }
            let keys = AnswerKeys.keys(for: a, prompt: self.prompts[d.sessionId], agent: d.agent, reply: reply)
            for k in keys.sends {
                switch k {
                case AnswerKeys.escape, "esc": _ = Foundations.run(self.herdrPath, ["pane", "send-keys", pane, "esc"], timeout: 5)
                case "\r": _ = Foundations.run(self.herdrPath, ["pane", "send-keys", pane, "enter"], timeout: 5)
                default: _ = Foundations.run(self.herdrPath, ["pane", "send-text", pane, k], timeout: 5)
                }
                usleep(150_000)
            }
            if let i = self.decisions.firstIndex(where: { $0.id == d.id }) {
                self.decisions[i].answer = a
                self.decisions[i].answeredAt = Date()
                self.decisions[i].replyText = reply
            }
            self.store?.answer(decision: d.id, a, reply: reply)
            if a == .always { self.store?.save(DecisionRule(pattern: d.pattern, repo: d.repo)) }
            self.openDecision[d.sessionId] = nil
            self.publishAll()
        }
    }

    // MARK: Subagents (ENGINES §4)

    private func scanSubagents(_ s: Live, now: Date) -> Bool {
        let config = AccountResolver.launchEnv(agent: .claude, account: s.account)["CLAUDE_CONFIG_DIR"]
        let folder = ConversationIndex.folder(forLaunchDirectory: s.launchDirectory, configDir: config)
        let convs = ConversationIndex.recent(in: folder, limit: 30)
        guard let title = s.title?.trimmingCharacters(in: .whitespaces), !title.isEmpty,
              let conv = convs.first(where: { $0.title == title }) else { return false }
        var jsonl = ""
        let main = folder + "/\(conv.id).jsonl"
        if let d = Self.tail(main, bytes: 3 << 20) { jsonl = String(decoding: d, as: UTF8.self) }
        let sub = ClaudeTranscript.subagentsFolder(configDir: config ?? NSHomeDirectory() + "/.claude", cwd: s.launchDirectory, sessionId: conv.id)
        for f in (try? FileManager.default.contentsOfDirectory(atPath: sub)) ?? [] where f.hasSuffix(".jsonl") {
            if let d = Self.tail(sub + "/" + f, bytes: 1 << 20) { jsonl += "\n" + String(decoding: d, as: UTF8.self) }
        }
        let list = ClaudeTranscript.subagents(jsonl: jsonl, sessionId: s.id)
        let before = Set((subagents[s.id] ?? []).map(\.id))
        let started = list.filter { !before.contains($0.id) && $0.ended == nil }.map(\.name)
        if !started.isEmpty, let e = FeedSignals.subagentsStarted(sessionId: s.id, names: started, at: now) { add(e) }
        guard list != subagents[s.id] ?? [] else { return false }
        subagents[s.id] = list
        return true
    }

    static func tail(_ path: String, bytes: Int) -> Data? {
        guard let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        return try? h.readToEnd()
    }

    // MARK: Publish

    private func publishAll() {
        let caps = lastCaption
        let events = feed.events
        let ds = decisions
        let subs = subagents
        let chs = chapters
        let cl = claims
        DispatchQueue.main.async { [weak self] in
            guard let m = self?.model else { return }
            m.applyEngines(captions: caps, feed: events, decisions: ds, subagents: subs, chapters: chs, claims: cl)
        }
    }

    func mute(session: String, on: Bool) { q.async { [weak self] in on ? self?.feed.mute(session: session) : self?.feed.unmute(session: session) } }
}

extension Decision {
    /// A blocked session whose prompt no matcher recognises: still a decision, with the question line and no guess.
    static func fallback(sessionId: String, agent: AgentKind, text: String, repo: String, now: Date) -> Decision {
        let lines = TerminalText.lines(text).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !TerminalText.isChrome($0) }
        let question = lines.last { $0.contains("?") } ?? lines.last ?? "The agent is waiting for you"
        return Decision(sessionId: sessionId, agent: agent, kind: .other, why: DecisionBuilder.noWhy, whyMissing: true,
                        touches: "One Roof could not read what this prompt does. Open the session to see it.",
                        risk: .high, ifNo: "The agent keeps waiting; it does nothing until you answer.",
                        pattern: "ask:" + String(question.prefix(80)), repo: Workspace.repoLabel(for: repo), askedAt: now)
    }

    /// What the card says: the engine's title, or the agent's own question when the prompt was not recognised.
    var headline: String {
        if pattern.hasPrefix("ask:") { return "\(agent.displayName) is asking: " + pattern.dropFirst(4) }
        return title
    }
}
