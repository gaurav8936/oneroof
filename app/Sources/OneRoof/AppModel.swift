import AppKit
import Combine
import OneRoofCore

/// App state: stored sessions + the session runtime's live sessions → sidebar rows. Polls the runtime once a second.
final class AppModel: ObservableObject {
    /// Every stored session, manual and loop rounds (roofd, engines and the Loops area need them all).
    @Published private(set) var items: [BoardItem] = [] { didSet { sessionItems = SessionScope.sessions(items) } }
    /// LAB-1933 · the sessions a person started: what every session list, count, search and Needs you shows.
    private(set) var sessionItems: [BoardItem] = []
    @Published var grouping: Grouping {
        didSet { if !SelfTest.isActive { Prefs.defaults.set(grouping.rawValue, forKey: "grouping") } }
    }
    /// Main windows, one per workspace (WINDOW_SHELL §1). `active` is the key one (or the first).
    @Published var windows: [WindowState] = []
    /// Latest caption per session (caption engine; S02, S06 rows, S01 cards).
    var captions: [String: LiveCaption] { get { EngineState.shared.captions } set { EngineState.shared.captions = newValue } }   // LAB-1338
    /// Schedule label per session ("2:00 AM"), from the schedules table.
    @Published var schedules: [String: String] = [:]
    /// Subagents per session (Subagents engine), in tree order.
    var subagents: [String: [Subagent]] { get { EngineState.shared.subagents } set { EngineState.shared.subagents = newValue } }   // LAB-1338
    /// Open and recently answered decisions (Decisions engine; S03, S02 approval card).
    @Published var decisions: [Decision] = []
    /// Chapters per session.
    var chapters: [String: [Chapter]] { get { EngineState.shared.chapters } set { EngineState.shared.chapters = newValue } }   // LAB-1338
    /// "Explain this step" answers, by session · step (LAB-259).
    @Published var stepExplanations: [String: StepExplainState] = [:]
    /// The step a session's terminal is rewound to, shown in the right panel's Step review (LAB-260); nil = latest.
    @Published var reviewStep: [String: Int] = [:]
    /// Files the agents are editing right now (S07 claim banner).
    var fileClaims = FileClaims()
    var scheduleRecords: [String: ScheduleRecord] = [:]
    lazy var engines = EngineHub(model: self, store: store, runtime: runtime)
    /// The FYI feed, newest first (Feed engine; S01).
    var feed: [FeedEntry] { get { EngineState.shared.feed } set { EngineState.shared.feed = newValue } }   // LAB-1338
    @Published var mutedWindows: Set<String> = []
    @Published var mutedSessions: Set<String> = []
    @Published var activeWindowId: String?
    /// Which workspace each session belongs to (session id → workspace id); unassigned sessions are in the first.
    @Published var sessionWorkspace: [String: String] = [:]
    var windowBags: [String: AnyCancellable] = [:]
    /// The owner's theme per panel (Settings, plan panel). `themes` is what the panels draw with.
    @Published var chosenThemes: PanelThemes {
        didSet {
            saveThemes(); applyAppearance()
            if settings.ui2 { let name = Look.matching(chosenThemes)?.rawValue ?? "custom"; if settings.lookName != name { settings.lookName = name } }
        }
    }
    @Published private(set) var themes: PanelThemes

    /// Recompute `themes` from the choice, the macOS appearance and Settings › Follow macOS.
    func applyAppearance() {
        let dark = NSApp?.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let t = chosenThemes.forAppearance(systemDark: dark, follow: settings.followSystemAppearance)
        if t != themes { themes = t }
    }
    @Published private(set) var runtimeState: String = "Connecting…"
    @Published private(set) var runtimeOK = false
    /// The version the running roofd reports (LAB-526), for the footer's "older than the app" note.
    @Published private(set) var daemonVersion: String?
    @Published var lastError: String? {
        // LAB-1584: an error while a catalog row is resuming belongs on that row, where the button was pressed.
        didSet { if let e = lastError, let id = catalogPending { catalogNotes[id] = .failed(e); catalogPending = nil } }
    }
    /// LAB-1584 · what Resume did, per catalog row, and the row waiting for its answer.
    @Published var catalogNotes: [String: CatalogNote] = [:]
    var catalogPending: String?
    @Published var busy: Set<String> = []
    /// A Learn page to open (e.g. a skill's page from Foundations › Skills).
    @Published var learnTarget: String?
    /// A "how do I…" question for Learn to answer; Learn ranks its pages and opens the best one (v2: the best card's
    /// station, LAB-1274).
    @Published var learnQuery: String?
    /// LAB-1274 · a One Roof Help page for the v2 Help page (B4.1) to open at (Learn has no Pages list any more).
    @Published var helpTarget: String?
    /// Every Learn page (loaded once, in the background, on first use).
    @Published private(set) var learnItems: [LearnItem] = []
    private var learnDocs: [LearnMatch.Doc] = []
    /// Course audio; keeps playing whatever the centre shows.
    let player = CoursePlayer()
    private var learnLoading = false
    /// Sessions whose terminal is in its own window (runtime ids).
    @Published var poppedOut: Set<String> = []
    @Published var workstreams: [LinearWorkstream] = []
    /// Usage windows per seat (Claude1, Claude2, Codex), refreshed every 30 s.
    @Published var seats: [SeatUsage] = []
    /// LAB-1998: which agents are set up on this Mac (for the bottom bar); refreshed with the seats, at most every 10 min.
    @Published var dockFacts: DockSeats.Facts?
    private var dockFactsAt = Date.distantPast
    /// v2 (CAP-26): the rule just learned from Always allow on a terminal's approval card, offered for Undo for 5 s.
    @Published var v2UndoRule: (decision: Decision, window: String)? = nil
    /// Self-test: the Needs you entry to show (a decision id), as a click in its list would.
    @Published var needsPick: String? = nil
    /// LAB-2042 · self-test only (ONEROOF_SELFTEST_INBOX): asks of the demo sessions, answered in place (no pane).
    @Published var selfTestDecisions: [Decision] = []
    /// Objectives typed by the owner, with their plans.
    @Published var objectives: [Objective] = []
    @Published var issues: [String: [LinearIssue]] = [:]     // project id → tickets
    /// When each project's issues last came from Linear, and the projects being fetched now (LAB-546: the list was
    /// fetched once and never again, so issues created after that never showed).
    /// LAB-2103: published, so the Projects page can say "updated N min ago".
    @Published var issuesFetchedAt: [String: Date] = [:]
    /// When the project list was last fetched from Linear (LAB-1255).
    @Published var workstreamsFetchedAt: Date?
    @Published var issuesLoading: Set<String> = []
    /// A commit-watch scan is running (LAB-474), so ticks never overlap.
    var commitWatchBusy = false
    /// Agent issue requests being applied ("runtime id:seq"), so a 3 s tick never applies one twice (LAB-518).
    var issueRequestsInFlight = Set<String>()
    @Published var linearError: String?
    @Published var linearLoading = false
    /// Re-created when a key is saved (Setup…), so Linear connects without a restart.
    var linear = LinearClient(mapping: LinearMapping.load())
    /// LAB-2102: Settings › Linear's mapping (state and label names, hidden teams); published so Projects redraws.
    @Published var linearMapping: LinearMapping = LinearMapping.load()
    var teams: [String: LinearTeam] = [:]
    /// Linear teams for the pickers (LAB-237).
    @Published var linearTeams: [LinearTeamRef] = []
    @Published var settings: AppSettings {
        didSet {
            if !SelfTest.isActive, let d = try? JSONEncoder().encode(settings) { Prefs.defaults.set(d, forKey: "settings") }
            if settings.projectsPath != oldValue.projectsPath || settings.commonPath != oldValue.commonPath
                || settings.localModelPath != oldValue.localModelPath { Self.applyFolders(settings) }
            if settings.learnFolders != oldValue.learnFolders { learnItems = [] }
            if !settings.dockBadge { NSApp.dockTile.badgeLabel = nil }
            if settings.accounts != oldValue.accounts || settings.removedAccounts != oldValue.removedAccounts {
                AgentAccounts.use(stored: settings.accounts, removed: settings.removedAccounts)   // LAB-1999
            }
            if settings.hostedRuntime != oldValue.hostedRuntime || settings.hostedConnections != oldValue.hostedConnections
                || settings.accounts != oldValue.accounts || settings.removedAccounts != oldValue.removedAccounts {
                refreshSeats(facts: true)
            }
            if settings.followSystemAppearance != oldValue.followSystemAppearance { applyAppearance() }
            if settings.scheduledRuns != oldValue.scheduledRuns || settings.projectsPath != oldValue.projectsPath { configureRoofdScheduler() }
            if settings.agenticEngineeringPath != oldValue.agenticEngineeringPath { learnItems = [] }   // re-read on next open
            if settings.shortcuts != oldValue.shortcuts || settings.globalHotkey != oldValue.globalHotkey {
                NotificationCenter.default.post(name: .shortcutsChanged, object: nil)
            }
        }
    }

