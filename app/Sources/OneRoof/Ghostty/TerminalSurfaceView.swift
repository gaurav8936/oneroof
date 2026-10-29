import AppKit
import GhosttyKit
import OneRoofCore

/// One libghostty terminal in an NSView. Runs a command (for One Roof: `roofd attach <id>`).
///
/// Keyboard, IME and mouse handling are ported from Ghostty's macOS app
/// (macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift and NSEvent+Extension.swift, MIT,
/// © Mitchell Hashimoto and Ghostty contributors), trimmed to what One Roof needs.
final class TerminalSurfaceView: NSView, NSTextInputClient {
    private(set) var surface: ghostty_surface_t?
    private var markedText = NSMutableAttributedString()
    private var keyTextAccumulator: [String]?
    private var trackingArea: NSTrackingArea?
    private var contentSize: CGSize = .zero
    private(set) var theme: ThemeName

    let command: String
    let workingDirectory: String

    var onTitle: ((String) -> Void)?
    /// Search feedback from libghostty (matches found, which one is selected) and links clicked with ⌘.
    var onSearchTotal: ((Int) -> Void)?
    var onSearchSelected: ((Int) -> Void)?
    var onOpenURL: ((String) -> Void)?
    var onProcessExit: ((Bool) -> Void)?
    /// The roofd session this terminal shows (set by `AppModel.wire`), so notifications and Run in Terminal know it.
    var runtimeId: String?
    /// A command finished (libghostty COMMAND_FINISHED, from the shell's OSC 133 marks): exit code (nil = not
    /// reported) and how long it ran, in seconds (LAB-197).
    var onCommandFinished: ((Int?, TimeInterval) -> Void)?
    /// A program asked for a desktop notification (OSC 9 / OSC 777): title, body (LAB-197).
    var onDesktopNotification: ((String, String) -> Void)?
    /// Right-click › Run in Terminal with the selected text (LAB-598).
    var onRunSelection: ((String) -> Void)?
    /// Right-click › New Terminal Here (false) / Split Right with New Terminal (true) (LAB-745). Without it the menu
    /// still offers File › New Terminal.
    var onNewTerminal: ((Bool) -> Void)?
    /// LAB-825: whether the viewport is at the live bottom (libghostty SCROLLBAR), reported when it changes.
    var onScrollBottom: ((Bool) -> Void)?
    /// The last value reported to `onScrollBottom` (main thread).
    var atScrollBottom: Bool?

