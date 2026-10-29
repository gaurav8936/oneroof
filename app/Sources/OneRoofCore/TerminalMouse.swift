import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Terminal mouse and drop rules that do not need a live surface (tested in OneRoofCoreTests).
public enum TerminalMouse {
    #if canImport(AppKit)
    /// A left drag selects text unless Option is held (Option sends the mouse to the program).
    /// LAB-1554: when the program has turned mouse reporting on (Claude's fullscreen view, most full-screen tools),
    /// clicks and drags go to it, as in other Mac terminals: its buttons work ("Jump to bottom") and it does its own
    /// selection. Option then selects in the terminal instead.
    public static func selects(flags: NSEvent.ModifierFlags, captured: Bool = false) -> Bool {
        captured ? flags.contains(.option) : !flags.contains(.option)
    }
    #endif

    /// Dropped files become their paths, shell-quoted and space-separated, with a trailing space (as Terminal.app does).
    public static func droppedPaths(_ paths: [String]) -> String {
        paths.map(quote).joined(separator: " ") + " "
    }

    #if canImport(AppKit)
    /// Where pasted and dropped images are saved. No spaces in the path, so it pastes unquoted and Claude Code, Codex
    /// and the others see a plain image path they can attach.
    public static var pastedImagesDir: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("OneRoof/pastes")
    }

    /// What ⌘V types (owner 10-20, as in other Mac terminals): files copied in Finder → their full paths (Finder also
    /// puts the bare file name on the clipboard as text); text → the text; an image alone (a screenshot) → it is saved
    /// as a PNG and its path is typed. Nil when there is nothing to paste.
    public static func pasteText(from pb: NSPasteboard, imagesDir: URL? = nil) -> String? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return droppedPaths(urls.map(\.path))
        }
        if let s = pb.string(forType: .string), !s.isEmpty { return s }
        guard let path = saveImage(from: pb, in: imagesDir ?? pastedImagesDir) else { return nil }
        return droppedPaths([path])
    }

    /// What a drop types: files → their paths; an image (dragged from a browser, which also carries its URL as
    /// text) → saved, its path. Text drops are not taken. `save: false` only checks (draggingEntered).
    public static func droppedText(from pb: NSPasteboard, save: Bool = true, imagesDir: URL? = nil) -> String? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            return droppedPaths(urls.map(\.path))
        }
        guard pb.availableType(from: imageTypes) != nil else { return nil }
        guard save else { return "" }
        return saveImage(from: pb, in: imagesDir ?? pastedImagesDir).map { droppedPaths([$0]) }
    }

    /// True when ⌘V would type something (enables Paste in the menu).
    public static func canPaste(_ pb: NSPasteboard) -> Bool {
        pb.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            || pb.string(forType: .string)?.isEmpty == false
            || pb.availableType(from: imageTypes) != nil
    }

    static let imageTypes: [NSPasteboard.PasteboardType] = [.png, .tiff, NSPasteboard.PasteboardType("public.jpeg")]

    /// Save the pasteboard's image as paste-<time>.png; images older than 7 days are cleared first.
    public static func saveImage(from pb: NSPasteboard, in dir: URL) -> String? {
        guard let type = pb.availableType(from: imageTypes), let data = pb.data(forType: type) else { return nil }
        return saveImage(data: data, isPNG: type == .png, in: dir)
    }

    /// Save image data (PNG, TIFF, JPEG, …) as paste-<time>.png in `dir`: the same place and name as a terminal paste
    /// (LAB-462: the New session sheet saves its pasted and dropped images here too).
    public static func saveImage(data: Data, isPNG: Bool = false, in dir: URL) -> String? {
        let png: Data?
        if isPNG || data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { png = data }
        else { png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) }
        guard let png else { return nil }
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let weekAgo = Date().addingTimeInterval(-7 * 86_400)
        for f in (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            if let d = try? f.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate, d < weekAgo {
                try? fm.removeItem(at: f)
            }
        }
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        let file = dir.appendingPathComponent("paste-\(stamp.string(from: Date()))-\(UUID().uuidString.prefix(4)).png")
        do { try png.write(to: file) } catch { return nil }
        return file.path
    }
    #endif

    /// Single-quote a path for the shell when it needs it.
    public static func quote(_ p: String) -> String {
        let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._-+,:@%~="))
        if !p.isEmpty, p.unicodeScalars.allSatisfy({ safe.contains($0) }) { return p }
        return "'" + p.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