    /// Rows matching the sidebar filter (name, repo, workstream, tags, agent, account).
    var visibleItems: [BoardItem] {
        let q = filter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { i in
            [i.session.name, i.repoLabel, i.session.workstream ?? "", i.session.tags.joined(separator: " "),
             i.session.agent.displayName, i.account ?? "", i.status.label].joined(separator: " ").lowercased().contains(q)
        }
    }

    /// What runs every session: roofd (LAB-ROOFD).
    let runtime: SessionRuntime = Runtimes.make()
    let store: SessionStore?
    private var stored: [Session] = []
    private var lastSnapshot = RuntimeSnapshot() { didSet { snapshotIndex = nil } }
    /// LAB-1328: the by-id table of the latest snapshot, built once per snapshot (it was built again for every row).
    private var snapshotIndex: [RuntimeID: RuntimeSessionState]?
    /// The rows have been built from a real snapshot once (status changes before that are the app starting up).
    private var sawSnapshot = false
    /// Live sessions by runtime id from the latest snapshot (output seq for the caption engine).
    var lastSnapshotSessions: [RuntimeID: RuntimeSessionState] {
        if let i = snapshotIndex { return i }
        let i = Dictionary(lastSnapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        snapshotIndex = i
        return i
    }
    private var accounts: [String: String] = [:]     // runtime id → account label
    /// Runtime ids the rows were reloaded for already (sessions started outside the app).
    private var reloadedFor = Set<RuntimeID>()
    private var probing = Set<String>()
    /// Agents whose account the runtime queue has read, or tried often enough (LAB-1328: the queue keeps its own list,
    /// instead of asking the main thread for the model's every second with main.sync).
    private var probed = Set<String>()
    private var probeTries: [String: Int] = [:]
    private var timer: Timer?
    /// Commands to type into a terminal session once it starts (session id → command).
    private var pendingCommands: [String: String] = [:]
    /// Latest foundations check.
    @Published private(set) var foundations: [CheckResult] = []
    @Published private(set) var checkingFoundations = false
    @Published private(set) var foundationsCheckedAt: Date?
    /// Set when the owner chose "Launch anyway" for this run of the app.
    var foundationsOverride = false

    /// When each row last changed status or was working (in memory; falls back to the launch time). Not published
    /// (LAB-1314): it moves every second while an agent works; views read it when they redraw for a real change.
    private(set) var lastActive: [String: Date] = [:]
    /// LAB-490: settles each row's status before the list moves it.
    private var statusSmoother = StatusSmoother()
    /// Branch and diff size per session repo path, refreshed every 10 s off the main thread.
    @Published private(set) var repoStats: [String: RepoStat] = [:]
    /// When the owner last had each session in front of them (selected or showing in a pane).
    private var lastViewed: [String: Date] = [:]
    private let startedAt = Date()
    private let queue = DispatchQueue(label: "oneroof.runtime", qos: .userInitiated)
    /// What One Roof itself costs, per session and overall (LAB-493).
    let resources = ResourceMonitor()
    /// LAB-1316 · Learn rankings by question (not published: a cache, not state).
    final class LearnRankCache { var cards: [String: [String]] = [:]; var pages: [String: [String]] = [:] }
    let learnRankCache = LearnRankCache()
    /// LAB-1315 · handoff matches for exited sessions (PanePlaceholder).
    let handoffCache = HandoffCache()
    /// LAB-675 · Get the model (Settings and the Foundations check).
    let modelDownload = ModelDownloadController()

    init() {
        grouping = Grouping(rawValue: Prefs.defaults.string(forKey: "grouping") ?? "") ?? .status
        var chosen = PanelThemes.load(Prefs.defaults)
        // LAB-1951: ONEROOF_SELFTEST_LOOK picks the panels' themes too (a self-test never saves them).
        if SelfTest.isActive, let v = ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_LOOK"], let t = Look.selfTestThemes(v) { chosen = t }
        chosenThemes = chosen
        themes = chosen
        let loaded = Prefs.loadSettings()
        AgentAccounts.use(stored: loaded.accounts, removed: loaded.removedAccounts)   // LAB-1999, before anything reads it
        settings = loaded
        Self.applyFolders(loaded)
        var openError: Error?
        let opened: SessionStore?
        do {
            if let path = ProcessInfo.processInfo.environment["ONEROOF_STORE"] ?? Prefs.freshStorePath {
                opened = try SessionStore(path: path)
            } else {
                opened = try SessionStore()
            }
        } catch { openError = error; opened = nil }
        store = opened
        stored = store?.all() ?? []
        objectives = store?.allObjectives() ?? []
        // LAB-1517: say why (a newer One Roof's store is refused, never written).
        if store == nil { lastError = "Could not open the session store. " + (openError?.localizedDescription ?? "") }
        WorkspaceStore.shared.attach(store)
        let records = WorkspaceStore.shared.workspaces
        for id in WindowMembership.toRestore(records.map { ($0.id, $0.open) }) {
            if let r = records.first(where: { $0.id == id }) { adopt(WindowState(id: r.id, name: r.name, colour: r.colour)) }
        }
        scheduleRecords = Dictionary((store?.schedules() ?? []).map { ($0.sessionId, $0) }, uniquingKeysWith: { a, _ in a })
        schedules = scheduleRecords.compactMapValues { ScheduleClock.rowLabel($0) }
        sessionWorkspace = WorkspaceStore.shared.assignments
        activeWindowId = windows.first?.id
    }

    /// Point the core at the folders in Settings (projects, shared, on-device model).
    static func applyFolders(_ s: AppSettings) {
        Workspace.configure(root: s.projectsFolder, shared: s.sharedFolder)
        LocalModel.configure(path: s.modelFile)
    }

    func start() {
        modelDownload.onDone = { [weak self] _ in self?.modelDownloaded() }
        if settings.startupCheck { runFoundations() }
        // macOS light/dark switches.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.applyAppearance() }
        }
        applyAppearance()
        resources.start(model: self)
        ResourceMonitor.stopLeftoverLocalModel()
        queue.async { [weak self] in
            guard let self else { return }
            do {
                // roofd as a background item (launchd keeps it running, at login too); the app starts it otherwise.
                if let roofd = self.runtime as? RoofdRuntime { roofd.managedByLaunchd = RoofdService.register() }
                try self.runtime.ensureRunning()
                DispatchQueue.main.async { self.configureRoofdScheduler() }
            } catch {
                DispatchQueue.main.async { self.runtimeState = "\(self.runtime.kind.displayName) not running: \(error)" }
            }
            self.poll()
        }
        var ticks = 0
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            ticks += 1
            // LAB-1323: with no window on screen (hidden, minimised or covered), poll every 3 s instead of every second.
            if ticks % 3 == 0 || Self.anyWindowOnScreen { self?.queue.async { self?.poll() } }
            if ticks % 3 == 0 { self?.tickObjectives(); self?.deliverPendingMessages(); self?.applyIssueRequests() }
            if ticks % 30 == 1 { self?.refreshSeats() }
            if ticks % 10 == 2 { self?.refreshRepoStats() }
            if ticks % 30 == 5 { self?.tickSchedules() }
            if ticks % 60 == 40 { self?.closeIdleFinishedShells(); self?.closeIdleSessions() }   // LAB-1524 · LAB-1535: once a minute
            if ticks % 30 == 15 { self?.checkRoofdOwner() }
            if ticks % 60 == 40 { self?.tickCommitWatch() }
            if ticks % 15 == 3 { self?.refreshLoopInbox() }   // LAB-1866 · LAB-1919: loop items for Needs you
        }
        timer?.tolerance = 0.1   // LAB-1323: let the system batch wake-ups
    }

    /// A main or pop-out window the owner can see (not hidden, minimised or fully covered).
    static var anyWindowOnScreen: Bool {
        NSApp.windows.contains { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) && $0.canBecomeMain }
    }

    /// Once the background item is on (approved in Login Items after start, say), launchd's roofd should serve:
    /// re-check every 30 s; ensureRunning hands over from an app-started daemon without touching sessions.
    func checkRoofdOwner() {
        guard let roofd = runtime as? RoofdRuntime, !SelfTest.isActive else { return }
        queue.async {
            // register() also registers again after a rebuild (a new signature launchd would refuse to start).
            roofd.managedByLaunchd = RoofdService.register()
            try? roofd.ensureRunning()
        }
    }

    /// roofd fires Tonight / Nightly itself when scheduled runs are allowed (Q7); the app's own tick stands down then.
    var roofdRunsSchedules: Bool { runtime.kind == .roofd && settings.scheduledRuns }

    func configureRoofdScheduler() {
        guard let roofd = runtime as? RoofdRuntime, let path = store?.path, !SelfTest.isActive else { return }
        let s = settings
        queue.async { roofd.configureScheduler(enabled: s.scheduledRuns, store: path, projects: s.projectsFolder, shared: s.sharedFolder) }
    }

    private func saveThemes() {
        guard !SelfTest.isActive else { return }   // test runs never change the owner's preferences
        if let d = try? JSONEncoder().encode(chosenThemes) { Prefs.defaults.set(d, forKey: PanelThemes.storageKey) }
    }

    // MARK: Polling (runs on `queue`)

    private func poll() {
        do {
            var snap = try runtime.snapshot()
            // Demo mode (screenshots for the public help): show only the seeded demo sessions, never live ones.
            if ProcessInfo.processInfo.environment["ONEROOF_SELFTEST_DEMO"] == "1" { snap.sessions = [] }
            let state = runtime.statusLine(snap)
            probeAccounts(snap)
            DispatchQueue.main.async {
                // A session started without the app (a scheduled run in roofd) was saved to the store by roofd:
                // reload the rows once, so it shows as its own session and not as a stray.
                let known = Set(self.stored.compactMap(\.runtimeId))
                let fresh = Set(snap.agents.map(\.id)).subtracting(known).subtracting(self.reloadedFor)
                if !fresh.isEmpty, let store = self.store, case let rows = self.storeQ.sync(execute: { store.all() }) {   // after queued writes
                    self.reloadedFor.formUnion(fresh)
                    self.stored = rows
                }
                self.lastSnapshot = snap
                // LAB-1314: assign published values only when they change; each assignment re-renders every view
                // observing the model, and this runs every second.
                if !self.runtimeOK { self.runtimeOK = true }
                if self.runtimeState != state { self.runtimeState = state }
                if self.daemonVersion != snap.version { self.daemonVersion = snap.version }
                self.rebuild()
            }
        } catch {
            DispatchQueue.main.async {
                if self.runtimeOK { self.runtimeOK = false }
                if self.runtimeState != "\(error)" { self.runtimeState = "\(error)" }
                self.rebuild()
            }
            // roofd is not answering (it stopped, or was never started): start it again at once, at most every 5 s.
            // Sessions live in their holders; a new daemon finds them by their sockets.
            if Date().timeIntervalSince(lastRecovery) > 5 {
                lastRecovery = Date()
                try? runtime.ensureRunning()
            }
        }
    }
    /// Last time poll() tried to bring roofd back (on the runtime queue).
    private var lastRecovery = Date.distantPast

    /// Read each new agent's account from its process environment (pane → foreground PID → sysctl).
    private func probeAccounts(_ snap: RuntimeSnapshot) {
        for a in snap.agents where !probed.contains(a.id) && !probing.contains(a.id) {
            guard let kind = a.agent else { continue }
            probing.insert(a.id)
            defer { probing.remove(a.id) }
            // An agent just starting has no foreground process or environment yet: try again on the next polls, a
            // minute at most (the old code asked every second, forever, for an agent whose account can't be read).
            probeTries[a.id, default: 0] += 1
            if probeTries[a.id, default: 0] >= 60 { probed.insert(a.id) }
            guard let procs = try? runtime.processes(pane: a.pane).foreground else { continue }
            // Prefer the process whose argv names the agent; otherwise the first foreground process.
            let pick = procs.first { p in p.argv.joined(separator: " ").lowercased().contains(kind.rawValue) } ?? procs.first
            guard let pid = pick?.pid, let args = ProcessProbe.args(pid: pid), !args.env.isEmpty else { continue }
            probed.insert(a.id)
            if let label = AccountResolver.label(agent: kind, env: args.env) {
                DispatchQueue.main.async { self.accounts[a.id] = label; self.rebuild() }
            }
        }
    }

    private func rebuild() {
        var new = Board.merge(stored: stored, snapshot: lastSnapshot, accounts: accounts)
        // Remember the repo each session was last seen working in, so it keeps its group after it exits.
        let learnt = new.filter { !$0.adopted && $0.workRepo != nil && $0.workRepo != $0.session.lastRepo }
        if !learnt.isEmpty {
            var rows: [Session] = []
            for i in learnt {
                guard let k = stored.firstIndex(where: { $0.id == i.id }) else { continue }
                stored[k].lastRepo = i.workRepo
                rows.append(stored[k])
            }
            if let store { storeQ.async { rows.forEach(store.save) } }   // LAB-1336: off the main thread
            new = Board.merge(stored: stored, snapshot: lastSnapshot, accounts: accounts)
        }
        // LAB-1510: remember each agent's conversation (Claude's transcript the engines follow) on the session itself,
        // so Resume and the session catalog work after the terminal is gone or the app restarts.
        rememberConversations(new)
        // Last active (LAB-258): what roofd says, since its holders outlive the app; for a runtime that does not say,
        // any status change seen while the app runs, or while an agent is working. Not the first statuses after a
        // (re)start: those are the app catching up, not the session doing something.
        let now = Date()
        let runtimeActive = Dictionary(lastSnapshot.sessions.compactMap { s in s.activeAt.map { (s.id, $0) } },
                                       uniquingKeysWith: { a, _ in a })
        let before = Dictionary(items.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a })
        for i in new {
            if let id = i.liveAgent, let at = runtimeActive[id] {
                lastActive[i.id] = i.status == .running ? now : at
            } else if i.status == .running || (sawSnapshot && before[i.id] != nil && before[i.id] != i.status) {
                lastActive[i.id] = now
            }
        }
        let wasWatching = sawSnapshot
        sawSnapshot = sawSnapshot || !lastSnapshot.sessions.isEmpty
        let inView = visibleInPanes.union([selectedId].compactMap { $0 })
        for id in inView { lastViewed[id] = now }
        // A finished turn the owner is looking at is no longer news (roofd: done → idle).
        let seenDone = new.filter { inView.contains($0.id) && $0.status == .done }.compactMap(\.liveAgent)
        if !seenDone.isEmpty { let r = runtime; queue.async { seenDone.forEach(r.markSeen) } }
        // LAB-490: list rows by a status that has held for a moment, so they do not jump on every flicker.
        new = statusSmoother.settle(new, now: now)
        // LAB-197: a finished turn → a desktop notification (not the statuses seen while the app catches up).
        if wasWatching { notifyStatusChanges(before: Dictionary(items.map { ($0.id, $0.status) }, uniquingKeysWith: { a, _ in a }), after: new) }
        if new != items {
            items = new
            updateDockBadge()
        }
        feedEngines()
        if let sel = selectedId, !items.contains(where: { $0.id == sel }) {
            // An adopted row that was just saved changes id; keep the selection on its agent.
            selectedId = nil
        }
    }

    // MARK: Queries

    var groups: [BoardGroup] { Board.group(visibleItems, by: grouping) }
    var selected: BoardItem? { items.first { $0.id == selectedId } }
    func item(_ id: String) -> BoardItem? { items.first { $0.id == id } }

    // MARK: Learn

    func loadLearn() {
        guard learnItems.isEmpty, !learnLoading else { return }
        learnLoading = true
        let ae = settings.agenticEngineering.path, extra = settings.learnFolders
        DispatchQueue.global(qos: .userInitiated).async {
            let list = LearnIndex.build(agenticEngineering: ae, extraFolders: extra)
            let docs = list.map { LearnMatch.Doc(id: $0.id, title: $0.title, text: $0.section + " " + $0.summary) }
            DispatchQueue.main.async { self.learnItems = list; self.learnDocs = docs; self.learnLoading = false }
        }
    }

    /// LAB-1274 · the bundled deck (Radio · Writing · All cards), read once. Nil when the build has no deck.
    var learnDeck: LearnDeck? {
        let root = AEFolder.deckRoot(settings.agenticEngineering.path)
        if let d = deckCache, d.root == root { return d }
        deckCache = LearnDeck.load(deck: root)
        return deckCache
    }
    private var deckCache: LearnDeck?

    /// LAB-1835 · the shared Learn page saved in this build (`agentic_engineering/learn/`) and the deck it plays, checked once
    /// per folder. Nil: no saved page (a build from source without the deck); Learn then says so.
    var learnShared: LearnShared.Location? {
        let ae = settings.agenticEngineering.path
        if let c = learnSharedCache, c.ae == ae { return c.loc }
        let loc = LearnShared.locate(ae: ae, deck: AEFolder.deckRoot(ae))
        learnSharedCache = (ae, loc)
        return loc
    }
    private var learnSharedCache: (ae: String, loc: LearnShared.Location?)?

    /// LAB-1274 · the deck cards that best answer `question` (v2: How do I…, Search, the Plan panel), best first.
    /// LAB-1316: ranking all the deck's cards runs from view bodies (the Plan panel's Related in Learn) on every
    /// redraw; the answer depends only on the question and the deck, so it is kept per question.
    func learnCards(_ question: String, limit: Int = 8) -> [DeckCard] {
        guard let deck = learnDeck else { return [] }
        let key = "\(deck.root)\u{1}\(limit)\u{1}\(question)"
        if let hit = rankCache[key] { return hit.compactMap { deck.cards[$0] } }
        let ids = deck.bestCards(for: question, limit: limit)
        if rankCache.count > 256 { rankCache.removeAll() }
        rankCache[key] = ids
        return ids.compactMap { deck.cards[$0] }
    }
    private var rankCache: [String: [String]] {
        get { learnRankCache.cards }
        set { learnRankCache.cards = newValue }
    }

    /// LAB-1274 · open a deck card's station in Learn (v2). Re-set so the same card opens again. `show` false: the
    /// caller opens Learn itself (e.g. in its own window).
    func openLearnCard(_ slug: String, show: Bool = true) {
        guard let deck = learnDeck, deck.cards[slug] != nil else { return }
        learnTarget = nil
        learnTarget = deck.htmlPath(slug)
        if show { learnMode = true }
    }

    /// Learn pages that best answer `question`, best first.
    func learnMatches(_ question: String, limit: Int = 8) -> [LearnItem] {
        let byId = Dictionary(learnItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let key = "\(learnDocs.count)\u{1}\(limit)\u{1}\(question)"   // LAB-1316: learnDocs only grows from empty once
        if let hit = learnRankCache.pages[key] { return hit.compactMap { byId[$0] } }
        let ids = LearnMatch.rank(question, learnDocs, limit: limit)
        if learnRankCache.pages.count > 256 { learnRankCache.pages.removeAll() }
        learnRankCache.pages[key] = ids
        return ids.compactMap { byId[$0] }
    }

    /// "How do I…": open Learn on the best page for the question, with the ranked list beside it.
    func howDoI(_ question: String) {
        loadLearn()
        learnQuery = question
        learnMode = true
    }

    // MARK: Mutations

    func save(_ s: Session) { saveAll([s]) }

    /// LAB-1336: several sessions at once, one rebuild; the SQLite writes run in order on the store's own queue
    /// (the store is locked, so reads on the main thread stay safe), not on the main thread.
    func saveAll(_ list: [Session]) {
        guard !list.isEmpty else { return }
        for s in list {
            if let i = stored.firstIndex(where: { $0.id == s.id }) { stored[i] = s } else { stored.append(s) }
        }
        // LAB-1516: a save keeps a newer launch roofd wrote (Scheduler, Loops) instead of erasing it, and the app adopts it.
        if let store {
            storeQ.async { [weak self] in
                let written = list.map { store.saveKeepingNewerLaunch($0) }
                let adopted = written.filter { w in !list.contains(w) }
                guard !adopted.isEmpty else { return }
                DispatchQueue.main.async {
                    guard let self else { return }
                    for w in adopted { if let i = self.stored.firstIndex(where: { $0.id == w.id }) { self.stored[i].copyLaunch(from: w) } }
                    self.rebuild()
                }
            }
        }
        rebuild()
    }
    /// LAB-1336: where session rows are written.
    let storeQ = DispatchQueue(label: "oneroof.store", qos: .utility)

    /// Edit a row. Adopted rows (live agents started elsewhere) become stored sessions on first edit.
    func update(_ item: BoardItem, _ change: (inout Session) -> Void) {
        var s = item.session
        change(&s)
        if item.adopted { s.lifecycle = .idle }
        if item.agentInTerminal { s.agent = .shell }
        save(s)
    }

    // MARK: Stickers, icon, colour, pin, rename

    func toggleSticker(_ item: BoardItem, _ tag: String) {
        let key = Sticker.resolve(tag).id
        if key == "next" { setLifecycle(item, item.status == .next ? .planned : .next); return }
        if key == "dnu" { setLifecycle(item, item.status == .doNotUse ? (item.liveAgent == nil ? .planned : .idle) : .doNotUse); return }
        update(item) { s in
            if let i = s.tags.firstIndex(where: { Sticker.resolve($0).id == key }) { s.tags.remove(at: i) } else { s.tags.append(tag) }
        }
    }
    func setIcon(_ item: BoardItem, _ icon: String?) { update(item) { $0.icon = icon } }
    func setColor(_ item: BoardItem, _ color: String?) { update(item) { $0.color = color } }
    func togglePin(_ item: BoardItem) { update(item) { $0.pinned.toggle() } }
    func rename(_ item: BoardItem, _ name: String) {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty, n != item.session.name else { return }
        update(item) { $0.name = n }
    }
    /// New since the owner last looked: the agent finished, went idle or needs them while out of sight.
    func isUnread(_ item: BoardItem) -> Bool {
        guard [.done, .idle, .needsYou].contains(item.status), item.id != selectedId, !visibleInPanes.contains(item.id),
              let active = lastActive[item.id] else { return false }
        return active > (lastViewed[item.id] ?? startedAt)
    }

    /// Sessions the owner closed or removed, newest last, for Session › Reopen Closed Session.
    private(set) var recentlyClosed: [Session] = []

    private func rememberClosed(_ s: Session) {
        recentlyClosed.removeAll { $0.id == s.id }
        recentlyClosed.append(s)
        if recentlyClosed.count > 20 { recentlyClosed.removeFirst() }
    }

    /// Bring back the newest closed session: restore its row if it was removed, select it, and relaunch it.
    func reopenClosed() {
        guard let s = recentlyClosed.popLast() else { lastError = "Nothing closed to reopen."; return }
        if let k = stored.firstIndex(where: { $0.id == s.id }), stored[k].archived {   // LAB-1537: back in its window
            var back = stored[k]; back.archived = false; save(back)
        } else if !stored.contains(where: { $0.id == s.id }) {
            var back = s
            back.runtimeId = nil; back.runtimeGroup = nil; back.openingSent = false
            save(back)
        }
        selectedId = s.id
        guard let item = item(s.id) else { return }
        if item.liveAgent == nil && item.status != .doNotUse { launch(item) }
    }

    /// The repo a session's Files and Changes show (v2): where it works (seen live, else last seen), else the folder it
    /// started in. Sessions started at the workspace root (One Roof's default, "one memory") work in a repo below it;
    /// 1.8.1: the v2 tabs and ⌥⌘R showed the root ("not in a git repo") for them. The classic window keeps the start folder.
    func workRepo(_ i: BoardItem) -> String { settings.ui2 ? (i.repoPath ?? i.session.repoPath) : i.session.repoPath }

    /// Branch and diff size per session repo (LAB-1319). Called every 10 s; each repo costs four or five git processes,
    /// so a repo is read again only when it is due: every 10 s while a live session in it is working or in front of
    /// the owner, every 60 s while its sessions are live but out of sight, every 5 min when none of them is live
    /// (exited and planned rows keep the last numbers). Folders that are not in a repo are never asked.
    func refreshRepoStats(now: Date = Date()) {
        let inView = visibleInPanes.union([selectedId].compactMap { $0 })
        var interval: [String: TimeInterval] = [:]
        for i in items where i.status != .doNotUse {
            let every: TimeInterval = i.liveAgent == nil ? 300 : (i.status == .running || inView.contains(i.id)) ? 10 : 60
            for p in Set([i.session.repoPath, workRepo(i)]) where p != Workspace.projectsRoot {
                interval[p] = min(interval[p] ?? .infinity, every)
            }
        }
        let due = interval.filter { p, every in repoStatAt[p].map { now.timeIntervalSince($0) >= every - 0.5 } ?? true }.map(\.key)
        let gone = Set(repoStats.keys).subtracting(interval.keys)
        for p in due { repoStatAt[p] = now }
        for p in gone { repoStatAt[p] = nil }
        guard !due.isEmpty || !gone.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var got: [String: RepoStat?] = [:]
            for p in due { got.updateValue(GitDiff.repoRoot(for: p) == nil ? nil : GitDiff.stat(repo: p), forKey: p) }
            DispatchQueue.main.async {
                guard let self else { return }
                var out = self.repoStats
                for p in gone { out[p] = nil }
                for (p, s) in got { out[p] = s }
                if self.repoStats != out { self.repoStats = out }
            }
        }
    }
    /// When each repo's stats were last asked for (LAB-1319).
    private var repoStatAt: [String: Date] = [:]

    func lastActiveDate(_ item: BoardItem) -> Date? { lastActive[item.id] ?? item.session.launchedAt }

    func setLifecycle(_ item: BoardItem, _ status: SessionStatus) {
        update(item) { $0.lifecycle = status }
    }

    /// LAB-1537 · Remove: the row leaves its window's list and stays in All sessions (archived); its terminal, if any, is
    /// closed. Nothing is deleted — Delete forever in All sessions does that. ⇧⌘T brings it back.
    func delete(_ item: BoardItem) {
        guard !item.adopted else { return }
        rememberClosed(item.session)
        if item.liveAgent == nil, let ws = item.session.runtimeGroup {
            let id = item.session.runtimeId ?? ""
            queue.async { [weak self] in try? self?.runtime.close(id, group: ws) }
        }
        guard let k = stored.firstIndex(where: { $0.id == item.id }) else { return }
        var s = stored[k]
        s.archived = true
        save(s)
    }

    /// LAB-1537 · Delete forever (All sessions only, asked first): the record itself goes.
    func deleteForever(_ item: BoardItem) {
        guard !item.adopted else { return }
        rememberClosed(item.session)
        if item.liveAgent == nil, let ws = item.session.runtimeGroup {
            let id = item.session.runtimeId ?? ""
            queue.async { [weak self] in try? self?.runtime.close(id, group: ws) }
        }
        stored.removeAll { $0.id == item.id }
        if let store { let id = item.id; storeQ.async { store.delete(id: id) } }   // LAB-1336: in order with the writes
        Notifier.shared.clear(session: item.id)
        if selectedId == item.id { selectedId = nil }
        rebuild()
    }

    /// Run the foundations check in the background (at launch when Settings says so, and on demand).
    func runFoundations() {
        guard !checkingFoundations else { return }
        checkingFoundations = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self else { return }
            let r = self.checkFoundationsNow()
            DispatchQueue.main.async {
                self.foundations = r
                self.checkingFoundations = false
                self.foundationsCheckedAt = Date()
            }
        }
    }

    /// One full foundations pass (blocking; call off the main thread).
    nonisolated func checkFoundationsNow() -> [CheckResult] {
        let s = DispatchQueue.main.sync { settings }
        var r = Foundations.runAll(FoundationPaths(common: s.sharedFolder, agenticEngineering: s.agenticEngineering.path), runtime: runtime)
        r.insert(RoofdService.check(), at: min(1, r.count))
        return r
    }

    /// Red foundations before an agent starts (owner D5). The startup check can be hours old and the problem already
    /// fixed (owner 10-20: a doors warning on the first launch of the day), so check again first and only ask when it
    /// is still red. The question offers "Fix and launch" when every red check has a fix command.
    func recheckFoundationsThenLaunch(_ item: BoardItem) {
        busy.insert(item.id)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var r = self.checkFoundationsNow()
            // LAB-290: doors go stale every time CLAUDE.md is edited (~/Projects/AGENTS.md is generated from it), and the
            // fix only rewrites generated door files, so repair silently instead of asking on every launch.
            let silent = r.filter { $0.level == .fail && Foundations.silentFixIds.contains($0.id) }.compactMap(\.fix)
            if !silent.isEmpty {
                for fix in silent { _ = Foundations.run("/bin/zsh", ["-lc", fix], cwd: Workspace.projectsRoot, timeout: 120) }
                r = self.checkFoundationsNow()
            }
            DispatchQueue.main.async {
                self.foundations = r
                self.foundationsCheckedAt = Date()
                self.busy.remove(item.id)
                guard Foundations.overall(r) == .fail, let fresh = self.item(item.id) else {
                    if let fresh = self.item(item.id) { self.launch(fresh, foundationsChecked: true) }
                    return
                }
                self.askAboutFoundations(fresh, triedFix: false)
            }
        }
    }

    private func askAboutFoundations(_ item: BoardItem, triedFix: Bool) {
        let reds = foundations.filter { $0.level == .fail }
        let fixes = reds.compactMap(\.fix)
        let canFix = !triedFix && !fixes.isEmpty && fixes.count == reds.count
        let a = NSAlert()
        a.messageText = triedFix ? "The fix did not clear every problem" : "The foundations check found problems"
        a.informativeText = reds.map { "• \($0.title): \($0.detail)" }.joined(separator: "\n")
            + "\n\nAn agent started now may miss shared rules, skills or memory."
            + (canFix ? " Fix and launch runs the fix for you, then starts the agent." : " Fix them in Window › Foundations, or launch anyway.")
        if canFix { a.addButton(withTitle: "Fix and launch") }
        a.addButton(withTitle: "Open Foundations")
        a.addButton(withTitle: "Launch anyway")
        a.addButton(withTitle: "Cancel")
        var choice = a.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        if !canFix { choice += 1 }
        switch choice {
        case 0:
            busy.insert(item.id)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self else { return }
                for fix in fixes { _ = Foundations.run("/bin/zsh", ["-lc", fix], cwd: Workspace.projectsRoot, timeout: 120) }
                let r = self.checkFoundationsNow()
                DispatchQueue.main.async {
                    self.foundations = r
                    self.foundationsCheckedAt = Date()
                    self.busy.remove(item.id)
                    guard let fresh = self.item(item.id) else { return }
                    if Foundations.overall(r) == .fail { self.askAboutFoundations(fresh, triedFix: true) }
                    else { self.launch(fresh, foundationsChecked: true) }
                }
            }
        case 1: NotificationCenter.default.post(name: .openFoundations, object: nil)
        case 2: foundationsOverride = true; launch(item, foundationsChecked: true)
        default: break
        }
    }

    var foundationsLevel: CheckLevel? { foundations.isEmpty ? nil : Foundations.overall(foundations) }

    /// Open a terminal in ~/Projects and run a workspace command in it, so the owner sees the output.
    func runInTerminal(_ command: String, title: String) {
        var s = Session(name: title, agent: .shell, repoPath: Workspace.projectsRoot, lifecycle: .idle)
        s.startInRepo = false
        pendingCommands[s.id] = command
        createPlanned(s, launchNow: true)
    }

    /// File › New Terminal (⌘T): a plain shell in ~/Projects (or the selected session's repo), launched at once.
    func newTerminal(in dir: String? = nil) {
        let repo = dir ?? Workspace.projectsRoot
        let n = stored.filter { !$0.agent.isAgent }.count + 1
        var s = Session(name: "Terminal \(n)", agent: .shell, repoPath: repo, lifecycle: .idle)
        s.startInRepo = repo != Workspace.projectsRoot
        createPlanned(s, launchNow: true)
    }

    func refreshSeats(facts: Bool = false) {
        let settings = self.settings
        let wantFacts = facts || Date().timeIntervalSince(dockFactsAt) > 600
        if wantFacts { dockFactsAt = Date() }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let u = Usage.all()
            let f = wantFacts ? DockSeats.facts(settings: settings) : nil
            DispatchQueue.main.async {
                if self?.seats != u { self?.seats = u }   // LAB-1314: only on change
                if let f, self?.dockFacts != f { self?.dockFacts = f }
            }
        }
    }

    /// LAB-1998: the agents the bottom bar shows, in order: set up on this Mac, minus the ones hidden in Settings.
    var dockMarks: [SeatMark] {
        let usage = Set(seats.map(\.seat))
        guard let f = dockFacts else {
            return DockSeats.order.map { SeatMark($0) }.filter { m in DockSeats.usageName(m).map(usage.contains) ?? false || m == .claude1 }
                .filter { !settings.dockHidden.contains($0.rawValue) }
        }
        return DockSeats.shown(f, hidden: settings.dockHidden, usageSeats: usage)
    }

    /// Router suggestion for a step, with the policy read in place from the agentic-engineering folder.
    func route(kind: String?, budget: String, avoid: AgentKind? = nil) -> RouteSuggestion {
        Router.suggest(kind: kind, budget: budget, usage: seats, policy: routingPolicy(), avoid: avoid)
    }

    /// routing.json (or the built-in rules) with the owner's Settings › Seats & accounts routing rules on top (NEW-6).
    func routingPolicy() -> RoutingPolicy {
        var p = RoutingPolicy.load(agenticEngineering: settings.agenticEngineering.path)
        if settings.handOffAt > 0 { p.skipFiveHour = Double(settings.handOffAt) }
        return p
    }

    /// Task text → kind (on-device model) → router suggestion. Calls back on the main thread.
    func suggestAgent(for text: String, budget: String = "normal", done: @escaping (RouteSuggestion, String?) -> Void) {
        let ae = settings.agenticEngineering.path
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let kind = LocalModel.shared.classify(text, kinds: RoutingPolicy.kindDescriptions(agenticEngineering: ae))
            DispatchQueue.main.async {
                var r = self.route(kind: kind, budget: budget)
                if kind != nil { r.reason = "on-device model: \(kind!) · " + r.reason }
                done(r, kind)
            }
        }
    }

    /// Back to the terminals (Workspace) in the window in front.
    func goTerminals() { show(.workspace) }

    /// Open a file or folder in the centre viewer; a folder with a README opens on the README.

    func openInViewer(_ path: String, line: Int? = nil) {
        viewerLine = line
        var p = path
        var dir: ObjCBool = false
        if FileManager.default.fileExists(atPath: p, isDirectory: &dir), dir.boolValue {
            for readme in ["README.md", "readme.md", "Readme.md"] where FileManager.default.fileExists(atPath: p + "/" + readme) { p += "/" + readme; break }
        }
        // A search hit (a line) in Markdown or HTML opens the source at that line; otherwise the formatted page.
        if line != nil, DocumentRoute.hasPreview(FileKind.of(p).core) { EditorState.of(active.id).setMode(.source, for: p) }
        viewerPath = p
        NSApp.mainWindow?.makeKeyAndOrderFront(nil)
    }

    /// Follow a oneroof:// link. Selects, shows or plans; never launches anything.
    func open(_ link: RoofLink) {
        switch link {
        case .session(let key):
            guard let i = items.first(where: { $0.id == key || $0.liveAgent == key || $0.session.name == key }) else {
                lastError = "No session \"\(key)\" in One Roof."; return
            }
            goTerminals(); selectedId = i.id
        case .objective(let key):
            guard let o = objectives.first(where: { $0.id == key || $0.title == key }) else { lastError = "No objective \"\(key)\"."; return }
            objectiveId = o.id
        case .view(let v, let q):
            switch v {
            case "launchpad": launchpadMode = true
            case "board": boardMode = true
            case "work": workMode = true
            case "learn": learnMode = true
            case "review": openDiff()
            case "search": openSearch(q)
            default: goTerminals()
            }
        case .file(let path, let line):
            openInViewer(path, line: line)
        case .plan(let agent, let repo, let name, let message):
            var s = Session(name: name, agent: agent, repoPath: repo, workstream: Workspace.workstream(in: name),
                            openingMessage: message, lifecycle: .planned)
            s.startInRepo = repo != Workspace.projectsRoot
            createPlanned(s, launchNow: false)
            goTerminals(); selectedId = s.id
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Search in Workspace in the centre viewer.
    func openSearch(_ seed: String? = nil) { searchSeed = seed; viewerLine = nil; viewerPath = FileKind.searchPath }
    /// A query to start Search in Workspace with (self-test, palette).
    var searchSeed: String?

    /// Code review panel for a repo: the selected session's when none is given, else ~/Projects' own.
    func openDiff(_ path: String? = nil) {
        let start = path ?? selected.map { workRepo($0) } ?? Workspace.projectsRoot
        guard let root = GitDiff.repoRoot(for: start) else {
            lastError = "\((start as NSString).lastPathComponent) is not in a git repo, so there is nothing to review."
            return
        }
        viewerPath = FileKind.diffPrefix + root
    }

    /// The agent session a review comment goes to: the selected one if it works in this repo, else the most
    /// recently active live agent in it.
    func reviewTarget(repo: String) -> BoardItem? {
        func inRepo(_ i: BoardItem) -> Bool {
            i.session.agent.isAgent && i.liveAgent != nil && (i.session.repoPath == repo || i.session.repoPath.hasPrefix(repo + "/"))
        }
        if let s = selected, inRepo(s) { return s }
        return items.filter(inRepo).max { (lastActive[$0.id] ?? .distantPast) < (lastActive[$1.id] ?? .distantPast) }
    }

    /// Send a review comment to the repo's agent when it is between turns. Returns a line for the panel.
    func sendReview(_ text: String, repo: String) -> String {
        guard let target = reviewTarget(repo: repo), let agent = target.liveAgent else { return "No live agent session in this repo." }
        if let no = target.status.typingRefusal(name: target.session.name) { return no }
        let r = runtime
        DispatchQueue.global().async { try? r.submit(agent, text: text) }
        return "Comment sent to \(target.session.name)."
    }

    func viewerBack() {
        let w = active
        guard w.viewerHistory.count >= 2 else { return }
        w.viewerHistory.removeLast()
        if let p = w.viewerHistory.last { w.viewerPath = p }
    }

    /// Session › Remove Exited Sessions: drop rows whose agent is gone (not pinned, not on a running objective).
    func removeExited() {
        let busySteps = Set(objectives.filter { $0.status == .running }.flatMap { $0.stepSessions.values })
        for i in items where i.status == .exited && !i.session.pinned && !i.adopted && !busySteps.contains(i.id) { delete(i) }
    }

    /// A new session, in `window` (the window that asked for it) or the window in front (LAB-705).
    /// LAB-1600: a new agent session takes its agent's permission mode from Settings › Permissions (Auto by default),
    /// unless it was given one (New session sheet, objective step) or its own arguments already set one.
    func createPlanned(_ s: Session, launchNow: Bool, in window: WindowState? = nil) {
        var s = s
        if s.agent.isAgent, s.permissionMode == nil, !PermissionMode.hasExplicit(s.agentArgs, agent: s.agent) {
            s.permissionMode = settings.permissionMode(for: s.agent)
            s.permissionFlags = settings.permissionFlags(for: s.agent, mode: settings.permissionMode(for: s.agent))   // LAB-1935
        }
        assign(s.id, to: window)
        save(s)
        (self.window(of: s.id) ?? active).selectedId = s.id
        if launchNow, let item = item(s.id) { launch(item) }
    }

    /// Start the session's agent in the runtime (in ~/Projects or the repo, with the account's env). The opening
    /// message travels in the launch spec: roofd sends it once the agent is ready (it arrives with the app closed too).
    func launch(_ item: BoardItem, foundationsChecked: Bool = false) {
        let s = item.session
        // Red foundations block starting an agent (owner D5), with a way through for this run.
        if s.agent.isAgent, !foundationsChecked, foundationsLevel == .fail, !foundationsOverride, !SelfTest.isActive {
            recheckFoundationsThenLaunch(item)
            return
        }
        if s.agent.isHosted {
            guard let connection = settings.hostedConnections.resolved(id: s.hostedConnectionID, model: s.model),
                  connection.model == s.model, connection.configurationErrors().isEmpty else {
                lastError = "Choose a saved hosted connection with today's verified prices and its exact model."
                return
            }
        }
        if s.agent.isHosted {
            guard let runtime = settings.hostedRuntime,
                  let connection = settings.hostedConnections.resolved(id: s.hostedConnectionID, model: s.model) else {
                lastError = "Configure the hosted runtime and connection in Settings › Seats & accounts."
                return
            }
            if s.hostedLaunch?.isCurrent(connection: connection, runtime: runtime) != true {
                prepareHostedLaunch(s, foundationsChecked: foundationsChecked)
                return
            }
        }
        let spec: LaunchSpec
        switch LaunchPlan.spec(s, stored: stored, command: pendingCommands[s.id], deliverOpening: true) {
        case .failure(let refusal): lastError = refusal.description; return
        case .success(let sp): spec = sp
        }
        lastError = nil
        busy.insert(s.id)
        let briefRuntime = InterimBrief.needsOpeningBrief(s.agent) && !SelfTest.isActive ? settings.hostedRuntime : nil
        queue.async { [weak self] in
            guard let self else { return }
            var spec = spec
            // LAB-1971: OpenCode and Goose have no session-start hook; the interim brief rides in the opening message.
            if let r = briefRuntime { spec.opening = InterimBrief.opening(brief: InterimBrief.fetch(runtime: r, cwd: (s.repoPath as NSString).expandingTildeInPath), opening: spec.opening) }
            do { self.finishLaunch(s, .success(try self.runtime.start(spec))) }
            catch { self.finishLaunch(s, .failure(error)) }
        }
    }

    /// LAB-1510: save a session's conversation id and transcript the first time the engines see it (and again if the
    /// agent moves to another conversation). Only rows that change are written, off the main thread.
    private func rememberConversations(_ items: [BoardItem]) {
        var rows: [Session] = []
        for i in items where i.session.agent == .claude {
            guard let path = engines.transcriptPath(i.id), let id = ClaudeResume.sessionId(transcriptPath: path),
                  let k = stored.firstIndex(where: { $0.id == i.id }),
                  stored[k].conversationId != id || stored[k].conversationPath != path else { continue }
            stored[k].conversationId = id
            stored[k].conversationPath = path
            rows.append(stored[k])
        }
        if !rows.isEmpty, let store { storeQ.async { rows.forEach(store.save) } }
    }

    /// LAB-1511 · once per run: find the Claude conversation of sessions saved before One Roof kept its id (only a
    /// confident match: first message within 10 minutes of the launch, and the opening message when there was one).
    func backfillConversations(done: @escaping (_ found: Int, _ looked: Int) -> Void = { _, _ in }) {
        let todo: [Session] = stored.filter { $0.agent == .claude && $0.conversationId == nil && $0.launchedAt != nil }
        guard !todo.isEmpty, !SelfTest.isActive else { done(0, todo.count); return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let dirs = ConversationBackfill.configDirs()
            var found: [(String, ConversationBackfill.Candidate)] = []
            for s in todo {
                let candidates = ConversationBackfill.candidates(for: s, configDirs: dirs)
                if case .found(let c) = ConversationBackfill.match(s, candidates) { found.append((s.id, c)) }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                var rows: [Session] = []
                for (id, c) in found {
                    guard let k = self.stored.firstIndex(where: { $0.id == id }), self.stored[k].conversationId == nil else { continue }
                    self.stored[k].conversationId = c.id
                    self.stored[k].conversationPath = c.path
                    rows.append(self.stored[k])
                }
                if !rows.isEmpty { self.saveAll(rows) }
                done(rows.count, todo.count)
            }
        }
    }

    /// LAB-1524 · close the shells finished agents left behind (Settings › When an agent ends; default: after an hour
    /// untouched). Only a shell at its prompt, not pinned, idle long enough; roofd is asked, off the main thread. The
    /// row stays, as history, resumable from the session catalog.
    func closeIdleFinishedShells(now: Date = Date()) {
        let minutes = settings.closeFinishedAfterMinutes
        guard minutes >= 0, !SelfTest.isActive else { return }
        let due = items.filter { i in
            i.endedShell != nil && FinishedShellPolicy.shouldClose(finishedShell: true, liveAgent: i.liveAgent != nil,
                pinned: i.session.pinned, atPrompt: true, lastActive: lastActiveDate(i), minutes: minutes, now: now)
        }
        guard !due.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let ready = due.filter { i in
                guard let pane = i.endedShell, let p = try? self.runtime.processes(pane: pane) else { return false }
                return FinishedShellPolicy.atPrompt(shellPid: p.shellPid, foreground: p.foreground.map(\.pid))
            }
            guard !ready.isEmpty else { return }
            DispatchQueue.main.async { ready.forEach { self.closeAgent($0, remember: false) } }
        }
    }

    /// LAB-1535 · close running sessions nobody touched for a day (Settings › General); see IdleSessionPolicy. Agent
    /// sessions need no probe (status says working or not); a plain terminal is closed only at its prompt (asked of roofd).
    func closeIdleSessions(now: Date = Date()) {
        let hours = settings.closeIdleSessionsAfterHours
        guard hours >= 0, !SelfTest.isActive else { return }
        let candidates = items.filter { i in
            i.liveAgent != nil && !i.adopted && IdleSessionPolicy.shouldClose(running: true, status: i.status, pinned: i.session.pinned,
                tags: i.session.tags, agent: i.session.agent, conversationId: i.session.conversationId, atPrompt: true,
                lastActive: lastActiveDate(i), hours: hours, now: now)
        }
        guard !candidates.isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            let ready = candidates.filter { i in
                guard !i.session.agent.isAgent else { return true }
                guard let pane = i.liveAgent, let p = try? self.runtime.processes(pane: pane) else { return false }
                return FinishedShellPolicy.atPrompt(shellPid: p.shellPid, foreground: p.foreground.map(\.pid))
            }
            guard !ready.isEmpty else { return }
            DispatchQueue.main.async { ready.forEach { self.closeAgent($0, remember: false) } }
        }
    }

    /// LAB-1362: continue an exited Claude session's conversation. Its terminal usually lives on (roofd runs
    /// `claude …; exec zsh`): type `claude --resume <id>` into it, so the folder, account, environment and scrollback
    /// are the same. Otherwise start it again with `--resume <id>` and no opening message. The id comes from the
    /// transcript the engines followed, else from Claude's exit hint on the screen.
    func resume(_ item: BoardItem) {
        guard item.session.agent == .claude else { launch(item); return }
        var s = item.session
        let shell = item.endedShell
        // LAB-1510: the saved conversation id covers a session whose terminal is gone and that the engines no longer follow.
        let known = engines.transcriptPath(item.id).flatMap(ClaudeResume.sessionId(transcriptPath:)) ?? s.conversationId
        busy.insert(s.id)
        queue.async { [weak self] in
            guard let self else { return }
            // Claude's own last word wins (an in-process /resume may have moved on since the engines looked).
            let onScreen = shell.flatMap { try? self.runtime.read(pane: $0, lines: 120) }.flatMap(ClaudeResume.sessionId(fromScreen:))
            guard let id = onScreen ?? known else {
                DispatchQueue.main.async {
                    self.busy.remove(s.id)
                    self.lastError = "No Claude conversation found to resume for \(s.name). Start a new session instead."
                }
                return
            }
            let command = ClaudeResume.command(launchArgs: s.launchArgs, sessionId: id)
            if let shell {
                do {
                    try self.runtime.type(pane: shell, text: "\u{15}")   // clear a half-typed line first (Ctrl-U)
                    try self.runtime.submit(shell, text: command)
                    DispatchQueue.main.async {
                        self.busy.remove(s.id)
                        s.launchedAt = Date()   // "starting" until Claude is back in the foreground
                        self.save(s)
                    }
                } catch {
                    DispatchQueue.main.async { self.busy.remove(s.id); self.lastError = "Resume failed: \(error)" }
                }
                return
            }
            var resumed = s
            resumed.agentArgs = ClaudeResume.args(s.agentArgs, sessionId: id)
            DispatchQueue.main.async {
                switch LaunchPlan.spec(resumed, stored: self.stored, command: nil, deliverOpening: false) {
                case .failure(let refusal): self.busy.remove(s.id); self.lastError = refusal.description
                case .success(let spec):
                    self.queue.async {
                        do { self.finishLaunch(s, .success(try self.runtime.start(spec))) }
                        catch { self.finishLaunch(s, .failure(error)) }
                    }
                }
            }
        }
    }

    private func finishLaunch(_ session: Session, _ result: Result<RuntimeSessionRef, Error>) {
        DispatchQueue.main.async {
            var s = session
            self.busy.remove(s.id)
            let ref: RuntimeSessionRef
            switch result {
            case .failure(let error): self.lastError = "Launch failed: \(error)"; return
            case .success(let r): ref = r
            }
            let name = ref.id, workspaceId = ref.groupId, adopted = ref.adopted
            // Fold the auto-saved "started outside One Roof" row for this agent into the session.
            if let i = self.stored.firstIndex(where: { $0.id == Session.adoptedPrefix + name }) {
                let extra = self.stored[i]
                if s.notes.isEmpty { s.notes = extra.notes }
                s.tags = Array(Set(s.tags + extra.tags)).sorted()
                self.stored.remove(at: i)
                if let store = self.store { let id = extra.id; self.storeQ.async { store.delete(id: id) } }
            }
            s.runtimeId = name
            s.runtimeGroup = workspaceId
            if !adopted {
                s.launchedAt = Date()
                // roofd delivers the opening message itself (it is in the launch spec).
                s.openingSent = true
            } else if s.launchedAt == nil {
                s.launchedAt = Date()
            }
            if s.lifecycle != .doNotUse { s.lifecycle = .idle }
            self.save(s)
            // Selected in its own window, not whichever is in front when the launch finishes (LAB-705).
            if let w = self.window(of: s.id) { w.selectedId = s.id }
            if !adopted { for i in s.ticketsToStartOnLaunch { if let id = i.id, let team = i.team { self.ticketStarted(id: id, team: team) } } }
            self.queue.async { self.poll() }
        }
    }

    /// End the session in the runtime (its agent or shell process).
    func closeAgent(_ item: BoardItem, remember: Bool = true) {
        let group = item.workspaceId ?? item.session.runtimeGroup
        // LAB-1545: a finished session (agent gone, shell open) has neither a live agent nor a group under roofd; its
        // shell's runtime id is what to close. Without this, "Close finished" and the 10-minute rule did nothing.
        guard let id = FinishedShellPolicy.closeTarget(liveAgent: item.liveAgent, endedShell: item.endedShell,
                                                       runtimeId: item.session.runtimeId, hasGroup: group != nil) else { return }
        if remember { rememberClosed(item.session) }
        queue.async { [weak self] in
            do { try self?.runtime.close(id, group: group) }
            catch { DispatchQueue.main.async { self?.lastError = "Close failed: \(error)" } }
            self?.poll()
        }
    }
}

extension Notification.Name {
    static let openFoundations = Notification.Name("oneroof.openFoundations")
    static let openSetup = Notification.Name("oneroof.openSetup")
    /// LAB-2102: Settings › Linear (Projects' Connect Linear…).
    static let openLinearSettings = Notification.Name("oneroof.openLinearSettings")
    static let newWorkItem = Notification.Name("oneroof.newWorkItem")
    static let projectsFind = Notification.Name("oneroof.projectsFind")   // LAB-2050: ⌘F in Projects focuses its filter
    static let newObjective = Notification.Name("oneroof.newObjective")
    static let panelCommand = Notification.Name("oneroof.panelCommand")
    static let shortcutsChanged = Notification.Name("oneroof.shortcutsChanged")
}
