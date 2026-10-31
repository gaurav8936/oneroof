import AppKit
import OneRoofCore

/// Menu spec for v2 (shared/MENUS.md). Every key comes from KeymapV2 — no literal key equivalents in this file.
/// Titles and order follow AppDelegate.buildMenu() in 0.5.2.9; v2 changes are marked ★. AppDelegate builds the NSMenus
/// with `MenuSpecV2.install(target:)` when settings.ui2 is on and routes each `action` id to its existing @objc handler
/// (PATCHES.md P5). The five "* Theme" submenus are replaced by Look ▸; Overview/Resources/Decisions/Board/Subagents/
/// Work items keep their keys but now open places.
struct MenuSpecV2 {
    typealias K = KeymapV2
    struct V2Item {
        var title: String
        var action: String
        var key: KeymapV2.Key = .none
        var hidden = false          // allowsKeyEquivalentWhenHidden
        var submenu: [V2Item]? = nil
        static let sep = V2Item(title: "-", action: "")
    }
    private static func i(_ t: String, _ a: String, _ k: KeymapV2.Key = .none, hidden: Bool = false) -> V2Item { V2Item(title: t, action: a, key: k, hidden: hidden) }
    private static func sub(_ t: String, _ items: [V2Item]) -> V2Item { V2Item(title: t, action: "", submenu: items) }
    private static let sep = V2Item.sep

    static let app: [V2Item] = [
        i("About One Roof", "app.about"), sep,
        i("Settings…", "app.settings", K.settings), i("Setup…", "app.setup"), i("Foundations…", "app.foundations", K.foundations),
        i("Run Startup Check", "app.runCheck"), i("Command Palette…", "app.palette", K.palette), i("Command Palette (⌘P)", "app.palette", K.paletteAlt, hidden: true), sep,
        sub("Services", []), sep,
        i("Hide One Roof", "app.hide", K.hide), i("Hide Others", "app.hideOthers", K.hideOthers), i("Show All", "app.showAll"), sep,
        i("Quit One Roof", "app.quit", K.quit)]

    static let file: [V2Item] = [
        i("New Session…", "file.newSession", K.newSession), i("New Terminal", "file.newTerminal", K.newTerminal),
        i("New Terminal in Selected Repo", "file.newTerminalInRepo", K.newTerminalInRepo),
        i("New Workspace Window…", "file.newWorkspace", K.newWorkspaceWindow), i("New Roof Window for Selected Repo", "file.newRoofWindow", K.newRoofWindow),
        i("New Objective…", "file.newObjective", K.newObjective), i("New Work V2Item…", "file.newWorkItem", K.newWorkItem), sep,
        i("Open File…", "file.open", K.openFile), i("Save", "file.save", K.save), sep,
        i("Launch Selected Session", "session.launch", K.launchSelected), i("Close Session…", "session.close", K.closeSession),
        i("Reopen Closed Session", "session.reopen", K.reopenClosed), i("Reopen Closed Session (⌥⌘T)", "session.reopen", K.reopenClosedHidden, hidden: true),
        i("Open in New Window", "session.popOut", K.popOut), sep,
        i("Close Window", "window.close", K.closeWindow)]

    static let edit: [V2Item] = [
        i("Undo", "edit.undo", K.undo), i("Redo", "edit.redo", K.redo), sep,
        i("Cut", "edit.cut", K.cut), i("Copy", "edit.copy", K.copy), i("Paste", "edit.paste", K.paste), i("Select All", "edit.selectAll", K.selectAll), sep,
        i("Clear Terminal", "terminal.clear", K.clearTerminal), i("Copy Session Output", "terminal.copyOutput"), sep,   // ★ NEW-13
        i("Find…", "find.terminal", K.find), i("Find Next", "find.next", K.findNext), i("Find Previous", "find.previous", K.findPrevious),
        i("Find in Workspace", "find.workspace", K.findInWorkspace), i("Ask Agent About Selection", "edit.askAgent")]

