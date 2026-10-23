import AppKit
import GhosttyKit
import OneRoofCore

/// Owns the single libghostty app instance and one config per theme.
///
/// Callback wiring follows Ghostty's own macOS app (macos/Sources/Ghostty/Ghostty.App.swift, MIT,
/// © Mitchell Hashimoto and Ghostty contributors), cut down to what One Roof needs.
final class GhosttyRuntime {
    static let shared = GhosttyRuntime()

    private(set) var app: ghostty_app_t?
    private var themeConfigs: [ThemeName: ghostty_config_t] = [:]
    private(set) var initError: String?

    private init() {
        // libghostty needs its resources (terminfo, shell integration) next to the binary:
        // bundle.sh copies them to Contents/Resources/ghostty and Contents/Resources/terminfo.
        if let res = Bundle.main.resourceURL?.appendingPathComponent("ghostty").path,
           FileManager.default.fileExists(atPath: res) {
            setenv("GHOSTTY_RESOURCES_DIR", res, 1)
        }

        if ghostty_init(UInt(CommandLine.argc), CommandLine.unsafeArgv) != GHOSTTY_SUCCESS {
            initError = "ghostty_init failed"
            return
        }

        guard let base = Self.makeConfig(theme: .midnight) else {
            initError = "ghostty config failed"
            return
        }
        themeConfigs[.midnight] = base

        var rt = ghostty_runtime_config_s(
            userdata: Unmanaged.passUnretained(self).toOpaque(),
            supports_selection_clipboard: false,
            wakeup_cb: { _ in DispatchQueue.main.async { GhosttyRuntime.shared.tick() } },
            action_cb: { app, target, action in GhosttyRuntime.handleAction(app, target: target, action: action) },
            read_clipboard_cb: { userdata, location, state in
                GhosttyRuntime.readClipboard(userdata, location: location, state: state)
            },
            confirm_read_clipboard_cb: { userdata, str, state, _ in
                // Paste confirmations (e.g. multi-line paste) complete without a prompt. Programs reading the clipboard
                // through OSC 52 never get here: the config denies clipboard-read.
                guard let view = GhosttyRuntime.view(from: userdata), let surface = view.surface, let str else { return }
                ghostty_surface_complete_clipboard_request(surface, str, state, true)
            },
            write_clipboard_cb: { _, location, content, len, _ in
                GhosttyRuntime.writeClipboard(location: location, content: content, len: len)
            },
            close_surface_cb: { userdata, processAlive in
                guard let view = GhosttyRuntime.view(from: userdata) else { return }
                DispatchQueue.main.async { view.onProcessExit?(processAlive) }
            }
        )
        guard let app = ghostty_app_new(&rt, base) else {
            initError = "ghostty_app_new failed"
            return
        }
        self.app = app
        ghostty_app_set_focus(app, NSApp.isActive)

        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if let app = self?.app { ghostty_app_set_focus(app, true) }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if let app = self?.app { ghostty_app_set_focus(app, false) }
        }
    }

    func tick() {
        if let app { ghostty_app_tick(app) }
    }

    /// The config for terminals drawn in `theme`.
    func config(for theme: ThemeName) -> ghostty_config_t? {
        if let c = themeConfigs[theme] { return c }
        let c = Self.makeConfig(theme: theme)
        themeConfigs[theme] = c
        return c
    }

    /// Build a config from One Roof's own settings only — never the user's Ghostty config file,
    /// so the look is the same on every Mac.
    private static func makeConfig(theme: ThemeName) -> ghostty_config_t? {
        guard let cfg = ghostty_config_new() else { return nil }
        let text = """
        font-size = 13
        window-padding-x = 10
        window-padding-y = 8
        window-padding-balance = true
        cursor-style = block
        cursor-style-blink = false
        confirm-close-surface = false
        shell-integration = none
        mouse-hide-while-typing = true
        copy-on-select = false
        mouse-shift-capture = never
        macos-option-as-alt = left
        clipboard-read = deny
        clipboard-write = allow
        notify-on-command-finish = always
        notify-on-command-finish-action = no-bell,notify
        notify-on-command-finish-after = 1s
        """ + "\n" + theme.tokens.ghosttyConfig
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("oneroof-ghostty", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("theme-\(theme.rawValue).conf")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        ghostty_config_load_file(cfg, file.path)
        ghostty_config_finalize(cfg)
        return cfg
    }

    // MARK: Callbacks

    static func view(from userdata: UnsafeMutableRawPointer?) -> TerminalSurfaceView? {
        guard let userdata else { return nil }
        return Unmanaged<TerminalSurfaceView>.fromOpaque(userdata).takeUnretainedValue()
    }

    private static func handleAction(_ app: ghostty_app_t?, target: ghostty_target_s, action: ghostty_action_s) -> Bool {
        guard target.tag == GHOSTTY_TARGET_SURFACE, let surface = target.target.surface,
              let view = view(from: ghostty_surface_userdata(surface)) else {
            return false
        }
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            if let t = action.action.set_title.title {
                let title = String(cString: t)
                DispatchQueue.main.async { view.onTitle?(title) }
            }
            return true
        case GHOSTTY_ACTION_MOUSE_SHAPE:
            DispatchQueue.main.async { view.setCursorShape(action.action.mouse_shape) }
            return true
        case GHOSTTY_ACTION_RING_BELL:
            DispatchQueue.main.async { NSSound.beep() }
            return true
        case GHOSTTY_ACTION_SEARCH_TOTAL:
            let n = Int(action.action.search_total.total)
            DispatchQueue.main.async { view.onSearchTotal?(n) }
            return true
        case GHOSTTY_ACTION_SEARCH_SELECTED:
            let n = Int(action.action.search_selected.selected)
            DispatchQueue.main.async { view.onSearchSelected?(n) }
            return true
        case GHOSTTY_ACTION_START_SEARCH, GHOSTTY_ACTION_END_SEARCH:
            return true
        case GHOSTTY_ACTION_OPEN_URL:
            let u = action.action.open_url
            if let p = u.url {
                let data = Data(bytes: p, count: Int(u.len))
                let url = String(decoding: data, as: UTF8.self)
                DispatchQueue.main.async { if let f = view.onOpenURL { f(url) } else if let x = URL(string: url) { NSWorkspace.shared.open(x) } }
            }
            return true
        case GHOSTTY_ACTION_COMMAND_FINISHED:
            // LAB-197: a command ended (the shell marks commands with OSC 133); the app decides whether to notify.
            let f = action.action.command_finished
            let code: Int? = f.exit_code < 0 ? nil : Int(f.exit_code)
            let seconds = TimeInterval(f.duration) / 1_000_000_000
            DispatchQueue.main.async { view.onCommandFinished?(code, seconds) }
            return true
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            // OSC 9 / OSC 777 from a program in the terminal: passed through as a One Roof notification.
            let n = action.action.desktop_notification
            let title = n.title.map { String(cString: $0) } ?? ""
            let body = n.body.map { String(cString: $0) } ?? ""
            DispatchQueue.main.async { view.onDesktopNotification?(title, body) }
            return true
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            DispatchQueue.main.async { view.onProcessExit?(false) }
            return true
        default:
            return false
        }
    }

    private static func readClipboard(_ userdata: UnsafeMutableRawPointer?, location: ghostty_clipboard_e, state: UnsafeMutableRawPointer?) -> Bool {
        guard location == GHOSTTY_CLIPBOARD_STANDARD,
              let view = view(from: userdata), let surface = view.surface,
              let str = TerminalMouse.pasteText(from: .general) else { return false }
        str.withCString { ghostty_surface_complete_clipboard_request(surface, $0, state, false) }
        return true
    }

    private static func writeClipboard(location: ghostty_clipboard_e, content: UnsafePointer<ghostty_clipboard_content_s>?, len: Int) {
        guard location == GHOSTTY_CLIPBOARD_STANDARD, let content, len > 0 else { return }
        // Plain text, whatever charset suffix the mime type carries ("text/plain", "text/plain;charset=utf-8").
        for i in 0..<len {
            let item = content[i]
            guard let mime = item.mime, let data = item.data, String(cString: mime).hasPrefix("text/plain") else { continue }
            let text = String(cString: data)
            let write = {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            if Thread.isMainThread { write() } else { DispatchQueue.main.async(execute: write) }
            return
        }
    }
}
