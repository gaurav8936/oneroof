import Foundation

/// Files that ship inside One Roof.app (Contents/Resources, copied by scripts/bundle.sh), with a fallback to the
/// source checkout this file was built from, so a `swift build` run finds them too.
public enum AppResources {
    /// `<repo>`: app/Sources/OneRoofCore/AppResources.swift → four folders up, in a debug build. "" in a release
    /// build, so no build-machine path is compiled into the app (swiftc's -file-prefix-map does not remap #filePath);
    /// a release app reads its folders from Resources only.
    public static var sourceCheckout: String {
        #if DEBUG
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().path
        #else
        return ""
        #endif
    }

    /// `bundled` inside the app's Resources if present, else `checkout` (relative to the source checkout).
    public static func path(bundled: String, checkout: String, resources: String? = Bundle.main.resourcePath) -> String? {
        var candidates: [String] = []
        if let r = resources { candidates.append(r + "/" + bundled) }
        if !sourceCheckout.isEmpty { candidates.append(sourceCheckout + "/" + checkout) }
        return candidates.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The Help pages folder (Resources/help, or docs/help in the checkout).
    public static var helpFolder: String? { path(bundled: "help", checkout: "docs/help") }
    /// The app README (Resources/app-README.md, or app/README.md).
    public static var readme: String? { path(bundled: "app-README.md", checkout: "app/README.md") }
    /// Release notes (Resources/RELEASE-NOTES.md, or CHANGELOG.md in the checkout).
    public static var releaseNotes: String? { path(bundled: "RELEASE-NOTES.md", checkout: "CHANGELOG.md") }

    /// The first Help page to open: 00_index.md, else the first numbered page, else any .md page.
    public static func helpStartPage(in folder: String? = AppResources.helpFolder) -> String? {
        guard let folder else { return nil }
        let pages = ((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []).filter { $0.hasSuffix(".md") }.sorted()
        let pick = pages.first { $0 == "00_index.md" } ?? pages.first { $0.first?.isNumber == true } ?? pages.first
        return pick.map { folder + "/" + $0 }
    }
}

/// An extra Learn folder (Settings › Foundations › Learn folders), read in place.
public enum LearnFolder {
    public struct Entry: Equatable, Sendable {
        public var title: String
        public var section: String
        public var path: String
        /// A folder of .mp3 narration clips (shown as a track list), rather than a Markdown page.
        public var narration: Bool
        /// Clip file names, for a narration folder.
        public var clips: [String]
    }

    /// Every `.md` file under `folder` (recursive, node_modules skipped) is a page; every sub-folder holding `.mp3`
    /// files is a narration list. Section = the folder's name.
    public static func scan(_ folder: String) -> [Entry] {
        let fm = FileManager.default
        let root = ((folder as NSString).expandingTildeInPath as NSString).standardizingPath
        guard Workspace.folderExists(root) else { return [] }
        let section = sectionName(root)
        var pages: [Entry] = [], lists: [Entry] = []
        var clipsByDir: [String: [String]] = [:]
        guard let e = fm.enumerator(atPath: root) else { return [] }
        for case let rel as String in e {
            let parts = rel.split(separator: "/")
            if parts.contains(where: { $0 == "node_modules" || $0.hasPrefix(".") }) {
                if (rel as NSString).lastPathComponent == "node_modules" { e.skipDescendants() }
                continue
            }
            let name = (rel as NSString).lastPathComponent
            if name.hasSuffix(".md") {
                let title = (name as NSString).deletingPathExtension
                    .replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
                pages.append(Entry(title: title.capitalized, section: section, path: root + "/" + rel, narration: false, clips: []))
            } else if name.hasSuffix(".mp3") {
                let dir = (rel as NSString).deletingLastPathComponent
                clipsByDir[dir, default: []].append(name)
            }
        }
        for (dir, clips) in clipsByDir.sorted(by: { $0.key < $1.key }) {
            let path = dir.isEmpty ? root : root + "/" + dir
            let title = dir.isEmpty ? section : section + " · " + (dir as NSString).lastPathComponent
            let listSection = section.lowercased().contains("narration") ? section : section + " narration"
            lists.append(Entry(title: title, section: listSection, path: path, narration: true, clips: clips.sorted()))
        }
        return pages.sorted { $0.path < $1.path } + lists
    }

    /// "help-content" → "Help content".
    public static func sectionName(_ folder: String) -> String {
        let n = (folder as NSString).lastPathComponent.replacingOccurrences(of: "-", with: " ").replacingOccurrences(of: "_", with: " ")
        return n.prefix(1).uppercased() + n.dropFirst()
    }
}