    static let view: [V2Item] = {
        let p = K.places
        // Each place has its named key (kept) plus a hidden ⌃⌘n alias (★).
        func place(_ t: String, _ a: String, _ named: KeymapV2.Key?, _ pl: Place) -> [V2Item] {
            named.map { [i(t, a, $0), i(t + " (⌃⌘)", a, p[pl]!, hidden: true)] } ?? [i(t, a, p[pl]!)]
        }
        var v: [V2Item] = []
        v += place("Home", "place.home", K.home, .home)
        v += place("Needs You", "place.needsYou", K.needsYou, .needsYou)
        v += place("Sessions", "place.sessions", K.focusTerminal, .sessions)
        v += place("Work", "place.work", K.work, .work)
        v += [i("Board", "work.board", K.board)]
        v += place("Machine", "place.machine", K.machine, .machine)
        v += place("Loops", "place.loops", nil, .loops)
        v += place("Learn", "place.learn", K.learn, .learn)
        v += [i("Subagents", "home.subagents", K.subagents), sep]
        v += [i("Single", "layout.single", K.layouts[0]), i("Grid", "layout.grid", K.layouts[1]), i("Wall", "layout.wall", K.layouts[2]), i("Scroll", "layout.scroll", K.layouts[3]),   // ★ Scroll: LAB-1831
              i("Focus: Step On", "focus.next", K.focusForward), i("Focus: Step Back", "focus.previous", K.focusBack), sep]                  // ★ back
        v += [i("Sessions Column", "toggle.sessions", K.sessionsColumn), i("Plan", "toggle.plan", K.plan),
              i("Terminal Panel", "toggle.centre", K.terminalPanel), i("Files Tab", "tab.files", K.filesTab),
              i("Dock", "toggle.dock", K.dockToggle),                                                                                     // ★
              i("Changes", "tab.changes", K.changes), i("Search in Workspace", "find.workspace"), sep]
        v += [sub("Group By", ["Status", "Repo", "Project", "Agent", "Account", "Folder"].enumerated().map { n, g in i(g, "group.\(n)", K.groupBy[n]) }), sep]
        v += [i("Split Right", "pane.splitRight", K.splitRight), i("Split Down", "pane.splitDown", K.splitDown),
              i("Close Pane", "pane.close", K.closePane), i("Maximize Pane", "pane.zoom", K.maximizePane), i("Even Out Panes", "pane.even")]
        v += zip(["Left", "Right", "Up", "Down"], K.focusPane).map { d, k in i("Focus Pane \(d)", "pane.focus\(d)", k) }
        v += [sep, i("Raw Stream / Run", "terminal.raw", K.rawStream), i("Table View", "terminal.table"), i("Debug", "file.debug", K.debug), sep,
              i("Bigger Text", "text.bigger", K.biggerText), i("Smaller Text", "text.smaller", K.smallerText), i("Actual Size", "text.actual", K.actualSize), sep,
              i("Look…", "look.picker")]                                                                                                 // ★ replaces 5 theme submenus
        return v
    }()

    static let session: [V2Item] = [
        i("Launch", "session.launch"), i("Mark as Next", "session.next"), i("Mark as Planned", "session.planned"), i("Do Not Use", "session.dnu"),
        i("Pin", "session.pin"), i("Rename…", "session.rename"), sub("Move to Window", []), sep,
        sub("Schedule", [i("Tonight 2:00 AM", "schedule.tonight"), i("Nightly at 2:00 AM", "schedule.nightly"), i("On Demand", "schedule.off")]),
        i("Run Now", "session.launch"), i("Interrupt", "session.interrupt", K.interrupt), i("Send Handoff", "session.handoff"), sep,
        i("Open in New Window", "session.popOut"), i("Open Repo in Finder", "session.openRepo"), i("Copy session id", "copy.id"),
        i("Copy Working Directory", "copy.cwd"), i("Copy Attach Command", "copy.attach"), i("Copy Link to Session", "copy.link"), sep,
        i("Close Agent…", "session.close"), i("Delete Session", "session.delete"), i("Remove Exited Sessions…", "session.removeExited"), sep,
        i("Next Session", "session.selectNext", K.nextSession), i("Previous Session", "session.selectPrevious", K.previousSession)]

    static let window: [V2Item] = [
        i("Minimize", "window.minimize", K.minimize), i("Zoom", "window.zoom"), sep,
        i("All Windows", "window.all", K.allWindows), i("Rename Window…", "window.rename"), sub("Window Colour", []), sub("Workspaces", []),
        sub("Roof Windows", []), i("Foundations", "app.foundations"), sep, i("Bring All to Front", "window.front")]
        + (0..<9).map { n in i("Workspace \(n + 1)", "workspace.\(n + 1)", K.workspaces[n], hidden: true) }

    static let help: [V2Item] = [
        i("One Roof Help", "help.open"), i("How Do I…?", "help.howDoI", K.howDoI), i("Keyboard Shortcuts", "help.shortcuts"),
        i("Release Notes", "help.releaseNotes"), sep, i("One Roof README", "help.readme"), i("Help Pages Folder", "help.folder")]

    static let menus: [(String, [V2Item])] = [("One Roof", app), ("File", file), ("Edit", edit), ("View", view), ("Session", session), ("Window", window), ("Help", help)]

    /// Builds the whole main menu. `selector` receives every item; read `representedObject as? String` for the action id.
    static func install(target: AnyObject, selector: Selector) -> NSMenu {
        let main = NSMenu()
        for (title, items) in menus {
            let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            top.submenu = build(title, items, target: target, selector: selector)
            main.addItem(top)
        }
        return main
    }

    static func build(_ title: String, _ items: [V2Item], target: AnyObject, selector: Selector) -> NSMenu {
        let m = NSMenu(title: title)
        for it in items {
            if it.title == "-" { m.addItem(.separator()); continue }
            let mi = NSMenuItem(title: it.title, action: it.submenu == nil ? selector : nil, keyEquivalent: it.key.key)
            mi.keyEquivalentModifierMask = it.key.mods
            mi.target = it.submenu == nil ? target : nil
            mi.representedObject = it.action
            if it.hidden { mi.isHidden = true; mi.allowsKeyEquivalentWhenHidden = true }
            if let s = it.submenu { mi.submenu = build(it.title, s, target: target, selector: selector) }
            m.addItem(mi)
        }
        return m
    }
}
