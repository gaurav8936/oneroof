import Foundation

/// Defaults for one agent, used when planning a session (Settings › Agents).
public struct AgentDefaults: Codable, Equatable, Sendable {
    public var account: String?
    public var model: String
    public var args: String

    public init(account: String? = nil, model: String = "", args: String = "") {
        self.account = account
        self.model = model
        self.args = args
    }
}

/// One Roof's preferences (Settings window, ⌘,). Stored as JSON in UserDefaults.
public struct AppSettings: Codable, Equatable, Sendable {
    /// Per agent (AgentKind raw value).
    public var agents: [String: AgentDefaults]
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
    /// The on-device router model (.gguf); "" = `LocalModel.defaultModelPath`.
    public var localModelPath: String
    /// The first-run setup window has been completed (or skipped by a settings migration).
    public var setupDone: Bool
    /// "bold" (filled stickers, white text) or "soft" (tinted stickers, coloured text). Owner picks.
    public var stickerStyle: String
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

    public init() {
        stepReview = false
        captionsModel = true
        scheduledRuns = false
        tintRows = true
        menuBarExtra = true
        followSystemAppearance = false
        shortcuts = [:]
        globalHotkey = ""
        stickerStyle = "bold"
        agents = ["claude": AgentDefaults(account: "Claude1")]
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
        localModelPath = ""
        setupDone = false
    }

    public func defaults(for agent: AgentKind) -> AgentDefaults {
        agents[agent.rawValue] ?? AgentDefaults(account: AccountResolver.choices(for: agent).first)
    }

    public init(from d: Decoder) throws {
        let fresh = AppSettings()
        let c = try d.container(keyedBy: CodingKeys.self)
        agents = try c.decodeIfPresent([String: AgentDefaults].self, forKey: .agents) ?? fresh.agents
        dockBadge = try c.decodeIfPresent(Bool.self, forKey: .dockBadge) ?? fresh.dockBadge
        notifyNeedsYou = try c.decodeIfPresent(Bool.self, forKey: .notifyNeedsYou) ?? fresh.notifyNeedsYou
        notifyDone = try c.decodeIfPresent(Bool.self, forKey: .notifyDone) ?? fresh.notifyDone
        notifyLongCommands = try c.decodeIfPresent(Bool.self, forKey: .notifyLongCommands) ?? fresh.notifyLongCommands
        longCommandSeconds = try c.decodeIfPresent(Int.self, forKey: .longCommandSeconds) ?? fresh.longCommandSeconds
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
        projectsPath = try c.decodeIfPresent(String.self, forKey: .projectsPath) ?? fresh.projectsPath
        learnFolders = try c.decodeIfPresent([String].self, forKey: .learnFolders) ?? fresh.learnFolders
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
