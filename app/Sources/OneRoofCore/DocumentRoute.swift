import Foundation

/// LAB-479 / LAB-480: which way the centre shows a file. The centre is a terminal while code runs; for a file it is a
/// viewer: Markdown renders formatted, HTML renders like a browser page, images show as images, code and text open in
/// the editor. Markdown and HTML also have a Source mode (the editor), so editing them is one click away.
public enum ViewerFileKind: String, Sendable, CaseIterable {
    case markdown, html, image, text, other
}

/// Preview (rendered) or Source (the editor) for a file that has both.
public enum ViewerMode: String, Sendable {
    case preview, source
}

public enum DocumentRoute {
    /// The kind of a file, by extension (folders, diffs and search are decided by the app before this).
    public static func kind(path: String) -> ViewerFileKind {
        let name = (path as NSString).lastPathComponent.lowercased()
        if ["dockerfile", "makefile", "gemfile", "procfile", "license", "readme"].contains(name) { return .text }
        return kind(extension: (path as NSString).pathExtension)
    }

    public static func kind(extension raw: String) -> ViewerFileKind {
        switch raw.lowercased() {
        case "md", "markdown", "mdown", "mkd", "mkdn", "mdx": return .markdown
        case "html", "htm", "xhtml": return .html
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "svg", "ico": return .image
        case "swift", "ts", "tsx", "js", "jsx", "mjs", "cjs", "mts", "cts", "py", "pyi", "go", "rs", "rb", "java", "kt", "c", "h",
             "cpp", "hpp", "cc", "m", "mm", "sh", "zsh", "bash", "fish", "json", "jsonc", "jsonl", "yaml", "yml", "toml", "xml",
             "css", "scss", "less", "sql", "txt", "text", "log", "csv", "tsv", "env", "ini", "cfg", "conf", "svelte", "vue",
             "dockerfile", "makefile", "gitignore", "gitattributes", "lock", "plist", "tf", "hcl", "graphql", "proto", "zig",
             "lua", "pl", "r", "dart", "ex", "exs", "erl", "hs", "ml", "scala", "cs", "fs", "php", "rst", "adoc", "org",
             "patch", "diff", "": return .text
        default: return .other
        }
    }

    /// Markdown and HTML have a rendered Preview and a Source (editor) view.
    public static func hasPreview(_ k: ViewerFileKind) -> Bool { k == .markdown || k == .html }

    /// True: the centre shows the editor (text and code, or Markdown/HTML in Source mode). False: the rendered viewer.
    public static func opensInEditor(_ k: ViewerFileKind, mode: ViewerMode) -> Bool {
        k == .text || (hasPreview(k) && mode == .source)
    }

    /// The nearest folder above `path` holding `.git` (no git process: the viewer asks on every redraw).
    public static func enclosingRepo(of path: String, exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        var dir = (path as NSString).deletingLastPathComponent
        while !dir.isEmpty, dir != "/" {
            if exists(dir + "/.git") { return dir }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// The folder an HTML page may read from, so relative CSS, scripts, images and audio load: the repo it sits in
    /// (pages often reach `../assets`), else its own folder.
    public static func webReadRoot(page: String, repoRoot: String?) -> String {
        let folder = (page as NSString).deletingLastPathComponent
        if let r = repoRoot, !r.isEmpty, folder == r || folder.hasPrefix(r.hasSuffix("/") ? r : r + "/") { return r }
        return folder
    }
}

/// What the HTML viewer does with a navigation (LAB-480): local pages and their assets load in place; a clicked web
/// link, a mail link or any other app's link opens outside One Roof (the default browser), never inside the viewer.
public enum WebLinkPolicy {
    public enum Decision: Equatable, Sendable { case allow, openExternally, ignore }

    /// - Parameters:
    ///   - url: the navigation's URL string.
    ///   - clicked: the user activated a link (or a form) rather than a page load, redirect or script.
    public static func decide(_ url: String, clicked: Bool) -> Decision {
        let scheme = url.split(separator: ":", maxSplits: 1).first.map { $0.lowercased() } ?? ""
        switch scheme {
        case "file", "about", "data", "blob": return .allow
        case "http", "https":
            return clicked ? .openExternally : .allow     // embeds, iframes and CDN loads stay; clicks go to the browser
        case "javascript": return .ignore
        case "": return .ignore
        default: return clicked ? .openExternally : .ignore   // mailto:, oneroof:, vscode:, …
        }
    }
}
