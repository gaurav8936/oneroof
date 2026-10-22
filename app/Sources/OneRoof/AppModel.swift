import AppKit
import Combine
import OneRoofCore

/// App state: stored sessions + the session runtime's live sessions → sidebar rows. Polls the runtime once a second.
final class AppModel: ObservableObject {
    @Published private(set) var items: [BoardItem] = []
    @Published var grouping: Grouping {
        didSet { if !SelfTest.isActive { Prefs.defaults.set(grouping.rawValue, forKey: "grouping") } }
    }
    /// Main windows, one per workspace (WINDOW_SHELL §1). `active` is the key one (or the first).
    @Published var windows: [WindowState] = []
    /// Latest caption per session (caption engine; S02, S06 rows, S01 cards).
    @Published var captions: [String: LiveCaption] = [:]
    /// Schedule label per session ("2:00 AM"), from the schedules table.
    @Published var schedules: [String: String] = [:]
    /// Subagents per session (Subagents engine), in tree order.
    @Published var subagents: [String: [Subagent]] = [:]
    /// Open and recently answered decisions (Decisions engine; S03, S02 approval card).
    @Published var decisions: [Decision] = []
    /// Chapters per session.
    @Published var chapters: [String: [Chapter]] = [:]
    /// "Explain this step" answers, by session · step (LAB-259).
    @Published var stepExplanations: [String: StepExplainState] = [:]
    /// The step a session's terminal is rewound to, shown in the right panel's Step review (LAB-260); nil = latest.
    @Published var reviewStep: [String: Int] = [:]
    /// Files the agents are editing right now (S07 claim banner).
    var fileClaims = FileClaims()
    var scheduleRecords: [String: ScheduleRecord] = [:]
    lazy var engines = EngineHub(model: self, store: store, runtime: runtime)
    /// The FYI feed, newest first (Feed engine; S01).
    @Published var feed: [FeedEntry] = []
    @Published var mutedWindows: Set<String> = []
    @Published var mutedSessions: Set<String> = []
    @Published var activeWindowId: String?
    /// Which workspace each session belongs to (session id → workspace id); unassigned sessions are in the first.
    @Published var sessionWorkspace: [String: String] = [:]
    var windowBags: [String: AnyCancellable] = [:]
    /// The owner's theme per panel (Settings, plan panel). `themes` is what the panels draw with.
    @Published var chosenThemes: PanelThemes {
        didSet { saveThemes(); applyAppearance() }
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
    @Published var lastError: String?
    @Published var busy: Set<String> = []
    /// A Learn page to open (e.g. a skill's page from Foundations › Skills).
    @Published var learnTarget: String?
    /// A "how do I…" question for Learn to answer; Learn ranks its pages and opens the best one.
    @Published var learnQuery: String?
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
    /// Objectives typed by the owner, with their plans.
    @Published var objectives: [Objective] = []
    @Published var issues: [String: [LinearIssue]] = [:]     // project id → tickets
    @Published var linearError: String?
    @Published var linearLoading = false
    /// Re-created when a key is saved (Setup…), so Linear connects without a restart.
    var linear = LinearClient()
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
    private var lastSnapshot = RuntimeSnapshot()
    /// The rows have been built from a real snapshot once (status changes before that are the app starting up).
    private var sawSnapshot = false
    /// Live sessions by runtime id from the latest snapshot (output seq for the caption engine).
    var lastSnapshotSessions: [RuntimeID: RuntimeSessionState] {
        Dictionary(lastSnapshot.sessions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }
    private var accounts: [String: String] = [:]     // runtime id → account label
    /// Runtime ids the rows were reloaded for already (sessions started outside the app).
    private var reloadedFor = Set<RuntimeID>()
    private var probing = Set<String>()
    private var timer: Timer?
    /// Commands to type into a terminal session once it starts (session id → command).
    private var pendingCommands: [String: String] = [:]
    /// Latest foundations check.
    @Published private(set) var foundations: [CheckResult] = []
    @Published private(set) var checkingFoundations = false
    @Published private(set) var foundationsCheckedAt: Date?
    /// Set when the owner chose "Launch anyway" for this run of the app.
    var foundationsOverride = false

    /// When each row last changed status or was working (in memory; falls back to the launch time).
    @Published private(set) var lastActive: [String: Date] = [:]
    /// Branch and diff size per session repo path, refreshed every 10 s off the main thread.
    @Published private(set) var repoStats: [String: RepoStat] = [:]
    /// When the owner last had each session in front of them (selected or showing in a pane).
    private var lastViewed: [String: Date] = [:]
    private let startedAt = Date()
    private let queue = DispatchQueue(label: "oneroof.runtime", qos: .userInitiated)

    init() {
        grouping = Grouping(rawValue: Prefs.defaults.string(forKey: "grouping") ?? "") ?? .status
        let chosen = PanelThemes.load(Prefs.defaults)
        chosenThemes = chosen
        themes = chosen
        let loaded = Prefs.loadSettings()
        settings = loaded
        Self.applyFolders(loaded)
        if let path = ProcessInfo.processInfo.environment["ONEROOF_STORE"] ?? Prefs.freshStorePath {
            store = try? SessionStore(path: path)
        } else {
            store = try? SessionStore()
        }
        stored = store?.all() ?? []
        objectives = store?.allObjectives() ?? []
        if store == nil { lastError = "Could not open the session store." }
        WorkspaceStore.shared.attach(store)
        for r in WorkspaceStore.shared.workspaces where r.open { adopt(WindowState(id: r.id, name: r.name, colour: r.colour)) }
        if windows.isEmpty, let r = WorkspaceStore.shared.workspaces.first { adopt(WindowState(id: r.id, name: r.name, colour: r.colour)) }
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
        if settings.startupCheck { runFoundations() }
        // macOS light/dark switches.
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("AppleInterfaceThemeChangedNotification"),
                                                            object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self?.applyAppearance() }
        }
        applyAppearance()
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
            self?.queue.async { self?.poll() }
            ticks += 1
            if ticks % 3 == 0 { self?.tickObjectives() }
            if ticks % 30 == 1 { self?.refreshSeats() }
            if ticks % 10 == 2 { self?.refreshRepoStats() }
            if ticks % 30 == 5 { self?.tickSchedules() }
            if ticks % 30 == 15 { self?.checkRoofdOwner() }
        }
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
                if !fresh.isEmpty, let rows = self.store?.all() {
                    self.reloadedFor.formUnion(fresh)
                    self.stored = rows
                }
                self.lastSnapshot = snap
                self.runtimeOK = true
                self.runtimeState = state
                self.rebuild()
            }
        } catch {
            DispatchQueue.main.async {
                self.runtimeOK = false
                self.runtimeState = "\(error)"
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
        let known = DispatchQueue.main.sync { Set(accounts.keys) }
        for a in snap.agents where !known.contains(a.id) && !probing.contains(a.id) {
            guard let kind = a.agent else { continue }
            probing.insert(a.id)
            defer { probing.remove(a.id) }
            guard let procs = try? runtime.processes(pane: a.pane).foreground else { continue }
            // Prefer the process whose argv names the agent; otherwise the first foreground process.
            let pick = procs.first { p in p.argv.joined(separator: " ").lowercased().contains(kind.rawValue) } ?? procs.first
            guard let pid = pick?.pid, let args = ProcessProbe.args(pid: pid), !args.env.isEmpty else { continue }
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
            for i in learnt {
                guard let k = stored.firstIndex(where: { $0.id == i.id }) else { continue }
                stored[k].lastRepo = i.workRepo
                store?.save(stored[k])
            }
            new = Board.merge(stored: stored, snapshot: lastSnapshot, accounts: accounts)
        }
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
        sawSnapshot = sawSnapshot || !lastSnapshot.sessions.isEmpty
        let inView = visibleInPanes.union([selectedId].compactMap { $0 })
        for id in inView { lastViewed[id] = now }
        // A finished turn the owner is looking at is no longer news (roofd: done → idle).
        let seenDone = new.filter { inView.contains($0.id) && $0.status == .done }.compactMap(\.liveAgent)
        if !seenDone.isEmpty { let r = runtime; queue.async { seenDone.forEach(r.markSeen) } }
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

    /// Learn pages that best answer `question`, best first.
    func learnMatches(_ question: String, limit: Int = 8) -> [LearnItem] {
        let byId = Dictionary(learnItems.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return LearnMatch.rank(question, learnDocs, limit: limit).compactMap { byId[$0] }
    }

    /// "How do I…": open Learn on the best page for the question, with the ranked list beside it.
    func howDoI(_ question: String) {
        loadLearn()
        learnQuery = question
        learnMode = true
    }

    // MARK: Mutations

    func save(_ s: Session) {
        if let i = stored.firstIndex(where: { $0.id == s.id }) { stored[i] = s } else { stored.append(s) }
        store?.save(s)
        rebuild()
    }

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
        if !stored.contains(where: { $0.id == s.id }) {
            var back = s
            back.runtimeId = nil; back.runtimeGroup = nil; back.openingSent = false
            save(back)
        }
        selectedId = s.id
        guard let item = item(s.id) else { return }
        if item.liveAgent == nil && item.status != .doNotUse { launch(item) }
    }

    func refreshRepoStats() {
        let paths = Set(items.filter { $0.status != .doNotUse }.map(\.session.repoPath))
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var out: [String: RepoStat] = [:]
            for p in paths where p != Workspace.projectsRoot { if let s = GitDiff.stat(repo: p) { out[p] = s } }
            DispatchQueue.main.async { if self?.repoStats != out { self?.repoStats = out } }
        }
    }

    func lastActiveDate(_ item: BoardItem) -> Date? { lastActive[item.id] ?? item.session.launchedAt }

    func setLifecycle(_ item: BoardItem, _ status: SessionStatus) {
        update(item) { $0.lifecycle = status }
    }

    func delete(_ item: BoardItem) {
        guard !item.adopted else { return }
        rememberClosed(item.session)
        if item.liveAgent == nil, let ws = item.session.runtimeGroup {
            let id = item.session.runtimeId ?? ""
            queue.async { [weak self] in try? self?.runtime.close(id, group: ws) }
        }
        stored.removeAll { $0.id == item.id }
        store?.delete(id: item.id)
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

    func refreshSeats() {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let u = Usage.all()
            DispatchQueue.main.async { self?.seats = u }
        }
    }

    /// Router suggestion for a step, with the policy read in place from the agentic-engineering folder.
    func route(kind: String?, budget: String, avoid: AgentKind? = nil) -> RouteSuggestion {
        Router.suggest(kind: kind, budget: budget, usage: seats,
                       policy: RoutingPolicy.load(agenticEngineering: settings.agenticEngineering.path), avoid: avoid)
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
        let start = path ?? selected?.session.repoPath ?? Workspace.projectsRoot
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
        guard target.status != .running else { return "\(target.session.name) is working; send when it is idle." }
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

    func createPlanned(_ s: Session, launchNow: Bool) {
        assignToActive(s.id)
        save(s)
        selectedId = s.id
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
        let spec: LaunchSpec
        switch LaunchPlan.spec(s, stored: stored, command: pendingCommands[s.id], deliverOpening: true) {
        case .failure(let refusal): lastError = refusal.description; return
        case .success(let sp): spec = sp
        }
        lastError = nil
        busy.insert(s.id)
        queue.async { [weak self] in
            guard let self else { return }
            do { self.finishLaunch(s, .success(try self.runtime.start(spec))) }
            catch { self.finishLaunch(s, .failure(error)) }
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
                self.store?.delete(id: extra.id)
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
            self.selectedId = s.id
            if !adopted { for i in s.allTickets { if let id = i.id, let team = i.team { self.ticketStarted(id: id, team: team) } } }
            self.queue.async { self.poll() }
        }
    }

    /// End the session in the runtime (its agent or shell process).
    func closeAgent(_ item: BoardItem, remember: Bool = true) {
        let group = item.workspaceId ?? item.session.runtimeGroup
        guard group != nil || item.liveAgent != nil else { return }
        let id = item.liveAgent ?? item.session.runtimeId ?? ""
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
    static let newWorkItem = Notification.Name("oneroof.newWorkItem")
    static let newObjective = Notification.Name("oneroof.newObjective")
    static let panelCommand = Notification.Name("oneroof.panelCommand")
    static let shortcutsChanged = Notification.Name("oneroof.shortcutsChanged")
}