    /// `size`: where the surface will be shown (LAB-606), so its program starts at the right number of rows and
    /// columns instead of libghostty's default until the first layout.
    init(command: String, workingDirectory: String, env: [String: String] = [:], theme: ThemeName,
         size: NSSize = NSSize(width: 800, height: 600)) {
        self.command = command
        self.workingDirectory = workingDirectory
        self.theme = theme
        super.init(frame: NSRect(origin: .zero, size: size.width > 0 && size.height > 0 ? size : NSSize(width: 800, height: 600)))
        wantsLayer = true
        registerForDraggedTypes([.fileURL, .png, .tiff])

        guard let app = GhosttyRuntime.shared.app else { return }
        var cfg = ghostty_surface_config_new()
        cfg.platform_tag = GHOSTTY_PLATFORM_MACOS
        cfg.platform = ghostty_platform_u(macos: ghostty_platform_macos_s(nsview: Unmanaged.passUnretained(self).toOpaque()))
        cfg.userdata = Unmanaged.passUnretained(self).toOpaque()
        cfg.scale_factor = Double(NSScreen.main?.backingScaleFactor ?? 2)
        cfg.font_size = 0
        cfg.context = GHOSTTY_SURFACE_CONTEXT_WINDOW
        cfg.wait_after_command = false

        // C strings must outlive ghostty_surface_new.
        let cmd = strdup(command)
        let wd = strdup(workingDirectory)
        var keys: [UnsafeMutablePointer<CChar>?] = []
        var vals: [UnsafeMutablePointer<CChar>?] = []
        var envVars: [ghostty_env_var_s] = []
        for (k, v) in env {
            let kp = strdup(k), vp = strdup(v)
            keys.append(kp); vals.append(vp)
            envVars.append(ghostty_env_var_s(key: kp, value: vp))
        }
        defer {
            free(cmd); free(wd)
            keys.forEach { free($0) }; vals.forEach { free($0) }
        }
        cfg.command = UnsafePointer(cmd)
        cfg.working_directory = UnsafePointer(wd)
        surface = envVars.withUnsafeMutableBufferPointer { buf -> ghostty_surface_t? in
            cfg.env_vars = buf.baseAddress
            cfg.env_var_count = buf.count
            return ghostty_surface_new(app, &cfg)
        }
        applyTheme(theme)
        // LAB-606: the grid size at once (in pixels at the screen's scale; there is no window yet to convert with).
        if let surface {
            let scale = cfg.scale_factor
            contentSize = frame.size
            ghostty_surface_set_size(surface, UInt32(max(frame.width * scale, 1)), UInt32(max(frame.height * scale, 1)))
        }
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    deinit {
        if let surface { ghostty_surface_free(surface) }
    }

    func applyTheme(_ t: ThemeName) {
        theme = t
        guard let surface, let cfg = GhosttyRuntime.shared.config(for: t) else { return }
        ghostty_surface_update_config(surface, cfg)
        ghostty_surface_set_color_scheme(surface, !t.isDark ? GHOSTTY_COLOR_SCHEME_LIGHT : GHOSTTY_COLOR_SCHEME_DARK)
        ghostty_surface_refresh(surface)
    }

    // MARK: Layout

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        sizeDidChange(newSize)
    }

    private func sizeDidChange(_ size: CGSize) {
        contentSize = size
        guard let surface else { return }
        let scaled = convertToBacking(size)
        ghostty_surface_set_size(surface, UInt32(max(scaled.width, 1)), UInt32(max(scaled.height, 1)))
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let window {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer?.contentsScale = window.backingScaleFactor
            CATransaction.commit()
        }
        guard let surface, frame.width > 0, frame.height > 0 else { return }
        let fb = convertToBacking(frame)
        ghostty_surface_set_content_scale(surface, fb.width / frame.width, fb.height / frame.height)
        sizeDidChange(contentSize == .zero ? frame.size : contentSize)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        guard let window, let surface else { updateOcclusion(); return }
        if let screen = window.screen,
           let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            ghostty_surface_set_display_id(surface, id.uint32Value)
        }
        viewDidChangeBackingProperties()
        NotificationCenter.default.addObserver(self, selector: #selector(windowOcclusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
        updateOcclusion()
    }

    // LAB-1320: libghostty draws a surface every frame while it is told the surface is visible. It was told so once,
    // when the view joined a window, and never told otherwise: terminals hidden behind another pane, in a hidden
    // window, a minimised one or one covered by other apps kept rendering. Now visible = in a window, not hidden
    // (itself or an ancestor) and the window's occlusion state says visible; un-occluded again just before it shows.
    private var lastOcclusionVisible: Bool?
    @objc private func windowOcclusionChanged(_ n: Notification) { updateOcclusion() }
    override func viewDidHide() { super.viewDidHide(); updateOcclusion() }
    override func viewDidUnhide() { super.viewDidUnhide(); updateOcclusion() }
    func updateOcclusion() {
        guard let surface else { return }
        // Self-test windows are drawn off screen: macOS reports them occluded, so they count as on screen (as the
        // foreground poll does); a terminal told it is occluded draws nothing (a re-attached one stayed blank).
        let onScreen = window.map { SelfTest.isActive || ($0.occlusionState.contains(.visible) && !$0.isMiniaturized) } == true
        let visible = onScreen && !isHiddenOrHasHiddenAncestor
        guard visible != lastOcclusionVisible else { return }
        lastOcclusionVisible = visible
        ghostty_surface_set_occlusion(surface, visible)
        // LAB-1365: becoming visible, libghostty draws once from the frame data it already has and does not rebuild
        // it; an unfocused surface then draws only when output arrives. A pane resized or re-attached while hidden
        // came back cut off (the old size) or blank until the program printed again. Re-send the size and ask for a
        // full frame.
        if visible {
            sizeDidChange(frame.size)
            ghostty_surface_refresh(surface)
        }
    }

