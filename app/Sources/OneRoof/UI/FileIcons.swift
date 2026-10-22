import AppKit
import UniformTypeIdentifiers

/// Finder's own icons for files and folders (LAB-478, LAB-513): a Markdown file looks like a Markdown file, a folder
/// like a folder. Icons for files are cached by type, so long lists stay cheap; folders and apps use the item's own icon.
enum FileIcons {
    private static var byType: [String: NSImage] = [:]

    static func icon(for path: String, isDirectory: Bool? = nil, size: CGFloat = 16) -> NSImage {
        let dir = isDirectory ?? {
            var d: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
        }()
        let img: NSImage
        if dir || path.hasSuffix(".app") {
            img = NSWorkspace.shared.icon(forFile: path)
        } else {
            let ext = (path as NSString).pathExtension.lowercased()
            if let cached = byType[ext] {
                img = cached
            } else {
                let type = UTType(filenameExtension: ext) ?? .data
                img = NSWorkspace.shared.icon(for: type)
                byType[ext] = img
            }
        }
        let copy = img.copy() as? NSImage ?? img
        copy.size = NSSize(width: size, height: size)
        return copy
    }
}
