import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Terminal mouse and drop rules that do not need a live surface (tested in OneRoofCoreTests).
public enum TerminalMouse {
    #if canImport(AppKit)
    /// A left drag selects text unless Option is held (Option sends the mouse to the program).
    public static func selects(flags: NSEvent.ModifierFlags) -> Bool { !flags.contains(.option) }
    #endif

    /// Dropped files become their paths, shell-quoted and space-separated, with a trailing space (as Terminal.app does).
    public static func droppedPaths(_ paths: [String]) -> String {
        paths.map(quote).joined(separator: " ") + " "
    }

    /// Single-quote a path for the shell when it needs it.
    public static func quote(_ p: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+,:@%~="))
        if !p.isEmpty, p.unicodeScalars.allSatisfy({ safe.contains($0) }) { return p }
        return "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