    /// Whether libghostty was last told this surface is visible (self-test and tests read it).
    var drawsWhenVisible: Bool? { lastOcclusionVisible }

    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        if ok, let surface { ghostty_surface_set_focus(surface, true) }
        return ok
    }

    override func resignFirstResponder() -> Bool {
        let ok = super.resignFirstResponder()
        if ok, let surface { ghostty_surface_set_focus(surface, false) }
        return ok
    }

    func setCursorShape(_ shape: ghostty_action_mouse_shape_e) {
        switch shape {
        case GHOSTTY_MOUSE_SHAPE_TEXT: NSCursor.iBeam.set()
        case GHOSTTY_MOUSE_SHAPE_POINTER: NSCursor.pointingHand.set()
        default: NSCursor.arrow.set()
        }
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        let t = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .mouseMoved, .inVisibleRect, .activeAlways], owner: self)
        addTrackingArea(t)
        trackingArea = t
        super.updateTrackingAreas()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // Selection wins over mouse reporting. Many TUIs turn on mouse tracking, which would send every drag to
    // the program and leave nothing to copy. So a plain left drag selects text, the way it does in Terminal.app and
    // other Mac terminals: One Roof marks left-button events as shift-held, which Ghostty treats as "select, don't report"
    // (`mouse-shift-capture = never` stops the program from overriding that). Holding Option sends the mouse to the
    // program instead. The wheel is never changed, so scrolling still reaches the program.
    private var leftButtonSelects = false

    /// Mods for a left-button event: shift added while a selecting drag is in progress.
    private func leftMods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var m = Self.mods(flags)
        if leftButtonSelects { m = ghostty_input_mods_e(rawValue: m.rawValue | GHOSTTY_MODS_SHIFT.rawValue) }
        return m
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let surface else { return }
        let flags = event.modifierFlags
        leftButtonSelects = TerminalMouse.selects(flags: flags, captured: mouseCaptured)
        // A plain single click clears an existing selection (with shift held Ghostty would extend it instead).
        mouseMoved(with: event)
        if leftButtonSelects, !flags.contains(.shift), event.clickCount == 1, ghostty_surface_has_selection(surface) {
            clearSelection(flags)
        }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, leftMods(flags))
    }

    override func mouseUp(with event: NSEvent) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, leftMods(event.modifierFlags))
        ghostty_surface_mouse_pressure(surface, 0, 0)
        leftButtonSelects = false
    }

    /// Ghostty clears the selection on a plain (unshifted) click and resets its click count, so the shifted press
    /// that follows starts a new selection instead of extending the old one.
    private func clearSelection(_ flags: NSEvent.ModifierFlags) {
        guard let surface else { return }
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_LEFT, Self.mods(flags))
        _ = ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_LEFT, Self.mods(flags))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let surface else { return super.rightMouseDown(with: event) }
        // Right-click opens One Roof's menu; Option-right-click goes to the program.
        if !event.modifierFlags.contains(.option) {
            NSMenu.popUpContextMenu(contextMenu(), with: event, for: self)
            return
        }
        if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_PRESS, GHOSTTY_MOUSE_RIGHT, Self.mods(event.modifierFlags)) {
            super.rightMouseDown(with: event)
        }
    }

    override func rightMouseUp(with event: NSEvent) {
        guard let surface, event.modifierFlags.contains(.option) else { return }
        if !ghostty_surface_mouse_button(surface, GHOSTTY_MOUSE_RELEASE, GHOSTTY_MOUSE_RIGHT, Self.mods(event.modifierFlags)) {
            super.rightMouseUp(with: event)
        }
    }

    /// Copy · Paste · Select All · Clear, like any Mac terminal.
    func contextMenu() -> NSMenu {
        let m = NSMenu()
        let hasSel = surface.map { ghostty_surface_has_selection($0) } ?? false
        let copy = NSMenuItem(title: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
        copy.isEnabled = hasSel
        m.autoenablesItems = false
        m.addItem(copy)
        let paste = NSMenuItem(title: "Paste", action: #selector(paste(_:)), keyEquivalent: "v")
        paste.isEnabled = TerminalMouse.canPaste(.general)
        m.addItem(paste)
        m.addItem(NSMenuItem(title: "Select All", action: #selector(selectAll(_:)), keyEquivalent: "a"))
        if onRunSelection != nil {
            // LAB-598: type the selected command into a run terminal, without pressing Return.
            m.addItem(.separator())
            let run = NSMenuItem(title: "Run in Terminal", action: #selector(runSelection(_:)), keyEquivalent: "")
            run.isEnabled = hasSel
            run.toolTip = "Types the selected command into this session's run terminal. Nothing runs until you press Return there."
            m.addItem(run)
        }
        // LAB-745: start a plain terminal from the centre panel.
        m.addItem(.separator())
        let titles = TerminalMenu.newTerminalItems(inPane: onNewTerminal != nil)
        let here = NSMenuItem(title: titles[0], action: #selector(newTerminalHere(_:)), keyEquivalent: "")
        here.toolTip = onNewTerminal != nil
            ? "Opens a plain shell in this session's folder (\((workingDirectory as NSString).abbreviatingWithTildeInPath)) and shows it in this pane. The session keeps running in the Sessions list."
            : "Opens a plain shell in your projects folder (File › New Terminal, ⌘T)."
        m.addItem(here)
        if onNewTerminal != nil {
            let split = NSMenuItem(title: titles[1], action: #selector(splitWithNewTerminal(_:)), keyEquivalent: "")
            split.toolTip = "Splits this pane and opens a plain shell in this session's folder on the right, next to this terminal."
            m.addItem(split)
        }
        m.addItem(.separator())
        m.addItem(NSMenuItem(title: "Clear", action: #selector(clearScreen(_:)), keyEquivalent: ""))
        for i in m.items { i.target = self }
        return m
    }

    @objc func newTerminalHere(_ sender: Any?) {
        if let onNewTerminal { onNewTerminal(false) } else { NSApp.sendAction(#selector(AppDelegate.newTerminal(_:)), to: nil, from: self) }
    }

    @objc func splitWithNewTerminal(_ sender: Any?) { onNewTerminal?(true) }

    @objc func clearScreen(_ sender: Any?) { bindingAction("clear_screen") }

    @objc func runSelection(_ sender: Any?) {
        guard let text = selectionText(), !text.isEmpty else { return }
        onRunSelection?(text)
    }

    /// The program in the terminal has turned on mouse reporting (many TUIs do).
    var mouseCaptured: Bool { surface.map { ghostty_surface_mouse_captured($0) } ?? false }
    var hasSelection: Bool { surface.map { ghostty_surface_has_selection($0) } ?? false }

    override func mouseMoved(with event: NSEvent) {
        guard let surface else { return }
        let pos = convert(event.locationInWindow, from: nil)
        ghostty_surface_mouse_pos(surface, pos.x, frame.height - pos.y, leftMods(event.modifierFlags))
    }

    override func mouseDragged(with event: NSEvent) { mouseMoved(with: event) }
    override func rightMouseDragged(with event: NSEvent) { mouseMoved(with: event) }

    override func mouseExited(with event: NSEvent) {
        guard let surface else { return }
        ghostty_surface_mouse_pos(surface, -1, -1, Self.mods(event.modifierFlags))
    }

    override func scrollWheel(with event: NSEvent) {
        guard let surface else { return }
        var x = event.scrollingDeltaX, y = event.scrollingDeltaY
        let precise = event.hasPreciseScrollingDeltas
        if precise { x *= 2; y *= 2 }
        // Scroll mods bitfield (Ghostty.Input.ScrollMods): bit 0 = precision, bits 1–3 = momentum phase.
        var mods: Int32 = precise ? 1 : 0
        let momentum: Int32
        switch event.momentumPhase {
        case .began: momentum = 1
        case .stationary: momentum = 2
        case .changed: momentum = 3
        case .ended: momentum = 4
        case .cancelled: momentum = 5
        case .mayBegin: momentum = 6
        default: momentum = 0
        }
        mods |= momentum << 1
        ghostty_surface_mouse_scroll(surface, x, y, mods)
    }

    // MARK: Keyboard

    static func mods(_ flags: NSEvent.ModifierFlags) -> ghostty_input_mods_e {
        var m: UInt32 = GHOSTTY_MODS_NONE.rawValue
        if flags.contains(.shift) { m |= GHOSTTY_MODS_SHIFT.rawValue }
        if flags.contains(.control) { m |= GHOSTTY_MODS_CTRL.rawValue }
        if flags.contains(.option) { m |= GHOSTTY_MODS_ALT.rawValue }
        if flags.contains(.command) { m |= GHOSTTY_MODS_SUPER.rawValue }
        if flags.contains(.capsLock) { m |= GHOSTTY_MODS_CAPS.rawValue }
        let raw = flags.rawValue
        if raw & UInt(NX_DEVICERSHIFTKEYMASK) != 0 { m |= GHOSTTY_MODS_SHIFT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCTLKEYMASK) != 0 { m |= GHOSTTY_MODS_CTRL_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERALTKEYMASK) != 0 { m |= GHOSTTY_MODS_ALT_RIGHT.rawValue }
        if raw & UInt(NX_DEVICERCMDKEYMASK) != 0 { m |= GHOSTTY_MODS_SUPER_RIGHT.rawValue }
        return ghostty_input_mods_e(m)
    }

    private static func flags(_ mods: ghostty_input_mods_e) -> NSEvent.ModifierFlags {
        var f = NSEvent.ModifierFlags(rawValue: 0)
        if mods.rawValue & GHOSTTY_MODS_SHIFT.rawValue != 0 { f.insert(.shift) }
        if mods.rawValue & GHOSTTY_MODS_CTRL.rawValue != 0 { f.insert(.control) }
        if mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0 { f.insert(.option) }
        if mods.rawValue & GHOSTTY_MODS_SUPER.rawValue != 0 { f.insert(.command) }
        return f
    }

    override func keyDown(with event: NSEvent) {
        guard let surface else {
            interpretKeyEvents([event])
            return
        }
        // Translate mods for option-as-alt.
        let translated = Self.flags(ghostty_surface_key_translation_mods(surface, Self.mods(event.modifierFlags)))
        var translationMods = event.modifierFlags
        for f in [NSEvent.ModifierFlags.shift, .control, .option, .command] {
            if translated.contains(f) { translationMods.insert(f) } else { translationMods.remove(f) }
        }
        let translationEvent: NSEvent
        if translationMods == event.modifierFlags {
            translationEvent = event
        } else {
            translationEvent = NSEvent.keyEvent(
                with: event.type, location: event.locationInWindow, modifierFlags: translationMods,
                timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                characters: event.characters(byApplyingModifiers: translationMods) ?? "",
                charactersIgnoringModifiers: event.charactersIgnoringModifiers ?? "",
                isARepeat: event.isARepeat, keyCode: event.keyCode) ?? event
        }

        let action = event.isARepeat ? GHOSTTY_ACTION_REPEAT : GHOSTTY_ACTION_PRESS
        keyTextAccumulator = []
        defer { keyTextAccumulator = nil }
        let markedBefore = markedText.length > 0

        interpretKeyEvents([translationEvent])
        syncPreedit(clearIfNeeded: markedBefore)

        if let list = keyTextAccumulator, !list.isEmpty {
            for text in list {
                _ = keyAction(action, event: event, translationEvent: translationEvent, text: text)
            }
        } else {
            _ = keyAction(action, event: event, translationEvent: translationEvent,
                          text: Self.ghosttyCharacters(translationEvent),
                          composing: markedText.length > 0 || markedBefore)
        }
    }

    override func keyUp(with event: NSEvent) {
        _ = keyAction(GHOSTTY_ACTION_RELEASE, event: event)
    }

    /// Let control/command combos reach the terminal instead of the menu bar,
    /// except the app's own shortcuts (⌘Q, ⌘W, ⌘N, ⌘C, ⌘V, ⌘, …), which the menu handles first.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown, window?.firstResponder === self else { return false }
        if event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.command) {
            keyDown(with: event)
            return true
        }
        return false
    }

    override func flagsChanged(with event: NSEvent) {
        let mod: UInt32
        switch event.keyCode {
        case 0x39: mod = GHOSTTY_MODS_CAPS.rawValue
        case 0x38, 0x3C: mod = GHOSTTY_MODS_SHIFT.rawValue
        case 0x3B, 0x3E: mod = GHOSTTY_MODS_CTRL.rawValue
        case 0x3A, 0x3D: mod = GHOSTTY_MODS_ALT.rawValue
        case 0x37, 0x36: mod = GHOSTTY_MODS_SUPER.rawValue
        default: return
        }
        if hasMarkedText() { return }
        let mods = Self.mods(event.modifierFlags)
        var action = GHOSTTY_ACTION_RELEASE
        if mods.rawValue & mod != 0 {
            let sidePressed: Bool
            switch event.keyCode {
            case 0x3C: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERSHIFTKEYMASK) != 0
            case 0x3E: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCTLKEYMASK) != 0
            case 0x3D: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERALTKEYMASK) != 0
            case 0x36: sidePressed = event.modifierFlags.rawValue & UInt(NX_DEVICERCMDKEYMASK) != 0
            default: sidePressed = true
            }
            if sidePressed { action = GHOSTTY_ACTION_PRESS }
        }
        _ = keyAction(action, event: event)
    }

    private func keyAction(_ action: ghostty_input_action_e, event: NSEvent, translationEvent: NSEvent? = nil,
                           text: String? = nil, composing: Bool = false) -> Bool {
        guard let surface else { return false }
        var ev = ghostty_input_key_s()
        ev.action = action
        ev.keycode = UInt32(event.keyCode)
        ev.mods = Self.mods(event.modifierFlags)
        ev.consumed_mods = Self.mods((translationEvent?.modifierFlags ?? event.modifierFlags).subtracting([.control, .command]))
        ev.unshifted_codepoint = 0
        if event.type == .keyDown || event.type == .keyUp,
           let chars = event.characters(byApplyingModifiers: []), let cp = chars.unicodeScalars.first {
            ev.unshifted_codepoint = cp.value
        }
        ev.composing = composing
        if let text, !text.isEmpty, let first = text.utf8.first, first >= 0x20 {
            return text.withCString { ptr in
                ev.text = ptr
                return ghostty_surface_key(surface, ev)
            }
        }
        ev.text = nil
        return ghostty_surface_key(surface, ev)
    }

    private static func ghosttyCharacters(_ event: NSEvent) -> String? {
        guard let characters = event.characters else { return nil }
        if characters.count == 1, let scalar = characters.unicodeScalars.first {
            if scalar.value < 0x20 {
                return event.characters(byApplyingModifiers: event.modifierFlags.subtracting(.control))
            }
            if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return nil }
        }
        return characters
    }

    private func syncPreedit(clearIfNeeded: Bool = true) {
        guard let surface else { return }
        if markedText.length > 0 {
            let str = markedText.string
            str.withCString { ptr in ghostty_surface_preedit(surface, ptr, UInt(str.utf8.count)) }
        } else if clearIfNeeded {
            ghostty_surface_preedit(surface, nil, 0)
        }
    }

    // MARK: Edit menu

    @objc func copy(_ sender: Any?) { bindingAction("copy_to_clipboard") }

    // MARK: Drag a file in → its path is typed, shell-quoted (as in Terminal.app); a dragged image (e.g. from a
    // browser) is saved and its path typed, as ⌘V does.

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        TerminalMouse.droppedText(from: sender.draggingPasteboard, save: false) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let surface, let text = TerminalMouse.droppedText(from: sender.draggingPasteboard) else { return false }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
        window?.makeFirstResponder(self)
        return true
    }
    @objc func paste(_ sender: Any?) { bindingAction("paste_from_clipboard") }
    @objc override func selectAll(_ sender: Any?) { bindingAction("select_all") }

    func bindingAction(_ name: String) {
        guard let surface else { return }
        _ = ghostty_surface_binding_action(surface, name, UInt(name.utf8.count))
    }

    /// Scrollback and screen as plain text, soft-wrapped lines joined (Wrap for reading, LAB-657).
    func allText() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_SCREEN, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false)
        guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let p = text.text else { return nil }
        return String(cString: p)
    }

    /// The terminal's width in cells (LAB-1299: the Table view rejoins rows cut at exactly this width).
    func columns() -> Int? {
        guard let surface else { return nil }
        let c = Int(ghostty_surface_size(surface).columns)
        return c > 0 ? c : nil
    }

    /// The visible screen as plain text (viewport top-left → bottom-right).
    func screenText() -> String? {
        guard let surface else { return nil }
        var text = ghostty_text_s()
        let sel = ghostty_selection_s(
            top_left: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_TOP_LEFT, x: 0, y: 0),
            bottom_right: ghostty_point_s(tag: GHOSTTY_POINT_VIEWPORT, coord: GHOSTTY_POINT_COORD_BOTTOM_RIGHT, x: 0, y: 0),
            rectangle: false)
        guard ghostty_surface_read_text(surface, sel, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        return String(cString: text.text)
    }

    /// The selected text, or nil when nothing is selected.
    func selectionText() -> String? {
        guard let surface, ghostty_surface_has_selection(surface) else { return nil }
        var text = ghostty_text_s()
        guard ghostty_surface_read_selection(surface, &text) else { return nil }
        defer { ghostty_surface_free_text(surface, &text) }
        guard let p = text.text else { return nil }
        return String(decoding: Data(bytes: p, count: Int(text.text_len)), as: UTF8.self)
    }

    /// Send literal text as if typed (used to deliver nothing by default; kept for future use).
    func sendText(_ text: String) {
        guard let surface else { return }
        text.withCString { ghostty_surface_text(surface, $0, UInt(text.utf8.count)) }
    }

    // MARK: NSTextInputClient

    func hasMarkedText() -> Bool { markedText.length > 0 }
    func markedRange() -> NSRange { markedText.length > 0 ? NSRange(location: 0, length: markedText.length) : NSRange() }
    func selectedRange() -> NSRange { NSRange() }
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        switch string {
        case let v as NSAttributedString: markedText = NSMutableAttributedString(attributedString: v)
        case let v as String: markedText = NSMutableAttributedString(string: v)
        default: return
        }
        if keyTextAccumulator == nil { syncPreedit() }
    }
    func unmarkText() {
        if markedText.length > 0 {
            markedText.mutableString.setString("")
            syncPreedit()
        }
    }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func characterIndex(for point: NSPoint) -> Int { 0 }
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let surface else { return .zero }
        var x = 0.0, y = 0.0, w = 0.0, h = 0.0
        ghostty_surface_ime_point(surface, &x, &y, &w, &h)
        let viewRect = NSRect(x: x, y: frame.height - y, width: w, height: max(h, 1))
        let winRect = convert(viewRect, to: nil)
        return window?.convertToScreen(winRect) ?? .zero
    }
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard NSApp.currentEvent != nil else { return }
        var chars = ""
        switch string {
        case let v as NSAttributedString: chars = v.string
        case let v as String: chars = v
        default: return
        }
        unmarkText()
        if var acc = keyTextAccumulator {
            acc.append(chars)
            keyTextAccumulator = acc
            return
        }
        sendText(chars)
    }
    override func doCommand(by selector: Selector) {
        // Swallow AppKit editing commands so they don't beep; the key event already went to the terminal.
    }
}
