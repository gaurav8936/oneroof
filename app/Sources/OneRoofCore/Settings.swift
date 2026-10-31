import Foundation

/// Defaults for one agent, used when planning a session (Settings › Agents).
public struct AgentDefaults: Codable, Equatable, Sendable {
    public var account: String?
    public var model: String
    public var args: String
    public var hostedConnectionID: String?

    public init(account: String? = nil, model: String = "", args: String = "", hostedConnectionID: String? = nil) {
        self.account = account
        self.model = model
        self.args = args
        self.hostedConnectionID = hostedConnectionID
    }
}

/// One Roof's preferences (Settings window, ⌘,). Stored as JSON in UserDefaults.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Per agent (AgentKind raw value).
    public var agents: [String: AgentDefaults]
    public var hostedConnections: [HostedConnection]
    public var hostedRuntime: HostedRuntimeConfiguration?
    /// Count of sessions that need you on the Dock icon.
    public var dockBadge: Bool
    /// Desktop notifications (LAB-197): an agent needs you · an agent finished its turn · a long command finished
    /// (or a program asked for one, OSC 9 / 777), and how long counts as long.
    public var notifyNeedsYou: Bool
    public var notifyDone: Bool
    public var notifyLongCommands: Bool
    public var longCommandSeconds: Int
    /// Run the foundations check at every launch.
    public var startupCheck: Bool
    /// The agentic-engineering folder chosen in Settings; "" = the copy bundled with the app. Read it through
    /// `agenticEngineering` (env `ONEROOF_AE_PATH` → this → bundled). Read in place, never copied.
    public var agenticEngineeringPath: String
    /// The shared rules-and-docs folder; "" = `<projects>/_common`. Read it through `sharedFolder`
    /// (env `ONEROOF_SHARED` → this → default). Optional: features that need it stay quiet when it is missing.
    public var commonPath: String
    /// The projects folder agents start in; "" = ~/Projects if it exists, else the home folder. Read it through
    /// `projectsFolder` (env `ONEROOF_PROJECTS` → this → default).
    public var projectsPath: String
    /// Extra folders shown in Learn: every .md file is a page, every sub-folder of .mp3 files a narration list.
    public var learnFolders: [String]
    /// LAB-1621 · Learn: a card played to its end counts down three seconds and opens the next card, playing. On by default.
    public var learnAutoAdvance: Bool
    /// LAB-1837 · Learn: the classic native screens instead of the shared Agentic Engineering page (the one copy every site
    /// shows, saved in the app at build). Off by default (1.9.32); kept for one release as the way back.
    public var learnClassic: Bool
    /// The on-device router model (.gguf); "" = `LocalModel.defaultModelPath`.
    public var localModelPath: String
    /// The first-run setup window has been completed (or skipped by a settings migration).
    public var setupDone: Bool
    /// "bold" (filled stickers, white text) or "soft" (tinted stickers, coloured text). Owner picks.
    public var stickerStyle: String
    /// LAB-1524 · When an agent ends, its shell stays (so its last screen can be read). Close that shell after this many
    /// minutes untouched: -1 = keep it (the old behaviour), 0 = right away. The row stays and Resume works from the
    /// session catalog (the conversation id is saved since 1.9.15).
    public var closeFinishedAfterMinutes: Int
    /// LAB-1535 · close a running session nobody touched for this many hours (agent, shell and holder); -1 = never.
    /// Never a working, waiting, pinned or loop session, nor one that cannot be resumed.
    public var closeIdleSessionsAfterHours: Int
    /// LAB-1535 · 2 = "When an agent ends" defaults to 10 minutes (owner rules, 10-29: exiting Claude closes its roofd
    /// session); settings saved by 1.9.16/1.9.17 with the old 60-minute default move to 10 minutes once.
    public var finishedPolicyVersion: Int
    /// Panels follow macOS light/dark: in Dark Mode light themes use their dark twins.
    public var followSystemAppearance: Bool
    /// Menu shortcut overrides by item title; "" removes a shortcut.
    public var shortcuts: ShortcutOverrides
    /// System-wide shortcut that shows or hides One Roof from any app; "" = off.
    public var globalHotkey: String
    /// Fill whole session rows with their colour (v0.1 behaviour, kept on by default; GAPS D1 lets the owner turn it off).
    public var tintRows: Bool
    /// Show a menu-bar extra with what needs you.
    public var menuBarExtra: Bool
    /// Ask the on-device model for captions and reasons; off = the heuristic captions only.
    public var captionsModel: Bool
    /// Let roofd start Tonight / Nightly / loop sessions on time with the app open or closed (roofd Scheduler, LAB-23);
    /// off = the app runs them itself only while it is open.
    public var scheduledRuns: Bool
    /// Step review (LAB-260): Claude reads each finished step of the session on screen. Off by default: every step it
    /// reviews is one more model call on the owner's Claude account.
    public var stepReview: Bool
    /// LAB-1298: keep One Roof's composer under every agent pane. Off (default): an agent with its own prompt (Claude's
    /// ❯ line) is typed into in the terminal, and the composer shows only on demand (Compose in the pane header) or while
    /// the pane shows its Table view.
    public var alwaysShowComposer: Bool
    /// LAB-1907: One Roof's approval card over a terminal prompt. Hidden (default): every agent shows its own choices
    /// on screen and takes a click or a key there; the card covered them. Kept, off, in case it is wanted back.
    public var terminalApprovalCard: Bool
    /// One Roof 1.x v2 window (LAB-ONEROOF-UI-REDESIGN). Off: the classic 0.5 layout. On by default from 1.6.0.
    public var ui2: Bool
    /// True once the owner picked a window (Classic layout / Use the new window). Until then 1.6.0 moves them to v2.
    public var ui2Chosen: Bool
    /// The look that set every panel theme (P2), saved by name; "custom" = the owner customised panels one by one.
    public var lookName: String
    /// v2 General › Done when required (NEW-30): New session cannot launch without a Done when. Off = today's "optional".
    public var doneWhenRequired: Bool
    /// Seat routing (NEW-6): hand a running step to another seat at this % of its 5-hour window; 0 = routing.json's value.
    public var handOffAt: Int
    /// Seat routing (NEW-6): a review step goes to a different model family from the one that wrote the code.
    public var reviewOtherFamily: Bool
    /// LAB-1600: Settings › Permissions, one mode per agent (AgentKind raw value). Missing = Auto.
    public var permissionModes: [String: PermissionMode]
    /// LAB-1935: the owner's own flags for one agent's mode, keyed "<agent>.<mode>" (e.g. "agy.full"); missing = the
    /// mode's standard flags. Edited in Settings › Permissions, with Reset.
    public var permissionFlags: [String: String]
    /// LAB-1935: one-time moves of the permission defaults already applied (1 = Antigravity to Full, 10-31).
    public var permissionDefaultsVersion: Int
    /// LAB-1998: agents (AgentMark raw values) the owner took out of the bottom bar in Settings › Seats & accounts.
    /// Every agent that is set up on this Mac shows there unless it is listed here.
    public var dockHidden: [String]
    /// The look, or nil when the panels were customised one by one.
    public var look: Look? {
        get { Look(rawValue: lookName) }
        set { lookName = newValue?.rawValue ?? "custom" }
    }

    public init() {
        ui2 = true
        ui2Chosen = false
        lookName = Look.skyStudio.rawValue
        doneWhenRequired = false
        handOffAt = 0
        reviewOtherFamily = true
        permissionModes = [:]
        permissionFlags = [:]
        permissionDefaultsVersion = 1
        dockHidden = []
        stepReview = false
        alwaysShowComposer = false
        terminalApprovalCard = false
        captionsModel = true
        scheduledRuns = false
        tintRows = true
        menuBarExtra = true
        followSystemAppearance = false
        shortcuts = [:]
        globalHotkey = ""
        stickerStyle = "bold"
        closeFinishedAfterMinutes = FinishedShellPolicy.defaultMinutes   // owner rules, 10-29: 10 minutes after the agent exits
        finishedPolicyVersion = 2
        closeIdleSessionsAfterHours = 24 // owner, 10-28: a day untouched
        agents = ["claude": AgentDefaults(account: "Claude1")]
        hostedConnections = []
        hostedRuntime = nil
        dockBadge = true
        notifyNeedsYou = true
        notifyDone = true
        notifyLongCommands = true
        longCommandSeconds = 30
        startupCheck = true
        agenticEngineeringPath = ""
        commonPath = ""
        projectsPath = ""
        learnFolders = []
        learnAutoAdvance = true
        learnClassic = false
        localModelPath = ""
        setupDone = false
    }

    /// The permission mode new sessions of `agent` start in (LAB-1600; Auto unless the owner chose another).
    public func permissionMode(for agent: AgentKind) -> PermissionMode {
        agent.isHosted ? .manual : (permissionModes[agent.rawValue] ?? PermissionMode.defaultMode(for: agent))
    }

    /// The owner's own flags for `agent` in `mode`, or nil for the mode's standard flags (LAB-1935).
    public func permissionFlags(for agent: AgentKind, mode: PermissionMode) -> [String]? {
        let t = (permissionFlags["\(agent.rawValue).\(mode.rawValue)"] ?? "").trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : Session.parseArgs(t)
    }

    /// The flags a new `agent` session in `mode` launches with: the owner's own, else the standard ones.
    public func effectiveFlags(for agent: AgentKind, mode: PermissionMode) -> [String] {
        permissionFlags(for: agent, mode: mode) ?? mode.args(for: agent)
    }

    public func defaults(for agent: AgentKind) -> AgentDefaults {
        agents[agent.rawValue] ?? AgentDefaults(account: AccountResolver.choices(for: agent).first)
    }

    public init(from d: Decoder) throws {
        let fresh = AppSettings()
        let c = try d.container(keyedBy: CodingKeys.self)
        agents = try c.decodeIfPresent([String: AgentDefaults].self, forKey: .agents) ?? fresh.agents
        hostedConnections = try c.decodeIfPresent([HostedConnection].self, forKey: .hostedConnections) ?? []
        hostedRuntime = try c.decodeIfPresent(HostedRuntimeConfiguration.self, forKey: .hostedRuntime)
        dockBadge = try c.decodeIfPresent(Bool.self, forKey: .dockBadge) ?? fresh.dockBadge
        notifyNeedsYou = try c.decodeIfPresent(Bool.self, forKey: .notifyNeedsYou) ?? fresh.notifyNeedsYou
        notifyDone = try c.decodeIfPresent(Bool.self, forKey: .notifyDone) ?? fresh.notifyDone
        notifyLongCommands = try c.decodeIfPresent(Bool.self, forKey: .notifyLongCommands) ?? fresh.notifyLongCommands
        longCommandSeconds = try c.decodeIfPresent(Int.self, forKey: .longCommandSeconds) ?? fresh.longCommandSeconds
        closeFinishedAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .closeFinishedAfterMinutes) ?? fresh.closeFinishedAfterMinutes
        closeIdleSessionsAfterHours = try c.decodeIfPresent(Int.self, forKey: .closeIdleSessionsAfterHours) ?? fresh.closeIdleSessionsAfterHours
        finishedPolicyVersion = try c.decodeIfPresent(Int.self, forKey: .finishedPolicyVersion) ?? 1
        if finishedPolicyVersion < 2 {                       // LAB-1535: the old untouched default (1 h) becomes 10 minutes
            if closeFinishedAfterMinutes == 60 { closeFinishedAfterMinutes = FinishedShellPolicy.defaultMinutes }
            finishedPolicyVersion = 2
        }
        startupCheck = try c.decodeIfPresent(Bool.self, forKey: .startupCheck) ?? fresh.startupCheck
        agenticEngineeringPath = try c.decodeIfPresent(String.self, forKey: .agenticEngineeringPath) ?? fresh.agenticEngineeringPath
        commonPath = try c.decodeIfPresent(String.self, forKey: .commonPath) ?? fresh.commonPath
        stickerStyle = try c.decodeIfPresent(String.self, forKey: .stickerStyle) ?? fresh.stickerStyle
        followSystemAppearance = try c.decodeIfPresent(Bool.self, forKey: .followSystemAppearance) ?? fresh.followSystemAppearance
        shortcuts = try c.decodeIfPresent(ShortcutOverrides.self, forKey: .shortcuts) ?? fresh.shortcuts
        globalHotkey = try c.decodeIfPresent(String.self, forKey: .globalHotkey) ?? fresh.globalHotkey
        tintRows = try c.decodeIfPresent(Bool.self, forKey: .tintRows) ?? fresh.tintRows
        menuBarExtra = try c.decodeIfPresent(Bool.self, forKey: .menuBarExtra) ?? fresh.menuBarExtra
        captionsModel = try c.decodeIfPresent(Bool.self, forKey: .captionsModel) ?? fresh.captionsModel
        scheduledRuns = try c.decodeIfPresent(Bool.self, forKey: .scheduledRuns) ?? fresh.scheduledRuns
        stepReview = try c.decodeIfPresent(Bool.self, forKey: .stepReview) ?? fresh.stepReview
        alwaysShowComposer = try c.decodeIfPresent(Bool.self, forKey: .alwaysShowComposer) ?? fresh.alwaysShowComposer
        terminalApprovalCard = try c.decodeIfPresent(Bool.self, forKey: .terminalApprovalCard) ?? fresh.terminalApprovalCard
        ui2 = try c.decodeIfPresent(Bool.self, forKey: .ui2) ?? fresh.ui2
        ui2Chosen = try c.decodeIfPresent(Bool.self, forKey: .ui2Chosen) ?? false
        if !ui2Chosen { ui2 = true }   // 1.6.0: the new window by default, unless the owner chose the classic one
        // Settings saved before 1.0.0 have no look: keep the owner's per-panel themes ("custom") rather than
        // replace them with Sky Studio when the v2 window is first turned on. New installs start on Sky Studio.
        lookName = try c.decodeIfPresent(String.self, forKey: .lookName) ?? "custom"
        doneWhenRequired = try c.decodeIfPresent(Bool.self, forKey: .doneWhenRequired) ?? false
        handOffAt = try c.decodeIfPresent(Int.self, forKey: .handOffAt) ?? 0
        reviewOtherFamily = try c.decodeIfPresent(Bool.self, forKey: .reviewOtherFamily) ?? true
        permissionModes = (try? c.decodeIfPresent([String: PermissionMode].self, forKey: .permissionModes)) ?? [:]
        permissionFlags = (try? c.decodeIfPresent([String: String].self, forKey: .permissionFlags)) ?? [:]
        dockHidden = (try? c.decodeIfPresent([String].self, forKey: .dockHidden)) ?? []
        permissionDefaultsVersion = (try? c.decodeIfPresent(Int.self, forKey: .permissionDefaultsVersion)) ?? 0
        // LAB-1935 (owner 10-31): Antigravity moves to Full once, even where Auto was saved; a later choice stays.
        if permissionDefaultsVersion < 1 {
            if (permissionModes[AgentKind.agy.rawValue] ?? .auto) == .auto { permissionModes[AgentKind.agy.rawValue] = .full }
            permissionDefaultsVersion = 1
        }
        projectsPath = try c.decodeIfPresent(String.self, forKey: .projectsPath) ?? fresh.projectsPath
        learnFolders = try c.decodeIfPresent([String].self, forKey: .learnFolders) ?? fresh.learnFolders
        learnAutoAdvance = try c.decodeIfPresent(Bool.self, forKey: .learnAutoAdvance) ?? fresh.learnAutoAdvance
        learnClassic = try c.decodeIfPresent(Bool.self, forKey: .learnClassic) ?? fresh.learnClassic
        localModelPath = try c.decodeIfPresent(String.self, forKey: .localModelPath) ?? fresh.localModelPath
        setupDone = try c.decodeIfPresent(Bool.self, forKey: .setupDone) ?? fresh.setupDone
    }

    /// The projects folder in use (env `ONEROOF_PROJECTS` → `projectsPath` → ~/Projects or home).
    public var projectsFolder: String { Workspace.resolveProjects(setting: projectsPath) }
    /// The shared folder in use (env `ONEROOF_SHARED` → `commonPath` → `<projects>/_common`). May not exist.
    public var sharedFolder: String { Workspace.resolveShared(setting: commonPath, projects: projectsFolder) }
    /// The on-device model file in use.
    public var modelFile: String { LocalModel.resolve(setting: localModelPath) }
}
