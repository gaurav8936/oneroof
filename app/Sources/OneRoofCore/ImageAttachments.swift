import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Images attached to a new session (LAB-462): pasted (⌘V) or dropped into the New session sheet, saved where the
/// terminal saves its pasted images, named in the opening message so the agent reads them, and embedded in a new
/// Linear issue's description when they could be uploaded.
public enum ImageAttachments {
    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp"]

    public static func isImagePath(_ path: String) -> Bool {
        imageExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    /// The opening message with the images named at the end, on the same line (roofd types it into the agent's input
    /// box, where a newline could submit early). No images: the message unchanged.
    public static func openingMessage(_ message: String, images: [String]) -> String {
        guard !images.isEmpty else { return message }
        let paths = images.map(TerminalMouse.quote).joined(separator: " ")
        let lead = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = images.count == 1 ? "Attached image (read it): \(paths)" : "Attached images (read each one): \(paths)"
        return lead.isEmpty ? note : lead + " " + note
    }

    /// One image for an issue description: uploaded (`url`) or only on this Mac (`url` nil).
    public struct Upload: Equatable, Sendable {
        public var path: String
        public var url: String?
        public init(path: String, url: String?) { self.path = path; self.url = url }
    }

    /// The issue description with the images below it: uploaded ones embedded as Markdown images, the rest named by
    /// their local path (they could not be uploaded, so Linear cannot show them).
    public static func issueDescription(_ details: String, images: [Upload]) -> String {
        guard !images.isEmpty else { return details }
        var lines: [String] = []
        for (i, im) in images.enumerated() {
            let name = (im.path as NSString).lastPathComponent
            if let url = im.url { lines.append("![\(name)](\(url))") }
            else { lines.append("Image \(i + 1) (not uploaded, on the owner's Mac): `\(im.path)`") }
        }
        let body = details.trimmingCharacters(in: .whitespacesAndNewlines)
        return (body.isEmpty ? "" : body + "\n\n") + lines.joined(separator: "\n\n")
    }

    /// The MIME type Linear's upload needs, from the file name.
    public static func contentType(for path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        case "tif", "tiff": return "image/tiff"
        case "bmp": return "image/bmp"
        default: return "image/png"
        }
    }

    #if canImport(AppKit)
    /// What ⌘V in the sheet attaches: image files copied in Finder → their paths; a screenshot or copied image →
    /// saved as a PNG (as the terminal's paste does), its path. Nil when the clipboard holds no image, or holds text
    /// that is not just the image's own link: then ⌘V pastes text as usual.
    public static func pastedImages(from pb: NSPasteboard, imagesDir: URL? = nil) -> [String]? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            let images = urls.map(\.path).filter(isImagePath)
            return images.isEmpty ? nil : images
        }
        guard pb.availableType(from: TerminalMouse.imageTypes) != nil else { return nil }
        if let s = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty,
           !(s.hasPrefix("http://") || s.hasPrefix("https://")) || s.contains(" ") || s.contains("\n") {
            return nil
        }
        return TerminalMouse.saveImage(from: pb, in: imagesDir ?? TerminalMouse.pastedImagesDir).map { [$0] }
    }
    #endif
}
