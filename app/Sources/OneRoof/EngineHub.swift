import Foundation
import OneRoofCore

/// Runs the v2 engines (ENGINES §1–§6) off the main thread and publishes their results to the model:
/// captions (heuristic first, the on-device model when it answers), the FYI feed, decisions with their "why",
/// Claude subagents from the transcript, chapters, and file claims. Input each second from the runtime poll: which
/// sessions are live, their status and their output seq (a cheap "new output" signal); terminal text comes from
/// the runtime's `read` (read-only). Every engine has a deterministic fallback, so the UI never waits on a model.
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
        var lastActive: Date?
        var added: Int?
        var removed: Int?
        var plan: CaptionPlan?
        /// In a pane or selected in a window (LAB-1330: the on-device model is asked for visible sessions only).
        var visible = false
        /// LAB-1606: the question the agent's turn ended with (it is waiting for your reply, not at a prompt).
        var question: String?
    }

    private let q = DispatchQueue(label: "oneroof.engines", qos: .utility)
    private weak var model: AppModel?
    private let store: SessionStore?
    private let runtime: SessionRuntime
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
    private var scannedStatus: [String: SessionStatus] = [:]
    private var subagents: [String: [Subagent]] = [:]
    private var lastCaption: [String: Caption] = [:]
    private let modelClient = CaptionModelClient()
    /// LAB-1330: model calls run here, one at a time, never on `q`.
    private let modelQ = DispatchQueue(label: "oneroof.engines.model", qos: .utility)
    private var modelBusy = Set<String>()
    private var lastModelAsk: [String: Date] = [:]
    private var modelStatus: [String: SessionStatus] = [:]
    private var modelUp = false
    private var lastModelCheck = Date.distantPast
    /// Tests and self-tests can feed text instead of reading the runtime.
    var textOverride: ((String) -> String?)?
    /// LAB-1286: the transcript file each Claude session shows (found by the subagent scan, every 5 s), for the
    /// terminal pane's Table view. Read from the main thread, written on the engine queue.
    private let transcriptLock = NSLock()
    private var transcripts: [String: String] = [:]
    func transcriptPath(_ sessionId: String) -> String? {
        transcriptLock.lock(); defer { transcriptLock.unlock() }
        return transcripts[sessionId]
    }
    private func setTranscript(_ sessionId: String, _ path: String?) {
        transcriptLock.lock(); defer { transcriptLock.unlock() }
        transcripts[sessionId] = path
    }

    init(model: AppModel, store: SessionStore?, runtime: SessionRuntime) {
        self.model = model
        self.store = store
        self.runtime = runtime
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

    // MARK: Tick (called after every runtime poll)

    func tick(_ live: [Live]) {
        q.async { [weak self] in self?.step(live, now: Date()) }
    }

    private func step(_ live: [Live], now: Date) {
        let ids = Set(live.map(\.id))
        for (id, _) in revisions where !ids.contains(id) { scheduler.remove(id); revisions[id] = nil }
        for id in Set(agentFiles.keys).union(claudeLinks.keys).union(scanSig.keys) where !ids.contains(id) {
            agentFiles[id] = nil; claudeLinks[id] = nil; lastLinkTry[id] = nil; scanSig[id] = nil
            setTranscript(id, nil)
        }
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
        // Claude subagents: scan the transcript every 5 s while the session is live and on screen, every 20 s out of
        // sight (LAB-1331), and at once when its status changes.
        for s in live where s.agent == .claude && s.status.isLive
            && now.timeIntervalSince(lastSubagentScan[s.id] ?? .distantPast) > (s.visible || statuses[s.id] != scannedStatus[s.id] ? 5 : 20) {
            scannedStatus[s.id] = statuses[s.id]
            lastSubagentScan[s.id] = now
            if scanSubagents(s, now: now) { changed = true }
        }
        if changed { publishAll() }
    }

    // MARK: Captions (ENGINES §1)

    private func text(_ s: Live, lines: Int = 300) -> String {
        if let o = textOverride?(s.id) { return o }
        guard let pane = s.pane else { return "" }
        return (try? runtime.read(pane: pane, lines: lines)) ?? ""
    }

    private func caption(_ s: Live, now: Date) {
        let t = text(s)
        let input = CaptionInput(text: t, agent: s.agent, status: s.status, objective: s.objective, plan: s.plan,
                                 lastActivity: s.lastActive ?? s.launchedAt, now: now)
        let heur = CaptionEngine.heuristic(input)
        // LAB-1330: the on-device model is asked at most every 30 s per session, only for a session on screen or one
        // whose status changed, off the engine queue (a call blocked it up to 6 s), one call at a time; a tick that
        // finds a call running skips it. Between calls a model caption stays up to 90 s while the status holds;
        // the heuristic caption shows meanwhile otherwise, as before.
        let statusChanged = modelStatus[s.id] != s.status
        if checkModel(now), s.visible || statusChanged, !modelBusy.contains(s.id),
           now.timeIntervalSince(lastModelAsk[s.id] ?? .distantPast) >= 30 || statusChanged {
            lastModelAsk[s.id] = now; modelStatus[s.id] = s.status; modelBusy.insert(s.id)
            let client = modelClient, id = s.id
            modelQ.async { [weak self] in
                let reply = client.reply(for: input, timeout: 6)
                self?.q.async {
                    guard let self else { return }
                    self.modelBusy.remove(id)
                    let (cap, events) = CaptionEngine.resolve(heuristic: nil, modelReply: reply, input: input, sessionId: id)
                    guard let cap else { return }
                    self.lastCaption[id] = cap
                    self.store?.saveCaption(cap, session: id)
                    for e in events { _ = self.add(e) }
                    self.publishAll()
                }
            }
        }
        let held = lastCaption[s.id].map { $0.source == .model && now.timeIntervalSince($0.updatedAt) < 90 && !statusChanged } ?? false
        let cap = held ? lastCaption[s.id] : heur
        if !held, let cap {
            lastCaption[s.id] = cap
            store?.saveCaption(cap, session: s.id)
        }
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
        if let q = s.question {
            // LAB-1606: no prompt on screen, a question at the end of the turn: answered with a reply, never a key.
            prompts[s.id] = nil
            let d = Decision.asked(sessionId: s.id, agent: s.agent, question: q, repo: s.repoPath, now: now)
            decisions.append(d)
            openDecision[s.id] = d.id
            store?.save(d)
            return
        }
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

    /// Answer a decision: the agent's own keys via the runtime (y / a / n or the CLI's numbers; Esc then text for Reply).
    func answer(_ d: Decision, _ a: Answer, reply: String? = nil, pane: String?) {
        q.async { [weak self] in
            guard let self, let pane else { return }
            let keys = d.isQuestion ? AnswerKeys.reply(reply)
                : AnswerKeys.keys(for: a, prompt: self.prompts[d.sessionId], agent: d.agent, reply: reply)
            // Unsupported native prompts remain unanswered and visible for manual terminal handling.
            guard !keys.sends.isEmpty else { return }
            for k in keys.sends {
                switch k {
                case AnswerKeys.escape, "esc": try? self.runtime.keys(pane: pane, [.escape])
                case "\r": try? self.runtime.keys(pane: pane, [.enter])
                default: try? self.runtime.type(pane: pane, text: k)
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

    /// A session's claude process and the config dir holding its `sessions/<pid>.json` (LAB-652), kept per session so
    /// the process tree is walked once, not every scan. The small sessions file is re-read each scan, so a /clear or
    /// /resume inside the same process (a new session id) is followed.
    private struct ClaudeLink { var pid: Int32; var configDir: String }
    private var claudeLinks: [String: ClaudeLink] = [:]
    private var lastLinkTry: [String: Date] = [:]
    private struct FileSig: Equatable { var size: UInt64; var modified: Date }
    private var agentFiles: [String: [String: (sig: FileSig, file: SubagentFile)]] = [:]   // session → path → read
    private var scanSig: [String: (sig: [FileSig], at: Date)] = [:]

    /// The Claude conversation a session shows: exactly, from its claude process's sessions file; else (no process
    /// found, e.g. an older Claude Code) the conversation whose ai-title is the session's title.
    private func conversation(_ s: Live, now: Date) -> (id: String, folder: String)? {
        let account = AccountResolver.launchEnv(agent: .claude, account: s.account)["CLAUDE_CONFIG_DIR"]
        if claudeLinks[s.id] == nil, now.timeIntervalSince(lastLinkTry[s.id] ?? .distantPast) > 15 {
            lastLinkTry[s.id] = now
            claudeLinks[s.id] = findClaude(s, account: account)
        }
        if let link = claudeLinks[s.id] {
            let file = ClaudeSessionLocator.sessionFile(configDir: link.configDir, pid: link.pid)
            if let d = FileManager.default.contents(atPath: file), let live = ClaudeSessionLocator.parseSessionFile(d, pid: link.pid) {
                for dir in [live.cwd, s.launchDirectory].compactMap({ $0 }) {
                    let folder = ConversationIndex.folder(forLaunchDirectory: dir, configDir: link.configDir)
                    if FileManager.default.fileExists(atPath: folder + "/\(live.sessionId).jsonl") { return (live.sessionId, folder) }
                }
            } else {
                claudeLinks[s.id] = nil   // the process ended or was replaced: look again next time
            }
        }
        let folder = ConversationIndex.folder(forLaunchDirectory: s.launchDirectory, configDir: account)
        guard let conv = ClaudeSessionLocator.byTitle(s.title, in: ConversationIndex.recent(in: folder, limit: 30)) else { return nil }
        return (conv.id, folder)
    }

    /// The claude process in the session's pane (the foreground group first, else the shell's process tree) and the
    /// config dir whose sessions file names it.
    private func findClaude(_ s: Live, account: String?) -> ClaudeLink? {
        guard let pane = s.pane, let info = try? runtime.processes(pane: pane) else { return nil }
        var pid = ClaudeSessionLocator.claudePid(in: info.foreground.map { .init(pid: $0.pid, name: $0.name, argv: $0.argv) })
        if pid == nil, let shell = info.shellPid {
            let table = ProcTable(LiveResourceSource().processes())
            let procs = table.tree(shell).compactMap { node -> ClaudeSessionLocator.Proc? in
                guard let e = table.byPid[node.pid], ["claude", "node", "bun"].contains(e.name) else { return nil }
                return .init(pid: e.pid, ppid: e.ppid, name: e.name, argv: ProcessProbe.args(pid: e.pid)?.argv ?? [])
            }
            pid = ClaudeSessionLocator.claudePid(in: procs)
        }
        guard let pid else { return nil }
        let dirs = ClaudeSessionLocator.configDirs(processEnv: ProcessProbe.args(pid: pid)?.env, account: account, home: NSHomeDirectory())
        for dir in dirs where FileManager.default.fileExists(atPath: ClaudeSessionLocator.sessionFile(configDir: dir, pid: pid)) {
            return ClaudeLink(pid: pid, configDir: dir)
        }
        return nil
    }

    private func scanSubagents(_ s: Live, now: Date) -> Bool {
        guard let conv = conversation(s, now: now) else { setTranscript(s.id, nil); return false }
        setTranscript(s.id, conv.folder + "/\(conv.id).jsonl")
        let fm = FileManager.default
        func sig(_ path: String) -> FileSig? {
            guard let a = try? fm.attributesOfItem(atPath: path) else { return nil }
            return FileSig(size: (a[.size] as? NSNumber)?.uint64Value ?? 0, modified: a[.modificationDate] as? Date ?? .distantPast)
        }
        let main = conv.folder + "/\(conv.id).jsonl"
        let sub = conv.folder + "/\(conv.id)/subagents"
        let names = ((try? fm.contentsOfDirectory(atPath: sub)) ?? []).filter { $0.hasSuffix(".jsonl") }.sorted()
        var sigs = [sig(main) ?? FileSig(size: 0, modified: .distantPast)]
        var files: [SubagentFile] = []
        var cache = agentFiles[s.id] ?? [:]
        var seen: [String: (sig: FileSig, file: SubagentFile)] = [:]
        defer { agentFiles[s.id] = seen }
        for n in names {
            let path = sub + "/" + n
            guard let fs = sig(path) else { continue }
            sigs.append(fs)
            if let c = cache.removeValue(forKey: path), c.sig == fs { seen[path] = c; files.append(c.file); continue }
            let meta = fm.contents(atPath: SubagentMeta.metaPath(forTranscript: path)).flatMap(SubagentMeta.parse)
            let tailBytes = 512 << 10
            let tail = Self.tail(path, bytes: tailBytes).map { String(decoding: $0, as: UTF8.self) } ?? ""
            // A long file's tail misses its first line (start time, prompt): read that separately.
            let head = fs.size > UInt64(tailBytes) ? Self.firstLine(path, bytes: 256 << 10) : ""
            let file = SubagentFile(meta: meta, head: head, tail: tail, modified: fs.modified)
            seen[path] = (fs, file)
            files.append(file)
        }
        // Nothing changed on disk and the time-based done rules were checked within the minute: nothing to redo.
        if let last = scanSig[s.id], last.sig == sigs, now.timeIntervalSince(last.at) < 60 { return false }
        scanSig[s.id] = (sigs, now)
        let jsonl = TailReader.shared.tail(main, bytes: 3 << 20).map { String(decoding: $0, as: UTF8.self) } ?? ""   // LAB-1331
        let list = ClaudeTranscript.subagents(main: jsonl, files: files, sessionId: s.id, now: now)
        let before = Set((subagents[s.id] ?? []).map(\.id))
        let started = list.filter { !before.contains($0.id) && $0.ended == nil }.map(\.name)
        if !started.isEmpty, let e = FeedSignals.subagentsStarted(sessionId: s.id, names: started, at: now) { add(e) }
        guard list != subagents[s.id] ?? [] else { return false }
        subagents[s.id] = list
        return true
    }

    static func firstLine(_ path: String, bytes: Int) -> String {
        guard let h = FileHandle(forReadingAtPath: path) else { return "" }
        defer { try? h.close() }
        guard let d = try? h.read(upToCount: bytes), let nl = d.firstIndex(of: 0x0A) else { return "" }
        return String(decoding: d[d.startIndex..<nl], as: UTF8.self)
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
        let question = DecisionBuilder.fallbackQuestion(text)
        return Decision(sessionId: sessionId, agent: agent, kind: .other, why: DecisionBuilder.noWhy, whyMissing: true,
                        touches: DecisionBuilder.unreadPrompt,
                        risk: .high, ifNo: "The agent keeps waiting; it does nothing until you answer.",
                        pattern: "ask:" + question, repo: Workspace.repoLabel(for: repo), askedAt: now)
    }

    /// LAB-1606 · a turn that ended with a plain-text question: the card shows the question and a reply box.
    static func asked(sessionId: String, agent: AgentKind, question: String, repo: String, now: Date) -> Decision {
        Decision(sessionId: sessionId, agent: agent, kind: .other, why: question, touches: "Nothing: it is a question, not an action.",
                 risk: .low, ifNo: "The agent keeps waiting for your answer.",
                 pattern: Decision.questionPrefix + question, repo: Workspace.repoLabel(for: repo), askedAt: now)
    }

    /// What the card says: the engine's title, or the agent's own question when the prompt was not recognised.
    var headline: String {
        if isQuestion { return "\(agent.displayName) asked: " + pattern.dropFirst(Decision.questionPrefix.count) }
        if pattern.hasPrefix("ask:") { return "\(agent.displayName) is asking: " + pattern.dropFirst(4) }
        return title
    }
}
