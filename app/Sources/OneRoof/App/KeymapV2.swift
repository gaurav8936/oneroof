import AppKit
import SwiftUI
import OneRoofCore

/// Single source of truth for v2 key equivalents. Mirrors 01_handover/shared/SHORTCUTS.md, which was verified line by
/// line against AppDelegate.buildMenu() in 0.5.2.9. Every 0.5.2.9 key keeps its meaning; new keys are ⌘-based so they
/// reach the menu while the terminal has focus (⌃-only keys are swallowed by TerminalSurfaceView).
/// MenusV2.swift reads every key from here. Do not type a key equivalent anywhere else.
enum KeymapV2 {
    struct Key: Equatable {
        let key: String
        let mods: NSEvent.ModifierFlags
        init(_ key: String, _ mods: NSEvent.ModifierFlags = [.command]) { self.key = key; self.mods = mods }
        static let none = Key("", [])
        static func == (a: Key, b: Key) -> Bool { a.key == b.key && a.mods == b.mods }
    }
    private static let up = String(Character(UnicodeScalar(NSUpArrowFunctionKey)!))
    private static let down = String(Character(UnicodeScalar(NSDownArrowFunctionKey)!))
    private static let left = String(Character(UnicodeScalar(NSLeftArrowFunctionKey)!))
    private static let right = String(Character(UnicodeScalar(NSRightArrowFunctionKey)!))

    // MARK: Kept from 0.5.2.9 (AppDelegate.buildMenu)
    // App
    static let settings = Key(","), foundations = Key("f", [.command, .shift]), palette = Key("k"), paletteAlt = Key("p")
    static let hide = Key("h"), hideOthers = Key("h", [.command, .option]), quit = Key("q")
    // File
    static let newSession = Key("n"), newTerminal = Key("t"), newTerminalInRepo = Key("t", [.command, .control])
    static let newWorkspaceWindow = Key("n", [.command, .shift]), newRoofWindow = Key("n", [.command, .option])
    static let newObjective = Key("o", [.command, .shift]), newWorkItem = Key("n", [.command, .control])
    static let openFile = Key("o"), save = Key("s")
    static let launchSelected = Key("\r"), closeSession = Key("w"), reopenClosed = Key("t", [.command, .shift])
    static let reopenClosedHidden = Key("t", [.command, .option]), popOut = Key("o", [.command, .option])
    static let closeWindow = Key("w", [.command, .control])
    // Edit
    static let undo = Key("z"), redo = Key("Z"), cut = Key("x"), copy = Key("c"), paste = Key("v"), selectAll = Key("a")
    static let clearTerminal = Key("k", [.command, .option])
    static let find = Key("f"), findNext = Key("g"), findPrevious = Key("g", [.command, .shift]), findInWorkspace = Key("s", [.command, .shift])
    // View (today's named view keys now open places)
    static let groupBy: [Key] = (1...6).map { Key("\($0)") }
    static let home = Key("l", [.command, .shift])          // was Overview
    static let machine = Key("u", [.command, .shift])       // was Resources
    static let board = Key("b")                             // Work › Board
    static let needsYou = Key("i")                          // was Decisions
    static let subagents = Key("a", [.command, .shift])     // Home › Subagents
    static let learn = Key("e", [.command, .shift])
    static let work = Key("w", [.command, .shift])
    static let biggerText = Key("+"), smallerText = Key("-"), actualSize = Key("0")
    static let sessionsColumn = Key("s", [.command, .option]), plan = Key("p", [.command, .option])
    static let terminalPanel = Key("c", [.command, .option]), filesTab = Key("b", [.command, .option])
    static let changes = Key("r", [.command, .option])      // was Review Changes
    static let splitRight = Key("d"), splitDown = Key("d", [.command, .shift])
    static let closePane = Key("w", [.command, .option]), maximizePane = Key("\r", [.command, .shift])
    static let focusPane: [Key] = [left, right, up, down].map { Key($0, [.command, .option]) }  // also Grid tiles
    static let focusForward = Key("f", [.command, .option]) // was Focus: Terminal Only
    static let focusTerminal = Key("l")                     // Sessions place
    static let rawStream = Key("r"), debug = Key("r", [.command, .shift])
    // Session
    static let interrupt = Key("."), nextSession = Key("]"), previousSession = Key("[")
    // Window
    static let minimize = Key("m"), allWindows = Key(up, [.control])  // Home window cards in 1.0.0, Wall from 1.2.0
    static let workspaces: [Key] = (1...9).map { Key("\($0)", [.command, .option]) }
    // Needs you (DecisionsView.swift:171–177): Return allows once, Esc denies, ⌘] / ⌘[ next / previous decision.
    static let allowOnce = Key("\r", []), deny = Key("\u{1b}", [])
    static let nextDecision = nextSession, previousDecision = previousSession
    // Help
    static let howDoI = Key("/", [.command, .option])

    // MARK: New in v2 (all ⌘-based; none clash with macOS)
    static let places: [Place: Key] = [
        .home: Key("1", [.control, .command]), .needsYou: Key("2", [.control, .command]), .sessions: Key("3", [.control, .command]),
        .work: Key("4", [.control, .command]), .machine: Key("5", [.control, .command]), .loops: Key("6", [.control, .command]),
        .learn: Key("7", [.control, .command])]
    static let layouts: [Key] = (1...4).map { Key("\($0)", [.control, .option, .command]) }  // Single, Grid, Wall, Scroll
    static let focusBack = Key("f", [.shift, .option, .command])
    static let dockToggle = Key("j", [.control, .command])

    // Duplicate check (TEST_CHECKLIST K1): walk NSApp.mainMenu after MenuSpecV2.install and assert no two visible,
    // enabled items share keyEquivalent + modifier mask. Hidden alternates (⌘P, ⌥⌘T, ⌥⌘1–9) are excluded.
}

extension KeymapV2.Key {
    /// The same key for SwiftUI buttons, so views never type a key equivalent themselves.
    var swiftUI: KeyboardShortcut {
        var m: EventModifiers = []
        if mods.contains(.command) { m.insert(.command) }
        if mods.contains(.shift) { m.insert(.shift) }
        if mods.contains(.option) { m.insert(.option) }
        if mods.contains(.control) { m.insert(.control) }
        let k: KeyEquivalent = key == "\r" ? .return : key == "\u{1b}" ? .escape : KeyEquivalent(Character(key))
        return KeyboardShortcut(k, modifiers: m)
    }
}
