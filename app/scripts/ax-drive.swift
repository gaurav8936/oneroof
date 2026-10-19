// Drive a running One Roof through the macOS Accessibility API.
// Targets one process by pid, so nothing goes to the frontmost app and the owner's keyboard focus is never taken.
// Needs Accessibility permission for the terminal that runs it (System Settings › Privacy & Security › Accessibility).
//
//   swift scripts/ax-drive.swift <pid> menus                       list every menu item (enabled / off)
//   swift scripts/ax-drive.swift <pid> menu "Session" "Mark as Next" press a menu item
//   swift scripts/ax-drive.swift <pid> tree [depth]                 print the window's element tree (role, title, value)
//   swift scripts/ax-drive.swift <pid> texts                        every static text in the main window, in order
//   swift scripts/ax-drive.swift <pid> press "<button title>"       press the first button with that title
import ApplicationServices
import Foundation

func attr(_ e: AXUIElement, _ name: String) -> AnyObject? {
    var v: AnyObject?
    return AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success ? v : nil
}
func children(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func str(_ e: AXUIElement, _ name: String) -> String { (attr(e, name) as? String) ?? "" }
func label(_ e: AXUIElement) -> String {
    for n in [kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute] {
        let s = str(e, n as String)
        if !s.isEmpty { return s }
    }
    return ""
}

let args = CommandLine.arguments
guard args.count >= 3, let pid = pid_t(args[1]) else {
    FileHandle.standardError.write("usage: ax-drive.swift <pid> menus|menu|tree|texts|press …\n".data(using: .utf8)!)
    exit(64)
}
guard AXIsProcessTrusted() else {
    FileHandle.standardError.write("Accessibility permission missing for this terminal\n".data(using: .utf8)!)
    exit(65)
}
let app = AXUIElementCreateApplication(pid)

func menuBar() -> AXUIElement? {
    guard let v = attr(app, kAXMenuBarAttribute) else { return nil }
    return (v as! AXUIElement)
}
func menuItems(_ top: AXUIElement) -> [AXUIElement] {
    children(top).flatMap { children($0) }   // menu bar item → menu → items
}
func mainWindow() -> AXUIElement? {
    let wins = (attr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
    return wins.first { str($0, kAXTitleAttribute) == "One Roof" } ?? wins.first
}
func walk(_ e: AXUIElement, depth: Int = 0, max: Int, visit: (AXUIElement, Int) -> Bool) {
    guard depth <= max, visit(e, depth) else { return }
    for c in children(e) { walk(c, depth: depth + 1, max: max, visit: visit) }
}

switch args[2] {
case "menus":
    for top in children(menuBar() ?? app) {
        let t = str(top, kAXTitleAttribute)
        let items = menuItems(top).map { i -> String in
            let enabled = (attr(i, kAXEnabledAttribute) as? Bool) ?? true
            return str(i, kAXTitleAttribute) + (enabled ? "" : " (off)")
        }.filter { !$0.isEmpty }
        print("\(t): \(items.joined(separator: " · "))")
    }
case "menu":
    guard args.count >= 5 else { exit(64) }
    guard let top = children(menuBar() ?? app).first(where: { str($0, kAXTitleAttribute) == args[3] }),
          let item = menuItems(top).first(where: { str($0, kAXTitleAttribute) == args[4] }) else {
        print("not found: \(args[3]) › \(args[4])"); exit(1)
    }
    let r = AXUIElementPerformAction(item, kAXPressAction as CFString)
    print(r == .success ? "pressed \(args[3]) › \(args[4])" : "press failed (\(r.rawValue))")
case "tree":
    let max = args.count > 3 ? Int(args[3]) ?? 12 : 12
    guard let w = mainWindow() else { print("no window"); exit(1) }
    walk(w, max: max) { e, d in
        let l = label(e)
        print(String(repeating: "  ", count: d) + str(e, kAXRoleAttribute) + (l.isEmpty ? "" : "  \"\(l.prefix(80))\""))
        return true
    }
case "texts":
    guard let w = mainWindow() else { print("no window"); exit(1) }
    walk(w, max: 40) { e, _ in
        if str(e, kAXRoleAttribute) == kAXStaticTextRole as String { let l = label(e); if !l.isEmpty { print(l) } }
        return true
    }
case "press":
    guard args.count >= 4, let w = mainWindow() else { exit(64) }
    var done = false
    walk(w, max: 40) { e, _ in
        if !done, str(e, kAXRoleAttribute) == kAXButtonRole as String, label(e) == args[3] {
            done = AXUIElementPerformAction(e, kAXPressAction as CFString) == .success
        }
        return !done
    }
    print(done ? "pressed \(args[3])" : "button not found: \(args[3])")
    exit(done ? 0 : 1)
default:
    exit(64)
}
